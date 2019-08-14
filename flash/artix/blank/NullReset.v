module NullReset ( RESET, RESET_N );
	output RESET;
	output RESET_N;

	assign RESET = 0;
	assign RESET_N = 1;
endmodule
