import FIFO::*;
import FIFOF::*;
import Clocks::*;
import Vector::*;
import Connectable::*;

import Serializer::*;

import BRAM::*;
import BRAMFIFO::*;

import PcieCtrl::*;
import DRAMController::*;

import FlashManagerCommon::*;
import ControllerTypes::*;
//import FlashCtrlVirtex1::*;
import DualFlashManagerOrdered::*;

interface HwMainIfc;
endinterface

typedef 64 UserTagCnt;

module mkHwMain#(PcieUserIfc pcie, DRAMUserIfc dram, Vector#(2,FlashCtrlUser) flashes) 
	(HwMainIfc);

	Clock curClk <- exposeCurrentClock;
	Reset curRst <- exposeCurrentReset;

	Clock pcieclk = pcie.user_clk;
	Reset pcierst = pcie.user_rst;

	DualFlashManagerOrderedIfc flashuser <- mkDualFlashManagerOrdered(flashes); 

	BRAM2Port#(Bit#(14), Bit#(32)) pageBuffer <- mkBRAM2Server(defaultValue); // 8KB*8 = 64 KB


	FIFOF#(Bit#(32)) eraseDoneQ <- mkFIFOF;
	Reg#(Bit#(16)) writeWordLeft <- mkReg(0);
	rule flashStats;// ( writeWordLeft == 0 );
		let stat <- flashuser.doneStat;
		if ( stat.code == ERASE_DONE ) begin
			$display( "ERASE DONE @ %x", stat.addr );
			eraseDoneQ.enq({1'b0,truncate(stat.addr)});
		end else if (stat.code == ERASE_ERROR) begin
			$display( "ERASE ERROR @ %x", stat.addr );
			eraseDoneQ.enq({1'b1,truncate(stat.addr)});
		end
	endrule
	rule reqBufferRead (writeWordLeft > 0);
		writeWordLeft <= writeWordLeft - 1;

		pageBuffer.portA.request.put(
			BRAMRequest{
			write:False, responseOnWrite:False,
			address:truncate(fromInteger(512*4)-writeWordLeft),
			datain:?
			}
		);
	endrule
	DeSerializerIfc#(32, 8) des <- mkDeSerializer;
	rule relayBRAMRead;
		let v <- pageBuffer.portA.response.get();
		des.put(v);
	endrule

	Reg#(Bit#(1)) curWriteTarget <- mkReg(0);
	rule relayFlashWrite;
		let wd <- des.get;
		flashuser.writeWord(wd);
	endrule

	SerializerIfc#(256,8) ser <- mkSerializer;
	Reg#(Bit#(32)) readWords <- mkReg(0);

	Reg#(Bit#(256)) readBuffer <- mkReg(0);
	rule readFlashData;
		Bit#(256) word <- flashuser.readWord;
		readWords <= readWords + 1;
		readBuffer <= word;
		ser.put(word);
	endrule
	Reg#(Bit#(16)) bramWriteOff <- mkReg(0);
	rule relayFlashRead;
		let d <- ser.get;

		bramWriteOff <= bramWriteOff + 1;

		$display ( "Writing %x to BRAM %d", d, bramWriteOff );

		pageBuffer.portA.request.put(
			BRAMRequest{
			write:True,
			responseOnWrite:False,
			address:truncate(bramWriteOff),
			datain:d
			}
		);
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

			if ( cmd == 0 ) flashuser.readPage(d);
			else if ( cmd == 1 ) flashuser.writePage(d);
			else flashuser.eraseBlock(d);
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


		let a = r.addr;
		let offset = (a>>2);
		if ( offset < (8192/4)*8 ) begin
			readReqQ.enq(r);
			pageBuffer.portB.request.put(
				BRAMRequest{
				write:False, responseOnWrite:False,
				address:truncate(offset),
				datain:?
				}
			);
		end else if ( offset == 16384 && eraseDoneQ.notEmpty ) begin
			eraseDoneQ.deq;
			pcieRespQ.enq(tuple2(r,eraseDoneQ.first));
		end else begin
			//pcieRespQ.enq(tuple2(r,readWords));
			pcieRespQ.enq(tuple2(r,truncate(readBuffer)));
			readBuffer <= readBuffer>>32;
		end
		//pcie.dataSend(r, truncate(dramReadVal>>noff));
	endrule
	rule returnStat;
		readReqQ.deq;
		let r = readReqQ.first;

		let v <- pageBuffer.portB.response.get();
		pcieRespQ.enq(tuple2(r,v));
	endrule


endmodule
