package PageSortToDram;

import FIFO::*;
import FIFOF::*;
import Clocks::*;
import Vector::*;
import BRAM::*;
import BRAMFIFO::*;

import Serializer::*;
import PageSorterSingle::*;
import SortingNetwork::*;
import SortingNetworkN::*;
import MergeSortReducerSingle::*;

typedef 4 PageSorterCnt;

interface PageSortToDramIfc;
	method Action put(Bit#(32) key, Bit#(32) val);
	method ActionValue#(Tuple3#(Bool,Bit#(32),Bit#(16))) dramReq;
	method ActionValue#(Bit#(512)) dramWriteData;
endinterface

(* synthesize *)
module mkPageSortToDram (PageSortToDramIfc);
	Integer icnt = valueOf(PageSorterCnt);

	SortingNetworkIfc#(Bit#(64),8) sortingnet <- mkSortingNetwork8(False);
	DeSerializerIfc#(64, 8) sortingNetDes <- mkDeSerializer;
	SerializerIfc#(512,8) sortingNetSer <- mkSerializer;
	// only 4 to keep BRAM footprint low -- needs 5 to get full 1.6 GB/s with presort = 3
	Vector#(PageSorterCnt,PageSorterSingleIfc#(Bit#(64), 8)) pagesorters <- replicateM(mkPageSorterSingle(3, False)); // 8 = 2KB of 8byte values. 3 = preSorted 8 elements
	
	rule feedSortingNet;
		let v <- sortingNetDes.get;
		Vector#(8,Bit#(64)) snetin = newVector;
		for ( Integer i = 0; i < 8; i=i+1 ) begin
			snetin[i] = v[(i*64)+63:(i*64)];
		end
		sortingnet.enq(snetin);
	endrule
	rule reserializeSortingNet;
		let r <- sortingnet.get;
		Bit#(512) sorted = {r[7],r[6],r[5],r[4],r[3],r[2],r[1],r[0]};
		sortingNetSer.put(sorted);
	endrule
	Reg#(Bit#(16)) pageSorterElementCount <- mkReg(0);
	Reg#(Bit#(3)) curPageSorterTarget <- mkReg(0); // only 4
	//TODO padding when not 2kb aligned


	rule relayPageSorter;
		let r <- sortingNetSer.get;
		if ( pageSorterElementCount + 1 >= 256 ) begin // TODO 2kb!
			pageSorterElementCount <= 0;
			if ( curPageSorterTarget + 1 >= fromInteger(icnt) ) begin
				curPageSorterTarget <= 0;
			end else begin
				curPageSorterTarget <= curPageSorterTarget + 1;
			end
			pagesorters[curPageSorterTarget].enq(r);
		end else begin
			pagesorters[curPageSorterTarget].enq(r);
			pageSorterElementCount <= pageSorterElementCount + 1;
		end
	endrule
	MergeSortReducerSingleIfc#(PageSorterCnt,Bit#(32),Bit#(32)) mergeToDRAM <- mkMergeSortReducerSingle;
	for ( Integer i = 0; i < icnt; i=i+1 ) begin
		FIFO#(Bit#(64)) bufferQ <- mkSizedBRAMFIFO(256); // TODO 2kb!
		rule getsorted;
			let d <- pagesorters[i].get;
			bufferQ.enq(d);
		endrule
		Reg#(Bit#(16)) sortedElemCnt <- mkReg(0);
		rule relaysorted;
			bufferQ.deq;
			let d = bufferQ.first;
			if ( sortedElemCnt + 1 >= 256 ) begin
				mergeToDRAM.enq[i].enq(truncate(d>>32),truncate(d), True);
				sortedElemCnt <= 0;
			end else begin
				mergeToDRAM.enq[i].enq(truncate(d>>32),truncate(d), False);
				sortedElemCnt <= sortedElemCnt + 1;
			end
		endrule
	end

	DeSerializerIfc#(64, 8) desToDram <- mkDeSerializer;
	DeSerializerIfc#(1, 8) desToLast <- mkDeSerializer;
	Reg#(Bit#(3)) desPaddingCnt <- mkReg(0);
	Reg#(Bit#(3)) desOffset <- mkReg(0);
	Reg#(Bit#(32)) totalBytes <- mkReg(0);
	FIFO#(Bit#(32)) totalBytesQ <- mkFIFO;
	rule getSRResult (desPaddingCnt == 0);
		let d <- mergeToDRAM.get;
		desOffset <= desOffset + 1;
		if ( tpl_3(d) ) begin
			desPaddingCnt <= desOffset + 1;
			totalBytes <= 0;
			totalBytesQ.enq(totalBytes);
			desToLast.put(1);
		end else begin
			totalBytes <= totalBytes + 8;
			desToLast.put(0);
		end
		desToDram.put({tpl_1(d),tpl_2(d)});
	endrule
	rule padSRResult ( desPaddingCnt > 0 );
		desPaddingCnt <= desPaddingCnt + 1;
		desToDram.put(0);
		desToLast.put(1);
	endrule
	FIFO#(Bit#(512)) outQ <- mkSizedBRAMFIFO(64);
	Reg#(Bit#(16)) bufferCount <- mkReg(0);
	FIFO#(Tuple3#(Bool, Bit#(32), Bit#(16))) dramReqQ <- mkFIFO;
	FIFO#(Bit#(8)) outBufDoneQ <- mkFIFO;

	Reg#(Bit#(8)) curOutBufIdx <- mkReg(0);
	rule bufferDes;
		let r <- desToDram.get;
		let l <- desToLast.get;
		outQ.enq(r);
		if ( bufferCount +1 > 32 ) begin
			bufferCount <= bufferCount + 1 - 32;
			dramReqQ.enq(tuple3(True, zeroExtend(curOutBufIdx)*32, 32)); //FIXME offset
			curOutBufIdx <= (curOutBufIdx + 1 ) & 8'h3f;
			outBufDoneQ.enq(curOutBufIdx);
		end else if ( l > 0 ) begin // last element 
			bufferCount <= 0;
			dramReqQ.enq(tuple3(True, zeroExtend(curOutBufIdx)*32, bufferCount+1)); //FIXME offset
			curOutBufIdx <= (curOutBufIdx + 1 ) & 8'h3f;
			outBufDoneQ.enq(curOutBufIdx);
		end else begin
			bufferCount <= bufferCount + 1;
		end
	endrule


	method Action put(Bit#(32) key, Bit#(32) val);
		sortingNetDes.put({key,val});
	endmethod
	method ActionValue#(Tuple3#(Bool,Bit#(32),Bit#(16))) dramReq;
		dramReqQ.deq;
		return dramReqQ.first;
	endmethod
	method ActionValue#(Bit#(512)) dramWriteData;
		outQ.deq;
		return outQ.first;
	endmethod
endmodule

endpackage: PageSortToDram
