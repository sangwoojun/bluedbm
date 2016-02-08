
interface VNandInfra;
	interface Clock clk0;
	interface Clock clk90;
	interface Reset rst0;
	interface Reset rst90;
endinterface

import "BVI" nand_infrastructure_artix_model = 
module vMkNandInfraArtixModel#(Clock sysClkP, Clock sysClkN, Reset sysRstN)(VNandInfra);

default_clock no_clock;
default_reset no_reset;

input_clock sysClkP(sys_clk_p, (*unused*) sys_clk_p_GATE) = sysClkP;
input_clock sysClkN(sys_clk_n, (*unused*) sys_clk_n_GATE) = sysClkN;
input_reset sysRstN(sys_rst_n) clocked_by(no_clock) = sysRstN;

output_clock clk0(clk0);
output_clock clk90(clk90);

output_reset rst0(rstn0);
output_reset rst90(rstn90);

endmodule
