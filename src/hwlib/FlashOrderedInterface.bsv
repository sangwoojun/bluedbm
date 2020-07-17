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

interface FlashOrderedInterfaceUserIfc;
	method Action readPage(FlashAddress page);
	method Action writePage(FlashAddress page);
	method Action eraseBlock(FlashAddress block);

	// ONLY RETURNS ERASE RESULTS NOW!
	method ActionValue#(Tuple2#(FlashStatusCode,FlashAddress)) fevent;
	method ActionValue#(FlashWord) readWord;
	method Action writeWord(FlashWord data);
endinterface

interface FlashHwInterfaceIfc;
	method ActionValue#(Tuple2#(Bit#(8), FlashAddress)) readPage;
	method ActionValue#(Tuple2#(Bit#(8), FlashAddress)) writePage;
	method ActionValue#(Tuple2#(Bit#(8), FlashAddress)) eraseBlock;
	method Action fevent(FlashStatus status);
	method Action readWord(FlashTaggedWord word);
	method ActionValue#(FlashWord) writeWord;
endinterface




interface FlashOrderedInterfaceIfc;
	interface FlashOrderedInterfaceUserIfc user;
	interface FlashHwInterfaceIfc hw;
endinterface


// IMPORTANT all three should add up to less than 256!
typedef 32 ReadTagCnt;
typedef 32 WriteTagCnt;
typedef 32 EraseTagCnt;

