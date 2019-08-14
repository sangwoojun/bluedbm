/*
*/

import Clocks :: *;
import DefaultValue :: *;
import Xilinx :: *;
import XilinxCells :: *;


import NullReset :: *;

interface ControllerTopIfc;
	(* always_ready *)
	method Bit#(4) leds;
endinterface

(* no_default_clock, no_default_reset *)
module mkControllerTop #(
	Clock sys_clk_p, Clock sys_clk_n
	) 
		(ControllerTopIfc);

	Clock sys_clk <- mkClockIBUFDS(defaultValue, sys_clk_p, sys_clk_n); // 100Mz
	Clock sys_clk_buf <- mkClockBUFG(clocked_by sys_clk);
	//MakeResetIfc sys_clk_rst_ifc <- mkReset(2, False, sys_clk_buf);
	NullResetIfc nullReset <- mkNullReset;
	Reset sys_clk_rst <- mkAsyncReset(4, nullReset.rst /*cpu_reset*/, sys_clk_buf, clocked_by sys_clk_buf);
	Reset sys_clk_rst_n <- mkResetInverter(sys_clk_rst, clocked_by sys_clk_buf);
	
	Reg#(Bit#(32)) auroraResetCounter <- mkReg(0, clocked_by sys_clk_buf, reset_by sys_clk_rst_n);
	rule incAuroraRstC;
		auroraResetCounter <= auroraResetCounter + 1;
	endrule


	method Bit#(4) leds;
		Bit#(4) leddata = 0;
		leddata[0] = auroraResetCounter[27];
		leddata[1] = auroraResetCounter[27];
		leddata[2] = auroraResetCounter[27];
		leddata[3] = auroraResetCounter[27];
		return leddata;
	endmethod
endmodule
