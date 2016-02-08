import Connectable       ::*;
import Clocks            ::*;
import FIFO              ::*;
import FIFOF             ::*;
import SpecialFIFOs      ::*;
import TriState          ::*;
import Vector            ::*;
import Counter           ::*;
import DefaultValue      ::*;


(* always_enabled, always_ready *)
interface NANDPins;
	//(* prefix = "", result = "WEN_NCLK" *)
	//method    Bit#(4)           wen_nclk;
	(* prefix = "", result = "CLE" *)
	method    Bit#(1)           cle;
	(* prefix = "", result = "ALE" *)
	method    Bit#(1)           ale;
	(* prefix = "", result = "WRN" *)
	method    Bit#(1)           wrn;
	(* prefix = "", result = "WPN" *)
	method    Bit#(1)           wpn;
	(* prefix = "", result = "CEN" *)
	method    Bit#(8)           cen;
	(* prefix = "DQ" *)
	interface Inout#(Bit#(8))  dq;
	(* prefix = "DQS" *)
	interface Inout#(Bit#(1))   dqs;
	
	//(* prefix = "", result = "DEBUG0" *)
	//method	Bit#(8)				debug0;
	//(* prefix = "", result = "DEBUG1" *)
	//method	Bit#(8)				debug1;
endinterface 

