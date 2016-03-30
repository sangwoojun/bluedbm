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


typedef 8 BusCount; // 8 per card in hw, 2 per card in sim
typedef TMul#(2,BusCount) BBusCount; //Board*bus
//typedef 64 TagCount; // Has to be larger than the software setting
typedef 2 DMAEngineCount;
typedef 4 DestCount;

interface HwMainIfc;
endinterface

module mkHwMain#(PcieUserIfc pcie, Vector#(2,FlashCtrlUser) flashes, FlashManagerIfc flashMan, 
	DRAMUserIfc dram) 
	(HwMainIfc);

	Clock curClk <- exposeCurrentClock;
	Reset curRst <- exposeCurrentReset;

	Clock pcieclk = pcie.user_clk;
	Reset pcierst = pcie.user_rst;

	Integer busCount = valueOf(BusCount);
	//Integer tagCount = valueOf(TagCount);
	Integer dmaEngineCount = valueOf(DMAEngineCount);
	Integer destCount = valueOf(DestCount);

	DMASplitterIfc#(DMAEngineCount) dma <- mkDMASplitter(pcie);

	Merge2Ifc#(Bit#(128)) m0 <- mkMerge2;
	Merge2Ifc#(Bit#(32)) m4flash <- mkMerge2;

	FIFO#(FlashCmd) flashCmdQ <- mkFIFO;
	Vector#(8, Reg#(Bit#(32))) writeBuf <- replicateM(mkReg(0));

	DualFlashManagerIfc flashman <- mkDualFlashManager(flashes);
	
	// 8'available 8'type 16'data
	// type: 0: readdone, 1: writedone 2: erasedone 3:erasefail 4: writeready
	FIFOF#(Bit#(32)) flashStatusQ <- mkFIFOF(clocked_by pcieclk, reset_by pcierst);
	Reg#(Bit#(8)) flashStatusOut <- mkReg(0);
	FIFO#(Bit#(8)) writeTagsQ <- mkSizedBRAMFIFO(128);

	Reg#(Bit#(16)) flashWriteBytes <- mkReg(0);
	Reg#(Maybe#(Bit#(64))) flashWriteBuf <- mkReg(tagged Invalid);

	//Vector#(TagCount,Reg#(Bit#(5))) tagBusMap <- replicateM(mkReg(0));
	Reg#(Bool) started <- mkReg(False);

	rule senddmaenq;
		m0.deq;
		dma.enq(0, m0.first);
	endrule
	/*
	rule flushm4flash;
		m4flash.deq;
		m0.enq[0].enq(zeroExtend(m4flash.first));
	endrule
	*/

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
	
	Reg#(Bit#(256)) readReqTagEpoch <- mkReg(0);
	Reg#(Bit#(256)) readDoneTagEpoch <- mkReg(0);

	//FIFO#(Bit#(8)) readReqTagOrderQ <- mkSizedBRAMFIFO(256);
	//FIFO#(Bit#(8)) readReqDestQ <- mkSizedBRAMFIFO(256);
	TagDestReorderIfc#(DestCount) tdreorder <- mkTagDestReorder;
	
	rule procFlashCmd;
		let d = dmainQ.first;
		dmainQ.deq;

		let conf = d[127:96];
		if ( conf == 0 ) begin
			let opcode = d[31:0];

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
		end else if ( conf == 1 ) begin
			Bit#(64) data = truncate(d);
			if ( isValid(flashWriteBuf) ) begin
				let d2 = fromMaybe(?, flashWriteBuf);
				flashWriteQ.enq(tuple2({data, d2}, truncate(writeTagsQ.first)));
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
		mFlashEvent.enq[0].enq(data);

		if ( stat == STATE_WRITE_READY ) begin
			writeTagsQ.enq(tag);
			$display( "writeTagsQ enqing %d", tag );
		end
	endrule
	Merge4Ifc#(Bit#(8)) m4dma <- mkMerge4;
	rule getReadDone;
		m4dma.deq;
		mFlashEvent.enq[1].enq({m4dma.first, 0});
	endrule

	Reg#(Bit#(128)) flashEventBuf <- mkReg(~0);
	Reg#(Bit#(16)) flashEventCnt <- mkReg(0);
	Reg#(Bit#(16)) flashEventCounter <- mkReg(0);
	(* descending_urgency = "sendFlashEvent, flashEventTimeout" *)
	rule sendFlashEvent;
		mFlashEvent.deq;
		Bit#(16) dat = mFlashEvent.first;
		flashEventCounter <= 0;

		if ( flashEventCnt >= 7 ) begin
			m0.enq[0].enq((flashEventBuf<<16)|zeroExtend(dat));
			flashEventBuf <= ~0;
			flashEventCnt <= 0;
		end else begin
			flashEventCnt <= flashEventCnt + 1;
			flashEventBuf <= (flashEventBuf<<16) | zeroExtend(dat);
		end
	endrule
	rule flashEventTimeout;
		if ( flashEventCounter >= 512 ) begin
			flashEventCounter <= 0;

			if ( flashEventCnt > 0 ) begin
				flashEventCnt <= 0;
				flashEventBuf <= ~0;
				m0.enq[0].enq(flashEventBuf);
			end
		end else begin
			flashEventCounter <= flashEventCounter + 1;
		end
	endrule

	Vector#(2,Vector#(BusCount, FIFO#(Tuple2#(Bit#(512), Bit#(8))))) pageReadWQ <- replicateM(replicateM(mkSizedBRAMFIFO(256))); // 2 pages per bus
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
			rule desread;
				let d = pageReadQ[j].first;
				pageReadQ[j].deq;
				if ( descnt >= 3 ) begin
					descnt <= 0;
					pageReadWQ[i][j].enq(tuple2((desreg<<128)|zeroExtend(tpl_1(d)), tpl_2(d)));
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

	//Merge2Ifc#(Bit#(8)) mReadDoneTag <- mkMerge2;
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

		dram.write(addr, data, 64);

		if ( writeBurstCnt == 1 ) begin
			//mReadDoneTag.enq[0].enq(tag);
			tdreorder.tagReady(tag);
		end
	endrule
	
	/*
	FIFO#(Bit#(8)) dramCachedTagQ <- mkSizedBRAMFIFO(256);
	rule relayReadDoneTag;
		mReadDoneTag.deq;
		dramCachedTagQ.enq(mReadDoneTag.first);
	endrule

	FIFO#(Bit#(8)) orderedReadReadyTagQ <- mkFIFO;
	rule matchReadPageOrder;
		dramCachedTagQ.deq;
		let d = dramCachedTagQ.first;
		let f = readReqTagOrderQ.first;
		if ( d == f ) begin
			readReqTagOrderQ.deq;
			orderedReadReadyTagQ.enq(f);

		end else begin
			mReadDoneTag.enq[1].enq(d);
		end
	endrule
	*/

	Vector#(DestCount, PageFIFOIfc) pfifov;
	MergeNIfc#(DestCount,Bit#(8)) mpreq <- mkMergeN;
	for ( Integer i = 0; i < destCount; i=i+1 ) begin
		pfifov[i] <- mkPageFIFO(1);
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
		//orderedReadReadyTagQ.deq;
		//readReqDestQ.deq;
		//orderedReadReadyTag <= orderedReadReadyTagQ.first;
		//readDest <= readReqDestQ.first;
		let t <- tdreorder.tagDestReady;
		orderedReadReadyTag <= tpl_1(t);
		readDest <= tpl_2(t);

		orderedReadCount <= 128;
		readByteOff <= 0;

		$display( "Tag %d ready for dest %d", tpl_1(t), tpl_2(t) );
	endrule

	FIFO#(Bit#(8)) dataWordDestQ <- mkSizedFIFO(64);
	rule readOrdDRAMReq( orderedReadCount > 0 );
		Bit#(64) addr = (zeroExtend(orderedReadReadyTag)<<13|zeroExtend(readByteOff));
		dram.readReq(addr, 64);
		orderedReadCount <= orderedReadCount - 1;
		readByteOff <= readByteOff + 64;
		dataWordDestQ.enq(readDest);
		if ( orderedReadCount == 1 ) begin
			m4dma.enq[0].enq(orderedReadReadyTag);
			$display( "Done reading %d", orderedReadReadyTag );
		end
	endrule

	FIFO#(Bit#(512)) dramReadQ <- mkFIFO;
	rule readOrdDRAMData;
		let d <- dram.read;
		dramReadQ.enq(d);
	endrule
	FIFO#(Bit#(512)) hostDestQ <- mkFIFO;
	rule relayDRAMData;
		dramReadQ.deq;
		dataWordDestQ.deq;
		let d = dramReadQ.first;
		let dst = dataWordDestQ.first;
		pfifov[dst].enq(d);
		//if ( dst == 0 ) begin
		//	hostDestQ.enq(d);
		//end
	endrule

	rule flushdst1;
		pfifov[1].deq;
	endrule
	Reg#(Bit#(16)) flush2cnt <- mkReg(0);
	rule flushdst2;
		flush2cnt <= flush2cnt + 1;

		if ( flush2cnt[6:0] == 0 ) begin
			pfifov[2].deq;
		end
	endrule

	Reg#(Bit#(4)) splitCounter <- mkReg(0);
	Reg#(Bit#(4)) dmaEngineDest <- mkReg(0);
	Vector#(DMAEngineCount, FIFO#(Bit#(512))) dmaSplitQ <- replicateM(mkFIFO);
	rule relayHostDest;
		//hostDestQ.deq;
		//let d = hostDestQ.first;
		pfifov[0].deq;
		let d = pfifov[0].first;

		dmaSplitQ[dmaEngineDest].enq(d);

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
		Reg#(Bit#(8)) dmaSplitCnt <- mkReg(0);
		Reg#(Bit#(512)) dmaSplitBuf <- mkReg(0);
		rule serializeSplit;
			if ( dmaSplitCnt == 0 ) begin
				dmaSplitQ[i].deq;
				let d = dmaSplitQ[i].first;
				dmaSplitCnt <= 3;
				dmaOutQ.enq(d[511:384]);
				dmaSplitBuf <= (d<<128);
			end else begin
				dmaSplitCnt <= dmaSplitCnt - 1;
				dmaOutQ.enq(dmaSplitBuf[511:384]);
				dmaSplitBuf <= (dmaSplitBuf<<128);
			end
		endrule
		Reg#(Bit#(32)) dmaOffset <- mkReg(128*fromInteger(i));
		Reg#(Bit#(32)) dmaWordCnt <- mkReg(0);
		Reg#(Bit#(5)) wtag <- mkReg(0);
		rule dmaWrite;
			dmaOutQ.deq;
			let d = dmaOutQ.first;

			if ( dmaWordCnt[2:0] == 3'b111 ) begin
				Bit#(32) dmao = zeroExtend(dmaOffset[19:0]); // 8K*256
				dma.users[i].dmaWriteReq(dmao, 8, 0); // tag is actually irrelevant in writes...
				//dma.users[i].dmaWriteReq(dmao, 8, (zeroExtend(wtag)|(fromInteger(i)<<5))); // tag is actually irrelevant in writes...
				wtag <= wtag + 1;
				dmaOffset <= dmaOffset + fromInteger(128*dmaEngineCount);
			end
			dma.users[i].dmaWriteData(d, 0); // tag is actually irrelevant in writes...
			dmaWordCnt <= dmaWordCnt + 1;
		endrule
	end



/*
	for ( Integer i = 0; i < 2; i=i+1 ) begin
		FIFO#(Tuple2#(Bit#(8), Bit#(128))) flashReadQ <- mkSizedBRAMFIFO(512);


		Vector#(BusCount, FIFO#(Tuple2#(Bit#(128), Bit#(8)))) dmaWriteQ <- replicateM(mkSizedBRAMFIFO(512));
		Vector#(BusCount, Reg#(Bit#(16))) dmaWriteCnt <- replicateM(mkReg(0));

		//Tag, Count
		Vector#(TDiv#(BusCount,4), Merge4Ifc#(Tuple2#(Bit#(8),Bit#(10)))) dmaEngineSelect <- replicateM(mkMerge4);

		rule readDataFromFlash1;
			let taggedRdata <- flashman.ifc[i].readWord();
			flashReadQ.enq(taggedRdata);
		endrule

		rule relayDMAWrite;
			flashReadQ.deq;
			let d = flashReadQ.first;

			let tag = tpl_1(d);
			let data = tpl_2(d);
			Bit#(3) busid = tag[6:4];
			
			let curcnt = dmaWriteCnt[busid];
			if ( curcnt < 8192/16 ) begin
				dmaWriteQ[busid].enq(tuple2(data,tag));
				dmaWriteCnt[busid] <= curcnt+1;

				if ( curcnt[2:0] == 0 ) begin
				//if ( curcnt[2:0] == 3'b111 ) begin
					Tuple2#(Bit#(8),Bit#(10)) dmaReq;
					let mergeidx = busid[1:0];

					dmaReq = tuple2(tag, 8);
					dmaEngineSelect[busid>>2].enq[mergeidx].enq(dmaReq);
				end
			end else if ( curcnt < (8192+32)/16 -1 ) begin
				dmaWriteCnt[busid] <= curcnt+1;
			end else if ( curcnt >= (8192+32)/16 -1 ) begin
				dmaWriteCnt[busid] <= 0;
			end
		endrule

		// Per PCIe writeEngine
		for ( Integer j = 0; j < busCount/4; j = j + 1 ) begin
			Vector#(4, Reg#(Bit#(16))) dmaOffset <- replicateM(mkReg(0));
			Reg#(Bit#(5)) dmaSrcBus <- mkReg(0);
			Reg#(Bit#(5)) dmaEWriteCnt <- mkReg(0);

			rule startdmawrite(dmaEWriteCnt == 0);
				Bit#(2) dui = fromInteger(i)*2+fromInteger(j);
				dmaEngineSelect[j].deq;
				let d = dmaEngineSelect[j].first;

				let tag = tpl_1(d);
				let dmacnt = tpl_2(d);
				Bit#(3) busid = tag[6:4];
				let mergeidx = busid[1:0];

				dmaSrcBus <= zeroExtend(mergeidx);
				dmaEWriteCnt <= truncate(dmacnt);

				dma.users[dui].dmaWriteReq((zeroExtend(tag)<<13) | zeroExtend(dmaOffset[mergeidx]), dmacnt, tag);

				if ( dmaOffset[mergeidx] + 128 >= 8192) begin
					m4dma.enq[dui].enq(tag);
					dmaOffset[mergeidx] <= 0;
				end else begin
					dmaOffset[mergeidx] <= dmaOffset[mergeidx] + 128;
				end

			endrule

			rule sendDmaData(dmaEWriteCnt > 0);
				if ( dmaSrcBus == 0 ) begin
					Bit#(3) idx = fromInteger(j)*4;
					Bit#(2) dui = fromInteger(i)*2+fromInteger(j);
					
					dmaWriteQ[idx].deq;
					let data = dmaWriteQ[idx].first;
					dma.users[dui].dmaWriteData(tpl_1(data), tpl_2(data));
				end else 
				if ( dmaSrcBus == 1 ) begin
					Bit#(3) idx = fromInteger(j)*4 + 1;
					Bit#(2) dui = fromInteger(i)*2+fromInteger(j);

					dmaWriteQ[idx].deq;
					let data = dmaWriteQ[idx].first;
					dma.users[dui].dmaWriteData(tpl_1(data), tpl_2(data));
				end else 
				if ( dmaSrcBus == 2 ) begin
					Bit#(3) idx = fromInteger(j)*4 + 2;
					Bit#(2) dui = fromInteger(i)*2+fromInteger(j);

					dmaWriteQ[idx].deq;
					let data = dmaWriteQ[idx].first;
					dma.users[dui].dmaWriteData(tpl_1(data), tpl_2(data));
				end else 
				if ( dmaSrcBus == 3 ) begin
					Bit#(3) idx = fromInteger(j)*4 + 3;
					Bit#(2) dui = fromInteger(i)*2+fromInteger(j);

					dmaWriteQ[idx].deq;
					let data = dmaWriteQ[idx].first;
					dma.users[dui].dmaWriteData(tpl_1(data), tpl_2(data));
				end 
				dmaEWriteCnt <= dmaEWriteCnt - 1;
			endrule
		end
	end
*/


endmodule
