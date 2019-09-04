/*
*/

import Clocks::*;
import DefaultValue::*;
import FIFO::*;
import Vector::*;
import Connectable::*;

import Xilinx::*;
import XilinxCells::*;

// PCIe stuff
import PcieImport :: *;
import PcieCtrl :: *;
import PcieCtrl_bsim :: *;

// DRAM stuff
import DDR3Sim::*;
import DDR3Controller::*;
import DDR3Common::*;
import DRAMController::*;

import HwMain::*;

import AuroraImportFmc1::*;
import ControllerTypes::*;
import FlashCtrlVirtex1::*;
import FlashCtrlVirtex2::*;
import FlashCtrlModel::*;
import AuroraCommon::*;

interface TopIfc;
	(* always_ready *)
	interface PcieImportPins pcie_pins;
	(* always_ready *)
	method Bit#(4) led;
	
	interface DDR3_Pins_1GB pins_ddr3;
	
	(* always_ready *)
	interface Aurora_Pins#(4) aurora_fmc1;
	(* always_ready *)
	interface Aurora_Pins#(4) aurora_fmc2;
endinterface

(* no_default_clock, no_default_reset *)
module mkProjectTop #(
	Clock pcie_clk_p, Clock pcie_clk_n, Clock emcclk,
	Clock sys_clk_p, Clock sys_clk_n,
	Reset pcie_rst_n,

	Clock aurora_clk_fmc1_gtx_clk_n_v,
	Clock aurora_clk_fmc1_gtx_clk_p_v,
	Clock aurora_clk_fmc2_gtx_clk_n_v,
	Clock aurora_clk_fmc2_gtx_clk_p_v

	) 
		(TopIfc);


	PcieImportIfc pcie <- mkPcieImport(pcie_clk_p, pcie_clk_n, pcie_rst_n, emcclk);
	Clock pcie_clk_buf = pcie.sys_clk_o;
	Reset pcie_rst_n_buf = pcie.sys_rst_n_o;

	Clock sys_clk_200mhz <- mkClockIBUFDS(defaultValue, sys_clk_p, sys_clk_n);
	Clock sys_clk_200mhz_buf <- mkClockBUFG(clocked_by sys_clk_200mhz);
	Reset rst200 <- mkAsyncReset( 4, pcie_rst_n_buf, sys_clk_200mhz_buf);

	Clock user_clock = sys_clk_200mhz_buf;
	Reset user_reset = rst200;

	PcieCtrlIfc pcieCtrl <- mkPcieCtrl(pcie.user, clocked_by pcie.user_clk, reset_by pcie.user_reset);
	

	Clock ddr_buf = sys_clk_200mhz_buf;
	Reset ddr3ref_rst_n <- mkAsyncResetFromCR(4, ddr_buf, reset_by pcieCtrl.user.user_rst);

	DDR3Common::DDR3_Configure ddr3_cfg = defaultValue;
	ddr3_cfg.reads_in_flight = 32;   // adjust as needed
	DDR3_Controller_1GB ddr3_ctrl <- mkDDR3Controller_1GB(ddr3_cfg, ddr_buf, clocked_by ddr_buf, reset_by ddr3ref_rst_n);
	DRAMControllerIfc dramController <- mkDRAMController(ddr3_ctrl.user, clocked_by user_clock, reset_by user_reset); // clocked_by pcieCtrl.user.user_clk, reset_by pcieCtrl.user.user_rst);




	Vector#(2,FlashCtrlUser) flashes;
	FlashCtrlVirtexIfc flashCtrl1 <- mkFlashCtrlVirtex1(aurora_clk_fmc1_gtx_clk_p_v, aurora_clk_fmc1_gtx_clk_n_v, sys_clk_200mhz_buf, clocked_by user_clock, reset_by user_reset);
	FlashCtrlVirtexIfc flashCtrl2 <- mkFlashCtrlVirtex2(aurora_clk_fmc2_gtx_clk_p_v, aurora_clk_fmc2_gtx_clk_n_v, sys_clk_200mhz_buf, clocked_by user_clock, reset_by user_reset);
	flashes[0] = flashCtrl1.user;
	flashes[1] = flashCtrl2.user;



	HwMainIfc hwmain <- mkHwMain(pcieCtrl.user, dramController.user, flashes, clocked_by user_clock, reset_by user_reset);



	//ReadOnly#(Bit#(4)) leddata <- mkNullCrossingWire(noClock, pcieCtrl.leds);

	// Interfaces ////
	interface PcieImportPins pcie_pins = pcie.pins;

	interface DDR3_Pins_1GB pins_ddr3 = ddr3_ctrl.ddr3;
	
	interface Aurora_Pins aurora_fmc1 = flashCtrl1.aurora;
	interface Aurora_Pins aurora_fmc2 = flashCtrl2.aurora;

	method Bit#(4) led;
		//return leddata;
		return 0;
	endmethod
endmodule

module mkProjectTop_bsim (Empty);
	Clock curclk <- exposeCurrentClock;

	PcieCtrlIfc pcieCtrl <- mkPcieCtrl_bsim;
	
	let ddr3_ctrl_user <- mkDDR3Simulator;
	DRAMControllerIfc dramController <- mkDRAMController(ddr3_ctrl_user);
	
	FlashCtrlVirtexIfc flashCtrl1 <- mkFlashCtrlModel(curclk, curclk, curclk);
	FlashCtrlVirtexIfc flashCtrl2 <- mkFlashCtrlModel(curclk, curclk, curclk);
	Vector#(2,FlashCtrlUser) flashes;
	flashes[0] = flashCtrl1.user;
	flashes[1] = flashCtrl2.user;

	HwMainIfc hwmain <- mkHwMain(pcieCtrl.user, dramController.user, flashes);
	
	rule flushAlwaysEn;
		flashCtrl1.aurora.rxn_in(1);
		flashCtrl1.aurora.rxp_in(1);
		flashCtrl2.aurora.rxn_in(1);
		flashCtrl2.aurora.rxp_in(1);
	endrule
endmodule
