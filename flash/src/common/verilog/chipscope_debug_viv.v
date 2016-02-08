
module chipscope_debug_viv (
	input v_clk0,
	input v_rst0,
	input [63:0] v_debug_vin,
	output [63:0] v_debug_vout,

	input [15:0] v_debug0_0, //raw data
	input [15:0] v_debug0_1,//bus state
	input [15:0] v_debug0_2, //bus addr
	input [15:0] v_debug0_3, //ecc data
	input [15:0] v_debug0_4, //ctrl state
	input [63:0] v_debug0_5_64, //latency cnt
	input [63:0] v_debug0_6_64, //err cnt

	input [15:0] v_debug1_0, //raw data
	input [15:0] v_debug1_1,//bus state
	input [15:0] v_debug1_2, //ecc data
	input [15:0] v_debug1_3, //ctrl state
	input [15:0] v_debug1_4, //cmd cnt
	input [63:0] v_debug1_5_64, //latency cnt
	input [63:0] v_debug1_6_64, //err cnt

	input [15:0] v_debug2_0, //raw data
	input [15:0] v_debug2_1,//bus state
	input [15:0] v_debug2_2, //ecc data
	input [15:0] v_debug2_3, //ctrl state
	input [15:0] v_debug2_4, //cmd cnt
	input [63:0] v_debug2_5_64, //latency cnt
	input [63:0] v_debug2_6_64, //err cnt

	input [15:0] v_debug3_0, //raw data
	input [15:0] v_debug3_1,//bus state
	input [15:0] v_debug3_2, //ecc data
	input [15:0] v_debug3_3, //ctrl state
	input [15:0] v_debug3_4, //cmd cnt
	input [63:0] v_debug3_5_64, //latency cnt
	input [63:0] v_debug3_6_64, //err cnt

	input [15:0] v_debug4_0, //raw data
	input [15:0] v_debug4_1,//bus state
	input [15:0] v_debug4_2, //bus addr
	input [15:0] v_debug4_3, //ecc data
	input [15:0] v_debug4_4, //ctrl state
	input [63:0] v_debug4_5_64, //latency cnt
	input [63:0] v_debug4_6_64, //err cnt

	input [15:0] v_debug5_0, //raw data
	input [15:0] v_debug5_1,//bus state
	input [15:0] v_debug5_2, //ecc data
	input [15:0] v_debug5_3, //ctrl state
	input [15:0] v_debug5_4, //cmd cnt
	input [63:0] v_debug5_5_64, //latency cnt
	input [63:0] v_debug5_6_64, //err cnt

	input [15:0] v_debug6_0, //raw data
	input [15:0] v_debug6_1,//bus state
	input [15:0] v_debug6_2, //ecc data
	input [15:0] v_debug6_3, //ctrl state
	input [15:0] v_debug6_4, //cmd cnt
	input [63:0] v_debug6_5_64, //latency cnt
	input [63:0] v_debug6_6_64, //err cnt

	input [15:0] v_debug7_0, //raw data
	input [15:0] v_debug7_1,//bus state
	input [15:0] v_debug7_2, //ecc data
	input [15:0] v_debug7_3, //ctrl state
	input [15:0] v_debug7_4, //cmd cnt
	input [63:0] v_debug7_5_64, //latency cnt
	input [63:0] v_debug7_6_64 //err cnt
);


	vio_0 vio (
		.clk(v_clk0),
		.probe_in0(v_debug_vin),
		.probe_out0(v_debug_vout)
	);

	
