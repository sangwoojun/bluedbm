package FlashOrderedInterface;

import FIFO::*;
import FIFOF::*;
import Clocks::*;
import Vector::*;

import BRAM::*;
import BRAMFIFO::*;

import FlashManagerCommon::*;

import DualFlashManagerBurst::*;
import BLBurstOrderMerger::*;

interface FlashOrderedInterfaceIfc;
	method Action readPage(FlashAddress page);
	method Action writePage(FlashAddress page);
	method Action eraseBlock(FlashAddress block);

	method ActionValue#(FlashStatusCode) fevent;
	method ActionValue#(FlashWord) readWord;
	method Action writeWord(FlashWord data);
endinterface


typedef 64 ReadTagCnt;
typedef 64 WriteTagCnt;

module mkFlashOrderedInterface#(DualFlashManagerBurstIfc flashman) (FlashOrderedInterfaceIfc);
	Integer readTagCnt = valueOf(ReadTagCnt);
	Integer writeTagCnt = valueOf(WriteTagCnt);

	Reg#(Bit#(TAdd#(1,TLog#(ReadTagCnt)))) readTagHead <- mkReg(0);
	Reg#(Bit#(TAdd#(1,TLog#(ReadTagCnt)))) readTagTail <- mkReg(0);




	FIFO#(Bit#(8)) freeWriteTagsQ <- mkSizedBRAMFIFO(writeTagCnt);
	Reg#(Bit#(9)) freeWriteTagCnt <- mkReg(0);
	rule populateWriteTags (freeWriteTagCnt <= fromInteger(writeTagCnt));
		freeWriteTagCnt <= freeWriteTagCnt + 1;
		freeWriteTagsQ.enq(truncate(freeWriteTagCnt));
	endrule
	

	BLBurstOrderMergerIfc#(ReadTagCnt, FlashWord, 9) readOrder <- mkBLBurstOrderMerger(True); // 9 = 1+13-5 2*(8192/32)
	FIFO#(FlashAddress) readPageReqQ <- mkFIFO;
	rule procPageReadReq ( readTagHead-readTagTail < fromInteger(readTagCnt) );
		let tag = (readTagHead-readTagTail);
		readTagHead <= readTagHead + 1;

		readPageReqQ.deq;
		let page = readPageReqQ.first;

		flashman.readPage(zeroExtend(tag), page);
		readOrder.req(truncate(tag), 256); // 256 = 8192/32
	endrule
	FIFO#(FlashWord) readWordQ <- mkFIFO;
	Reg#(Bit#(16)) readWordCnt <- mkReg(0);
	rule procReadWord;
		readOrder.deq;
		let d = readOrder.first;
		readWordQ.enq(d);
		if ( readWordCnt + 1 >= 256 ) begin
			readWordCnt <= 0;
			readTagTail <= readTagTail + 1;
		end else begin
			readWordCnt <= readWordCnt + 1;
		end
	endrule

	rule relayReadRes;
		let r <- flashman.readWord;
		Bit#(8) tag = tpl_2(r);
		FlashWord word = tpl_1(r);
		readOrder.enq(word,truncate(tag));
	endrule
	BLBurstOrderMergerIfc#(WriteTagCnt, FlashWord, 9) writeOrder <- mkBLBurstOrderMerger(True); // 9 = 1+13-5 2*(8192/32)

	rule handleFEvent;
		FlashStatus stat <- flashman.fevent;
		if ( stat.code == STATE_WRITE_READY ) begin
			writeOrder.req(truncate(stat.tag), 256); // 256 = 8192/32
		end else begin
			//TODO reorder
		end
	endrule

	FIFO#(FlashWord) writeWordsQ <- mkFIFO;
	FIFO#(FlashAddress) writePageReqQ <- mkFIFO;
	Reg#(Bit#(8)) curWriteTag <- mkReg(0);
	Reg#(Bit#(10)) curWriteLeft <- mkReg(0);
	rule relayPageWrite;
		if ( curWriteLeft == 0 ) begin
			writePageReqQ.deq;
			let page = writePageReqQ.first;

			freeWriteTagsQ.deq;
			let tag = freeWriteTagsQ.first;
			flashman.writePage(tag, page);
			curWriteTag <= tag;
			curWriteLeft <= 256-1; // 256 = 8192/32
			writeWordsQ.deq;
			writeOrder.enq(writeWordsQ.first, truncate(tag));
		end else begin
			curWriteLeft <= curWriteLeft - 1;
			writeWordsQ.deq;
			writeOrder.enq(writeWordsQ.first, truncate(curWriteTag));
		end
	endrule
	rule relayOrderedWord;
		writeOrder.deq;
		flashman.writeWord(writeOrder.first);
	endrule

	method Action readPage(FlashAddress page);
		readPageReqQ.enq(page);
	endmethod
	method Action writePage(FlashAddress page);
		writePageReqQ.enq(page);
	endmethod

	method Action eraseBlock(FlashAddress block);
	endmethod

	method ActionValue#(FlashStatusCode) fevent;
		return ?;
	endmethod
	method ActionValue#(FlashWord) readWord;
		readWordQ.deq;
		return readWordQ.first;
	endmethod
	method Action writeWord(FlashWord data);
		writeWordsQ.enq(data);
	endmethod
endmodule

endpackage: FlashOrderedInterface
