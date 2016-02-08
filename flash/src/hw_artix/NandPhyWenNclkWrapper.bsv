import Connectable       ::*;
import Clocks            ::*;
import FIFO              ::*;
import Vector            ::*;


(* always_enabled, always_ready *)
interface NANDWenNclk;
	(* prefix = "", result = "WEN_NCLK" *)
	method    Bit#(4)           wen_nclk;
endinterface

(* always_ready, always_enabled *)
interface WenNclk;
	method Action setWEN (Bit#(1) i);
	method Action setWENSel (Bit#(1) i);
endinterface


interface VNANDPhyWenNclk;
	(* prefix = "" *)
	interface NANDWenNclk nandWenNclk;
	(* prefix = "" *)
	interface WenNclk wenNclk0;
	(* prefix = "" *)
	interface WenNclk wenNclk1;
endinterface


import "BVI" nand_phy_wen_nclk = 
module vMkNandPhyWenNclk#(Clock clk0, Reset rstn0)(VNANDPhyWenNclk);

default_clock no_clock;
default_reset no_reset;


input_clock clk0(v_clk0, (*unused*)vclk0_GATE) = clk0;
input_reset rstn0(v_rstn0) clocked_by (clk0) = rstn0;

interface NANDWenNclk nandWenNclk;
	method v_wen_nclk_shared wen_nclk clocked_by(no_clock) reset_by(no_reset);
endinterface

interface WenNclk wenNclk0;
	method setWEN (v_ctrl_wen_0) enable((*inhigh*)en0) clocked_by(clk0) reset_by(rstn0);
	method setWENSel (v_ctrl_wen_sel_0) enable((*inhigh*)en1) clocked_by(clk0) reset_by(rstn0);
endinterface

interface WenNclk wenNclk1;
	method setWEN (v_ctrl_wen_1) enable((*inhigh*)en2) clocked_by(clk0) reset_by(rstn0);
	method setWENSel (v_ctrl_wen_sel_1) enable((*inhigh*)en3) clocked_by(clk0) reset_by(rstn0);
endinterface


schedule
(nandWenNclk_wen_nclk, 
wenNclk0_setWEN, wenNclk0_setWENSel,
wenNclk1_setWEN, wenNclk1_setWENSel)
CF
(nandWenNclk_wen_nclk, 
wenNclk0_setWEN, wenNclk0_setWENSel,
wenNclk1_setWEN, wenNclk1_setWENSel);

endmodule


