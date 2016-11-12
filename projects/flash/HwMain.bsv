import FIFO::*;
import FIFOF::*;
import Clocks::*;
import Vector::*;

import BRAM::*;
import BRAMFIFO::*;

import MergeN::*;
import TagDestReorder::*;
import PageFIFO::*;

import PcieCtrl::*;

import DMASplitter::*;

import AuroraImportFmc1::*;
import ControllerTypes::*;
import FlashCtrlVirtex1::*;
import FlashCtrlModel::*;
import DualFlashManager::*;

import DRAMController::*;
import DRAMArbiter::*;

import AcceleratorReader::*;

import SparseCore::*;
import TiledSparseMatrix::*;
import CosineCore::*;


typedef 8 BusCount; // 8 per card in hw, 2 per card in sim
typedef TMul#(2,BusCount) BBusCount; //Board*bus
//typedef 64 TagCount; // Has to be larger than the software setting
typedef 4 DMAEngineCount;

typedef 3 AccelCount;
typedef TAdd#(AccelCount,1) DestCount; // 0 is always host DRAM

interface HwMainIfc;
endinterface

module mkHwMain#(PcieUserIfc pcie, Vector#(2,FlashCtrlUser) flashes, FlashManagerIfc flashMan, 
	DRAMUserIfc dram,
	Clock clk250,
	Reset rst250
	) 
	(HwMainIfc);

	Clock curClk <- exposeCurrentClock;
	Reset curRst <- exposeCurrentReset;

	Clock pcieclk = pcie.user_clk;
	Reset pcierst = pcie.user_rst;

	Integer busCount = valueOf(BusCount);
	//Integer tagCount = valueOf(TagCount);
	Integer dmaEngineCount = valueOf(DMAEngineCount);
	Integer destCount = valueOf(DestCount);
	Integer accelCount = valueOf(AccelCount);

	DMASplitterIfc#(DMAEngineCount) dma <- mkDMASplitter(pcie);

	DRAMArbiterIfc#(4) drama <- mkDRAMArbiter(dram);

	Merge2Ifc#(Tuple2#(Bit#(32), Bit#(128))) m0 <- mkMerge2;

	FIFO#(FlashCmd) flashCmdQ <- mkFIFO;
	Vector#(8, Reg#(Bit#(32))) writeBuf <- replicateM(mkReg(0));

	DualFlashManagerIfc flashman <- mkDualFlashManager(flashes);
	
	FIFO#(Bit#(8)) writeTagsQ <- mkSizedBRAMFIFO(128);
	FIFO#(Bit#(8)) writeTagsRQ <- mkSizedBRAMFIFO(128);

	Reg#(Bit#(16)) flashWriteBytes <- mkReg(0);

	rule senddmaenq;
		m0.deq;
		let d = m0.first;
		dma.enq(tpl_1(d), tpl_2(d));
	endrule

	FIFO#(Bit#(128)) dmainQ <- mkFIFO;
	FIFO#(Bit#(128)) flashWriteInQ <- mkFIFO;
	FIFO#(Tuple2#(Bit#(32), Bit#(128))) accelCmdQ <- mkFIFO;
	rule getFlashCmd;
		dma.deq;
		Bit#(128) d = dma.first;
		Bit#(32) h = dma.header;
		if ( h == 0 ) begin
			dmainQ.enq(d);
		end else
		if ( h == 255 ) begin
			flashWriteInQ.enq(d);
		end else begin
			accelCmdQ.enq(tuple2(h,d));
		end
	endrule




