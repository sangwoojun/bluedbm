import FIFO::*;
import FIFOF::*;
import Clocks::*;
import Vector::*;

import BRAM::*;
import BRAMFIFO::*;

import AuroraImportFmc1::*;
import ControllerTypes::*;
import FlashCtrlVirtex1::*;
import FlashCtrlModel::*;

import MergeN::*;

import VectorPacker::*;

//import DRAMArbiter::*;

/**
IMPORTANT: tags need to be encoded in a certain way now:
tag[0] board
tag[3:1] bus
tag[~7:4] tag
**/

typedef 8 BusCount; // 8 per card in hw, 2 per card in sim
typedef TMul#(2,BusCount) BBusCount; //Board*bus
typedef 128 TagCount;


typedef struct {
	Bit#(4) bus;
	ChipT chip; //Bit#(3)
	Bit#(16) block;
	Bit#(8) page;
} FlashAddress deriving (Bits, Eq);

typedef enum {
	PAGE_DRAM,
	PAGE_HOST,
	PAGE_ACCEL
} PageLocationType deriving (Bits, Eq);

typedef struct {
	PageLocationType ltype;
	Bit#(32) addr;
} PageLocation deriving (Bits,Eq);

function FlashAddress decodeAddress(Bit#(32) addr);
	Bit#(4) bbus = addr[3:0];
	ChipT chip = truncate(addr[7:4]);
	Bit#(16) block = addr[23:8];
	Bit#(8) page = addr[31:24];

	return FlashAddress{
		bus: bbus,
		chip: chip,
		block: block,
		page: page
	};

endfunction

interface DualFlashManagerWideIfc;
	method Action command(FlashOp cmd, FlashAddress addr, PageLocation loc);

	method ActionValue#(PageLocation) readReady;
	method ActionValue#(PageLocation) writeReady;

	method ActionValue#(Tuple2#(PageLocation, Bool)) eraseDone;
	method ActionValue#(Bit#(256)) readWord;
	method Action writeWord(Bit#(256) data);
endinterface

module mkDualFlashManagerWide#(Vector#(2,FlashCtrlUser) flashes) (DualFlashManagerWideIfc);
	
	BRAM2Port#(Bit#(8), PageLocation) tagLocMap <- mkBRAM2Server(defaultValue); 

	Vector#(16,FIFO#(Bit#(8))) vFreeTagList <- replicateM(mkSizedFIFO(16));
	Reg#(Bit#(8)) freeTagCnt <- mkReg(16);
	rule fillFreeTag(freeTagCnt > 0);
		for ( Integer i = 0; i < 8; i=i+1 ) begin
			Bit#(8) tag = freeTagCnt -1;
			Bit#(8) mask = fromInteger(i);
			tag = tag | (mask<<4);

			vFreeTagList[i].enq(tag);
		end
		freeTagCnt <= freeTagCnt - 1;
	endrule


	//tag,success
	Merge2Ifc#(Tuple2#(Bit#(8),Bool)) mErase <- mkMerge2;
	FIFO#(Tuple2#(Bit#(8),Bool)) eraseResQ <- mkFIFO;
	FIFO#(Tuple2#(PageLocation,Bool)) eraseResQ2 <- mkFIFO;

	Merge2Ifc#(Tuple2#(Bit#(8), Bit#(1))) mWriteReady <- mkMerge2;
	FIFO#(Tuple2#(Bit#(8), Bit#(1))) writeOrderQ <- mkSizedFIFO(128);

	for ( Integer i = 0; i < 2; i=i+1 ) begin
		rule flashAck;
			let ackStatus <- flashes[i].ackStatus();
			//Bit#(8) tag = zeroExtend(tpl_1(ackStatus));
			Bit#(8) tag = zeroExtend(tpl_1(ackStatus));
			Bit#(8) mask = (fromInteger(i)<<7);
			tag = tag | mask;
			StatusT status = tpl_2(ackStatus);
			//FlashStatus stat = STATE_NULL;
			case (status) 
				WRITE_DONE: begin
					Bit#(4) bus = truncate(tag>>4);
					vFreeTagList[bus].enq(tag);
				end
				ERASE_DONE: mErase.enq[i].enq(tuple2(tag, True));
				ERASE_ERROR: mErase.enq[i].enq(tuple2(tag, False));
			endcase
		endrule
		rule writeReadyRecv;
			TagT tag <- flashes[i].writeDataReq;
			Bit#(8) mask = (fromInteger(i)<<7);
			Bit#(8) ntag = zeroExtend(tag)|mask;
			//mstat.enq[i].enq(tuple2(ntag, STATE_WRITE_READY));
			mWriteReady.enq[i].enq(tuple2(ntag,fromInteger(i)));
		endrule
	end

	rule procWriteReq;
		mWriteReady.deq;
		let req = mWriteReady.first;
		writeOrderQ.enq(req);
		let tag = tpl_1(req);

		tagLocMap.portB.request.put( BRAMRequest {
			write:False, responseOnWrite: False,
			address:tag, datain: ?
		});
	endrule

	FIFO#(PageLocation) writeReadyQ <- mkFIFO;
	rule relayWriteReq;
		let loc <- tagLocMap.portB.response.get;
		writeReadyQ.enq(loc);
	endrule


	VectorUnpackerIfc#(256,2,Bit#(128)) writeUnpacker <- mkVectorUnpacker;
	Vector#(2,VectorSerializerIfc#(2,Bit#(128))) vWriteSerializer <- replicateM(mkVectorSerializer);
	Vector#(2,VectorSerializerIfc#(2,TagT)) vTagSerializer <- replicateM(mkVectorSerializer);
	FIFO#(Bit#(256)) writeDataQ <- mkFIFO;
	Reg#(Bit#(16)) writeDataOffset <- mkReg(0);
	
	rule unpackWriteData;
		let data = writeDataQ.first;
		writeDataQ.deq;
		writeUnpacker.enq(data);
	endrule
	rule routeWriteDataToBoard;
		writeUnpacker.deq;
		let d = writeUnpacker.first;

		let req = writeOrderQ.first;
		let tag = tpl_1(req);
		let board = tpl_2(req);

		vWriteSerializer[board].enq(d);
		Vector#(2,TagT) vtag;
		vtag[0] = truncate(tag);
		vtag[1] = truncate(tag);
		vTagSerializer[board].enq(vtag);
		
		if ( writeDataOffset >= (8192/32)-1 ) begin
			writeDataOffset <= 0;
			writeOrderQ.deq;
		end else begin
			writeDataOffset <= writeDataOffset + 1;
		end
	endrule
	for ( Integer i = 0; i < 2; i=i+1) begin
		rule writeData;
			vTagSerializer[i].deq;
			let tag = vTagSerializer[i].first;
			let data = vWriteSerializer[i].first;
			vWriteSerializer[i].deq;

			flashes[i].writeWord(tuple2(data,tag));
		endrule
	end


	rule procEraseResults;
		mErase.deq;
		let er = mErase.first;
		Bit#(8) tag = tpl_1(er);
		eraseResQ.enq(er);

		tagLocMap.portB.request.put( BRAMRequest {
			write:False, responseOnWrite: False,
			address:tag, datain: ?
		});
	endrule
	rule procEraseResults2;
		let r <- tagLocMap.portB.response.get;
		eraseResQ.deq;
		let re = eraseResQ.first;
		let tag = tpl_1(re);
		let res = tpl_2(re);
		//freeTagQ.enq(tag);
		Bit#(4) bus = truncate(tag>>4);
		vFreeTagList[bus].enq(tag);
		eraseResQ2.enq(tuple2(r,res));
	endrule

	Vector#(2,Vector#(8,FIFO#(Bit#(256)))) vReorderQ <- replicateM(replicateM(mkSizedBRAMFIFO(512+256)));
	Merge2Ifc#(Tuple2#(Bit#(1),Bit#(7))) mReorderTag <- mkMerge2;
	for ( Integer i = 0; i < 2; i=i+1 ) begin
		//Vector#(8,FIFO#(Bit#(8))) vReorderTagQ <- mkSizedFIFO(8);
		Vector#(8,Reg#(Bit#(16))) vBusReadCnt <- replicateM(mkReg(0));
		Vector#(8,FIFO#(Bit#(128))) vLocalReorderQ <- replicateM(mkFIFO);
		rule relayInData;
			let d <- flashes[i].readWord;
			let tag = tpl_2(d);
			Bit#(3) busid = truncate(tag>>4);

			if ( vBusReadCnt[busid] >= (8192/128)-1) begin
				vBusReadCnt[busid] <= vBusReadCnt[busid] + 1;
			end else begin
				vBusReadCnt[busid] <= 0;
				mReorderTag.enq[i].enq(tuple2(fromInteger(i),tag));
			end
			vLocalReorderQ[busid].enq(tpl_1(d));
			//readOrderDes.enq(tpl_1(d));
			//readOrderBusDes.enq(busid);
		endrule
		for ( Integer busid = 0; busid < 8; busid=busid+1 ) begin
			VectorDeserializerIfc#(2,Bit#(128)) readOrderDes <- mkVectorDeserializer;
			rule deserializeLocReorder;
				vLocalReorderQ[busid].deq;
				let d = vLocalReorderQ[busid].first;
				readOrderDes.enq(d);
			endrule
			rule relayDesOrd;
				let d = readOrderDes.first;
				readOrderDes.deq;
				vReorderQ[i][busid].enq({d[1],d[0]});
			endrule

		end
	end

	FIFO#(Bit#(256)) reorderQ <- mkSizedFIFO(16);
	Reg#(Bit#(16)) relayOrderedReadCnt <- mkReg(0);
	Reg#(Tuple2#(Bit#(1),Bit#(3))) curReorderSrc <- mkReg(?);
	rule procReadDone(relayOrderedReadCnt == 0);
		mReorderTag.deq;
		let d = mReorderTag.first;
		let boardid = tpl_1(d);
		let tag = tpl_2(d);
		Bit#(3) busid = truncate(tag>>4);



		let rd = vReorderQ[boardid][busid].first;
		vReorderQ[boardid][busid].deq;
		reorderQ.enq(rd);
		
		Bit#(8) gtag = zeroExtend(tag) | (zeroExtend(boardid)<<7);
		tagLocMap.portB.request.put( BRAMRequest {
			write:False, responseOnWrite: False,
			address:gtag, datain: ?
		});

		curReorderSrc <= tuple2(boardid,busid);
		relayOrderedReadCnt <= (8192/32)-1;
	endrule
	rule relayReadOrd(relayOrderedReadCnt > 0);
		let d = curReorderSrc;
		let boardid = tpl_1(d);
		let busid = tpl_2(d);
		
		let rd = vReorderQ[boardid][busid].first;
		vReorderQ[boardid][busid].deq;
		reorderQ.enq(rd);
		
		relayOrderedReadCnt <= relayOrderedReadCnt - 1;
	endrule
	FIFO#(PageLocation) readDoneLocQ <- mkFIFO;
	rule createReadDoneMsg;
		let loc <- tagLocMap.portB.response.get;
		readDoneLocQ.enq(loc);
	endrule

	FIFO#(Tuple3#(FlashOp, FlashAddress, PageLocation)) flashCmdQ <- mkFIFO;
	rule procFlashCmd;
		let d = flashCmdQ.first;
		flashCmdQ.deq;

		let op = tpl_1(d);
		let addr = tpl_2(d);
		let loc = tpl_3(d);

		vFreeTagList[addr.bus].deq;
		let newtag = vFreeTagList[addr.bus].first;
		TagT ltag = truncate(newtag);
		
		tagLocMap.portA.request.put( BRAMRequest {
			write:True, responseOnWrite: False,
			address:newtag, datain: loc
		});
		let board = addr.bus[3];
		let bus = truncate(addr.bus);
		flashes[board].sendCmd(FlashCmd{
			op:op,
			tag: ltag,
			bus: bus,
			chip: addr.chip,
			block:addr.block,
			page:addr.page
			});
	endrule
	
	method Action command(FlashOp cmd, FlashAddress addr, PageLocation loc);
		flashCmdQ.enq(tuple3(cmd, addr, loc));
	endmethod
	
	method ActionValue#(PageLocation) readReady;
		readDoneLocQ.deq;
		return readDoneLocQ.first;
	endmethod
	method ActionValue#(PageLocation) writeReady;
		writeReadyQ.deq;
		return writeReadyQ.first;
	endmethod

	method ActionValue#(Tuple2#(PageLocation, Bool)) eraseDone;
		eraseResQ2.deq;
		return eraseResQ2.first;
	endmethod
	method ActionValue#(Bit#(256)) readWord;
		reorderQ.deq;
		return reorderQ.first;
	endmethod
	method Action writeWord(Bit#(256) data);
		writeDataQ.enq(data);
	endmethod
endmodule
