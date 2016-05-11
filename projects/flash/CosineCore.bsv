import FIFO::*;
import FIFOF::*;
import Clocks::*;
import Vector::*;

import BRAM::*;
import BRAMFIFO::*;

import MergeN::*;
import AcceleratorReader::*;
import Split4Width::*;

interface CosineCoreIfc;
	method Action dataIn(Bit#(128) data);
	method Action setQuery(Bit#(8) idx, Bit#(128) val);
	method Action setDictSize(Bit#(16) size);
	method ActionValue#(Tuple2#(Bit#(64), Bit#(16))) resOut;
endinterface

function Bit#(8) absdiff8(Bit#(8) a, Bit#(8) b);
	Bit#(8) r = b-a;
	if ( a > b ) r= a-b;
	return r;
endfunction

function Bit#(16) absdiff32(Bit#(32) a, Bit#(32) b ) ;
	Bit#(8) a0 = truncate(a);
	Bit#(8) a1 = truncate(a>>8);
	Bit#(8) a2 = truncate(a>>(8*2));
	Bit#(8) a3 = truncate(a>>(8*3));
	Bit#(8) b0 = truncate(b);
	Bit#(8) b1 = truncate(b>>8);
	Bit#(8) b2 = truncate(b>>(8*2));
	Bit#(8) b3 = truncate(b>>(8*3));
	return zeroExtend(absdiff8(a0, b0))+zeroExtend(absdiff8(a1, b1))+zeroExtend(absdiff8(a2, b2))+zeroExtend(absdiff8(a3, b3));
endfunction

function Bit#(16) absdiff128(Bit#(128) a, Bit#(128) b );
	Bit#(32) a0 = truncate(a);
	Bit#(32) a1 = truncate(a>>32);
	Bit#(32) a2 = truncate(a>>(32*2));
	Bit#(32) a3 = truncate(a>>(32*3));
	Bit#(32) b0 = truncate(b);
	Bit#(32) b1 = truncate(b>>32);
	Bit#(32) b2 = truncate(b>>(32*2));
	Bit#(32) b3 = truncate(b>>(32*3));
	return zeroExtend(absdiff32(a0, b0))+zeroExtend(absdiff32(a1, b1))+zeroExtend(absdiff32(a2, b2))+zeroExtend(absdiff32(a3, b3));
endfunction

module mkCosineCore(CosineCoreIfc);
	Reg#(Bit#(16)) dictSize <- mkReg(7); //112/16
	Vector#(16,Reg#(Bit#(128))) query <- replicateM(mkReg(0));

	Reg#(Bit#(64)) ooff <- mkReg(0);
	Reg#(Bit#(16)) totdiff <- mkReg(0);
	
	Reg#(Bit#(16)) wordsRemain <- mkReg(0);
	FIFO#(Bit#(128)) dataQ <- mkFIFO;

	Reg#(Bit#(16)) diff <- mkReg(0);
	FIFO#(Tuple2#(Bit#(64),Bit#(16))) diffQ <- mkFIFO;

	rule recvHeader(wordsRemain == 0);
		let h = dataQ.first;
		dataQ.deq;
		Bit#(64) off = truncate(h);
		ooff <= off;
		diff <= 0;
		wordsRemain <= dictSize;
		diffQ.enq(tuple2(ooff,totdiff));
		totdiff <= 0;
		$display( "%x", h );
	endrule


	rule recvData(wordsRemain > 0);
		wordsRemain <= wordsRemain - 1;
		Bit#(128) qw = query[dictSize-wordsRemain];
		Bit#(128) dw = dataQ.first;
		dataQ.deq;
		Bit#(16) dif = absdiff128(qw,dw);
		totdiff <= totdiff + dif;
		$display( "%x %x", dw, qw );
	endrule

	FIFO#(Tuple2#(Bit#(64),Bit#(16))) outQ <- mkFIFO;
	Reg#(Bit#(16)) thresh <- mkReg(5);
	rule filterOut;
		let d = diffQ.first;
		$display( "%x diff %d\n", tpl_1(d), tpl_2(d) );
		diffQ.deq;
		if (tpl_2(d) < thresh) outQ.enq(d);
	endrule

	method Action dataIn(Bit#(128) data);
		dataQ.enq(data);
	endmethod
	method Action setQuery(Bit#(8) idx, Bit#(128) val);
		query[idx] <= val;
		$display( "setting query at %d to %x", idx, val);
	endmethod
	method Action setDictSize(Bit#(16) size);
		dictSize <= size;
	endmethod
	method ActionValue#(Tuple2#(Bit#(64), Bit#(16))) resOut;
		outQ.deq;
		return outQ.first;
	endmethod
endmodule

module mkCosineCoreAccel(AcceleratorReaderIfc);
	CosineCoreIfc cc <- mkCosineCore;
	Split4WidthIfc#(128) split <- mkSplit4Width;
	rule feedData;
		split.deq;
		cc.dataIn(split.first);
	endrule

	FIFO#(Bit#(128)) outQ <- mkFIFO;
	rule relayOut;
		let d <- cc.resOut;
		outQ.enq({tpl_1(d), 32'h0, 16'h0, tpl_2(d)});
	endrule

	method Action dataIn(Bit#(512) d);
		split.enq(d);
	endmethod
	method Action cmdIn(Bit#(32) header, Bit#(128) cmd_);
		$display("cmdIn header %x", header);
		Bit#(8) t = truncate(header>>(16+8));
		Bit#(8) arg = truncate(header>>(16));
		if ( t == 0 ) begin
			cc.setDictSize(truncate(cmd_));
		end
		else if ( t == 1 ) begin
			cc.setQuery(arg, cmd_);
		end
	endmethod
	method ActionValue#(Bit#(128)) resOut;
		outQ.deq;
		return outQ.first;
	endmethod
endmodule
