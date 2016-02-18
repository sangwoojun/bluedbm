import FIFO::*;
import FIFOF::*;
import Clocks::*;
import Vector::*;

import BRAM::*;
import BRAMFIFO::*;

import MergeN::*;

import PcieCtrl::*;

import DMASplitter::*;

import AuroraImportFmc1::*;
import ControllerTypes::*;
import FlashCtrlVirtex::*;
import FlashCtrlModel::*;

typedef 8 BusCount; // 8 per card in hw, 2 per card in sim
typedef 64 TagCount; // Has to be larger than the software setting

interface HwMainIfc;
endinterface

module mkHwMain#(PcieUserIfc pcie, FlashCtrlUser flash, FlashManagerIfc flashMan) 
	(HwMainIfc);

	Clock curClk <- exposeCurrentClock;
	Reset curRst <- exposeCurrentReset;

	Clock pcieclk = pcie.user_clk;
	Reset pcierst = pcie.user_rst;

	Integer busCount = valueOf(BusCount);
	Integer tagCount = valueOf(TagCount);

	DMASplitterIfc#(4) dma <- mkDMASplitter(pcie);

	Merge2Ifc#(Bit#(128)) m0 <- mkMerge2;
	Merge2Ifc#(Bit#(32)) m4flash <- mkMerge2;

	FIFO#(FlashCmd) flashCmdQ <- mkFIFO;
	Reg#(Bit#(16)) flashCmdCount <- mkReg(0);
	Reg#(Bit#(16)) flashReadWords <- mkReg(0);
	Vector#(8, Reg#(Bit#(32))) writeBuf <- replicateM(mkReg(0));
	
	// 8'available 8'type 16'data
	// type: 0: readdone, 1: writedone 2: erasedone 3:erasefail 4: writeready
	FIFOF#(Bit#(32)) flashStatusQ <- mkFIFOF(clocked_by pcieclk, reset_by pcierst);
	Reg#(Bit#(8)) flashStatusIn <- mkReg(0);
	Reg#(Bit#(8)) flashStatusOut <- mkReg(0);
	FIFO#(Bit#(8)) writeTagsQ <- mkSizedBRAMFIFO(128);

	Reg#(Bit#(16)) flashWriteBytes <- mkReg(0);
	Reg#(Maybe#(Bit#(64))) flashWriteBuf <- mkReg(tagged Invalid);

	Vector#(TagCount,Reg#(Bit#(5))) tagBusMap <- replicateM(mkReg(0));
	Reg#(Bool) started <- mkReg(False);

	rule senddmaenq;
		m0.deq;
		dma.enq(m0.first);
	endrule
	rule flushm4flash;
		m4flash.deq;
		m0.enq[0].enq(zeroExtend(m4flash.first));
	endrule

	FIFO#(Bit#(128)) dmainQ <- mkFIFO;
	rule getFlashCmd;
		dma.deq;
		started <= True;
		Bit#(128) d = dma.first;
		dmainQ.enq(d);
	endrule

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

			flash.writeWord(tuple2(data, truncate(tag)));
			flashWriteBytesOut <= flashWriteBytesOut + 16;
		end else begin
			flash.writeWord(tuple2(0, truncate(flashWriteTag)));
			if ( flashWriteBytesOut + 16 >= 8192+32 ) begin
				flashWriteBytesOut <= 0;
			end else begin
				flashWriteBytesOut <= flashWriteBytesOut + 16;
			end
		end
	endrule
	
	rule procFlashCmd;
		let d = dmainQ.first;
		dmainQ.deq;

		let conf = d[127:96];
		if ( conf == 0 ) begin
			let opcode = d[31:0];
			let cur_blockpagetag = d[63:32];
			let cur_buschip = d[96:64];
			
			Bit#(5) bus = truncate(cur_buschip>>8);
			Bit#(8) tag = truncate(cur_blockpagetag);

			let cur_flashop = ERASE_BLOCK;
			if ( opcode == 0 ) cur_flashop = ERASE_BLOCK;
			else if ( opcode == 1 ) begin
				cur_flashop = READ_PAGE;
				tagBusMap[tag] <= bus;
			end
			else if ( opcode == 2 ) begin
				cur_flashop = WRITE_PAGE;
				tagBusMap[tag] <= bus;
			end

			if ( opcode <= 2 ) begin
				//$display( "cmd recv %d", opcode );	
				flashCmdCount <= flashCmdCount + 1;
				/*
				if ( (flashCmdCount & 16'b111111) == 16'h0 ) begin
					Tuple4#(Bit#(32), Bit#(32), Bit#(32), Bit#(32)) dbg = flashMan.getDebugCnts;
					Bit#(8) gbs = truncate(tpl_1(dbg));
					Bit#(8) gbr = truncate(tpl_2(dbg));
					Bit#(8) as = truncate(tpl_3(dbg));
					Bit#(8) ar = truncate(tpl_4(dbg));
					//dma.enq({zeroExtend(flash.channel_up),
					m4flash.enq[0].enq({zeroExtend(flash.channel_up),
						gbs, gbr, as, ar,
						flashReadWords, flashCmdCount, 32'hFFFFFFFF});
				end
				*/
				flash.sendCmd(FlashCmd{
					op:cur_flashop,
					tag:truncate(tag),
					bus: truncate(bus),
					chip: truncate(cur_buschip),
					block:truncate(cur_blockpagetag>>16),
					page:truncate(cur_blockpagetag>>8)
					});
			end
		end else if ( conf == 1 ) begin
			Bit#(64) data = truncate(d);
			if ( isValid(flashWriteBuf) ) begin
				let d2 = fromMaybe(?, flashWriteBuf);
				flashWriteQ.enq(tuple2({data, d2}, truncate(writeTagsQ.first)));
				//flash.writeWord(tuple2({data, d2}, truncate(writeTagsQ.first)));
				if ( flashWriteBytes + 16 >= 8192 ) begin
					writeTagsQ.deq;
					flashWriteBytes <= 0;
				end else begin
					flashWriteBytes <= flashWriteBytes + 16;
				end

				flashWriteBuf <= tagged Invalid;
			end else begin
				flashWriteBuf <= tagged Valid data;
			end
		end
	endrule

