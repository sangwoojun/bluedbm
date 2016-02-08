package NullReset;

interface NullResetIfc;
	interface Reset rst;
	interface Reset rst_n;
endinterface

import "BVI" NullReset =
module mkNullReset (NullResetIfc);
	default_clock no_clock;
	default_reset no_reset;

	output_reset rst(RESET);
	output_reset rst_n(RESET_N);
endmodule

endpackage: NullReset
