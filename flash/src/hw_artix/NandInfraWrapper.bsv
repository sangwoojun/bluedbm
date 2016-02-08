
interface VNandInfra;
	interface Clock clk0;
	interface Clock clk90;
	interface Reset rst0;
	interface Reset rst90;
endinterface

import "BVI" nand_infrastructure = 
module vMkNandInfra#(Clock sysClkP, Clock sysClkN, Reset sysRstN)(VNandInfra);

default_clock no_clock;
default_reset no_reset;

input_clock sysClkP(sys_clk_p, (*unused*) sys_clk_p_GATE) = sysClkP;
input_clock sysClkN(sys_clk_n, (*unused*) sys_clk_n_GATE) = sysClkN;
input_reset sysRstN(sys_rst_n) clocked_by(no_clock) = sysRstN;

output_clock clk0(clk0);
output_clock clk90(clk90);

output_reset rst0(rstn0);
output_reset rst90(rstn90);

//ifc_inout dbgCtrl_0(dbg_ctrl_0) clocked_by(no_clock) reset_by(no_reset);
//ifc_inout dbgCtrl_1(dbg_ctrl_1) clocked_by(no_clock) reset_by(no_reset);
//ifc_inout dbgCtrl_2(dbg_ctrl_2) clocked_by(no_clock) reset_by(no_reset);
//ifc_inout dbgCtrl_3(dbg_ctrl_3) clocked_by(no_clock) reset_by(no_reset);
//ifc_inout dbgCtrl_4(dbg_ctrl_4) clocked_by(no_clock) reset_by(no_reset);
//ifc_inout dbgCtrl_5(dbg_ctrl_5) clocked_by(no_clock) reset_by(no_reset);
//ifc_inout dbgCtrl_6(dbg_ctrl_6) clocked_by(no_clock) reset_by(no_reset);
//ifc_inout dbgCtrl_7(dbg_ctrl_7) clocked_by(no_clock) reset_by(no_reset);
//ifc_inout dbgCtrl_8(dbg_ctrl_8) clocked_by(no_clock) reset_by(no_reset);
//ifc_inout dbgCtrl_9(dbg_ctrl_9) clocked_by(no_clock) reset_by(no_reset);
//ifc_inout dbgCtrl_10(dbg_ctrl_10) clocked_by(no_clock) reset_by(no_reset);
//ifc_inout dbgCtrl_11(dbg_ctrl_11) clocked_by(no_clock) reset_by(no_reset);
//ifc_inout dbgCtrl_12(dbg_ctrl_12) clocked_by(no_clock) reset_by(no_reset);
//ifc_inout dbgCtrl_13(dbg_ctrl_13) clocked_by(no_clock) reset_by(no_reset);
//ifc_inout dbgCtrl_14(dbg_ctrl_14) clocked_by(no_clock) reset_by(no_reset);
//ifc_inout dbgCtrl_15(dbg_ctrl_15) clocked_by(no_clock) reset_by(no_reset);

endmodule
