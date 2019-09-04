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
import DualFlashManagerBurst::*;

import SubString::*;

interface HwMainIfc;
endinterface

module mkHwMain#(PcieUserIfc pcie, DRAMUserIfc dram, Vector#(2,FlashCtrlUser) flashes) 
	(HwMainIfc);

	Clock curClk <- exposeCurrentClock;
	Reset curRst <- exposeCurrentReset;

	Clock pcieclk = pcie.user_clk;
	Reset pcierst = pcie.user_rst;

	DualFlashManagerBurstIfc flashman <- mkDualFlashManagerBurst(flashes, 128); // 128 bytes for PCIe bursts

	BRAM2Port#(Bit#(14), Bit#(32)) pageBuffer <- mkBRAM2Server(defaultValue); // 8KB*8 = 64 KB

	Reg#(Bit#(32)) cycles <- mkReg(0);
	rule countCycle;
		cycles <= cycles + 1;
	endrule


	FIFO#(Bit#(64)) stringQ <- mkSizedBRAMFIFO(2048);
	//SubStringFindAlignedIfc#(8) sfa <- mkSubStringFindAligned;
	SubStringFindAlignedIfc#(8) sfa <- mkSubStringFindAligned8;
	DeSerializerIfc#(32,2) stringDes <- mkDeSerializer;
	Reg#(Bit#(32)) stringInCnt <- mkReg(0);
	rule loadStringQ;
		let d <- stringDes.get;
		stringQ.enq(d);
		stringInCnt <= stringInCnt + 1;

		if ( stringInCnt == 0 ) sfa.queryString(64'h6f6c6c6568); // 'hello'
	endrule


	Reg#(Bit#(32)) stringOutCnt <- mkReg(0);
	rule relayStringMatch (stringInCnt >= 1024 && stringOutCnt < 1024);
		stringOutCnt <= stringOutCnt + 1;
		stringQ.deq;
		sfa.dataString(stringQ.first, (stringOutCnt == 1024-1)?True:False);
		if ( stringOutCnt == 1024-1 ) $display( "Enqueueing last");
	endrule

	Reg#(Bit#(32)) strCount <- mkReg(0);
	rule getMatchOut;
		let r_ <- sfa.found;
		if ( tpl_1(r_) ) begin
			$display( "Processing done %d", cycles );
		end
		if ( isValid(tpl_2(r_)) ) begin
			let r = fromMaybe(?,tpl_2(r_));
			if ( r ) begin
				$display( "%d String found %d", strCount, cycles );
			end else begin
				$display( "%d String not found %d", strCount, cycles );
			end
			strCount <= strCount + 1;
		end
	endrule



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
		flashman.writeWord(wd);
	endrule

	SerializerIfc#(256,8) ser <- mkSerializer;
	FIFO#(Bit#(8)) reptag <- mkStreamReplicate(8);
	Reg#(Bit#(32)) readWords <- mkReg(0);
	rule readFlashData;
		let taggedData <- flashman.readWord;
		readWords <= readWords + 1;

		//ser.put(tpl_1(taggedData));
		//reptag.enq(tpl_2(taggedData));
	endrule
	Vector#(8,Reg#(Bit#(16))) bramWriteOff <- replicateM(mkReg(0));
	rule relayFlashRead;
		let d <- ser.get;

		reptag.deq;
		let tag = reptag.first;
		
		if ( bramWriteOff[tag] + 1 >= (8192/4) ) begin
			bramWriteOff[tag] <= 0;
		end else begin
			bramWriteOff[tag] <= bramWriteOff[tag] + 1;
		end

		$display ( "Writing %x to BRAM %d", d, bramWriteOff[tag] );

		pageBuffer.portA.request.put(
			BRAMRequest{
			write:True,
			responseOnWrite:False,
			address:truncate(bramWriteOff[tag])+zeroExtend(tag)*(8192/4),
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

		if ( (off>>16) == 1 ) begin // command
			Bit#(2) cmd = truncate(off);
			Bit#(8) tag = truncate(off>>8);

			if ( cmd == 0 ) flashman.readPage(tag, d);
			else if ( cmd == 1 ) flashman.writePage(tag,d);
			else flashman.eraseBlock(tag,d);
		end else if ( (off>>16) == 2 ) begin // other stuff
			stringDes.put(d);
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
		end else if ( offset == 16384 && feventQ.notEmpty ) begin
			feventQ.deq;
			pcieRespQ.enq(tuple2(r,feventQ.first));
		end else begin
			pcieRespQ.enq(tuple2(r,readWords));
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