/*
	Reg#(Bit#(32)) watchdogCounter <- mkReg(0);
	rule watch(started == True);
		watchdogCounter <= watchdogCounter + 1;
		if ( watchdogCounter[28:0] == ~0 ) begin
			//dma.enq({zeroExtend(flash.channel_up), flashReadWords, flashCmdCount, 32'hFFFFFFFF});
		end
	endrule
	*/

	rule handleFlashWriteReady;
		TagT tag <- flash.writeDataReq;
		Bit#(32) data = {8'h0, 8'h4, zeroExtend(tag)};
		//dma.enq({zeroExtend(data)}); // 32'h1 for testing purposes
		m4flash.enq[0].enq((data)); // 32'h1 for testing purposes
		flashStatusIn <= flashStatusIn + 1;
		writeTagsQ.enq(zeroExtend(tag));
	endrule
	
	rule flashAck;
		let ackStatus <- flash.ackStatus();
		Bit#(8) tag = zeroExtend(tpl_1(ackStatus));
		StatusT status = tpl_2(ackStatus);
		Bit#(32) data = 0;
		case (status) 
			WRITE_DONE: data = {8'h00, 8'h1, zeroExtend(tag)};
			ERASE_DONE: data = {8'h00, 8'h2, zeroExtend(tag)};
			ERASE_ERROR: data = {8'h00, 8'h3, zeroExtend(tag)};
		endcase
		//flashStatusQ.enq(data);
		m4flash.enq[1].enq(data);
		//dma.enq(zeroExtend(data));
		flashStatusIn <= flashStatusIn + 1;
	endrule

	// CosineSimilarity Stuff begin//////////////////////
	// CosineSimilarity end//////////////////////////////
	

	Vector#(BusCount, FIFO#(Tuple2#(Bit#(128), Bit#(8)))) dmaWriteQ <- replicateM(mkSizedFIFO(32));
	Vector#(BusCount, Reg#(Bit#(16))) dmaWriteCnt <- replicateM(mkReg(0));

	// busid, tag, wordcount
	Vector#(TDiv#(BusCount,2), Merge2Ifc#(Tuple3#(Bit#(5),Bit#(8),Bit#(10)))) dmaEngineSelect <- replicateM(mkMerge2);

	FIFO#(Tuple2#(Bit#(128), TagT)) flashReadQ <- mkSizedFIFO(16);
	rule readDataFromFlash;
		let taggedRdata <- flash.readWord();
		flashReadQ.enq(taggedRdata);

		flashReadWords <= flashReadWords + 1;
	endrule

	FIFO#(Tuple3#(Bit#(5), Bit#(128), Bit#(8))) dmaWritetQ <- mkSizedFIFO(32);
	rule relayDMAWrite;
		dmaWritetQ.deq;
		let d = dmaWritetQ.first;
		let busid = tpl_1(d);
		let data = tpl_2(d);
		let tag = tpl_3(d);
		
		let curcnt = dmaWriteCnt[busid];
		if ( curcnt < 8192/16 ) begin
			dmaWriteQ[busid].enq(tuple2(data,tag));
			dmaWriteCnt[busid] <= curcnt+1;

			if ( curcnt[2:0] == 3'b111 ) begin
				Tuple3#(Bit#(5),Bit#(8),Bit#(10)) dmaReq;
				let mergeidx = busid[0];
				dmaReq = tuple3(zeroExtend(mergeidx), tag, 8);
				dmaEngineSelect[busid>>1].enq[mergeidx].enq(dmaReq);
			end
		end else if ( curcnt < (8192+32)/16 -1 ) begin
			dmaWriteCnt[busid] <= curcnt+1;
		end else if ( curcnt >= (8192+32)/16 -1 ) begin
			dmaWriteCnt[busid] <= 0;
		end
	endrule
	
	//Vector#(TagCount, FIFO#(Tuple2#(Bit#(128), Bit#(8)))) reorderPageBuffer <- replicateM(mkSizedBRAMFIFO#(8192/16));
	rule procDataFromFlash;
		let taggedRdata = flashReadQ.first;
		flashReadQ.deq;

		let data = tpl_1(taggedRdata);
		Bit#(8) tag = zeroExtend(tpl_2(taggedRdata));

		let busid = tagBusMap[tag];
		//$display ( "readd %d %x from %d", busid, data, tag );
		
		dmaWritetQ.enq(tuple3(busid, data, tag));
		
	endrule


	Merge4Ifc#(Bit#(8)) m4dma <- mkMerge4;
	rule sendReadDone;
		m4dma.deq;
		Bit#(8) tag = m4dma.first;
		Bit#(32) data = {8'h0, 8'h0, zeroExtend(tag)}; // read done
		//dma.enq({zeroExtend(data)}); 
		m0.enq[1].enq(zeroExtend(data));
		//$display( "dma.enq from %d", tag );
	endrule


	for ( Integer i = 0; i < busCount/2; i = i + 1 ) begin
		Vector#(2, Reg#(Bit#(16))) dmaOffset <- replicateM(mkReg(0));
		Reg#(Bit#(5)) dmaSrcBus <- mkReg(0);
		Reg#(Bit#(5)) dmaEWriteCnt <- mkReg(0);
		/*
		FIFO#(Bit#(32)) pageReadDoneQ <- mkFIFO;
		rule sendPageReadDone;
			pageReadDoneQ.deq;
			$display( "dma.enq from %d", i );
			//dma.enq(zeroExtend(pageReadDoneQ.first));
		endrule
		*/
		rule startdmawrite(dmaEWriteCnt == 0);
			dmaEngineSelect[i].deq;
			let d = dmaEngineSelect[i].first;

			let tag = tpl_2(d);
			let dmacnt = tpl_3(d);
			let mergeidx = tpl_1(d);
			//dmaSrcBus <= fromInteger(i)*2 + mergeidx;
			dmaSrcBus <= mergeidx;

			dmaEWriteCnt <= truncate(dmacnt);
		
			Bit#(16) nn = dmaOffset[mergeidx] + 128;

			dma.users[i].dmaWriteReq((zeroExtend(tag)<<13) | zeroExtend(dmaOffset[mergeidx]), dmacnt, tag);

			if ( dmaOffset[mergeidx] + 128 >= 8192) begin
				//Bit#(32) data = {8'h0, 8'h0, zeroExtend(tag)}; // read done
				
				//$display( "sending dma.enq from %d", i );
				//dma.enq({zeroExtend(data)}); 
				m4dma.enq[i].enq(tag);
				//pageReadDoneQ.enq(data);
				dmaOffset[mergeidx] <= 0;
			end else begin
				dmaOffset[mergeidx] <= dmaOffset[mergeidx] + 128;
			end
		endrule


		rule sendDmaData(dmaEWriteCnt > 0);
			if ( dmaSrcBus == 0 ) begin
				let idx = fromInteger(i)*2;
				dmaWriteQ[idx].deq;
				let data = dmaWriteQ[idx].first;


				dmaEWriteCnt <= dmaEWriteCnt - 1;
				dma.users[i].dmaWriteData(tpl_1(data), tpl_2(data));
			end else begin
				let idx = fromInteger(i)*2 + 1;
				dmaWriteQ[idx].deq;
				let data = dmaWriteQ[idx].first;

				dmaEWriteCnt <= dmaEWriteCnt - 1;
				dma.users[i].dmaWriteData(tpl_1(data), tpl_2(data));
			end
			

			//$display( "dma data from %d", tpl_2(data));
		endrule
	end
endmodule