//	(* mark_debug = "true", keep = "true" *) wire [15:0] v_test;
//	assign v_test = v_debug0_0;

	(* mark_debug = "true" *) reg [15:0] v_debug0_0_reg;
	(* mark_debug = "true" *) reg [15:0] v_debug0_1_reg;
	(* mark_debug = "true" *) reg [15:0] v_debug0_2_reg;
	(* mark_debug = "true" *) reg [15:0] v_debug0_3_reg;
	(* mark_debug = "true" *) reg [15:0] v_debug0_4_reg;
	(* mark_debug = "true" *) reg [63:0] v_debug0_5_64_reg;
	(* mark_debug = "true" *) reg [63:0] v_debug0_6_64_reg;

	(* mark_debug = "true" *) reg [15:0] v_debug1_0_reg;
	(* mark_debug = "true" *) reg [15:0] v_debug1_1_reg;
	(* mark_debug = "true" *) reg [15:0] v_debug1_2_reg;
	(* mark_debug = "true" *) reg [15:0] v_debug1_3_reg;
	(* mark_debug = "true" *) reg [15:0] v_debug1_4_reg;
	(* mark_debug = "true" *) reg [63:0] v_debug1_5_64_reg;
	(* mark_debug = "true" *) reg [63:0] v_debug1_6_64_reg;

	(* mark_debug = "true" *) reg [15:0] v_debug2_0_reg;
	(* mark_debug = "true" *) reg [15:0] v_debug2_1_reg;
	(* mark_debug = "true" *) reg [15:0] v_debug2_2_reg;
	(* mark_debug = "true" *) reg [15:0] v_debug2_3_reg;
	(* mark_debug = "true" *) reg [15:0] v_debug2_4_reg;
	(* mark_debug = "true" *) reg [63:0] v_debug2_5_64_reg;
	(* mark_debug = "true" *) reg [63:0] v_debug2_6_64_reg;

	(* mark_debug = "true" *) reg [15:0] v_debug3_0_reg;
	(* mark_debug = "true" *) reg [15:0] v_debug3_1_reg;
	(* mark_debug = "true" *) reg [15:0] v_debug3_2_reg;
	(* mark_debug = "true" *) reg [15:0] v_debug3_3_reg;
	(* mark_debug = "true" *) reg [15:0] v_debug3_4_reg;
	(* mark_debug = "true" *) reg [63:0] v_debug3_5_64_reg;
	(* mark_debug = "true" *) reg [63:0] v_debug3_6_64_reg;

	(* mark_debug = "true" *) reg [15:0] v_debug4_0_reg;
	(* mark_debug = "true" *) reg [15:0] v_debug4_1_reg;
	(* mark_debug = "true" *) reg [15:0] v_debug4_2_reg;
	(* mark_debug = "true" *) reg [15:0] v_debug4_3_reg;
	(* mark_debug = "true" *) reg [15:0] v_debug4_4_reg;
	(* mark_debug = "true" *) reg [63:0] v_debug4_5_64_reg;
	(* mark_debug = "true" *) reg [63:0] v_debug4_6_64_reg;

	(* mark_debug = "true" *) reg [15:0] v_debug5_0_reg;
	(* mark_debug = "true" *) reg [15:0] v_debug5_1_reg;
	(* mark_debug = "true" *) reg [15:0] v_debug5_2_reg;
	(* mark_debug = "true" *) reg [15:0] v_debug5_3_reg;
	(* mark_debug = "true" *) reg [15:0] v_debug5_4_reg;
	(* mark_debug = "true" *) reg [63:0] v_debug5_5_64_reg;
	(* mark_debug = "true" *) reg [63:0] v_debug5_6_64_reg;

	(* mark_debug = "true" *) reg [15:0] v_debug6_0_reg;
	(* mark_debug = "true" *) reg [15:0] v_debug6_1_reg;
	(* mark_debug = "true" *) reg [15:0] v_debug6_2_reg;
	(* mark_debug = "true" *) reg [15:0] v_debug6_3_reg;
	(* mark_debug = "true" *) reg [15:0] v_debug6_4_reg;
	(* mark_debug = "true" *) reg [63:0] v_debug6_5_64_reg;
	(* mark_debug = "true" *) reg [63:0] v_debug6_6_64_reg;

	(* mark_debug = "true" *) reg [15:0] v_debug7_0_reg;
	(* mark_debug = "true" *) reg [15:0] v_debug7_1_reg;
	(* mark_debug = "true" *) reg [15:0] v_debug7_2_reg;
	(* mark_debug = "true" *) reg [15:0] v_debug7_3_reg;
	(* mark_debug = "true" *) reg [15:0] v_debug7_4_reg;
	(* mark_debug = "true" *) reg [63:0] v_debug7_5_64_reg;
	(* mark_debug = "true" *) reg [63:0] v_debug7_6_64_reg;

	always @  (posedge v_clk0)  begin
		v_debug0_0_reg 		<=		v_debug0_0;
		v_debug0_1_reg 		<=		v_debug0_1;
		v_debug0_2_reg 		<=		v_debug0_2;
		v_debug0_3_reg 		<=		v_debug0_3;
		v_debug0_4_reg 		<= 	v_debug0_4;
		v_debug0_5_64_reg 	<=	 	v_debug0_5_64;
		v_debug0_6_64_reg 	<=	 	v_debug0_6_64;

		v_debug1_0_reg 		<=		v_debug1_0;
		v_debug1_1_reg 		<=		v_debug1_1;
		v_debug1_2_reg 		<=		v_debug1_2;
		v_debug1_3_reg 		<=		v_debug1_3;
		v_debug1_4_reg 		<=		v_debug1_4;
		v_debug1_5_64_reg 	<=		v_debug1_5_64;
		v_debug1_6_64_reg 	<=		v_debug1_6_64;

		v_debug2_0_reg 		<=		v_debug2_0;
		v_debug2_1_reg 		<=		v_debug2_1;
		v_debug2_2_reg 		<=		v_debug2_2;
		v_debug2_3_reg 		<=		v_debug2_3;
		v_debug2_4_reg 		<=		v_debug2_4;
		v_debug2_5_64_reg 	<=		v_debug2_5_64;
		v_debug2_6_64_reg 	<=		v_debug2_6_64;

		v_debug3_0_reg 		<=		v_debug3_0;
		v_debug3_1_reg 		<=		v_debug3_1;
		v_debug3_2_reg 		<=		v_debug3_2;
		v_debug3_3_reg 		<=		v_debug3_3;
		v_debug3_4_reg 		<=		v_debug3_4;
		v_debug3_5_64_reg 	<=		v_debug3_5_64;
		v_debug3_6_64_reg 	<=		v_debug3_6_64;


		v_debug4_0_reg			<=		v_debug4_0;  	
		v_debug4_1_reg		   <=		v_debug4_1;
		v_debug4_2_reg		   <=		v_debug4_2;
		v_debug4_3_reg		   <=		v_debug4_3;
		v_debug4_4_reg		   <= 	v_debug4_4;
		v_debug4_5_64_reg	   <=	 	v_debug4_5_64;
		v_debug4_6_64_reg	   <=	 	v_debug4_6_64;
								                        
		v_debug5_0_reg		   <=		v_debug5_0;
		v_debug5_1_reg		   <=		v_debug5_1;
		v_debug5_2_reg		   <=		v_debug5_2;
		v_debug5_3_reg		   <=		v_debug5_3;
		v_debug5_4_reg		   <=		v_debug5_4;
		v_debug5_5_64_reg	   <=		v_debug5_5_64;
		v_debug5_6_64_reg	   <=		v_debug5_6_64;
								                        
		v_debug6_0_reg		   <=		v_debug6_0;
		v_debug6_1_reg		   <=		v_debug6_1;
		v_debug6_2_reg		   <=		v_debug6_2;
		v_debug6_3_reg		   <=		v_debug6_3;
		v_debug6_4_reg		   <=		v_debug6_4;
		v_debug6_5_64_reg	   <=		v_debug6_5_64;
		v_debug6_6_64_reg	   <=		v_debug6_6_64;
								                        
		v_debug7_0_reg		   <=		v_debug7_0;
		v_debug7_1_reg		   <=		v_debug7_1;
		v_debug7_2_reg		   <=		v_debug7_2;
		v_debug7_3_reg		   <=		v_debug7_3;
		v_debug7_4_reg		   <=		v_debug7_4;
		v_debug7_5_64_reg	   <=		v_debug7_5_64;
		v_debug7_6_64_reg	   <=		v_debug7_6_64;


	end



	ila_0 ila0 (
		.clk(v_clk0),
		.probe0(v_debug0_0_reg), // IN BUS [15:0]
		.probe1(v_debug0_1_reg), // IN BUS [15:0]
		.probe2(v_debug0_2_reg), // IN BUS [15:0]
		.probe3(v_debug0_3_reg), // IN BUS [15:0]
		.probe4(v_debug0_4_reg), // IN BUS [15:0]
		.probe5(v_debug0_5_64_reg), // IN BUS [63:0]
		.probe6(v_debug0_6_64_reg), // IN BUS [63:0]

		.probe7(v_debug1_0_reg), // IN BUS [15:0]
		.probe8(v_debug1_1_reg), // IN BUS [15:0]
		.probe9(v_debug1_2_reg), // IN BUS [15:0]
		.probe10(v_debug1_3_reg), // IN BUS [15:0]
		.probe11(v_debug1_4_reg), // IN BUS [15:0]
		.probe12(v_debug1_5_64_reg), // IN BUS [63:0]
		.probe13(v_debug1_6_64_reg), // IN BUS [63:0]

		.probe14(v_debug2_0_reg), // IN BUS [15:0]
		.probe15(v_debug2_1_reg), // IN BUS [15:0]
		.probe16(v_debug2_2_reg), // IN BUS [15:0]
		.probe17(v_debug2_3_reg), // IN BUS [15:0]
		.probe18(v_debug2_4_reg), // IN BUS [15:0]
		.probe19(v_debug2_5_64_reg), // IN BUS [63:0]
		.probe20(v_debug2_6_64_reg), // IN BUS [63:0]

		.probe21(v_debug3_0_reg), // IN BUS [15:0]
		.probe22(v_debug3_1_reg), // IN BUS [15:0]
		.probe23(v_debug3_2_reg), // IN BUS [15:0]
		.probe24(v_debug3_3_reg), // IN BUS [15:0]
		.probe25(v_debug3_4_reg), // IN BUS [15:0]
		.probe26(v_debug3_5_64_reg), // IN BUS [63:0]
		.probe27(v_debug3_6_64_reg), // IN BUS [63:0]

		.probe28(	v_debug4_0_reg		), // IN BUS [15:0]
		.probe29(	v_debug4_1_reg		), // IN BUS [15:0]
		.probe30(	v_debug4_2_reg		), // IN BUS [15:0]
		.probe31(	v_debug4_3_reg		), // IN BUS [15:0]
		.probe32(	v_debug4_4_reg		), // IN BUS [15:0]
		.probe33(	v_debug4_5_64_reg	), // IN BUS [63:0]
		.probe34(	v_debug4_6_64_reg	), // IN BUS [63:0]

		.probe35(	v_debug5_0_reg		), // IN BUS [15:0]
		.probe36(	v_debug5_1_reg		), // IN BUS [15:0]
		.probe37(	v_debug5_2_reg		), // IN BUS [15:0]
		.probe38(	v_debug5_3_reg		), // IN BUS [15:0]
		.probe39(	v_debug5_4_reg		), // IN BUS [15:0]
		.probe40(	v_debug5_5_64_reg	), // IN BUS [63:0]
		.probe41(	v_debug5_6_64_reg	), // IN BUS [63:0]

		.probe42(	v_debug6_0_reg		), // IN BUS [15:0]
		.probe43(	v_debug6_1_reg		), // IN BUS [15:0]
		.probe44(	v_debug6_2_reg		), // IN BUS [15:0]
		.probe45(	v_debug6_3_reg		), // IN BUS [15:0]
		.probe46(	v_debug6_4_reg		), // IN BUS [15:0]
		.probe47(	v_debug6_5_64_reg	), // IN BUS [63:0]
		.probe48(	v_debug6_6_64_reg	), // IN BUS [63:0]

		.probe49(	v_debug7_0_reg		), // IN BUS [15:0]
		.probe50(	v_debug7_1_reg		), // IN BUS [15:0]
		.probe51(	v_debug7_2_reg		), // IN BUS [15:0]
		.probe52(	v_debug7_3_reg		), // IN BUS [15:0]
		.probe53(	v_debug7_4_reg		), // IN BUS [15:0]
		.probe54(	v_debug7_5_64_reg	), // IN BUS [63:0]
		.probe55(	v_debug7_6_64_reg	) // IN BUS [63:0]
	);

endmodule