////// Start write flash
	FIFO#(Tuple2#(Bit#(128), Bit#(8))) flashWriteQ <- mkFIFO;
	Reg#(Bit#(32)) flashWriteBytesOut <- mkReg(0);
	Reg#(Bit#(8)) flashWriteTag <- mkReg(0);
	rule flashWriteR;
		if ( flashWriteBytesOut + 16 <= 8192 ) begin
			let d = flashWriteQ.first;
			flashWriteQ.deq;
			let data = tpl_1(d);
			let tag = tpl_2(d);
			flashWriteTag <= tag;
			let board = tag[7];

			flashman.ifc[board].writeWord(tag, data);
			flashWriteBytesOut <= flashWriteBytesOut + 16;
		end else begin
			let board = flashWriteTag[7];
			flashman.ifc[board].writeWord(flashWriteTag, 0);
			if ( flashWriteBytesOut + 16 >= 8192+32 ) begin
				flashWriteBytesOut <= 0;
			end else begin
				flashWriteBytesOut <= flashWriteBytesOut + 16;
			end
		end
	endrule

	rule readDmaWord;
		let w <- dma.dmaReadWord;
		flashWriteInQ.enq(w);
	endrule
	rule flashWriteIn;
		let d = flashWriteInQ.first;
		flashWriteInQ.deq;
		//$display("DMA read %x", d);

		flashWriteQ.enq(tuple2(d, truncate(writeTagsQ.first)));
		if ( flashWriteBytes + 16 >= 8192 ) begin
			writeTagsQ.deq;
			flashWriteBytes <= 0;
		end else begin
			flashWriteBytes <= flashWriteBytes + 16;
		end
	endrule
	Reg#(Bit#(16)) dmaReadRemain <- mkReg(0);
	Reg#(Bit#(8)) dmaReadTagCur <- mkReg(0);
	rule reqDMARead;
		if ( dmaReadRemain == 0 ) begin
			dmaReadTagCur <= writeTagsRQ.first;
			writeTagsRQ.deq;
			dmaReadRemain <= 8192;
		end else begin
			dmaReadRemain <= dmaReadRemain - 128;
			Bit#(32) dmao = fromInteger(8192)-zeroExtend(dmaReadRemain) 
				+ 8192*zeroExtend(dmaReadTagCur); // 8K
			dma.dmaReadReq(dmao, 8);
		end
	endrule
	
	TagDestReorderIfc#(DestCount) tdreorder <- mkTagDestReorder;
	


// Start proc cmd
	rule procFlashCmd;
		let d = dmainQ.first;
		dmainQ.deq;

		let conf = d[127:96];
		//if ( conf == 0 ) begin

		let cur_blockpagechip = d[63:32];
		let cur_bustag = d[95:64];
		Bit#(1) board = cur_bustag[7];
		Bit#(3) bus = truncate(cur_bustag>>4);
		Bit#(4) bbus = truncate(cur_bustag>>4);
		Bit#(8) tag = truncate(cur_bustag);
		Bit#(8) dest = truncate(cur_bustag>>16);

		let cur_flashop = ERASE_BLOCK;
		if ( opcode == 0 ) cur_flashop = ERASE_BLOCK;
		else if ( opcode == 1 ) begin
			cur_flashop = READ_PAGE;
			tdreorder.tagDestReq(tag,dest);
		end
		else if ( opcode == 2 ) begin
			cur_flashop = WRITE_PAGE;
		end

		if ( opcode <= 2 ) begin
			//$display( "cmd recv %d", opcode );	
			flashman.command(FlashManagerCmd{
				op:cur_flashop,
				tag:tag,
				bus: bbus,
				chip: truncate(cur_blockpagechip),
				block:truncate(cur_blockpagechip>>16),
				page:truncate(cur_blockpagechip>>8)
				});
		end
/*
		end else if ( conf == 1 ) begin
		end
*/
	endrule

