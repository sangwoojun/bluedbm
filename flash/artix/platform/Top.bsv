/*
*/

import Clocks :: *;
import DefaultValue :: *;
import Xilinx :: *;
import XilinxCells :: *;

import AuroraImportArtix7 :: *;
import Platform :: *;

import NullReset :: *;
//import IlaImport :: *;

interface ControllerTopIfc;
/*
	(* always_ready *)
	method Bit#(2) sfp_mgt_clk_sel;
	(* always_ready *)
	method Bit#(2) pcie_mgt_clk_sel;
	(* always_ready *)
	method Bit#(4) leds;
*/
	(* always_ready *)
	method Bit#(4) leds;
	interface Aurora_Pins#(4) pins_aurora;
	//interface AuroraTx_Pins aurora0_0;
	//interface Gtp_Pins gtp_pins;
endinterface

(* no_default_clock, no_default_reset *)
module mkControllerTop #(
	Clock sys_clk_p, Clock sys_clk_n, 
	Clock gtp_clk_0_p, 
	Clock gtp_clk_0_n
	) 
		(ControllerTopIfc);

	Clock sys_clk <- mkClockIBUFDS(sys_clk_p, sys_clk_n); // 100Mz
	Clock sys_clk_buf <- mkClockBUFG(clocked_by sys_clk);
	//MakeResetIfc sys_clk_rst_ifc <- mkReset(2, False, sys_clk_buf);
	NullResetIfc nullReset <- mkNullReset;
	Reset sys_clk_rst <- mkAsyncReset(4, nullReset.rst /*cpu_reset*/, sys_clk_buf, clocked_by sys_clk_buf);
	Reset sys_clk_rst_n <- mkResetInverter(sys_clk_rst, clocked_by sys_clk_buf);
	
	ClockDividerIfc clockdiv2 <- mkDCMClockDivider(2, 10, clocked_by sys_clk_buf, reset_by sys_clk_rst_n);
	Clock clk50s = clockdiv2.slowClock;



	Clock clk50 =clk50s;//<- mkClockBUFG(clocked_by clk50s);
	Clock clk50drp =clk50s;// <- mkClockBUFG(clocked_by clk50s);
	MakeResetIfc rst50ifc <- mkReset(8, True, clk50, clocked_by sys_clk_buf, reset_by sys_clk_rst_n);
	MakeResetIfc rst50ifc2 <- mkReset(8, True, clk50, clocked_by sys_clk_buf, reset_by sys_clk_rst_n);
	Reset rst50 = rst50ifc.new_rst;
	Reset rst50_2 = rst50ifc2.new_rst;
	

	Clock gtp_clk_0 <- mkClockIBUFDS_GTE2(True, gtp_clk_0_p, gtp_clk_0_n, clocked_by sys_clk_buf, reset_by sys_clk_rst_n);

	AuroraIfc auroraIfc <- mkAuroraIntra(gtp_clk_0, clocked_by sys_clk_buf, reset_by sys_clk_rst_n);
	Clock aclk = auroraIfc.clk;
	Reset arst = auroraIfc.rst;

	ControllerPlatformIfc platform <- mkPlatform(auroraIfc, sys_clk_buf, sys_clk_rst_n, clocked_by sys_clk_buf, reset_by sys_clk_rst_n);
	//ControllerPlatformIfc platform <- mkPlatform(auroraIfc, sys_clk_buf, sys_clk_rst_n, clocked_by aclk, reset_by arst);

	Reg#(Bit#(32)) ledC <- mkReg(0, clocked_by aclk, reset_by arst);
	Reg#(Bit#(32)) ledV <- mkReg(0, clocked_by sys_clk_buf, reset_by sys_clk_rst_n);
	Reg#(Bit#(32)) auroraResetCounter <- mkReg(0, clocked_by sys_clk_buf, reset_by sys_clk_rst_n);
	rule incAuroraRstC;
		auroraResetCounter <= auroraResetCounter + 1;
	endrule

	SyncFIFOIfc#(Bit#(32)) auroraL <- mkSyncFIFOToCC(32, aclk, arst, clocked_by sys_clk_buf, reset_by sys_clk_rst_n);
	rule incLedC;
		ledC <= ledC + 1;
		auroraL.enq(ledC);
	endrule
	rule deqLedC;
		auroraL.deq;
		ledV <= auroraL.first;
	endrule







	method Bit#(4) leds;
		Bit#(4) leddata = 0;
		leddata[0] = auroraResetCounter[27];
		leddata[1] = auroraResetCounter[27];
		leddata[2] = auroraResetCounter[27];
		leddata[3] = auroraResetCounter[27];
		return leddata;
	endmethod
	//interface AuroraTx_Pins aurora0_0 = auroraImport0_0.aurora;
	interface Aurora_Pins pins_aurora = auroraIfc.aurora;
	//interface Gtp_Pins gtp_pins = gtp0.gtp_pins;

endmodule
