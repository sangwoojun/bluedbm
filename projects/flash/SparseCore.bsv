import FIFO::*;
import FIFOF::*;
import Clocks::*;
import Vector::*;

import BRAM::*;
import BRAMFIFO::*;

import MergeN::*;

/*
"last" is initialized to 0
00 : 30 bit delta
01 : 62 bit idx
10 : 30 bit delta (incr cidx)
11 : 62 bit idx (incr cidx)
*/

interface SparseDecoderIfc;
	method Action enq(Bit#(128) data);
	method Action deq;
	method Tuple3#(Bit#(64), Bit#(64), Bit#(64)) first;
endinterface

module mkSparseDecoder (SparseDecoderIfc);
	Reg#(Bit#(62)) lastridx <- mkReg(0);
	FIFO#(Bit#(128)) inQ <- mkFIFO;
	Reg#(Bit#(128)) inbuf <- mkReg(0);
	Reg#(Bit#(2)) inoff <- mkReg(0); // 32bit item offset (0~3)
	Reg#(Bit#(64)) cidx <- mkReg(0);

	FIFO#(Tuple3#(Bit#(64), Bit#(64), Bit#(64))) outQ <- mkFIFO;

	rule decodein( inoff == 0 );
		inQ.deq;
		let d = inQ.first;
		Bit#(2) code = truncate(d);
		Bit#(62) idx = truncate(d>>2);
		Bit#(62) last = lastridx;
		Bit#(64) cc = cidx;
		if ( code[1] == 1 ) begin
			last = 0;
			cidx <= cidx + 1;
			cc = cidx + 1;
		end

		Bit#(128) rbuf = (d>>64);
		if ( code[0] == 0 ) begin
			Bit#(30) delta = truncate(d>>2);
			idx = last + zeroExtend(delta);
			inoff <= 3;
			rbuf = (d>>32);
		end else begin
			inoff <= 2;
		end

		lastridx <= idx;

		inbuf <= rbuf;

		outQ.enq(tuple3(cc, zeroExtend(idx), 1));
		$display( "%d %d %d\n", cc, idx, 3 );
	endrule
	rule decodebuf( inoff >= 2 );
		let d = inbuf;
		Bit#(2) code = truncate(d);
		Bit#(62) idx = truncate(d>>2);
		Bit#(62) last = lastridx;
		Bit#(64) cc = cidx;
		if ( code[1] == 1 ) begin
			last = 0;
			cidx <= cidx + 1;
			cc = cidx + 1;
		end
		
		Bit#(128) rbuf = (d>>64);
		if ( code[0] == 0 ) begin
			Bit#(30) delta = truncate(d>>2);
			idx = last + zeroExtend(delta);
			inoff <= inoff-1;
			rbuf = (d>>32);
		end else begin
			inoff <= inoff-2;
		end
		lastridx <= idx;
		
		inbuf <= rbuf;

		outQ.enq(tuple3(cc, zeroExtend(idx), 1));
		$display( "%d %d %d\n", cc, idx, 2 );
	endrule

	rule decodelast( inoff == 1 );
		let d = inbuf;
		Bit#(2) code = truncate(d);
		Bit#(62) idx = 0;//truncate(d>>2);
		Bit#(62) last = lastridx;
		Bit#(64) cc = cidx;
		if ( code[1] == 1 ) begin
			last = 0;
			cidx <= cidx + 1;
			cc = cidx + 1;
		end
		
		Bit#(128) rbuf = (d>>32);
		if ( code[0] == 0 ) begin
			Bit#(30) delta = truncate(d>>2);
			idx = last + zeroExtend(delta);
			inoff <= inoff-1;
		end else begin
			inoff <= 3; // 2+1
			inQ.deq;
			let id = inQ.first;
			rbuf = (id>>32);
			Bit#(32) lid = truncate(id);
			Bit#(30) re = truncate(idx);
			idx = {0,lid,re};
		end
		
		lastridx <= idx;
		
		inbuf <= rbuf;

		outQ.enq(tuple3(cc, zeroExtend(idx), 1));
		$display( "%d %d %d\n", cc, idx, 1 );
	endrule

	method Action enq(Bit#(128) data);
		inQ.enq(data);
	endmethod
	method Action deq;
		outQ.deq;
	endmethod
	method Tuple3#(Bit#(64), Bit#(64), Bit#(64)) first;
		return outQ.first;
	endmethod
endmodule

interface SplitDRAM128Ifc;
	method Action enq(Bit#(512) data);
	method Action deq;
	method Bit#(128) first;
endinterface

module mkSplitDRAM128 (SplitDRAM128Ifc);
	Reg#(Bit#(512)) buffer <- mkReg(0);
	Reg#(Bit#(2)) cnt <- mkReg(0);
	FIFO#(Bit#(128)) outQ <- mkFIFO;
	rule split( cnt > 0 );
		cnt <= cnt - 1;
		outQ.enq(truncate(buffer));
		buffer <= (buffer>>128);
	endrule
	method Action enq(Bit#(512) data) if (cnt == 0);
		cnt <= 3;
		buffer <= (data>>128);
		outQ.enq(truncate(data));
	endmethod
	method Action deq;
		outQ.deq;
	endmethod
	method Bit#(128) first;
		return outQ.first;
	endmethod
endmodule


interface SparseCoreIfc;
	method Action queryIn(Bit#(64) idx, Bit#(64) val);

	method Action dataIn(Bit#(512) data);

	// Result, colIdx, done?
	//method ActionValue#(Tuple3#(Bit#(64),Bit#(64),Bool)) resultOut;
	// 
endinterface

typedef 12 SparseQueryIdxSz;

module mkSparseCore (SparseCoreIfc);

	SparseDecoderIfc dataDecoder <- mkSparseDecoder;
	SplitDRAM128Ifc split <- mkSplitDRAM128;
	rule feeddatadec;
		split.deq;
		dataDecoder.enq(split.first);
	endrule
	rule reda;
		dataDecoder.deq;
		let r = dataDecoder.first;
		let cidx = tpl_1(r);
		let ridx = tpl_2(r);
		let val = tpl_3(r);
		//$display( "%d %d %d\n", cidx, ridx, val );
	endrule


	FIFO#(Bit#(64)) queryIdxQ <- mkFIFO;
	BRAM2Port#(Bit#(SparseQueryIdxSz), Bit#(64)) queryBuffer <- mkBRAM2Server(defaultValue); //32KB
	Reg#(Bit#(SparseQueryIdxSz)) queryFillIdx; <- mkReg(0);
	Reg#(Bit#(64)) topQueryIdx <- mkReg(~0);
	rule fillQueryBuffer;
		queryIdxQ.deq;
		let idx = queryIdxQ.first;
		let qwidx = queryFillIdx;

		if ( idx < topQueryIdx ) begin
			queryFillIdx <= 0;
			qwidx = 0;
		end else begin
			queryFillIdx <= queryFillIdx + 1;
		end
		topQueryIdx <= idx;

		queryBuffer.portB.request.put(BRAMRequest{
			write: True, responseOnWrite:False,
			address: qwidx,
			datain: idx
			});
	endrule



	method Action queryIn(Bit#(64) idx, Bit#(64) val);
		queryIdxQ.enq(idx);
	endmethod

	method Action dataIn(Bit#(512) data);
		//dataDecoder.enq(data);
		split.enq(data);
	endmethod
	//method Action colIdx(Bit#(64) idx);
	//endmethod

	//method ActionValue#(Tuple3#(Bit#(64),Bit#(64),Bool)) resultOut;
	//	return ?;
	//endmethod
endmodule