/// Start relay flash event
	Merge2Ifc#(Bit#(16)) mFlashEvent <- mkMerge2;
	rule flashEvent;
		let evt <- flashman.fevent;
		Bit#(8) tag = tpl_1(evt);
		FlashStatus stat = tpl_2(evt);
		Bit#(16) data = 0;
		case (stat)
			STATE_WRITE_DONE: data = {tag, 8'h1};
			STATE_ERASE_DONE: data = {tag, 8'h2};
			STATE_ERASE_FAIL: data = {tag, 8'h3};
			STATE_WRITE_READY: data = {tag, 8'h4};
		endcase

		if ( stat == STATE_WRITE_READY ) begin
			writeTagsQ.enq(tag);
			//writeTagsRQ.enq(tag);
			mFlashEvent.enq[0].enq(data);
		end else begin
			mFlashEvent.enq[0].enq(data);
		end
	endrule
	Merge4Ifc#(Bit#(8)) m4dma <- mkMerge4;
	rule getReadDone;
		m4dma.deq;
		mFlashEvent.enq[1].enq({m4dma.first, 0});
	endrule

	Reg#(Bit#(128)) flashEventBuf <- mkReg(~0);
	Reg#(Bit#(16)) flashEventCnt <- mkReg(0);
	
	FIFOF#(Tuple2#(Bit#(32), Bit#(128))) fevQ <- mkFIFOF;
	(* descending_urgency = "flashEventCache, flashEventSend" *)
	rule flashEventCache (!fevQ.notFull && flashEventCnt < 7);
		mFlashEvent.deq;
		Bit#(16) dat = mFlashEvent.first;
		flashEventCnt <= flashEventCnt + 1;
		flashEventBuf <= (flashEventBuf<<16) | zeroExtend(dat);
	endrule
	rule flashEventSend(fevQ.notFull);// && flashEventCnt > 0);
		if ( flashEventCnt > 0 ) begin
			flashEventCnt <= 0;
			flashEventBuf <= ~0;
			//m0.enq[0].enq(tuple2(0,flashEventBuf));
			fevQ.enq(tuple2(0,flashEventBuf));
		end
		else begin
			mFlashEvent.deq;
			Bit#(16) dat = mFlashEvent.first;
			fevQ.enq(tuple2(0,(flashEventBuf<<16)|zeroExtend(dat)));
		end
	endrule
	rule sendFev;
		fevQ.deq;
		m0.enq[0].enq(fevQ.first);
	endrule



////// Start read from flash
	Vector#(2,Vector#(BusCount, FIFO#(Tuple2#(Bit#(512), Bit#(8))))) pageReadWQ <- replicateM(replicateM(mkSizedBRAMFIFO(128*2))); // 2 pages per bus
	Merge2Ifc#(Bit#(4)) mBurst <- mkMerge2;
	for ( Integer i = 0; i < 2; i=i+1 ) begin
		FIFO#(Tuple2#(Bit#(8), Bit#(128))) flashReadQ <- mkSizedFIFO(8);
		Vector#(BusCount, FIFO#(Tuple2#(Bit#(128), Bit#(8)))) pageReadQ <- replicateM(mkSizedFIFO(8));
		Vector#(BusCount, Reg#(Bit#(16))) busReadCnt <- replicateM(mkReg(0));

		rule readDataFromFlash1;
			let taggedRdata <- flashman.ifc[i].readWord();
			flashReadQ.enq(taggedRdata);
		endrule

		rule relayBusData;
			flashReadQ.deq;
			let d = flashReadQ.first;

			let tag = tpl_1(d);
			let data = tpl_2(d);
			Bit#(3) busid = tag[6:4];
			
			let curcnt = busReadCnt[busid];
			if ( curcnt < 8192/16 ) begin
				pageReadQ[busid].enq(tuple2(data,tag));
			
				busReadCnt[busid] <= curcnt+1;
			end else if ( curcnt < (8192+32)/16 -1 ) begin
				busReadCnt[busid] <= curcnt+1;
			end else if ( curcnt >= (8192+32)/16 -1 ) begin
				busReadCnt[busid] <= 0;

				mBurst.enq[i].enq(zeroExtend(busid)|fromInteger(i)<<3);
			end
		endrule

		for ( Integer j = 0; j < busCount; j=j+1 ) begin
			Reg#(Bit#(512)) desreg <- mkReg(0);
			Reg#(Bit#(2)) descnt <- mkReg(0);
			//Reg#(Bit#(16)) dramWriteByteOff <- mkReg(0);
			rule desread;
				let d = pageReadQ[j].first;
				pageReadQ[j].deq;
				let tag = tpl_2(d);

				if ( descnt >= 3 ) begin
					descnt <= 0;
					let data = (desreg<<128)|zeroExtend(tpl_1(d));

					pageReadWQ[i][j].enq(tuple2(data, tag));

				end else begin
					descnt <= descnt + 1;
					desreg <= (desreg<<128)|zeroExtend(tpl_1(d));
				end
			endrule
		end
	end
	Reg#(Bit#(8)) writeBurstCnt <- mkReg(0);
	Reg#(Bit#(4)) writeBurstBus <- mkReg(0);
	Reg#(Bit#(16)) writeByteOff <- mkReg(0);
	rule startWriteDRAMPage( writeBurstCnt == 0 );
		mBurst.deq;
		let bid = mBurst.first;
		writeBurstCnt <= 128;//8192/64;
		writeBurstBus <= bid;
		writeByteOff <= 0;
	endrule

	rule writeDRAMPage(writeBurstCnt > 0);
		writeBurstCnt <= writeBurstCnt - 1;
		let ii = writeBurstBus[3];
		let ji = writeBurstBus[2:0];
		pageReadWQ[ii][ji].deq;
		let d = pageReadWQ[ii][ji].first;
		let tag = tpl_2(d);
		let data = tpl_1(d);
		Bit#(64) addr = (zeroExtend(tag)<<13)|zeroExtend(writeByteOff);
		writeByteOff <= writeByteOff + 64;

		drama.users[0].write(addr, data, 64);

		if ( writeBurstCnt == 1 ) begin
			tdreorder.tagReady(tag);
		end
	endrule
	

	Vector#(DestCount, PageFIFOIfc) pfifov;
	Vector#(DestCount, FIFO#(Bit#(8))) dtagfifov;
	MergeNIfc#(DestCount,Bit#(8)) mpreq <- mkMergeN;
	for ( Integer i = 0; i < destCount; i=i+1 ) begin
		pfifov[i] <- mkPageFIFO(1);
		dtagfifov[i] <- mkSizedFIFO(256);
		rule relayreq;
			let d <- pfifov[i].req;
			mpreq.enq[i].enq(fromInteger(i));
		endrule
	end
	rule senddestready;
		mpreq.deq;
		tdreorder.destReady(mpreq.first);
	endrule
	
	Reg#(Bit#(8)) orderedReadCount <- mkReg(0);
	Reg#(Bit#(8)) orderedReadReadyTag <- mkReg(0);
	Reg#(Bit#(16)) readByteOff <- mkReg(0);
	Reg#(Bit#(8)) readDest <- mkReg(0);
	rule setReadReady ( orderedReadCount == 0 );
		let t <- tdreorder.tagDestReady;
		orderedReadReadyTag <= tpl_1(t);
		readDest <= tpl_2(t);

		orderedReadCount <= 128;
		readByteOff <= 0;

		$display( "Tag %d ready for dest %d", tpl_1(t), tpl_2(t) );
	endrule

	FIFO#(Bit#(8)) dataWordDestQ <- mkSizedFIFO(64);
	FIFO#(Bit#(8)) dataWordTagQ <- mkSizedFIFO(64);
	
	rule readOrdDRAMReq( orderedReadCount > 0 );
		Bit#(64) addr = (zeroExtend(orderedReadReadyTag)<<13|zeroExtend(readByteOff));
		orderedReadCount <= orderedReadCount - 1;
		readByteOff <= readByteOff + 64;
		
		drama.users[0].readReq(addr, 64);
		dataWordDestQ.enq(readDest);
		dataWordTagQ.enq(orderedReadReadyTag);
		if ( orderedReadCount == 1 ) begin
			m4dma.enq[0].enq(orderedReadReadyTag);
			$display( "Done reading %d", orderedReadReadyTag );
		end
	endrule

	FIFO#(Bit#(512)) dramReadQ <- mkFIFO;
	rule readOrdDRAMData;
		let d <- drama.users[0].read;
		dramReadQ.enq(d);
	endrule
	FIFO#(Bit#(512)) hostDestQ <- mkFIFO;
	rule relayDRAMData;
		dramReadQ.deq;
		dataWordDestQ.deq;
		dataWordTagQ.deq;
		let d = dramReadQ.first;
		let dst = dataWordDestQ.first;
		let tag = dataWordTagQ.first;
		if ( dst < fromInteger(destCount) ) begin
			pfifov[dst].enq(d);
			dtagfifov[dst].enq(tag);
		end
	endrule




////// Start Accelerators
	Vector#(AccelCount, AcceleratorReaderIfc) accelv;
	//accelv[0] <- mkTiledSparseMatrixAccel(drama.users[1]);
	accelv[0] <- mkNullAcceleratorReader;
	
	accelv[1] <- mkDocDistAccel;
	//accelv[1] <- mkTiledSparseMatrixAccel(drama.users[2]);
	accelv[2] <- mkDRAMWriterAccel(drama.users[3]);
	/*
	//accelv[2] <- mkSparseCoreAccel;
	accelv[0] <- mkNullAcceleratorReader;
	accelv[1] <- mkCosineCoreAccel;
	accelv[2] <- mkCosineCoreAccel;
	*/

	rule relayAccelCmd;
		accelCmdQ.deq;
		let d = accelCmdQ.first;
		let header = tpl_1(d);
		let data = tpl_2(d);
		Bit#(16) target = truncate(header);
		accelv[target-1].cmdIn(header,data);
	endrule
	MergeNIfc#(AccelCount, Tuple2#(Bit#(32),Bit#(128))) mAccelRes <- mkMergeN;
	for ( Integer _aidx = 0; _aidx < accelCount; _aidx = _aidx+1 ) begin
		Integer aidx = _aidx + 1;
		rule relayDataIn;
			//$display ( "Accel %d received data", _aidx );
			pfifov[aidx].deq;
			dtagfifov[aidx].deq;
			accelv[_aidx].dataIn(pfifov[aidx].first);
		endrule
		rule relayResOut;
			let r <- accelv[_aidx].resOut;
			mAccelRes.enq[_aidx].enq(tuple2(fromInteger(aidx), r));
		endrule
	end
	rule sendAccelRes;
		let d = mAccelRes.first;
		mAccelRes.deq;
		m0.enq[1].enq(tuple2(tpl_1(d),tpl_2(d)));
	endrule


////// Start DMA to Host DRAM
	Reg#(Bit#(4)) splitCounter <- mkReg(0);
	Reg#(Bit#(4)) dmaEngineDest <- mkReg(0);
	Vector#(DMAEngineCount, FIFO#(Bit#(512))) dmaSplitQ <- replicateM(mkFIFO);
	Vector#(DMAEngineCount, FIFO#(Bit#(8))) dmaSplitTagQ <- replicateM(mkFIFO);
	rule relayHostDest;
		pfifov[0].deq;
		dtagfifov[0].deq;
		let d = pfifov[0].first;
		let t = dtagfifov[0].first;

		dmaSplitQ[dmaEngineDest].enq(d);
		dmaSplitTagQ[dmaEngineDest].enq(t);

		if ( splitCounter >= 1 ) begin
			splitCounter <= 0;
			if ( dmaEngineDest +1 >= fromInteger(dmaEngineCount) ) begin
				dmaEngineDest <= 0;
			end else begin
				dmaEngineDest <= dmaEngineDest+1;
			end
		end else begin
			splitCounter <= splitCounter + 1;
		end
	endrule
	for ( Integer i = 0; i < dmaEngineCount; i=i+1 ) begin
		FIFO#(Bit#(128)) dmaOutQ <- mkSizedFIFO(16);
		FIFO#(Bit#(8)) dmaOutTagQ <- mkSizedFIFO(16);

		Reg#(Bit#(8)) dmaSplitCnt <- mkReg(0);
		Reg#(Bit#(512)) dmaSplitBuf <- mkReg(0);
		Reg#(Bit#(8)) dmaOutTag <- mkReg(0);
		rule serializeSplit;
			if ( dmaSplitCnt == 0 ) begin
				dmaSplitQ[i].deq;
				let d = dmaSplitQ[i].first;
				dmaSplitTagQ[i].deq;
				let t = dmaSplitTagQ[i].first;

				dmaOutQ.enq(d[511:384]);
				dmaOutTagQ.enq(t);

				dmaSplitBuf <= (d<<128);
				dmaOutTag <= t;
				dmaSplitCnt <= 3;
			end else begin
				dmaSplitCnt <= dmaSplitCnt - 1;
				dmaOutQ.enq(dmaSplitBuf[511:384]);
				dmaOutTagQ.enq(dmaOutTag);
				dmaSplitBuf <= (dmaSplitBuf<<128);
			end
		endrule
		Reg#(Bit#(32)) dmaOffset <- mkReg(128*fromInteger(i));
		Reg#(Bit#(32)) dmaWordCnt <- mkReg(0);
		Reg#(Bit#(5)) wtag <- mkReg(0);
		rule dmaWrite;
			dmaOutQ.deq;
			dmaOutTagQ.deq;

			let d = dmaOutQ.first;
			let t = dmaOutTagQ.first;

			if ( dmaWordCnt[2:0] == 3'b111 ) begin
				//Bit#(32) dmao = zeroExtend(dmaOffset[20:0]); // 8K*256
				Bit#(32) dmao = zeroExtend(dmaOffset[12:0]) + 8192*zeroExtend(t); // 8K
				dma.users[i].dmaWriteReq(dmao, 8, 0); // tag is actually irrelevant in writes...
				//dma.users[i].dmaWriteReq(dmao, 8, (zeroExtend(wtag)|(fromInteger(i)<<5))); // tag is actually irrelevant in writes...
				wtag <= wtag + 1;
				dmaOffset <= dmaOffset + fromInteger(128*dmaEngineCount);
			end
			dma.users[i].dmaWriteData(d, 0); // tag is actually irrelevant in writes...
			dmaWordCnt <= dmaWordCnt + 1;
		endrule
	end



endmodule
