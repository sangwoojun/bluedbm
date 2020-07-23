package DualFlashManagerOrdered;

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
import BLBurstOrderChain::*;

import Assert::*;

interface DualFlashManagerOrderedIfc;
	method Action readPage(FlashAddress page);
	method Action writePage(FlashAddress page);
	method Action eraseBlock(FlashAddress block);
	method ActionValue#(FlashStatus) fevent;
	method ActionValue#(FlashWord) readWord;
	method Action writeWord(FlashWord data);
endinterface

typedef 16 ReadTagCntPerCard;

// burstBytes MUST be multiples of 256 bits (32 bytes)
module mkDualFlashManagerOrdered#(Vector#(2,FlashCtrlUser) flashes) (DualFlashManagerOrderedIfc);

	Integer readTagCntPerCard = valueOf(ReadTagCntPerCard);


	Reg#(Bit#(8)) freeTagHead <- mkReg(0);
	Reg#(Bit#(8)) freeTagTail <- mkReg(0);

	FIFO#(FlashManagerCmd) flashCmdQ <- mkFIFO;
	FIFO#(FlashManagerCmd) flashCmdUpdatedTagQ <- mkFIFO;
	Vector#(2, FIFO#(TagT)) freeCardTagsQ <- replicateM(mkSizedFIFO(readTagCntPerCard));
	Reg#(Bit#(8)) freeTagPopCounter <- mkReg(0);
	rule populateFreeTags( freeTagPopCounter < fromInteger(readTagCntPerCard) );
		freeTagPopCounter <= freeTagPopCounter + 1;
		freeCardTagsQ[0].enq(truncate(freeTagPopCounter));
		freeCardTagsQ[1].enq(truncate(freeTagPopCounter));
	endrule

	Vector#(2, BRAM2Port#(TagT, Bit#(8))) tagMap <- replicateM(mkBRAM2Server(defaultValue)); // 128B
	Vector#(2, BLBurstOrderChainIfc#(ReadTagCntPerCard, TDiv#(PageSizeUser,16), Bit#(128))) reorderChain <- replicateM(mkBLBurstOrderChain(readTagCntPerCard));


	//////////////////////////////////////////////////////////////////////
	/////*********** Start Flash Command Issue //////////*/

	rule getFreeCardTag ( freeTagHead - freeTagTail < 128 );
		flashCmdQ.deq;
		let cmd = flashCmdQ.first;
		let c = cmd.card;
		let b = cmd.bus;
		let tag = freeTagHead;
		freeTagHead <= freeTagHead + 1;

		TagT newtag = freeCardTagsQ[c].first;
		freeCardTagsQ[c].deq;

		tagMap[c].portA.request.put( BRAMRequest{
			write:True, responseOnWrite:False,
			address:newtag,
			datain:tag
			}
		);
		cmd.tag = newtag;
		

		flashCmdUpdatedTagQ.enq(cmd);
	endrule

	FIFO#(Bit#(1)) reqCardOrderQ <- mkSizedFIFO(readTagCntPerCard*2);
	Vector#(2,FIFO#(TagT)) reqCardTagOrderQ <- replicateM(mkSizedFIFO(readTagCntPerCard));
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
		if ( cmd.op == READ_PAGE ) begin 
			reorderChain[cmd.card].req(truncate(cmd.tag), fromInteger(valueOf(PageSizeUser)/16));
			reqCardTagOrderQ[cmd.card].enq(cmd.tag);
			reqCardOrderQ.enq(cmd.card);
		end
	endrule


	//////*/////////////////// End Flash Command Issue //////////////////*/
	//////////////////////////////////////////////////////////////////////
	
	//////////////////////////////////////////////////////////////////////
	/*********** Start Flash Read / Burst reorder //////////*/


	Vector#(2,DeSerializerIfc#(128,2)) desRead <- replicateM(mkDeSerializer);
	for (Integer cidx = 0; cidx < 2; cidx = cidx + 1) begin
		//BLScatterNIfc#(NUM_BUSES, Tuple3#(Bit#(128),Bit#(8),TagT)) busOrderS <- mkBLScatterN;

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
			let otag <- tagMap[cidx].portB.response.get;

			let d_ = readDataQ.first;
			readDataQ.deq;
			let tag = tpl_1(d_);
			let data = tpl_2(d_);

			reorderChain[cidx].enq(data,truncate(tag));
		endrule
		Reg#(Bit#(10)) pageReadWordCnt <- mkReg(0);
		rule getOrderedData;
			reorderChain[cidx].deq;
			let d = reorderChain[cidx].first;
			if ( pageReadWordCnt + 1 < 512 ) begin
				desRead[cidx].put(d);
				//$display("Ordered Data Out" );
			end
			if ( pageReadWordCnt + 1 >= fromInteger(valueOf(PageSizeUser)/16) ) begin
				pageReadWordCnt <= 0;
				reqCardTagOrderQ[cidx].deq;
				freeCardTagsQ[cidx].enq(reqCardTagOrderQ[cidx].first);
			end else begin
				pageReadWordCnt <= pageReadWordCnt + 1;
			end
		endrule
	end
	Reg#(Bit#(10)) cardPageReadWordCnt <- mkReg(0);
	Reg#(Bit#(1)) curCardSrc <- mkReg(0);
	FIFO#(FlashWord) wordOutQ <- mkFIFO;
	rule collectCardData;
		if ( cardPageReadWordCnt == 0 ) begin
			reqCardOrderQ.deq;
			let c = reqCardOrderQ.first;
			curCardSrc <= c;
			cardPageReadWordCnt <= 1;

			let d <- desRead[c].get;
			wordOutQ.enq(d);
			$display("New page start" );
		end else begin
			if ( cardPageReadWordCnt + 1 >= 256 ) begin
				cardPageReadWordCnt <= 0;
			end else begin
				cardPageReadWordCnt <= cardPageReadWordCnt + 1;
			end
			let d <- desRead[curCardSrc].get;
			wordOutQ.enq(d);
			freeTagTail <= freeTagTail + 1;
		end
	endrule
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
			mstat.enq[cidx].enq(tuple4(ntag, word, tag, fromInteger(cidx)));
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

	//Vector#(2, BLBurstOrderChainIfc#(ReadTagCntPerCard, TDiv#(PageSizeUser,16), Bit#(128))) writeReorderChain <- replicateM(mkBLBurstOrderChain(readTagCntPerCard));
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

	method Action readPage(FlashAddress page);
		flashCmdQ.enq(decodeCommand(page, READ_PAGE));
	endmethod
	method Action writePage(FlashAddress page);
		flashCmdQ.enq(decodeCommand(page, WRITE_PAGE));
	endmethod
	method Action eraseBlock(FlashAddress block);
		flashCmdQ.enq(decodeCommand(block, ERASE_BLOCK));
	endmethod

	method ActionValue#(FlashStatus) fevent;
		statQ.deq;
		return FlashStatus {
			code: tpl_2(statQ.first),
			tag: tpl_1(statQ.first)
		};
	endmethod
	method ActionValue#(FlashWord) readWord;
		wordOutQ.deq;
		return wordOutQ.first;
	endmethod
	method Action writeWord(FlashWord data);
		dataInQ.enq(data);
	endmethod
endmodule

endpackage: DualFlashManagerOrdered

