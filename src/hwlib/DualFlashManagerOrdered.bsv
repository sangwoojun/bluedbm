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
	method ActionValue#(DoneStatus) doneStat;
	method ActionValue#(FlashWord) readWord;
	method Action writeWord(FlashWord data);
endinterface

typedef 16 ReadTagCntPerCard;
typedef 16 WriteTagCntPerCard;

// burstBytes MUST be multiples of 256 bits (32 bytes)
module mkDualFlashManagerOrdered#(Vector#(2,FlashCtrlUser) flashes) (DualFlashManagerOrderedIfc);

	Integer readTagCntPerCard = valueOf(ReadTagCntPerCard);
	Integer writeTagCntPerCard = valueOf(WriteTagCntPerCard);


	//Reg#(Bit#(8)) freeTagHead <- mkReg(0);
	//Reg#(Bit#(8)) freeTagTail <- mkReg(0);

	FIFO#(FlashManagerCmd) flashCmdQ <- mkFIFO;
	FIFO#(FlashAddress) flashWriteAddrQ <- mkSizedFIFO(4);
	FIFO#(FlashManagerCmd) flashCmdUpdatedTagQ <- mkFIFO;
	Vector#(2, FIFO#(TagT)) freeCardTagsQ <- replicateM(mkSizedFIFO(readTagCntPerCard));
	Vector#(2, Reg#(TagT)) freeReadTagHead <- replicateM(mkReg(0));
	Vector#(2, Reg#(TagT)) freeReadTagTail <- replicateM(mkReg(0));

	Reg#(Bit#(8)) freeTagPopCounter <- mkReg(0);
	rule populateFreeTags( freeTagPopCounter < fromInteger(writeTagCntPerCard) );
		freeTagPopCounter <= freeTagPopCounter + 1;
		freeCardTagsQ[0].enq(truncate(freeTagPopCounter));
		freeCardTagsQ[1].enq(truncate(freeTagPopCounter));
	endrule

	//Vector#(2, BRAM2Port#(TagT, Bit#(8))) tagMap <- replicateM(mkBRAM2Server(defaultValue)); // 128B
	BRAM2Port#(Bit#(TLog#(TMul#(2,WriteTagCntPerCard))), FlashAddress) writeAddrMap <- mkBRAM2Server(defaultValue);
	Vector#(2, BLBurstOrderChainIfc#(ReadTagCntPerCard, TDiv#(PageSizeUser,16), Bit#(128))) reorderChain <- replicateM(mkBLBurstOrderChain(readTagCntPerCard));


	//////////////////////////////////////////////////////////////////////
	/////*********** Start Flash Command Issue //////////*/

	rule getFreeCardTag;// ( freeTagHead - freeTagTail < 128 );
		let cmd = flashCmdQ.first;
		let c = cmd.card;
		let b = cmd.bus;
		//let tag = freeTagHead;
		//freeTagHead <= freeTagHead + 1;

		if ( cmd.op == READ_PAGE ) begin
			if ( freeReadTagHead[c] - freeReadTagTail[c] < fromInteger(readTagCntPerCard) ) begin
				cmd.tag = freeReadTagHead[c];
				freeReadTagHead[c] <= freeReadTagHead[c] + 1;
				flashCmdUpdatedTagQ.enq(cmd);

				flashCmdQ.deq;
			end
		end else if ( cmd.op == WRITE_PAGE ) begin
			TagT newtag = freeCardTagsQ[c].first;
			freeCardTagsQ[c].deq;
			cmd.tag = newtag;
			flashCmdUpdatedTagQ.enq(cmd);

			flashCmdQ.deq;
		end else begin // erase
			//FIXME shares write tags...!
			TagT newtag = freeCardTagsQ[c].first;
			freeCardTagsQ[c].deq;
			cmd.tag = newtag;
			flashCmdUpdatedTagQ.enq(cmd);

			flashCmdQ.deq;
		end


		/*
		tagMap[c].portA.request.put( BRAMRequest{
			write:True, responseOnWrite:False,
			address:newtag,
			datain:tag
			}
		);
		*/
	endrule

	FIFO#(Bit#(1)) reqCardOrderQ <- mkSizedFIFO(readTagCntPerCard*2);
	FIFO#(Tuple2#(Bit#(1),TagT)) writeReqOrderQ <- mkSizedFIFO(writeTagCntPerCard*2);
	//Vector#(2,FIFO#(TagT)) reqCardTagOrderQ <- replicateM(mkSizedFIFO(readTagCntPerCard));
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
			//reqCardTagOrderQ[cmd.card].enq(cmd.tag);
			reqCardOrderQ.enq(cmd.card);
		end else begin
			flashWriteAddrQ.deq;
			let addr = flashWriteAddrQ.first;
			writeAddrMap.portA.request.put( BRAMRequest{
				write:True, responseOnWrite:False,
				address:{cmd.card,truncate(cmd.tag)},
				datain:addr
				}
			);
			

			if ( cmd.op == WRITE_PAGE ) begin
				writeReqOrderQ.enq(tuple2(cmd.card,cmd.tag));
			end else if ( cmd.op == ERASE_BLOCK ) begin
			end
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

			readDataQ.enq(tuple2(tag,data));
		endrule
		rule scatterBus;
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
				//reqCardTagOrderQ[cidx].deq;
				//freeCardTagsQ[cidx].enq(reqCardTagOrderQ[cidx].first);
				freeReadTagTail[cidx]  <= freeReadTagTail[cidx] + 1;
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
			//freeTagTail <= freeTagTail + 1;
		end
	endrule
	////////*///////////////// End Flash Read / Burst reorder //////////*/
	//////////////////////////////////////////////////////////////////////
	
	Vector#(2, BLBurstOrderChainIfc#(WriteTagCntPerCard, TDiv#(PageSizeUser,16), Bit#(128))) writeReorderChain <- replicateM(mkBLBurstOrderChain(writeTagCntPerCard));

	////////*///////////////// Begin Flash Status  (comand done, etc) //////////*/
	//////////////////////////////////////////////////////////////////////

	
	MergeNIfc#(2, Tuple2#(Bit#(8), StatusT)) mdone <- mkMergeN;
	for (Integer cidx = 0; cidx < 2; cidx = cidx + 1) begin
		FIFO#(Tuple2#(TagT,FlashStatusCode)) flashStatQ <- mkFIFO;
		FIFO#(Tuple2#(TagT,FlashStatusCode)) flashStatBypassQ <- mkSizedFIFO(4);
		rule flashAck;
			let ackStatus <- flashes[cidx].ackStatus();
			StatusT status = tpl_2(ackStatus);
			TagT tag = tpl_1(ackStatus);
			mdone.enq[cidx].enq(tuple2({fromInteger(cidx),tag},status));
			// return done tag
			freeCardTagsQ[cidx].enq(tpl_1(ackStatus));
		endrule
	end

	FIFO#(StatusT) doneStatusQ <- mkFIFO;
	rule translateDoneTag;
		mdone.deq;
		let r_ = mdone.first;
		let tag = tpl_1(r_);
		let code = tpl_2(r_);

		doneStatusQ.enq(code);

		writeAddrMap.portB.request.put( BRAMRequest{
			write:False, responseOnWrite:False,
			address:truncate(tag),
			datain:?
			}
		);
	endrule
	FIFO#(DoneStatus) doneAddrQ <- mkFIFO;
	rule relayDoneAddr;
		let addr <- writeAddrMap.portB.response.get;
		let code = doneStatusQ.first;
		doneStatusQ.deq;
		doneAddrQ.enq(DoneStatus{code:code, addr:addr});
	endrule


	////////*///////////////// End Flash Status  (comand done, etc) //////////*/
	//////////////////////////////////////////////////////////////////////

	////////*///////////////// Start Flash Write //////////*/
	//////////////////////////////////////////////////////////////////////

	FIFO#(FlashWord) dataInQ <- mkFIFO;

	Reg#(Bit#(16)) writeWordCounter <- mkReg(0);
	Reg#(Tuple2#(Bit#(1),TagT)) curWriteTarget <- mkReg(?);

	Vector#(2, FIFO#(Tuple2#(TagT, FlashWord))) cardWriteQ <- replicateM(mkFIFO);

	Vector#(2, FIFO#(TagT)) writeOrderQ <- replicateM(mkSizedFIFO(writeTagCntPerCard));

	rule routeCardTarget;
		if ( writeWordCounter < (8192/32) ) begin
			dataInQ.deq;
			let w = dataInQ.first;

			let ctarget = curWriteTarget;
			if ( writeWordCounter == 0 ) begin
				writeReqOrderQ.deq;
				ctarget = writeReqOrderQ.first;
				curWriteTarget <= ctarget;
				writeOrderQ[tpl_1(ctarget)].enq(tpl_2(ctarget));
			end


			cardWriteQ[tpl_1(ctarget)].enq(tuple2(tpl_2(ctarget), w));

			writeWordCounter <= writeWordCounter + 1;
		end else if ( writeWordCounter + 1 < fromInteger(valueOf(PageSizeUser)/32) ) begin
			let ctarget = curWriteTarget;
			cardWriteQ[tpl_1(ctarget)].enq(tuple2(tpl_2(ctarget), 0));
			writeWordCounter <= writeWordCounter + 1;
		end else begin
			let ctarget = curWriteTarget;
			cardWriteQ[tpl_1(ctarget)].enq(tuple2(tpl_2(ctarget), 0));
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

			//flashes[cidx].writeWord(tuple2(w,t));
			writeReorderChain[cidx].enq(w,truncate(t));
		endrule
		Reg#(Bit#(16)) writeWordLeft <- mkReg(0);
		Reg#(TagT) curWriteTag <- mkReg(0);
		rule relayFlashWriteHW;
			let tag = curWriteTag;

			if ( writeWordLeft == 0 ) begin
				writeWordLeft <= fromInteger((valueOf(PageSizeUser)/16)-1);
				writeOrderQ[cidx].deq;
				tag = writeOrderQ[cidx].first;
			end else begin
				writeWordLeft <= writeWordLeft - 1;
			end
			writeReorderChain[cidx].deq;
			let d = writeReorderChain[cidx].first;
			flashes[cidx].writeWord(tuple2(d,tag));
		endrule
	end

	////////*///////////////// End Flash Write //////////*/
	//////////////////////////////////////////////////////////////////////

	method Action readPage(FlashAddress page);
		flashCmdQ.enq(decodeCommand(page, READ_PAGE));
	endmethod
	method Action writePage(FlashAddress page);
		flashCmdQ.enq(decodeCommand(page, WRITE_PAGE));
		flashWriteAddrQ.enq(page);
	endmethod
	method Action eraseBlock(FlashAddress block);
		flashCmdQ.enq(decodeCommand(block, ERASE_BLOCK));
		flashWriteAddrQ.enq(block);
	endmethod

	method ActionValue#(DoneStatus) doneStat;
		doneAddrQ.deq;
		return doneAddrQ.first;
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