(* always_ready, always_enabled *)
interface VPhyUser;
	method Action setCLE (Bit#(1) i);
	method Action setALE (Bit#(1) i);
	method Action setWRN (Bit#(1) i);
	method Action setWPN (Bit#(1) i);
	method Action setCEN (Bit#(8) i);
	//method Action setWEN (Bit#(1) i);
	//method Action setWENSel (Bit#(1) i);
	
	//DQS delay control
	method Action dlyValDQS (Bit#(5) i);
	method Action dlyLdDQS (Bit#(1) i);
	method Bit#(5) dlyValOutDQS();

	//DQS output; clk0 domain
	method Action oenDQS (Bit#(1) i);
	method Action rstnDQS (Bit#(1) i);

	//DQ delay control; clk90 domain
	//method Action dlyIncDQ (Bit#(8) i);
	//method Action dlyCeDQ (Bit#(8) i);
	method Action oenDataDQ (Bit#(1) i);
	method Action iddrRstDQ (Bit#(1) i);
	
	method Action wrDataRiseDQ (Bit#(8) d);
	method Action wrDataFallDQ (Bit#(8) d);
	method Bit#(8) rdDataRiseDQ();
	method Bit#(8) rdDataFallDQ();
	method Bit#(8) rdDataCombDQ();

	method Bit#(8) calibDqRise0();
	method Bit#(8) calibDqRise90();
	method Bit#(8) calibDqRise180();
	method Bit#(8) calibDqRise270();
	method Action setCalibClk0Sel (Bit#(1) i);
endinterface

/*
interface VPhyDebug;
	interface Inout#(Bit#(36))   dbgCtrlIla;
	interface Inout#(Bit#(36))   dbgCtrlVio;
	method Action setDebug0 (Bit#(16) i);
	method Action setDebug1 (Bit#(16) i);
	method Action setDebug2 (Bit#(16) i);
	method Action setDebug3 (Bit#(16) i);
	method Action setDebug4 (Bit#(16) i);
	method Action setDebug5 (Bit#(16) i);
	method Action setDebug6 (Bit#(16) i);
	method Action setDebug7 (Bit#(16) i);
	method Action setDebugVin (Bit#(64) i);
	method Bit#(64) getDebugVout();
endinterface
*/

interface VNANDPhy;
	(* prefix = "" *)
	interface NANDPins   nandPins;
	interface VPhyUser  vphyUser;
	//interface VPhyDebug vphyDebug;
endinterface



import "BVI" nand_phy =
module vMkNandPhy#(
	Clock clk0, 
	Clock clk90, 
	Reset rstn0, 
	Reset rstn90
	)
	(
	//Inout#(Bit#(36)) dbgCtrlIla,
	//Inout#(Bit#(36)) dbgCtrlVio,
	VNANDPhy ifc);

//no default clock and reset
default_clock no_clock; 
default_reset no_reset;

input_clock clk0(v_clk0, (*unused*)vclk0_GATE) = clk0;
input_clock clk90(v_clk90, (*unused*)vclk90_GATE) = clk90;
input_reset rstn0(v_rstn0) clocked_by (clk0) = rstn0;
input_reset rstn90(v_rstn90) clocked_by (clk90) = rstn90;

//inout v_dbg_ctrl_ila clocked_by(no_clock) reset_by(no_reset) = dbgCtrlIla;
//inout v_dbg_ctrl_vio clocked_by(no_clock) reset_by(no_reset) = dbgCtrlVio;



interface NANDPins nandPins;
	ifc_inout dq(v_dq)             clocked_by(no_clock) reset_by(no_reset);
	ifc_inout dqs(v_dqs)           clocked_by(no_clock) reset_by(no_reset);

	//method    v_wen_nclk       wen_nclk     clocked_by(no_clock) reset_by(no_reset);
	method    v_cle 	cle         clocked_by(no_clock) reset_by(no_reset);
	method    v_ale 	ale         clocked_by(no_clock) reset_by(no_reset);
	method    v_wrn 	wrn         clocked_by(no_clock) reset_by(no_reset);
	method    v_wpn 	wpn         clocked_by(no_clock) reset_by(no_reset);
	method    v_cen 	cen         clocked_by(no_clock) reset_by(no_reset);
	//debug ports are really just old R/B signals
	//method	 v_debug0 debug0			clocked_by(no_clock) reset_by(no_reset);
	//method	 v_debug1 debug1	clocked_by(no_clock) reset_by(no_reset);
endinterface


interface VPhyUser vphyUser;
	method setCLE (v_ctrl_cle) enable((*inhigh*)en0) clocked_by(clk0) reset_by(rstn0);
	method setALE (v_ctrl_ale) enable((*inhigh*)en1) clocked_by(clk0) reset_by(rstn0);
	method setWRN (v_ctrl_wrn) enable((*inhigh*)en2) clocked_by(clk0) reset_by(rstn0);
	method setWPN (v_ctrl_wpn) enable((*inhigh*)en3) clocked_by(clk0) reset_by(rstn0);
	method setCEN (v_ctrl_cen) enable((*inhigh*)en4) clocked_by(clk0) reset_by(rstn0);
	//method setWEN (v_ctrl_wen) enable((*inhigh*)en16) clocked_by(clk0) reset_by(rstn0);
	//method setWENSel (v_ctrl_wen_sel) enable((*inhigh*)en17) clocked_by(clk0) reset_by(rstn0);
	
	
	//DQS delay control; clk90 domain
	method dlyValDQS (v_dlyval_dqs) enable((*inhigh*) en5) clocked_by(clk0) reset_by(rstn0);
	method dlyLdDQS (v_dlyld_dqs) enable((*inhigh*) en6) clocked_by(clk0) reset_by(rstn0);
	method v_dlyvalout_dqs dlyValOutDQS clocked_by(clk0) reset_by(rstn0);

	//DQS output; clk0 domain
	method oenDQS (v_dqs_oe_n) enable((*inhigh*) en7) clocked_by(clk0) reset_by(rstn0); //active low
	method rstnDQS (v_dqs_rst_n) enable((*inhigh*) en8) clocked_by(clk0) reset_by(rstn0);

	//DQ delay control; clk90 domain
	//method dlyIncDQ (v_dlyinc_dq) enable((*inhigh*) en9) clocked_by(clk90) reset_by(rstn90);
	//method dlyCeDQ (v_dlyce_dq) enable((*inhigh*) en10) clocked_by(clk90) reset_by(rstn90);
	
	//DQ data; changed to clk0 too
	method oenDataDQ (v_dq_oe_n) enable((*inhigh*) en11) clocked_by(clk0) reset_by(rstn0);
	method iddrRstDQ (v_dq_iddr_rst) enable((*inhigh*) en21) clocked_by(clk0) reset_by(rstn0);
	method wrDataRiseDQ (v_wr_data_rise) enable((*inhigh*) en12) clocked_by(clk0) reset_by(rstn0);
	method wrDataFallDQ (v_wr_data_fall) enable((*inhigh*) en13) clocked_by(clk0) reset_by(rstn0);
	method v_rd_data_rise rdDataRiseDQ() clocked_by(clk0) reset_by(rstn0);
	method v_rd_data_fall rdDataFallDQ() clocked_by(clk0) reset_by(rstn0);
	//DQ combinational data for async mode; clk0
	method v_rd_data_comb rdDataCombDQ() clocked_by(clk0) reset_by(rstn0);

	//Calibration signals
	method v_calib_dq_rise_0 calibDqRise0 clocked_by(clk0) reset_by(rstn0);
	method v_calib_dq_rise_90 calibDqRise90 clocked_by(clk0) reset_by(rstn0);
	method v_calib_dq_rise_180 calibDqRise180 clocked_by(clk0) reset_by(rstn0);
	method v_calib_dq_rise_270 calibDqRise270 clocked_by(clk0) reset_by(rstn0);
	method setCalibClk0Sel (v_calib_clk0_sel) enable((*inhigh*) en20) clocked_by(clk0) reset_by(rstn0);
endinterface
/*
interface VPhyDebug vphyDebug;
	//Debug signals
	ifc_inout dbgCtrlIla(v_dbg_ctrl_ila) clocked_by(no_clock) reset_by(no_reset);
	ifc_inout dbgCtrlVio(v_dbg_ctrl_vio) clocked_by(no_clock) reset_by(no_reset);
	method setDebug0 (v_ctrl_debug0) enable((*inhigh*)en30) clocked_by(clk0) reset_by(rstn0);
	method setDebug1 (v_ctrl_debug1) enable((*inhigh*)en31) clocked_by(clk0) reset_by(rstn0);
	method setDebug2 (v_ctrl_debug2) enable((*inhigh*)en32) clocked_by(clk0) reset_by(rstn0);
	method setDebug3 (v_ctrl_debug3) enable((*inhigh*)en33) clocked_by(clk0) reset_by(rstn0);
	method setDebug4 (v_ctrl_debug4) enable((*inhigh*)en34) clocked_by(clk0) reset_by(rstn0);
	method setDebug5 (v_ctrl_debug5) enable((*inhigh*)en35) clocked_by(clk0) reset_by(rstn0);
	method setDebug6 (v_ctrl_debug6) enable((*inhigh*)en36) clocked_by(clk0) reset_by(rstn0);
	method setDebug7 (v_ctrl_debug7) enable((*inhigh*)en37) clocked_by(clk0) reset_by(rstn0);
	method setDebugVin (v_ctrl_debug_vin) enable((*inhigh*)en38) clocked_by(clk0) reset_by(rstn0);
	method v_ctrl_debug_vout getDebugVout clocked_by(clk0) reset_by(rstn0);
endinterface
*/
//NAND pins are CF
schedule 
(/*nandPins_wen_nclk, */nandPins_cle, nandPins_ale, nandPins_wrn, nandPins_wpn, nandPins_cen /*, nandPins_debug0, nandPins_debug1*/) 
CF
(/*nandPins_wen_nclk,*/ nandPins_cle, nandPins_ale, nandPins_wrn, nandPins_wpn, nandPins_cen /*, nandPins_debug0, nandPins_debug1*/);

//Just set all other signals as CF
schedule
(vphyUser_dlyValDQS, vphyUser_dlyLdDQS, vphyUser_dlyValOutDQS,
vphyUser_calibDqRise0, vphyUser_calibDqRise90, vphyUser_calibDqRise180, vphyUser_calibDqRise270, vphyUser_setCalibClk0Sel,
vphyUser_setCLE, vphyUser_setALE, vphyUser_setWRN, vphyUser_setWPN, vphyUser_setCEN,
//vphyUser_setWEN, vphyUser_setWENSel,
vphyUser_oenDQS, vphyUser_rstnDQS, vphyUser_oenDataDQ, vphyUser_iddrRstDQ,
vphyUser_rdDataRiseDQ, vphyUser_rdDataFallDQ, vphyUser_rdDataCombDQ, vphyUser_wrDataRiseDQ, vphyUser_wrDataFallDQ)
//vphyDebug_setDebug0, vphyDebug_setDebug1, vphyDebug_setDebug2, vphyDebug_setDebug3, vphyDebug_setDebug4, 
//vphyDebug_setDebug5, vphyDebug_setDebug6, vphyDebug_setDebug7, vphyDebug_setDebugVin, vphyDebug_getDebugVout)
CF
(vphyUser_dlyValDQS, vphyUser_dlyLdDQS, vphyUser_dlyValOutDQS,
vphyUser_calibDqRise0, vphyUser_calibDqRise90, vphyUser_calibDqRise180, vphyUser_calibDqRise270, vphyUser_setCalibClk0Sel,
vphyUser_setCLE, vphyUser_setALE, vphyUser_setWRN, vphyUser_setWPN, vphyUser_setCEN,
//vphyUser_setWEN, vphyUser_setWENSel,
vphyUser_oenDQS, vphyUser_rstnDQS, vphyUser_oenDataDQ, vphyUser_iddrRstDQ,
vphyUser_rdDataRiseDQ, vphyUser_rdDataFallDQ, vphyUser_rdDataCombDQ, vphyUser_wrDataRiseDQ, vphyUser_wrDataFallDQ);
//vphyDebug_setDebug0, vphyDebug_setDebug1, vphyDebug_setDebug2, vphyDebug_setDebug3, vphyDebug_setDebug4, 
//vphyDebug_setDebug5, vphyDebug_setDebug6, vphyDebug_setDebug7, vphyDebug_setDebugVin, vphyDebug_getDebugVout);



endmodule