(* synthesize *)
module mkFlashOrderedInterface (FlashOrderedInterfaceIfc);
	Integer readTagCnt = valueOf(ReadTagCnt);
	Integer writeTagCnt = valueOf(WriteTagCnt);
	Integer eraseTagCnt = valueOf(EraseTagCnt);
	Reg#(Bit#(TAdd#(1,TLog#(ReadTagCnt)))) readTagHead <- mkReg(0);
	Reg#(Bit#(TAdd#(1,TLog#(ReadTagCnt)))) readTagTail <- mkReg(0);
	Reg#(Bit#(TAdd#(1,TLog#(WriteTagCnt)))) writeTagHead <- mkReg(0);
	Reg#(Bit#(TAdd#(1,TLog#(WriteTagCnt)))) writeTagTail <- mkReg(0);
	Reg#(Bit#(TAdd#(1,TLog#(EraseTagCnt)))) eraseTagHead <- mkReg(0);
	Reg#(Bit#(TAdd#(1,TLog#(EraseTagCnt)))) eraseTagTail <- mkReg(0);
	
	FIFO#(Tuple2#(Bit#(8), FlashAddress)) flashmanReadPageReqQ <- mkFIFO;
	FIFO#(Tuple2#(Bit#(8), FlashAddress)) flashmanWritePageReqQ <- mkFIFO;
	FIFO#(Tuple2#(Bit#(8), FlashAddress)) flashmanEraseBlockReqQ <- mkFIFO;
	FIFO#(FlashWord) flashmanWriteWordQ <- mkFIFO;
	FIFO#(FlashStatus) flashmanFeventQ <- mkFIFO;
	FIFO#(FlashTaggedWord) flashmanReadWordQ <- mkFIFO;


	BLBurstOrderMergerIfc#(ReadTagCnt, FlashWord, 9) readOrder <- mkBLBurstOrderMerger(True); // 9 = 1+13-5 2*(8192/32)
	FIFO#(FlashAddress) readPageReqQ <- mkFIFO;
	rule procPageReadReq ( readTagHead-readTagTail < fromInteger(readTagCnt) );
		let tag = readTagHead;//(readTagHead-readTagTail);
		readTagHead <= readTagHead + 1;

		readPageReqQ.deq;
		let page = readPageReqQ.first;

		flashmanReadPageReqQ.enq(tuple2(zeroExtend(tag),page));
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
		flashmanReadWordQ.deq;
		let r = flashmanReadWordQ.first;
		Bit#(8) tag = tpl_2(r);
		FlashWord word = tpl_1(r);
		readOrder.enq(word,truncate(tag));
	endrule
	BLBurstOrderMergerIfc#(WriteTagCnt, FlashWord, 9) writeOrder <- mkBLBurstOrderMerger(True); // 9 = 1+13-5 2*(8192/32)



	//////////////// Write start //////////////////////////


	FIFO#(FlashWord) writeWordsQ <- mkFIFO;
	FIFO#(FlashAddress) writePageReqQ <- mkFIFO;
	Reg#(Bit#(8)) curWriteTag <- mkReg(0);
	Reg#(Bit#(10)) curWriteLeft <- mkReg(0);
	rule relayPageWrite;
		if ( curWriteLeft == 0 ) begin
			if ( writeTagHead - writeTagTail < fromInteger(writeTagCnt ) ) begin
				writePageReqQ.deq;
				let page = writePageReqQ.first;

				Bit#(8) tag = zeroExtend(writeTagHead+fromInteger(readTagCnt));
				writeTagHead <= writeTagHead + 1;

				flashmanWritePageReqQ.enq(tuple2(tag,page));
				curWriteTag <= tag;
				curWriteLeft <= 256-1; // 256 = 8192/32
				writeWordsQ.deq;
				writeOrder.enq(writeWordsQ.first, truncate(tag));
			end
		end else begin
			curWriteLeft <= curWriteLeft - 1;
			writeWordsQ.deq;
			writeOrder.enq(writeWordsQ.first, truncate(curWriteTag));
		end
	endrule

	Reg#(Bit#(16)) writeWordCnt <- mkReg(0);
	rule relayOrderedWord;
		writeOrder.deq;
		flashmanWriteWordQ.enq(writeOrder.first);
		
		if ( writeWordCnt + 1 >= 256 ) begin
			writeWordCnt <= 0;
			writeTagTail <= writeTagTail + 1;
		end else begin
			writeWordCnt <= writeWordCnt + 1;
		end
	endrule


	////////////  Erase start ////////////////////////////////////
	FIFO#(FlashAddress) eraseBlockReqQ <- mkFIFO;
	BRAM2Port#(Bit#(TLog#(EraseTagCnt)), FlashAddress) eraseTagMap <- mkBRAM2Server(defaultValue);
	rule procEraseReq ( eraseTagHead-eraseTagTail < fromInteger(eraseTagCnt) );
		eraseTagHead <= eraseTagHead + 1;
		Bit#(8) tag = zeroExtend(eraseTagHead) + fromInteger(writeTagCnt+readTagCnt);
		eraseBlockReqQ.deq;
		let block = eraseBlockReqQ.first;
		flashmanEraseBlockReqQ.enq(tuple2(zeroExtend(tag),block));
		eraseTagMap.portA.request.put(BRAMRequest{
			write:True, responseOnWrite:False,
			address:truncate(tag),
			datain: block
			});
	endrule


	FIFO#(FlashStatusCode) flashEventCodeQ <- mkSizedFIFO(4);
	FIFO#(Tuple2#(FlashStatusCode,FlashAddress)) flashEventQ <- mkSizedFIFO(8);
	rule handleFEvent;
		flashmanFeventQ.deq;
		FlashStatus stat = flashmanFeventQ.first;
		if ( stat.code == STATE_WRITE_READY ) begin
			writeOrder.req(truncate(stat.tag), 256); // 256 = 8192/32
		end else if ( stat.code == STATE_ERASE_FAIL || stat.code == STATE_ERASE_DONE ) begin
			flashEventCodeQ.enq(stat.code);
			eraseTagMap.portB.request.put(BRAMRequest{
				write:False, responseOnWrite:False,
				address:truncate(stat.tag),
				datain: ?
				});
		end else begin
			//TODO record... ignore?
		end
	endrule
	rule relayEraseStatus;
		let addr <- eraseTagMap.portB.response.get;
		flashEventCodeQ.deq;
		let code = flashEventCodeQ.first;
		flashEventQ.enq(tuple2(code, addr));
	endrule






	interface FlashOrderedInterfaceUserIfc user;
		method Action readPage(FlashAddress page);
			readPageReqQ.enq(page);
		endmethod
		method Action writePage(FlashAddress page);
			writePageReqQ.enq(page);
		endmethod

		method Action eraseBlock(FlashAddress block);
			eraseBlockReqQ.enq(block);
		endmethod

		method ActionValue#(Tuple2#(FlashStatusCode,FlashAddress)) fevent;
			flashEventQ.deq;
			return flashEventQ.first;
		endmethod
		method ActionValue#(FlashWord) readWord;
			readWordQ.deq;
			return readWordQ.first;
		endmethod
		method Action writeWord(FlashWord data);
			writeWordsQ.enq(data);
		endmethod
	endinterface

	interface FlashHwInterfaceIfc hw;
		method ActionValue#(Tuple2#(Bit#(8), FlashAddress)) readPage;
			flashmanReadPageReqQ.deq;
			return flashmanReadPageReqQ.first;
		endmethod
		method ActionValue#(Tuple2#(Bit#(8), FlashAddress)) writePage;
			flashmanWritePageReqQ.deq;
			return flashmanWritePageReqQ.first;
		endmethod
		method ActionValue#(Tuple2#(Bit#(8), FlashAddress)) eraseBlock;
			flashmanEraseBlockReqQ.deq;
			return flashmanEraseBlockReqQ.first;
		endmethod
		method Action fevent(FlashStatus status);
			flashmanFeventQ.enq(status);
		endmethod
		method Action readWord(FlashTaggedWord word);
			flashmanReadWordQ.enq(word);
		endmethod
		method ActionValue#(FlashWord) writeWord;
			flashmanWriteWordQ.deq;
			return flashmanWriteWordQ.first;
		endmethod
	endinterface
endmodule

endpackage: FlashOrderedInterface
