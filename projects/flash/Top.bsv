/*
*/

import Clocks :: *;
import DefaultValue :: *;
import Xilinx :: *;
import XilinxCells :: *;

import PcieImport :: *;
import PcieCtrl :: *;
import PcieCtrl_bsim :: *;

import Clocks       :: *;
import FIFO::*;

import HwMain::*;

import AuroraCommon::*;

import AuroraImportFmc1::*;
import ControllerTypes::*;
import FlashCtrlVirtex::*;
import FlashCtrlModel::*;

//import Platform :: *;

//import NullReset :: *;
//import IlaImport :: *;

interface TopIfc;
	(* always_ready *)
	interface PcieImportPins pcie_pins;
	(* always_ready *)
	method Bit#(4) led;
	
	(* always_ready *)
	interface Aurora_Pins#(4) aurora_fmc1;
endinterface

(* no_default_clock, no_default_reset *)
module mkProjectTop #(
	Clock aurora_clk_fmc1_gtx_clk_n_v,
	Clock aurora_clk_fmc1_gtx_clk_p_v,

	Clock sys_clk_p, Clock sys_clk_n, Clock emcclk,
	Reset sys_rst_n
	) 
		(TopIfc);



	PcieEngine pcie <- mkPcieEngine(sys_clk_p, sys_clk_n, sys_rst_n, emcclk);
	Clock sys_clk_buf = pcie.sys_clk_o;
	Reset sys_rst_n_buf = pcie.sys_rst_n_o;
/*
	PcieImportIfc pcie <- mkPcieImport(sys_clk_p, sys_clk_n, sys_rst_n, emcclk);
	Clock sys_clk_buf = pcie.sys_clk_o;
	Reset sys_rst_n_buf = pcie.sys_rst_n_o;

	PcieCtrlIfc pcieCtrl <- mkPcieCtrl(pcie.user, clocked_by pcie.user_clk, reset_by pcie.user_reset);
	*/
		
	ClockGenerator7Params clk_params = defaultValue();
	clk_params.clkin1_period     = 10.000;       // 100 MHz reference
	clk_params.clkin_buffer      = False;       // necessary buffer is instanced above
	clk_params.reset_stages      = 0;           // no sync on reset so input clock has pll as only load
	clk_params.clkfbout_mult_f   = 10.000;       // 1000 MHz VCO
	clk_params.clkout0_divide_f  = 4;          // 250MHz clock
	clk_params.clkout1_divide    = 8;           // 125MHz clock
	ClockGenerator7 clk_gen <- mkClockGenerator7(clk_params, clocked_by sys_clk_buf, reset_by sys_rst_n_buf);
	Clock clk250 = clk_gen.clkout0;
	Reset rst250 <- mkSyncReset( 4, sys_rst_n_buf, clk250);
	
	Clock clk125 = clk_gen.clkout0;
	Reset rst125a <- mkAsyncReset( 8, sys_rst_n_buf, clk125);
	Reset rst125 <- mkSyncReset( 4, rst125a, clk125);
	
	FlashCtrlVirtexIfc flashCtrl <- mkFlashCtrlVirtex(aurora_clk_fmc1_gtx_clk_p_v, aurora_clk_fmc1_gtx_clk_n_v, clk250, clocked_by clk125, reset_by rst125);
	
	HwMainIfc hwmain <- mkHwMain(pcie.ctrl.user, flashCtrl.user, flashCtrl.man, clocked_by clk125, reset_by rst125);

	//ReadOnly#(Bit#(4)) leddata <- mkNullCrossingWire(noClock, pcieCtrl.leds);

	// Interfaces ////
	interface PcieImportPins pcie_pins = pcie.pins;
	interface Aurora_Pins aurora_fmc1 = flashCtrl.aurora;

	method Bit#(4) led;
		//return leddata;
		return 0;
	endmethod
endmodule

module mkProjectTop_bsim (Empty);
	Clock curclk <- exposeCurrentClock;

	PcieCtrlIfc pcieCtrl <- mkPcieCtrl_bsim;
	FlashCtrlVirtexIfc flashCtrl <- mkFlashCtrlModel(curclk, curclk, curclk);

	HwMainIfc hwmain <- mkHwMain(pcieCtrl.user, flashCtrl.user, flashCtrl.man);
	rule flushAlwaysEn;
		flashCtrl.aurora.rxn_in(1);
		flashCtrl.aurora.rxp_in(1);
	endrule
endmodule
