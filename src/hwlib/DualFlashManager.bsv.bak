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

import DRAMArbiter::*;

/**
IMPORTANT: tags need to be encoded in a certain way now:
tag[0] board
tag[3:1] bus
tag[~7:4] tag
**/

typedef 8 BusCount; // 8 per card in hw, 2 per card in sim
typedef TMul#(2,BusCount) BBusCount; //Board*bus
typedef 128 TagCount;

typedef enum {
	STATE_NULL,
	STATE_WRITE_READY,
	STATE_WRITE_DONE,
	STATE_ERASE_DONE,
	STATE_ERASE_FAIL
} FlashStatus deriving (Bits, Eq);

typedef struct {
	FlashOp op;
	
	Bit#(8) tag;

	Bit#(4) bus;
	ChipT chip; //Bit#(3)
	Bit#(16) block;
	Bit#(8) page;
} FlashManagerCmd deriving (Bits, Eq);

function FlashManagerCmd decodeCommand(Bit#(64) code);
	Bit#(4) opcode = code[3:0];
	Bit#(4) bbus = code[7:4];
	Bit#(8) tag = code[15:8];
	Bit#(16) block = code[31:16];

	Bit#(8) page = code[39:32];
	ChipT chip = truncate(code>>40);
	let cur_flashop = ERASE_BLOCK;
	if ( opcode == 0 ) begin
		cur_flashop = ERASE_BLOCK;
	end else if ( opcode == 1 ) begin
		cur_flashop = READ_PAGE;
	end else if ( opcode == 2 ) begin
		cur_flashop = WRITE_PAGE;
	end

	return FlashManagerCmd{
		op:cur_flashop,
		tag:tag,
		bus:bbus,
		chip:chip,
		block:block,
		page:page
	};
endfunction

interface DualFlashManagerIfc;
	method Action command(FlashManagerCmd cmd);
	method ActionValue#(Tuple2#(Bit#(8), FlashStatus)) fevent;
	method ActionValue#(Tuple2#(Bit#(8), Bit#(512))) readWord;
	method Action writeWord(Bit#(8) tag, Bit#(512) data);
endinterface

module mkDualFlashManager#(Vector#(2,FlashCtrlUser) flashes) (DualFlashManagerIfc);
	

	Merge2Ifc#(Tuple2#(Bit#(8), FlashStatus)) mstat <- mkMerge2;
	for (Integer i = 0; i < 2; i=i+1 ) begin
		(* descending_urgency = "flashAck, writeReady" *)
		rule flashAck;
			let ackStatus <- flashes[i].ackStatus();
			Bit#(8) tag = zeroExtend(tpl_1(ackStatus));
			StatusT status = tpl_2(ackStatus);
			FlashStatus stat = STATE_NULL;
			case (status) 
				WRITE_DONE: stat = STATE_WRITE_DONE;
				ERASE_DONE: stat = STATE_ERASE_DONE;
				ERASE_ERROR: stat = STATE_ERASE_FAIL;
			endcase
			Bit#(8) mask = (fromInteger(i));
			mstat.enq[i].enq(tuple2((tag<<1)|mask, stat));
		endrule
		rule writeReady;
			TagT tag <- flashes[i].writeDataReq;
			Bit#(8) mask = (fromInteger(i));
			Bit#(8) ntag = (zeroExtend(tag)<<1)|mask;
			mstat.enq[i].enq(tuple2(ntag, STATE_WRITE_READY));
		endrule
	end
	

	Merge2Ifc#(Tuple2#(Bit#(8), Bit#(512))) collectedm2 <- mkMerge2;
	for ( Integer i = 0; i < 2; i=i+1 ) begin
		Vector#(BusCount, FIFO#(Tuple2#(Bit#(128), Bit#(8)))) pageReadQ <- replicateM(mkSizedFIFO(8));
		MergeNIfc#(BusCount, Tuple2#(Bit#(8), Bit#(512))) collectedm <- mkMergeN;
		rule readFlash;
			let d <- flashes[i].readWord;
			let tag = tpl_2(d);
			Bit#(3) bus = truncate(tag);
			pageReadQ[bus].enq(tuple2(tpl_1(d), zeroExtend(tag)));
		endrule

		for ( Integer j = 0; j < valueOf(BusCount); j=j+1 ) begin
			Reg#(Bit#(2)) busCollectCount <- mkReg(0);
			Reg#(Bit#(512)) busCollectBuffer <- mkReg(0);
			rule busCollect;
				pageReadQ[j].deq;
				let d = pageReadQ[j].first;

				if ( busCollectCount >= 3 ) begin
					busCollectCount <= 0;
					let data = (busCollectBuffer<<128)|zeroExtend(tpl_1(d));
					collectedm.enq[j].enq(tuple2(tpl_2(d), data));
				end else begin
					busCollectCount <= busCollectCount + 1;
					busCollectBuffer <= (busCollectBuffer<<128)|zeroExtend(tpl_1(d));
				end
			endrule
		end

		rule collectBusReads;
			collectedm.deq;
			let d = collectedm.first;
			collectedm2.enq[i].enq(d);
		endrule
	end
	
	// 14 = 7 + 7 (8K pages * 128 tags)
	BRAM2Port#(Bit#(14), Bit#(512)) reorderBuffer <- mkBRAM2Server(defaultValue); // 1MB
	Vector#(TagCount, Reg#(Bit#(8))) reorderWriteCount <- replicateM(mkReg(0));
	FIFO#(Bit#(8)) readReadyQ <- mkFIFO;
	rule writeReorder;
		let d = collectedm2.first;
		collectedm2.deq;
		let tag = tpl_1(d);
		let data = tpl_2(d);

		Bit#(14) writeOff = (zeroExtend(tag)<<7)|zeroExtend(reorderWriteCount[tag]);

		if ( reorderWriteCount[tag] >= 128 ) begin
			//reorderWriteCount <= 0;
			//readReadyQ.enq(tag);
		end else begin
			reorderWriteCount[tag] <= reorderWriteCount[tag] + 1;
		end

		reorderBuffer.portA.request.put( BRAMRequest{
			write:True, responseOnWrite: False,
			address: writeOff,
			datain: data
		});
	endrule
			
	FIFO#(Bit#(8)) pageReadOrderQ <- mkSizedFIFO(valueOf(TagCount));
	rule checkOrderReadDone;
		let curtag = pageReadOrderQ.first;
		if ( reorderWriteCount[curtag] >= 128 ) begin
			reorderWriteCount[curtag] <= 0;
			pageReadOrderQ.deq;
			readReadyQ.enq(curtag);
		end
	endrule

	Reg#(Bit#(7)) readReorderedCount <- mkReg(0);
	FIFO#(Bit#(8)) readReorderedTagQ <- mkSizedFIFO(8);
	rule readReordered;
		let curTag = readReadyQ.first;
		if ( readReorderedCount >= 127 ) begin
			readReadyQ.deq;
			readReorderedCount <= 0;
		end
		else begin
			readReorderedCount <= readReorderedCount + 1;
		end
		
		Bit#(14) readOff = (zeroExtend(curTag)<<7)|zeroExtend(readReorderedCount);

		reorderBuffer.portB.request.put( BRAMRequest{
			write:False, responseOnWrite: False,
			address: readOff, datain: ?
		});
		readReorderedTagQ.enq(curTag);
	endrule

	FIFO#(Tuple2#(Bit#(8),Bit#(128))) flashWriteSerQ <- mkFIFO;
	FIFO#(Tuple2#(Bit#(8),Bit#(512))) flashWriteQ <- mkFIFO;
	Reg#(Bit#(512)) flashWriteSerBuffer <- mkReg(0);
	Reg#(Bit#(2)) flashWriteSerCount <- mkReg(0);
	Reg#(Bit#(8)) flashWriteSerTag <- mkReg(0);
	rule serializeFlashWrite;
		if ( flashWriteSerCount == 0 ) begin
			let d = flashWriteQ.first;
			flashWriteQ.deq;
			flashWriteSerQ.enq(tuple2(tpl_1(d), truncate(tpl_2(d)>>(128*3))));

			flashWriteSerTag <= tpl_1(d);
			flashWriteSerBuffer <= (tpl_2(d)<<128);
			flashWriteSerCount <= 1;
		end else begin
			flashWriteSerQ.enq(tuple2(
				flashWriteSerTag, truncate(flashWriteSerBuffer>>(128*3))
			));
			flashWriteSerBuffer <= (flashWriteSerBuffer<<128);
			if ( flashWriteSerCount >= 3 ) begin
				flashWriteSerCount <= 0;
			end else begin
				flashWriteSerCount <= flashWriteSerCount + 1;
			end
		end
	endrule
	rule writeToFlash;
		let d = flashWriteSerQ.first;
		flashWriteSerQ.deq;

		let tag = tpl_1(d);
		let data = tpl_2(d);

		Bit#(1) board = tag[0];
		flashes[board].writeWord(tuple2(data, truncate(tag>>1)));
	endrule

	method ActionValue#(Tuple2#(Bit#(8), Bit#(512))) readWord;
		let v <- reorderBuffer.portB.response.get();
		let t = readReorderedTagQ.first;
		readReorderedTagQ.deq;
		return tuple2(t,v);
	endmethod
	method Action writeWord(Bit#(8) tag, Bit#(512) data);
		flashWriteQ.enq(tuple2(tag,data));
	endmethod

	method Action command(FlashManagerCmd cmd);
		Bit#(3) bus = truncate(cmd.bus);
		Bit#(7) tag = truncate(cmd.tag>>1);
		if ( cmd.op == READ_PAGE ) begin
			pageReadOrderQ.enq(cmd.tag);
		end

		if ( cmd.bus[3] == 0 ) begin // board(1), bus(3)
			flashes[0].sendCmd(FlashCmd{
				op:cmd.op,
				tag: tag,
				bus: bus,
				chip: cmd.chip,
				block:cmd.block,
				page:cmd.page
				});
		end else begin
			flashes[1].sendCmd(FlashCmd{
				op:cmd.op,
				tag: tag,
				bus: bus,
				chip: cmd.chip,
				block:cmd.block,
				page:cmd.page
				});
		end
	endmethod
	method ActionValue#(Tuple2#(Bit#(8), FlashStatus)) fevent;
		mstat.deq;
		return mstat.first;
	endmethod
endmodule
