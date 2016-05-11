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

typedef 16 BusCount; // 8 per card in hw, 2 per card in sim
typedef 128 TagCount; // Has to be larger than the software setting

interface FlashBusDataIfc;
	method Action writeWord#(Bit#(8) tag, Bit#(128) word);
	method ActionValue#(Tuple2#(Bit#(8), Bit#(128))) readWord;
endinterface

typedef enum {
	STATE_NULL,
	STATE_WRITE_READY,
	STATE_WRITE_DONE,
	STATE_ERASE_DONE,
	STATE_ERASE_FAIL
} FlashStatus deriving (Bits, Eq);

typedef struct {
	Bit#(8) tag;
	FlashOp op;

	Bit#(4) bus;
	ChipT chip;
	Bit#(16) block;
	Bit#(8) page;
} FlashManagerCmd deriving (Bits, Eq);

interface DualFlashManagerIfc;
	method Action command(FlashManagerCmd cmd);
	method ActionValue#(Tuple2#(Bit#(8), FlashStatus)) flashEvent;
	Vector#(BusCount, FlashBusDataIfc) buses;
endinterface

module mkDualFlashManager#(Vector#(2,FlashCtrlUser) flashes) (DualFlashManagerIfc);

	Merge2#(Tuple2#(Bit#(8), FlashStatus)) mstat <- mkMerge2;
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
			mstat.enq[i].enq(tuple2(tag, stat));
		endrule
		rule writeReady;
			TagT tag <- flashes[i].writeDataReq;
			mstat.enq[i].enq(zeroExtend(tag), STATE_WRITE_READY);
		endrule
	end

	//Tag translation
	Vector#(BusCount, FIFO#(Tuple2#(Bit#(128),Bit#(8)))) dmaWriteQ <- replicateM(mkSizedFIFO#(32));

	Vector#(BusCount, FlashBuDatasIfc) buses_;
	for ( Integer i = 0; i < valueOf(BusCount); i=i+1 ) begin
		buses_[i] = interface FlashBusDataIfc;
			method Action writeWord#(Bit#(8) tag, Bit#(128) word);
			endmethod
			method ActionValue#(Tuple2#(Bit#(8), Bit#(128))) readWord;
				return ?;
			endmethod
		endinterface: FlashBusDataIfc;
	end

	method Action command(FlashManagerCmd cmd);
		if ( cmd.bus[0] == 0 ) begin
			flashes[0].sendCmd(FlashCmd{
				op:cur_flashop,
				tag:truncate(cmd.tag),
				bus: truncate(cmd.bus>>1),
				chip: cmd.chip,
				block:cmd.block,
				page:cmd.page
				});
		end else begin
			flashes[1].sendCmd(FlashCmd{
				op:cur_flashop,
				tag:truncate(cmd.tag),
				bus: truncate(cmd.bus>>1),
				chip: cmd.chip,
				block:cmd.block,
				page:cmd.page
				});
		end
	endmethod
	method ActionValue#(Tuple2#(Bit#(8), FlashStatus)) flashEvent;
		mstat.deq;
		return mstat.first;
	endmethod
	interface buses = buses_;
endmodule
