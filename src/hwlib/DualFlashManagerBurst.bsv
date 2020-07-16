package DualFlashManagerBurst;

import FIFO::*;
import FIFOF::*;
import Clocks::*;
import Vector::*;

import BRAM::*;
import BRAMFIFO::*;

import FlashManagerCommon::*;
import ControllerTypes::*;
import FlashCtrlVirtex1::*;

import MergeN::*;
import Serializer::*;

import Assert::*;

interface DualFlashManagerBurstIfc;
	method Action readPage(Bit#(8) tag, FlashAddress page);
	method Action writePage(Bit#(8) tag, FlashAddress page);
	method Action eraseBlock(Bit#(8) tag, FlashAddress block);
	method ActionValue#(FlashStatus) fevent;
	method ActionValue#(FlashTaggedWord) readWord;
	method Action writeWord(FlashWord data);


	//TODO decode block mapping req
endinterface

// burstBytes MUST be multiples of 256 bits (32 bytes)
module mkDualFlashManagerBurst#(Vector#(2,FlashCtrlUser) flashes, Integer burstBytes) (DualFlashManagerBurstIfc);
	staticAssert(burstBytes%32==0, "burstBytes in mkDualFlashManagerBurst must be multiples of 32 bytes (256 bits)");
	Integer burstWords = burstBytes/32;

	FIFO#(Tuple2#(Bit#(8), FlashManagerCmd)) flashCmdQ <- mkFIFO;
	FIFO#(FlashManagerCmd) flashCmdUpdatedTagQ <- mkFIFO;
	Vector#(2, FIFO#(TagT)) freeCardTagsQ <- replicateM(mkSizedFIFO(128));
	Reg#(Bit#(8)) freeTagPopCounter <- mkReg(0);
	rule populateFreeTags( freeTagPopCounter < 128 );
		freeTagPopCounter <= freeTagPopCounter + 1;
		freeCardTagsQ[0].enq(truncate(freeTagPopCounter));
		freeCardTagsQ[1].enq(truncate(freeTagPopCounter));
	endrule

	Vector#(2, BRAM2Port#(TagT, Tuple2#(Bit#(8),BusT))) tagMap <- replicateM(mkBRAM2Server(defaultValue)); // 128B


	//////////////////////////////////////////////////////////////////////
	/////*********** Start Flash Command Issue //////////*/

	rule getFreeCardTag;
		flashCmdQ.deq;
		let cmd_ = flashCmdQ.first;
		let tag = tpl_1(cmd_);
		let cmd = tpl_2(cmd_);
		let c = cmd.card;

		TagT newtag = freeCardTagsQ[c].first;
		freeCardTagsQ[c].deq;

		tagMap[c].portA.request.put( BRAMRequest{
			write:True, responseOnWrite:False,
			address:newtag,
			datain:tuple2(tag,cmd.bus)
			}
		);
		cmd.tag = newtag;

		flashCmdUpdatedTagQ.enq(cmd);
	endrule

	rule forwardFlashCmd;
		let cmd = flashCmdUpdatedTagQ.first;
		flashCmdUpdatedTagQ.deq;

		flashes[cmd.card].sendCmd( FlashCmd{
			tag: cmd.tag,
			op: cmd.op,
			bus: cmd.bus,
			chip: cmd.chip,
			block: cmd.block,
			page: cmd.page
		});
	endrule

	//////*/////////////////// End Flash Command Issue //////////////////*/
	//////////////////////////////////////////////////////////////////////
	
	//////////////////////////////////////////////////////////////////////
	/*********** Start Flash Read / Burst reorder //////////*/

	//Burst merger
	BurstMergeNIfc#(TMul#(NUM_BUSES, 2), FlashTaggedWord, 12) burstorder <- mkBurstMergeN;
	FIFO#(FlashTaggedWord) wordOutQ <- mkFIFO;
	rule relayBurstReadData;
		burstorder.deq;
		wordOutQ.enq(burstorder.first);
	endrule
	rule ignoreBurst;
		let b <- burstorder.getBurst;
	endrule

	for (Integer cidx = 0; cidx < 2; cidx = cidx + 1) begin
		//TagT needed to return it later
		//Vector#(NUM_BUSES, FIFO#(Tuple3#(Bit#(128),Bit#(8),TagT))) busOrderQ <- replicateM(mkFIFO);
		ScatterNIfc#(NUM_BUSES, Tuple3#(Bit#(128),Bit#(8),TagT)) busOrderS <- mkScatterN;

		FIFO#(Tuple2#(TagT,Bit#(128))) readDataQ <- mkSizedFIFO(4);
		rule getRead;
			let taggedRdata <- flashes[cidx].readWord();
			Bit#(128) data = tpl_1(taggedRdata);
			TagT tag = tpl_2(taggedRdata);


			tagMap[cidx].portB.request.put( BRAMRequest{
				write:False, responseOnWrite:False,
				address: tag,
				datain:?
				});

			readDataQ.enq(tuple2(tag,data));
		endrule
		rule scatterBus;
			let d <- tagMap[cidx].portB.response.get;
			let otag = tpl_1(d);
			let bus = tpl_2(d);

			let d_ = readDataQ.first;
			readDataQ.deq;
			let data = tpl_2(d_);
			let tag = tpl_1(d_);

			//busOrderQ[bus].enq(tuple3(data, otag,tag));
			busOrderS.enq(tuple3(data, otag,tag), zeroExtend(bus));
			
		endrule

		MergeNIfc#(NUM_BUSES, TagT) doneTagM <- mkMergeN;
		rule returnDoneTags;
			doneTagM.deq;
			freeCardTagsQ[cidx].enq(doneTagM.first);
		endrule

		for (Integer bidx = 0; bidx < valueOf(NUM_BUSES); bidx = bidx + 1) begin
			//if burst is large (KBs), should use BRAMFIFO
			FIFO#(FlashTaggedWord) busBurstQ;
			if ( burstBytes > 1024 ) busBurstQ <- mkSizedBRAMFIFO((burstBytes/32)+1);
			else busBurstQ <- mkSizedFIFO((burstBytes/32)+1);

			DeSerializerIfc#(128, 2) desword <- mkDeSerializer;
			FIFO#(Bit#(8)) skiptag <- mkStreamSkip(2,1); // of every two elements, take only idx 1
			Reg#(Bit#(16)) readDoneBusCount <- mkReg(0);

			rule deserialize;
				//busOrderQ[bidx].deq;
				//let d = busOrderQ[bidx].first;
				busOrderS.get[bidx].deq;
				let d = busOrderS.get[bidx].first;

				desword.put(tpl_1(d));
				skiptag.enq(tpl_2(d));
			
				if ( readDoneBusCount + 1 >= fromInteger((valueOf(PageSizeUser)/16)) ) begin
					readDoneBusCount <= 0;

					doneTagM.enq[bidx].enq(tpl_3(d));
				end else begin
					readDoneBusCount <= readDoneBusCount + 1;
				end
			endrule

			//TODO assert less than 12
			Reg#(Bit#(12)) burstReadyUp <- mkReg(0);
			Reg#(Bit#(12)) burstReadyDown <- mkReg(0);
			Reg#(Bit#(16)) readWordCnt <- mkReg(0); // Used to ignore 32 bytes at the end of each page
			rule enqBurst1;
				let w <- desword.get;
				let t = skiptag.first;
				skiptag.deq;

				if ( readWordCnt < (8192/32) ) begin
					busBurstQ.enq(tuple2(w,t));
					burstReadyUp <= burstReadyUp + 1;
					// If enough data pushed in buffer, start burst
					if ( burstReadyUp-burstReadyDown+1 >= fromInteger(burstWords) ) begin
						burstReadyDown <= burstReadyDown + fromInteger(burstWords);
						burstorder.enq[cidx*valueOf(NUM_BUSES)+bidx].burst(fromInteger(burstWords));
					end
					readWordCnt <= readWordCnt + 1;
				end else if ( readWordCnt +1 < fromInteger(valueOf(PageSizeUser)/32) ) begin
					readWordCnt <= readWordCnt + 1;
					//$display( "Ignoring end bytes per page" );
				end else begin
					//$display( "Ignoring end bytes per page" );
					readWordCnt <= 0;
				end
				
			endrule
			rule relayBurstData;
				busBurstQ.deq;
				burstorder.enq[cidx*valueOf(NUM_BUSES)+bidx].enq(busBurstQ.first);
			endrule
		end
	end
	////////*///////////////// End Flash Read / Burst reorder //////////*/
	//////////////////////////////////////////////////////////////////////

	////////*///////////////// Begin Flash Status  (comand done, etc) //////////*/
	//////////////////////////////////////////////////////////////////////

	
	Merge2Ifc#(Tuple4#(Bit#(8), FlashStatusCode, TagT, Bit#(1))) mstat <- mkMerge2;
	for (Integer cidx = 0; cidx < 2; cidx = cidx + 1) begin
		FIFO#(Tuple2#(TagT,FlashStatusCode)) flashStatQ <- mkFIFO;
		FIFO#(Tuple2#(TagT,FlashStatusCode)) flashStatBypassQ <- mkSizedFIFO(4);
		(* descending_urgency = "flashAck, writeReady" *)
		rule flashAck;
			let ackStatus <- flashes[cidx].ackStatus();
			StatusT status = tpl_2(ackStatus);
			FlashStatusCode stat = case (status) 
				WRITE_DONE: return STATE_WRITE_DONE;
				ERASE_DONE: return STATE_ERASE_DONE;
				ERASE_ERROR: return STATE_ERASE_FAIL;
				default: STATE_NULL; // not reachable
			endcase;
			flashStatQ.enq(tuple2(tpl_1(ackStatus), stat));

			// return down tag
			freeCardTagsQ[cidx].enq(tpl_1(ackStatus));
		endrule
		rule writeReady;
			TagT tag <- flashes[cidx].writeDataReq;
			flashStatQ.enq(tuple2(tag, STATE_WRITE_READY));
		endrule

		rule translateTag;
			flashStatQ.deq;
			let d_ = flashStatQ.first;

			tagMap[cidx].portA.request.put( BRAMRequest{
				write:False, responseOnWrite:False,
				address: tpl_1(d_),
				datain:?
				});
			flashStatBypassQ.enq(d_);
		endrule
		rule enqMergeStat;
			flashStatBypassQ.deq;
			let d_ = flashStatBypassQ.first;
			let tag = tpl_1(d_);
			let word = tpl_2(d_);

			let ntag <- tagMap[cidx].portA.response.get;
			mstat.enq[cidx].enq(tuple4(tpl_1(ntag), word, tag, fromInteger(cidx)));
		endrule
	end

	////////*///////////////// End Flash Status  (comand done, etc) //////////*/
	//////////////////////////////////////////////////////////////////////

	////////*///////////////// Start Flash Write //////////*/
	//////////////////////////////////////////////////////////////////////

	FIFO#(Tuple2#(TagT, Bit#(1))) writeTargetOrderQ <- mkSizedBRAMFIFO(256);
	FIFO#(Tuple2#(Bit#(8), FlashStatusCode)) statQ <- mkFIFO;
	rule getWriteOrder;
		mstat.deq;
		let m = mstat.first;
		statQ.enq(tuple2(tpl_1(m), tpl_2(m)));

		if ( tpl_2(m) == STATE_WRITE_READY ) begin
			writeTargetOrderQ.enq(tuple2(tpl_3(m), tpl_4(m)));
		end
	endrule

	FIFO#(FlashWord) dataInQ <- mkFIFO;
	FIFO#(FlashWord) dataInBypassQ <- mkSizedFIFO(4);
	Reg#(Bit#(16)) writeWordCounter <- mkReg(0);

	Reg#(Tuple2#(TagT, Bit#(1))) curWriteTarget <- mkReg(?);
	Vector#(2, FIFO#(Tuple2#(TagT, FlashWord))) cardWriteQ <- replicateM(mkFIFO);

	rule routeCardTarget;
		if ( writeWordCounter < (8192/32) ) begin
			dataInQ.deq;
			let w = dataInQ.first;

			let ctarget = curWriteTarget;
			if ( writeWordCounter == 0 ) begin
				writeTargetOrderQ.deq;
				ctarget = writeTargetOrderQ.first;
				curWriteTarget <= ctarget;
			end


			cardWriteQ[tpl_2(ctarget)].enq(tuple2(tpl_1(ctarget), w));

			writeWordCounter <= writeWordCounter + 1;
		end else if ( writeWordCounter + 1 < fromInteger(valueOf(PageSizeUser)/32) ) begin
			let ctarget = curWriteTarget;
			cardWriteQ[tpl_2(ctarget)].enq(tuple2(tpl_1(ctarget), 0));
			writeWordCounter <= writeWordCounter + 1;
		end else begin
			let ctarget = curWriteTarget;
			cardWriteQ[tpl_2(ctarget)].enq(tuple2(tpl_1(ctarget), 0));
			writeWordCounter <= 0;
		end
	endrule

	for (Integer cidx = 0; cidx < 2; cidx=cidx+1 ) begin
		SerializerIfc#(256,2) wser <- mkSerializer;
		FIFO#(TagT) wrep <- mkStreamReplicate(2);
		rule serFlashWrite;
			cardWriteQ[cidx].deq;
			let d_ = cardWriteQ[cidx].first;

			wrep.enq(tpl_1(d_));
			wser.put(tpl_2(d_));
		endrule

		rule relayFlashWrite;
			let w <- wser.get;
			let t = wrep.first;
			wrep.deq;

			flashes[cidx].writeWord(tuple2(w,t));
		endrule
	end

	////////*///////////////// End Flash Write //////////*/
	//////////////////////////////////////////////////////////////////////

	method Action readPage(Bit#(8) tag, FlashAddress page);
		flashCmdQ.enq(tuple2(tag, decodeCommand(page, READ_PAGE)));
	endmethod
	method Action writePage(Bit#(8) tag, FlashAddress page);
		flashCmdQ.enq(tuple2(tag, decodeCommand(page, WRITE_PAGE)));
	endmethod
	method Action eraseBlock(Bit#(8) tag, FlashAddress block);
		flashCmdQ.enq(tuple2(tag, decodeCommand(block, ERASE_BLOCK)));
	endmethod

	method ActionValue#(FlashStatus) fevent;
		statQ.deq;
		return FlashStatus {
			code: tpl_2(statQ.first),
			tag: tpl_1(statQ.first)
		};
	endmethod
	method ActionValue#(FlashTaggedWord) readWord;
		wordOutQ.deq;
		return wordOutQ.first;
	endmethod
	method Action writeWord(FlashWord data);
		dataInQ.enq(data);
	endmethod
endmodule

endpackage: DualFlashManagerBurst
