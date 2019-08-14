import FIFO::*;
import FIFOF::*;
import Clocks::*;
import Vector::*;

import Serializer::*;

import BRAM::*;
import BRAMFIFO::*;

import PcieCtrl::*;
import DRAMController::*;

import ControllerTypes::*;
import FlashCtrlVirtex1::*;

interface HwMainIfc;
endinterface

module mkHwMain#(PcieUserIfc pcie, DRAMUserIfc dram, Vector#(2,FlashCtrlUser) flashes) 
	(HwMainIfc);

	Clock curClk <- exposeCurrentClock;
	Reset curRst <- exposeCurrentReset;

	Clock pcieclk = pcie.user_clk;
	Reset pcierst = pcie.user_rst;

	BRAM2Port#(Bit#(11), Bit#(32)) pageBuffer <- mkBRAM2Server(defaultValue); // 8KB

	FIFO#(Tuple2#(Bit#(1),FlashCmd)) flashCmdQ <- mkFIFO;


	rule sendFlashCmd;
		flashCmdQ.deq;
		let fcmd_ = flashCmdQ.first;
		
		flashes[tpl_1(fcmd_)].sendCmd(tpl_2(fcmd_));
	endrule

	Reg#(Bit#(1)) writeDst <- mkReg(0);
	Reg#(Bit#(16)) writeWordLeft <- mkReg(0);
	FIFO#(Bit#(1)) targetBoardQ <- mkSizedFIFO(8);
	rule writeReq1;
		TagT tag <- flashes[0].writeDataReq();
		writeDst <= 0;
		writeWordLeft <= 512*4; //32 bits
		targetBoardQ.enq(0);
	endrule
	rule writeReq2;
		TagT tag <- flashes[1].writeDataReq();
		writeDst <= 1;
		writeWordLeft <= 512*4; //32 bits
		targetBoardQ.enq(1);
	endrule
	rule reqBufferRead (writeWordLeft > 0);
		writeWordLeft <= writeWordLeft - 1;

		if ( writeWordLeft > 8 ) begin
			pageBuffer.portA.request.put(
				BRAMRequest{
				write:False, responseOnWrite:False,
				address:truncate(fromInteger(512*4)-writeWordLeft),
				datain:?
				}
			);
		end
	endrule
	DeSerializerIfc#(32, 4) des <- mkDeSerializer;
	rule relayBRAMRead;
		let v <- pageBuffer.portA.response.get();
		des.put(v);
	endrule
	Reg#(Bit#(16)) flashWriteOff <- mkReg(0);

	Reg#(Bit#(1)) curWriteTarget <- mkReg(0);
	rule relayFlashWrite;
		if ( flashWriteOff + 1 < 512 ) begin
			flashWriteOff <= flashWriteOff + 1;

			let wd <- des.get;

			Bit#(1) cwt = curWriteTarget;
			if ( flashWriteOff == 0 ) begin
				let t = targetBoardQ.first;
				targetBoardQ.deq;
				curWriteTarget <= t;
				cwt = t;
			end
			flashes[cwt].writeWord(tuple2(wd,0));

		end else if (flashWriteOff + 1 <= 514 ) begin
			if (flashWriteOff + 1 >= 514 ) flashWriteOff <= 0;
			else flashWriteOff <= flashWriteOff + 1;


			flashes[curWriteTarget].writeWord(tuple2(0,0));
		end
	endrule

	SerializerIfc#(128,4) ser <- mkSerializer;
	rule readFlashData1;
		let taggedRdata <- flashes[0].readWord();
		ser.put(tpl_1(taggedRdata));
	endrule
	rule readFlashData2;
		let taggedRdata <- flashes[1].readWord();
		ser.put(tpl_1(taggedRdata));
	endrule
	Reg#(Bit#(16)) bramWriteOff <- mkReg(0);
	rule relayFlashRead;
		bramWriteOff <= bramWriteOff + 1;
		let d <- ser.get;

		pageBuffer.portA.request.put(
			BRAMRequest{
			write:True,
			responseOnWrite:False,
			address:truncate(bramWriteOff),
			datain:d
			}
		);

	endrule

	rule getFlashAck0;
		let ackStatus <- flashes[0].ackStatus();
	endrule
	rule getFlashAck1;
		let ackStatus <- flashes[1].ackStatus();
	endrule


	SyncFIFOIfc#(Tuple2#(IOReadReq, Bit#(32))) pcieRespQ <- mkSyncFIFOFromCC(16,pcieclk);
	SyncFIFOIfc#(IOReadReq) pcieReadReqQ <- mkSyncFIFOToCC(16,pcieclk,pcierst);
	SyncFIFOIfc#(IOWrite) pcieWriteQ <- mkSyncFIFOToCC(16,pcieclk,pcierst);
	rule getWriteReq;
		let w <- pcie.dataReceive;
		pcieWriteQ.enq(w);
	endrule
	rule getReadReq;
		let r <- pcie.dataReq;
		pcieReadReqQ.enq(r);
	endrule
	rule returnReadResp;
		let r_ = pcieRespQ.first;
		pcieRespQ.deq;

		pcie.dataSend(tpl_1(r_), tpl_2(r_));
	endrule


	rule getCmd;
		pcieWriteQ.deq;
		let w = pcieWriteQ.first;

		let a = w.addr;
		let d = w.data;
		let off = (a>>2);

		if ( (off>>11) > 0 ) begin // command
			Bit#(2) cmd = truncate(off);
			Bit#(8) tag = truncate(off>>8);

			Bit#(8) page = truncate(d);
			Bit#(16) block = truncate(d>>8);
			Bit#(4) chip = truncate(d>>24);
			Bit#(3) bus = truncate(d>>28);
			Bit#(1) card = truncate(d>>31);

			FlashOp fcmd = READ_PAGE;
			if ( cmd == 1 ) fcmd = WRITE_PAGE;
			else if ( cmd == 2 ) fcmd = ERASE_BLOCK;
			
			//tag = 7b

			//bus = 3b
			//chip = 3b
			//block = 16b
			//page = 8b

			//FIXME now we have 16 busses (two cards)
			FlashCmd fcmdt = FlashCmd{
				tag: truncate(tag),
				op: fcmd,
				bus: truncate(bus),
				chip: truncate(chip),
				block: truncate(block),
				page: truncate(page)
				};
			flashCmdQ.enq(tuple2(card,fcmdt));
		end else begin //data
			pageBuffer.portA.request.put(
				BRAMRequest{
				write:True,
				responseOnWrite:False,
				address:truncate(off),
				datain:d
				}
			);
		end
	endrule

	
	FIFO#(IOReadReq) readReqQ <- mkFIFO;
	rule readStat;
		pcieReadReqQ.deq;
		let r = pcieReadReqQ.first;

		readReqQ.enq(r);

		let a = r.addr;
		let offset = (a>>2);
		pageBuffer.portB.request.put(
			BRAMRequest{
			write:False, responseOnWrite:False,
			address:truncate(offset),
			datain:?
			}
		);
		//pcie.dataSend(r, truncate(dramReadVal>>noff));
	endrule
	rule returnStat;
		readReqQ.deq;
		let r = readReqQ.first;

		let v <- pageBuffer.portB.response.get();
		pcieRespQ.enq(tuple2(r,v));
	endrule


endmodule
