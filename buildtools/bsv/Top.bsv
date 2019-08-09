/*
*/

import FIFO::*;
import Vector::*;
import Clocks :: *;
import DefaultValue :: *;
import Xilinx :: *;
import XilinxCells :: *;
import Connectable::*;

import PcieImport :: *;
import PcieCtrl :: *;
import PcieCtrl_bsim :: *;


import HwMain::*;

import AuroraCommon::*;

import ControllerTypes::*;
import FlashCtrlModel::*;

import FlashCtrlVirtex1::*;
import FlashCtrlVirtex2::*;
import AuroraImportFmc1::*;
import AuroraImportFmc2::*;

//import Platform :: *;

//import NullReset :: *;
//import IlaImport :: *;

interface TopIfc;
	(* always_ready *)
	interface PcieImportPins pcie_pins;
	(* always_ready *)
	method Bit#(4) led;

`ifdef USE_FLASH
	(* always_ready *)
	interface Aurora_Pins#(4) aurora_fmc1;
	(* always_ready *)
	interface Aurora_Pins#(4) aurora_fmc2;
`endif

endinterface

(* no_default_clock, no_default_reset *)
module mkProjectTop #(
	Clock aurora_clk_fmc1_gtx_clk_n_v,
	Clock aurora_clk_fmc1_gtx_clk_p_v,
	Clock aurora_clk_fmc2_gtx_clk_n_v,
	Clock aurora_clk_fmc2_gtx_clk_p_v,

	Clock sys_clk_p, Clock sys_clk_n, Clock emcclk,
	Reset pcie_rst_n
	) 
		(TopIfc);



	PcieEngine pcie <- mkPcieEngine(sys_clk_p, sys_clk_n, pcie_rst_n, emcclk);
	Clock sys_clk_buf = pcie.sys_clk_o;
	Reset sys_rst_n_buf = pcie.sys_rst_n_o;

	ClockGenerator7Params clk_params = defaultValue();
	clk_params.clkin1_period     = 10.000;       // 100 MHz reference
	clk_params.clkin_buffer      = False;       // necessary buffer is instanced above
	clk_params.reset_stages      = 0;           // no sync on reset so input clock has pll as only load
	clk_params.clkfbout_mult_f   = 10.000;       // 1000 MHz VCO
	clk_params.clkout0_divide_f  = 4;          // 250MHz clock
	clk_params.clkout1_divide    = 8;           // 125MHz clock
	clk_params.clkout2_divide    = 5;          // 200MHz clock
	ClockGenerator7 clk_gen <- mkClockGenerator7(clk_params, clocked_by sys_clk_buf, reset_by sys_rst_n_buf);
	Clock clk250 = clk_gen.clkout0;
	Reset rst250 <- mkAsyncReset( 4, sys_rst_n_buf, clk250);

	Clock clk200 = clk_gen.clkout2;
	
	Clock clk125 = clk_gen.clkout1;
	Reset rst125 <- mkAsyncReset( 4, sys_rst_n_buf, clk125);
	//Reset rst125 <- mkSyncReset( 4, rst125a, clk125);

	Clock uclk = clk125;
	Reset urst = rst125;
	
	Vector#(2,FlashCtrlUser) flashes;
`ifdef USE_FLASH
	FlashCtrlVirtexIfc flashCtrl1 <- mkFlashCtrlVirtex1(aurora_clk_fmc1_gtx_clk_p_v, aurora_clk_fmc1_gtx_clk_n_v, clk250, clocked_by uclk, reset_by urst);
	FlashCtrlVirtexIfc flashCtrl2 <- mkFlashCtrlVirtex2(aurora_clk_fmc2_gtx_clk_p_v, aurora_clk_fmc2_gtx_clk_n_v, clk250, clocked_by uclk, reset_by urst);
	flashes[0] = flashCtrl1.user;
	flashes[1] = flashCtrl2.user;
`else
	flashes[0] <- mkNullFlashCtrlUser;
	flashes[1] <- mkNullFlashCtrlUser;
`endif

   
////////////////
	//HwMainIfc hwmain <- mkHwMain(pcie.ctrl.user, flashes, dramController.user, clk250, rst250, clocked_by pcie.ctrl.user.user_clk, reset_by pcie.ctrl.user.user_rst);
	HwMainIfc hwmain <- mkHwMain(pcie.ctrl.user, flashes, clk250, rst250, clocked_by uclk, reset_by urst);

	//ReadOnly#(Bit#(4)) leddata <- mkNullCrossingWire(noClock, pcieCtrl.leds);

	// Interfaces ////
	interface PcieImportPins pcie_pins = pcie.pins;
`ifdef USE_FLASH
	interface Aurora_Pins aurora_fmc1 = flashCtrl1.aurora;
	interface Aurora_Pins aurora_fmc2 = flashCtrl2.aurora;
`endif


	method Bit#(4) led;
		//return leddata;
		return 0;
	endmethod
endmodule

module mkProjectTop_bsim (Empty);
	Clock curclk <- exposeCurrentClock;
	Reset currst <- exposeCurrentReset;

	PcieCtrlIfc pcieCtrl <- mkPcieCtrl_bsim;
	FlashCtrlVirtexIfc flashCtrl1 <- mkFlashCtrlModel(curclk, curclk, curclk);
	FlashCtrlVirtexIfc flashCtrl2 <- mkFlashCtrlModel(curclk, curclk, curclk);
	Vector#(2,FlashCtrlUser) flashes;
	flashes[0] = flashCtrl1.user;
	flashes[1] = flashCtrl2.user;
	

	//DRAMControllerIfc dramController <- mkDRAMController();
	//mkConnection(dramController.ddr3_cli, ddr3_ctrl_user);

	HwMainIfc hwmain <- mkHwMain(pcieCtrl.user, flashes, /*flashCtrl2.man,*/ curclk, currst);
	rule flushAlwaysEn;
		flashCtrl1.aurora.rxn_in(1);
		flashCtrl1.aurora.rxp_in(1);
		flashCtrl2.aurora.rxn_in(1);
		flashCtrl2.aurora.rxp_in(1);
	endrule
endmodule
