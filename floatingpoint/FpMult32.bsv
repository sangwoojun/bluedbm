
package FpMult32;

import FIFO::*;


interface FpMultImportIfc32;
	method Action enqa(Bit#(32) a);
	method Action enqb(Bit#(32) b);
	method ActionValue#(Bit#(32)) get;
endinterface

interface FpMultIfc32;
	method Action enq(Bit#(32) a, Bit#(32) b);
	method Action deq;
	method Bit#(32) first;
endinterface

import "BVI" fp_mult32 =
module mkFpMultImport32#(Clock aclk, Reset arst) (FpMultImportIfc32);
	default_clock no_clock;
	default_reset no_reset;

	input_clock (aclk) = aclk;
	method m_axis_result_tdata get enable(m_axis_result_tvalid) ready(m_axis_result_tready) clocked_by(aclk);

	method enqa(s_axis_a_tdata) enable(s_axis_a_tvalid) ready(s_axis_a_tready) clocked_by(aclk);
	method enqb(s_axis_b_tdata) enable(s_axis_b_tvalid) ready(s_axis_b_tready) clocked_by(aclk);

	schedule (
		get, enqa, enqb
	) CF (
		get, enqa, enqb
	);
endmodule

module mkFpMult32#(Clock aclk, Reset arst) (FpMultIfc32);
	FpMultImportIfc32 fp_mult <- mkFpMultImport32(aclk, arst);
	FIFO#(Bit#(32)) outQ <- mkFIFO;
	rule getOut;
		let v <- fp_mult.get;
		outQ.enq(v);
	endrule

	method Action enq(Bit#(32) a, Bit#(32) b);
		fp_mult.enqa(a);
		fp_mult.enqb(b);
	endmethod
	method Action deq;
		outQ.deq;
	endmethod
	method Bit#(32) first;
		return outQ.first;
	endmethod
endmodule


endpackage: FpMult32
