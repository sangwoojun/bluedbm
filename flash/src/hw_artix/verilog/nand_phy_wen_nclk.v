`timescale 1ns / 1ps

module nand_phy_wen_nclk (
	input v_clk0,
	input v_rstn0,
	//busn_0 ctrl
	input v_ctrl_wen_0,
	input v_ctrl_wen_sel_0,

	//busn_1 ctrl
	input v_ctrl_wen_1,
	input v_ctrl_wen_sel_1,

	//FPGA I/O
	output [3:0] v_wen_nclk_shared
	);


wire wen_nclk_0_d1, wen_nclk_0_d2;
assign wen_nclk_0_d1 = (v_ctrl_wen_sel_0) ? (v_ctrl_wen_0) : (1'b0);
assign wen_nclk_0_d2 = (v_ctrl_wen_sel_0) ? (v_ctrl_wen_0) : (1'b1);


wire wen_nclk_1_d1, wen_nclk_1_d2;
assign wen_nclk_1_d1 = (v_ctrl_wen_sel_1) ? (v_ctrl_wen_1) : (1'b0);
assign wen_nclk_1_d2 = (v_ctrl_wen_sel_1) ? (v_ctrl_wen_1) : (1'b1);

wire wen_nclk_merged_d1, wen_nclk_merged_d2;
assign wen_nclk_merged_d1 = wen_nclk_0_d1 & wen_nclk_1_d1;
assign wen_nclk_merged_d2 = wen_nclk_0_d2 & wen_nclk_1_d2;


//***************************************************************************
// NAND CLK / WE#  ODDR; tie all WE# together on the same bus
//***************************************************************************
genvar nclk_i;
generate
	for (nclk_i = 0; nclk_i < 4; nclk_i=nclk_i+1) begin: gen_nclk_oddr
		ODDR #
			(
			.SRTYPE       ("SYNC"),
			.DDR_CLK_EDGE ("OPPOSITE_EDGE")
			)
			u_oddr_ck
			(
				.Q   (v_wen_nclk_shared[nclk_i]),
				.C   (v_clk0),
				.CE  (1'b1),
				.D1  (wen_nclk_merged_d1),
				.D2  (wen_nclk_merged_d2),
				.R   (1'b0),
				.S   (1'b0)
			);
	end
endgenerate


endmodule




