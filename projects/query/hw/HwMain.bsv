import FIFO::*;
import FIFOF::*;
import Clocks::*;
import Vector::*;

import ColumnFilter::*;
import Serializer::*;
import BurstIOArbiter::*;
import PageSortToDram::*;

import PageSorterSingle::*;
import SortingNetwork::*;
import SortingNetworkN::*;
import MergeSortReducerSingle::*;

import BRAM::*;
import BRAMFIFO::*;

import PcieCtrl::*;
import DRAMController::*;

import ControllerTypes::*;
import FlashCtrlVirtex1::*;
import DualFlashManagerBurst::*;

import QueryProc::*;


interface HwMainIfc;
endinterface

module mkHwMain#(PcieUserIfc pcie, DRAMUserIfc dram, Vector#(2,FlashCtrlUser) flashes) 
	(HwMainIfc);

	Clock curClk <- exposeCurrentClock;
	Reset curRst <- exposeCurrentReset;

	Clock pcieclk = pcie.user_clk;
	Reset pcierst = pcie.user_rst;

	//DualFlashManagerBurstIfc flashman <- mkDualFlashManagerBurst(flashes, 128); // 128 bytes for PCIe bursts
	DualFlashManagerBurstIfc flashman <- mkDualFlashManagerBurst(flashes, 8192); // page-size bursts

	BRAM2Port#(Bit#(14), Bit#(32)) pageBuffer <- mkBRAM2Server(defaultValue); // 8KB*8 = 64 KB

	Reg#(Bit#(32)) cycles <- mkReg(0);
	rule countCycle;
		cycles <= cycles + 1;
	endrule


	////////////// Flash event management start //////////////////////////////////////////////
	FIFOF#(Bit#(32)) feventQ <- mkSizedFIFOF(32);
	Reg#(Bit#(16)) writeWordLeft <- mkReg(0);
	rule flashStats ( writeWordLeft == 0 );
		let stat <- flashman.fevent;
		if ( stat.code == STATE_WRITE_READY ) begin
			writeWordLeft <= (8192/4); // 32 bits
			$display( "Write request!" );
		end else begin
			//ignore for now
			Bit#(8) code = zeroExtend(pack(stat.code));
			Bit#(8) tag = stat.tag;
			feventQ.enq(zeroExtend({code,tag}));
		end
	endrule
	////// Flash write from buffer...
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


	//////// DRAM Arbiter management //////////////////////////////////////////
	BurstIOArbiterIfc#(4,Bit#(512)) dramArbiter <- mkBurstIOArbiter;
	Reg#(Bit#(32)) curDRAMBurstOffset <- mkReg(0);
	Reg#(Bit#(16)) curDRAMBurstLeft <- mkReg(0);
	Reg#(Bool) curDRAMBurstWrite <- mkReg(False);
	rule relayBurstReq ( curDRAMBurstLeft == 0 );
		let r <- dramArbiter.getBurstReq;
		curDRAMBurstWrite <= tpl_1(r);
		curDRAMBurstOffset <= tpl_2(r);
		curDRAMBurstLeft <= tpl_3(r);
	endrule
	rule sendDRAMCmd(curDRAMBurstLeft > 0);
		let d <- dramArbiter.getData;

		curDRAMBurstLeft <= curDRAMBurstLeft - 1;
		curDRAMBurstOffset <= curDRAMBurstOffset + 1;
		if ( curDRAMBurstWrite ) begin
			dram.write(zeroExtend(curDRAMBurstOffset)*64, d, 64);
		end else begin
			dram.readReq(zeroExtend(curDRAMBurstOffset)*64, 64);
		end
	endrule
	rule relayDRAMRead;
		let d <- dram.read;
		dramArbiter.putData(d);
	endrule

	QueryProcIfc queryproc <- mkQueryProc;
	PageSortToDramIfc pagesorter <- mkPageSortToDram;



	
	/// Get queryproc results -> DRAM /////////////////////////////

	rule getqres;
		let kv <- queryproc.processedElement;
		pagesorter.put(tpl_1(kv), tpl_2(kv));
	endrule

	rule getPageSorterBurstReq;
		let b <- pagesorter.dramReq;
		if ( tpl_1(b)) begin  // write
			dramArbiter.eps[1].burstWrite(tpl_2(b), tpl_3(b));
		end else begin
			dramArbiter.eps[2].burstRead(tpl_2(b), tpl_3(b));
		end
	endrule
	rule relayPageSorterDRAMWrite;
		let d <- pagesorter.dramWriteData;
		dramArbiter.eps[1].putData(d);
	endrule

	/// Flash Read /////////////////////////////////////////
	Reg#(Bit#(1)) curWriteTarget <- mkReg(0);
	rule relayFlashWrite;
		let wd <- des.get;
		flashman.writeWord(wd);
	endrule

	DeSerializerIfc#(256,2) flashDes <- mkDeSerializer;
	FIFO#(Bit#(8)) flashDesTag <- mkStreamSkip(2,0);
	rule readFlashData;
		let taggedData <- flashman.readWord;
		queryproc.flashData(tpl_1(taggedData),tpl_2(taggedData));
	endrule



	/// QueryProc DRAM 
	rule getFilterBurstReq;
		let b <- queryproc.dramReq; // write? offset, cnt
		//Tuple3#(Bool,Bit#(32),Bit#(16)) b <- queryproc.dramReq; // write? offset, cnt
		if ( tpl_1(b)) begin  // write
			dramArbiter.eps[0].burstWrite(tpl_2(b), tpl_3(b));
		end else begin
			dramArbiter.eps[0].burstRead(tpl_2(b), tpl_3(b));
		end
	endrule
	rule relayFilterBurstData;
		let d <- queryproc.dramWriteData;
		dramArbiter.eps[0].putData(d);
	endrule
	rule relayFilterDRAMRead;
		let d <- dramArbiter.eps[0].getData;
		queryproc.dramReadData(d);
	endrule

	


	/////////////////////////// PCIe clock crossing start ////////////////////////////////

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

	
	FIFO#(Tuple2#(Bit#(32),Bit#(32))) cmdQ1 <- mkSizedFIFO(16);
	FIFO#(Tuple2#(Bit#(32),Bit#(32))) cmdQ2 <- mkFIFO;

	rule procQueryCmd;
		let d_ = cmdQ2.first;
		cmdQ2.deq;
		let off = tpl_1(d_);
		let d = tpl_2(d_);
	endrule
	rule procFlashCmd;
		let d_ = cmdQ1.first;
		cmdQ1.deq;
		let off = tpl_1(d_);
		let d = tpl_2(d_);

		Bit#(4) target = truncate(off);
		if ( target == 0 ) begin // flash
			Bit#(2) fcmd = truncate(off>>4);
			Bit#(8) tag = truncate(off>>8);
			QidType qidx = truncate(off>>16); // only for reads, for now

			if ( fcmd == 0 ) begin
				flashman.readPage(tag,d);
				// tag -> qidx map
				queryproc.setTagQid(tag,qidx);
			end else if ( fcmd == 1 ) flashman.writePage(tag,d);
			else flashman.eraseBlock(tag,d);
		end else cmdQ2.enq(d_);
	endrule


	rule getCmd;
		pcieWriteQ.deq;
		let w = pcieWriteQ.first;

		let a = w.addr;
		let d = w.data;
		let off = (a>>2);
		Bit#(4) target = truncate(off);
		if ( target == 1 ) begin // i/o buffer
			let boff = truncate(off>>4);
			pageBuffer.portA.request.put(
				BRAMRequest{
				write:True,
				responseOnWrite:False,
				address:truncate(off>>4),
				datain:d
				}
			);
		end else cmdQ1.enq(tuple2(zeroExtend(off),d));
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
		end else if ( offset == 16384 && feventQ.notEmpty ) begin
			feventQ.deq;
			pcieRespQ.enq(tuple2(r,feventQ.first));
		end else begin
			pcieRespQ.enq(tuple2(r,32'hffffffff));
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
