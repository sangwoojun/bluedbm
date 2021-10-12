/*
*/

import Clocks::*;
import ClockImport::*;
import DefaultValue::*;
import FIFO::*;
import Vector::*;
import Connectable::*;

// PCIe stuff
import PcieImport :: *;
import PcieCtrl :: *;
import PcieCtrl_bsim :: *;

// DRAM stuff
import DDR3Sim::*;
import DDR3Controller::*;
import DDR3Common::*;
import DRAMController::*;

// Aurora stuff
import AuroraCommon::*;
import AuroraExtImport::*;
import AuroraExtImport117::*;
import AuroraImportFmc1::*;

import HwMain::*;

interface TopIfc;
	(* always_ready *)
	interface PcieImportPins pcie_pins;
	(* always_ready *)
	method Bit#(4) led;
	
	interface DDR3_Pins_1GB pins_ddr3;
	
	(* always_ready *)
	interface Vector#(AuroraExtPerQuad, Aurora_Pins#(1)) aurora_ext;
	(* always_ready *)
	interface Aurora_Clock_Pins aurora_quad_117;
	(* always_ready *)
	interface Aurora_Clock_Pins aurora_quad_119;
endinterface

(* no_default_clock, no_default_reset *)
module mkProjectTop #(
	Clock pcie_clk_p, Clock pcie_clk_n, Clock emcclk,
	Clock sys_clk_p, Clock sys_clk_n,
	Reset pcie_rst_n,

	Clock aurora_clk_117_gtx_clk_n_v,
	Clock aurora_clk_117_gtx_clk_p_v,
	Clock aurora_clk_119_gtx_clk_n_v,
	Clock aurora_clk_119_gtx_clk_p_v

	) 
		(TopIfc);


	PcieImportIfc pcie <- mkPcieImport(pcie_clk_p, pcie_clk_n, pcie_rst_n, emcclk);
	Clock pcie_clk_buf = pcie.sys_clk_o;
	Reset pcie_rst_n_buf = pcie.sys_rst_n_o;

	ClockGenIfc clk_200mhz_import <- mkClockIBUFDSImport(sys_clk_p, sys_clk_n);
	Clock sys_clk_200mhz = clk_200mhz_import.gen_clk;
	ClockGenIfc sys_clk_200mhz_buf_import <- mkClockBUFGImport(clocked_by sys_clk_200mhz);
	Clock sys_clk_200mhz_buf = sys_clk_200mhz_buf_import.gen_clk;
	Reset rst200 <- mkAsyncReset( 4, pcie_rst_n_buf, sys_clk_200mhz_buf);

	PcieCtrlIfc pcieCtrl <- mkPcieCtrl(pcie.user, clocked_by pcie.user_clk, reset_by pcie.user_reset);
	

	Clock ddr_buf = sys_clk_200mhz_buf;
	Reset ddr3ref_rst_n <- mkAsyncResetFromCR(4, ddr_buf, reset_by pcieCtrl.user.user_rst);

	DDR3Common::DDR3_Configure ddr3_cfg = defaultValue;
	ddr3_cfg.reads_in_flight = 32;   // adjust as needed
	DDR3_Controller_1GB ddr3_ctrl <- mkDDR3Controller_1GB(ddr3_cfg, ddr_buf, clocked_by ddr_buf, reset_by ddr3ref_rst_n);
	DRAMControllerIfc dramController <- mkDRAMController(ddr3_ctrl.user, clocked_by pcieCtrl.user.user_clk, reset_by pcieCtrl.user.user_rst);


	Clock user_clock = sys_clk_200mhz_buf;
	Reset user_reset = rst200;


	Vector#(2,AuroraExtUserIfc) auroraExts;
	AuroraExtIfc auroraExt117 <- mkAuroraExt117(aurora_clk_117_gtx_clk_p_v, aurora_clk_117_gtx_clk_n_v, sys_clk_200mhz_buf, clocked_by user_clock, reset_by user_reset);
	AuroraExtIfc auroraExt119 <- mkAuroraExt(aurora_clk_117_gtx_clk_p_v, aurora_clk_119_gtx_clk_n_v, sys_clk_200mhz_buf, clocked_by user_clock, reset_by user_reset);
	auroraExts[0] = auroraExt117.user;
	auroraExts[1] = auroraExt119.user;



	HwMainIfc hwmain <- mkHwMain(pcieCtrl.user, dramController.user, auroraExts, clocked_by user_clock, reset_by user_reset);



	//ReadOnly#(Bit#(4)) leddata <- mkNullCrossingWire(noClock, pcieCtrl.leds);

	// Interfaces ////
	interface PcieImportPins pcie_pins = pcie.pins;

	interface DDR3_Pins_1GB pins_ddr3 = ddr3_ctrl.ddr3;
	
	interface Aurora_Clock_Pins aurora_117 = auroraExt117.aurora;
	interface Aurora_Clock_Pins aurora_119 = auroraExt119.aurora;

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
	
	AuroraExtIfc auroraExt117 <- mkAuroraExt117(curclk, curclk, curclk);
	AuroraExtIfc auroraExt119 <- mkAuroraExt(curclk, curclk, curclk);
	Vector#(2,AuroraExtUserIfc) auroraExts;
	auroraExts[0] = auroraExt117.user;
	auroraExts[1] = auroraExt119.user;

	HwMainIfc hwmain <- mkHwMain(pcieCtrl.user, dramController.user, auroraExts);
	
endmodule
