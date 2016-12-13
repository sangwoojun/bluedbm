
package Float32;

import FIFO::*;
import FloatingPoint::*;


interface FpPairImportIfc32;
	method Action enqa(Bit#(32) a);
	method Action enqb(Bit#(32) b);
	method ActionValue#(Bit#(32)) get;
endinterface

interface FpPairIfc;
	method Action enq(Bit#(32) a, Bit#(32) b);
	method Action deq;
	method Bit#(32) first;
endinterface

import "BVI" fp_sub32 =
module mkFpSubImport32#(Clock aclk, Reset arst) (FpPairImportIfc32);
	default_clock no_clock;
	default_reset no_reset;

	input_clock (aclk) = aclk;
	method m_axis_result_tdata get enable(m_axis_result_tready) ready(m_axis_result_tvalid) clocked_by(aclk);

	method enqa(s_axis_a_tdata) enable(s_axis_a_tvalid) ready(s_axis_a_tready) clocked_by(aclk);
	method enqb(s_axis_b_tdata) enable(s_axis_b_tvalid) ready(s_axis_b_tready) clocked_by(aclk);

	schedule (
		get, enqa, enqb
	) CF (
		get, enqa, enqb
	);
endmodule
import "BVI" fp_add32 =
module mkFpAddImport32#(Clock aclk, Reset arst) (FpPairImportIfc32);
	default_clock no_clock;
	default_reset no_reset;

	input_clock (aclk) = aclk;
	method m_axis_result_tdata get enable(m_axis_result_tready) ready(m_axis_result_tvalid) clocked_by(aclk);

	method enqa(s_axis_a_tdata) enable(s_axis_a_tvalid) ready(s_axis_a_tready) clocked_by(aclk);
	method enqb(s_axis_b_tdata) enable(s_axis_b_tvalid) ready(s_axis_b_tready) clocked_by(aclk);

	schedule (
		get, enqa, enqb
	) CF (
		get, enqa, enqb
	);
endmodule
import "BVI" fp_mult32 =
module mkFpMultImport32#(Clock aclk, Reset arst) (FpPairImportIfc32);
	default_clock no_clock;
	default_reset no_reset;

	input_clock (aclk) = aclk;
	method m_axis_result_tdata get enable(m_axis_result_tready) ready(m_axis_result_tvalid) clocked_by(aclk);

	method enqa(s_axis_a_tdata) enable(s_axis_a_tvalid) ready(s_axis_a_tready) clocked_by(aclk);
	method enqb(s_axis_b_tdata) enable(s_axis_b_tvalid) ready(s_axis_b_tready) clocked_by(aclk);

	schedule (
		get, enqa, enqb
	) CF (
		get, enqa, enqb
	);
endmodule

module mkFpSub32 (FpPairIfc);
	Clock curClk <- exposeCurrentClock;
	Reset curRst <- exposeCurrentReset;

	FIFO#(Bit#(32)) outQ <- mkFIFO;
`ifdef BSIM
`else
	FpPairImportIfc32 fp_sub <- mkFpSubImport32(curClk, curRst);
	rule getOut;
		let v <- fp_sub.get;
		outQ.enq(v);
	endrule
`endif

	method Action enq(Bit#(32) a, Bit#(32) b);
`ifdef BSIM
	Bool asign = a[31] == 1;
	Bool bsign = a[31] == 1;
	Bit#(8) ae = truncate(a>>23);
	Bit#(8) be = truncate(b>>23);
	Bit#(23) as = truncate(a);
	Bit#(23) bs = truncate(b);
	Float fa = Float{sign: asign, exp: ae, sfd: as};
	Float fb = Float{sign: bsign, exp: be, sfd: bs};
	Float fm = fa - fb;
	outQ.enq( {fm.sign?1:0,fm.exp,fm.sfd} );
`else
		fp_sub.enqa(a);
		fp_sub.enqb(b);
`endif
	endmethod
	method Action deq;
		outQ.deq;
	endmethod
	method Bit#(32) first;
		return outQ.first;
	endmethod
endmodule


module mkFpAdd32 (FpPairIfc);
	Clock curClk <- exposeCurrentClock;
	Reset curRst <- exposeCurrentReset;

	FIFO#(Bit#(32)) outQ <- mkFIFO;
`ifdef BSIM
`else
	FpPairImportIfc32 fp_add <- mkFpAddImport32(curClk, curRst);
	rule getOut;
		let v <- fp_add.get;
		outQ.enq(v);
	endrule
`endif

	method Action enq(Bit#(32) a, Bit#(32) b);
`ifdef BSIM
	Bool asign = a[31] == 1;
	Bool bsign = a[31] == 1;
	Bit#(8) ae = truncate(a>>23);
	Bit#(8) be = truncate(b>>23);
	Bit#(23) as = truncate(a);
	Bit#(23) bs = truncate(b);
	Float fa = Float{sign: asign, exp: ae, sfd: as};
	Float fb = Float{sign: bsign, exp: be, sfd: bs};
	Float fm = fa + fb;
	outQ.enq( {fm.sign?1:0,fm.exp,fm.sfd} );
`else
		fp_add.enqa(a);
		fp_add.enqb(b);
`endif
	endmethod
	method Action deq;
		outQ.deq;
	endmethod
	method Bit#(32) first;
		return outQ.first;
	endmethod
endmodule

module mkFpMult32 (FpPairIfc);
	Clock curClk <- exposeCurrentClock;
	Reset curRst <- exposeCurrentReset;

	FIFO#(Bit#(32)) outQ <- mkFIFO;
`ifdef BSIM
`else
	FpPairImportIfc32 fp_mult <- mkFpMultImport32(curClk, curRst);
	rule getOut;
		let v <- fp_mult.get;
		outQ.enq(v);
	endrule
`endif

	method Action enq(Bit#(32) a, Bit#(32) b);
`ifdef BSIM
	Bool asign = a[31] == 1;
	Bool bsign = a[31] == 1;
	Bit#(8) ae = truncate(a>>23);
	Bit#(8) be = truncate(b>>23);
	Bit#(23) as = truncate(a);
	Bit#(23) bs = truncate(b);
	Float fa = Float{sign: asign, exp: ae, sfd: as};
	Float fb = Float{sign: bsign, exp: be, sfd: bs};
	Float fm = fa * fb;
	outQ.enq( {fm.sign?1:0,fm.exp,fm.sfd} );
`else
		fp_mult.enqa(a);
		fp_mult.enqb(b);
`endif
	endmethod
	method Action deq;
		outQ.deq;
	endmethod
	method Bit#(32) first;
		return outQ.first;
	endmethod
endmodule


endpackage: Float32
