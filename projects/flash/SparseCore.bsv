import FIFO::*;
import FIFOF::*;
import Clocks::*;
import Vector::*;

import BRAM::*;
import BRAMFIFO::*;

import MergeN::*;

interface SparseDecoderIfc;
	method Action enq(Bit#(128) data);
	method Action deq;
	method Tuple2#(Bit#(64), Bit#(64)) first;
endinterface

module mkSparseDecoder (SparseDecoderIfc);
	FIFO#(Tuple2#(Bit#(64),Bit#(64))) inQ <- mkFIFO;
	method Action enq(Bit#(128) data);
		inQ.enq(tuple2(truncate(data>>64),truncate(data)));
	endmethod
	method Action deq;
		inQ.deq;
	endmethod
	method Tuple2#(Bit#(64), Bit#(64)) first;
		return inQ.first;
	endmethod
endmodule


interface SparseCoreIfc;
	method Action queryIn(Bit#(128) data);

	method Action dataIn(Bit#(128) data);

	// Result, colIdx, done?
	//method ActionValue#(Tuple3#(Bit#(64),Bit#(64),Bool)) resultOut;
	// 
endinterface

module mkSparseCore (SparseCoreIfc);
	FIFO#(Bit#(128)) queryShardQ <- mkSizedBRAMFIFO(512+8); // +1 should work. +8 for safety
	Reg#(Bit#(32)) queryShardCnt <- mkReg(512);
	FIFO#(Bit#(128)) queryInQ <- mkFIFO;
	rule fillQueryShard;
		queryShardQ.enq(queryInQ.first);
		queryInQ.deq;
		if ( queryShardCnt > 0 ) begin
			queryShardCnt <= queryShardCnt - 1;
		end else begin
			queryShardQ.deq;
		end
	endrule

	SparseDecoderIfc dataDecoder <- mkSparseDecoder;




	method Action queryIn(Bit#(128) data);
		queryInQ.enq(data);
	endmethod

	method Action dataIn(Bit#(128) data);
		dataDecoder.enq(data);
	endmethod
	method Action colIdx(Bit#(64) idx);
	endmethod

	method ActionValue#(Tuple3#(Bit#(64),Bit#(64),Bool)) resultOut;
		return ?;
	endmethod
endmodule
