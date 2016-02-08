`timescale 1ns/1ps

module tb;
//---------------------------------------------
// Wires and Regs
//---------------------------------------------
	reg clk_in_p;
	reg clk_in_n;
	reg sys_resetn;
	
	wire [3:0] b0_shared_wen_nclk;
	wire [7:0] b0_0_dq;
	wire b0_0_dqs;
	wire b0_0_cle;
	wire b0_0_ale;
	wire b0_0_wrn;
	wire b0_0_wpn;
	wire [7:0] b0_0_cen;
	wire  [7:0] b0_0_rb;
	wire [7:0] b0_1_dq;
	wire b0_1_dqs;
	wire b0_1_cle;
	wire b0_1_ale;
	wire b0_1_wrn;
	wire b0_1_wpn;
	wire [7:0] b0_1_cen;
	wire  [7:0] b0_1_rb;
	
	wire [3:0] b1_shared_wen_nclk;
	wire [7:0] b1_0_dq;
	wire b1_0_dqs;
	wire b1_0_cle;
	wire b1_0_ale;
	wire b1_0_wrn;
	wire b1_0_wpn;
	wire [7:0] b1_0_cen;
	wire  [7:0] b1_0_rb;
	wire [7:0] b1_1_dq;
	wire b1_1_dqs;
	wire b1_1_cle;
	wire b1_1_ale;
	wire b1_1_wrn;
	wire b1_1_wpn;
	wire [7:0] b1_1_cen;
	wire  [7:0] b1_1_rb;


//---------------------------------------------
// Bus 0; Nand model instantiation
//---------------------------------------------
//Bus 0, Chip 0
nand_model nand_b0_0 (
	//clocks
	.Clk_We_n(b0_shared_wen_nclk[0]), //same connection to both wen/nclk
	.Clk_We2_n(b0_shared_wen_nclk[0]),
	
	//CE
	.Ce_n(b0_0_cen[0]),
	.Ce2_n(b0_1_cen[0]),
	.Ce3_n(b0_0_cen[1]),
	.Ce4_n(b0_1_cen[1]),
	
	//Ready/busy
	.Rb_n(b0_0_rb[0]),
	.Rb2_n(b0_1_rb[0]),
	.Rb3_n(b0_0_rb[1]),
	.Rb4_n(b0_1_rb[1]),
	 
	//DQ DQS
	.Dqs(b0_0_dqs), 
	.Dq_Io(b0_0_dq[7:0]), 
	.Dqs2(b0_1_dqs),
	.Dq_Io2(b0_1_dq[7:0]),
	 
	//ALE CLE WR WP
	.Cle(b0_0_cle), 
	.Cle2(b0_1_cle),
   .Ale(b0_0_ale), 
	.Ale2(b0_1_ale),
	.Wr_Re_n(b0_0_wrn), 
	.Wr_Re2_n(b0_1_wrn),
	.Wp_n(b0_0_wpn), 
	.Wp2_n(b0_1_wpn)
);

//Bus 0, Chip 1
nand_model nand_b0_1 (
	//clocks
	.Clk_We_n(b0_shared_wen_nclk[1]), //same connection to both wen/nclk
	.Clk_We2_n(b0_shared_wen_nclk[1]),
	
	//CE
	.Ce_n(b0_0_cen[2]),
	.Ce2_n(b0_1_cen[2]),
	.Ce3_n(b0_0_cen[3]),
	.Ce4_n(b0_1_cen[3]),
	
	//Ready/busy
	.Rb_n(b0_0_rb[2]),
	.Rb2_n(b0_1_rb[2]),
	.Rb3_n(b0_0_rb[3]),
	.Rb4_n(b0_1_rb[3]),
	 
	//DQ DQS
	.Dqs(b0_0_dqs), 
	.Dq_Io(b0_0_dq[7:0]), 
	.Dqs2(b0_1_dqs),
	.Dq_Io2(b0_1_dq[7:0]),
	 
	//ALE CLE WR WP
	.Cle(b0_0_cle), 
	.Cle2(b0_1_cle),
   .Ale(b0_0_ale), 
	.Ale2(b0_1_ale),
	.Wr_Re_n(b0_0_wrn), 
	.Wr_Re2_n(b0_1_wrn),
	.Wp_n(b0_0_wpn), 
	.Wp2_n(b0_1_wpn)
);

//Bus 0, Chip 2. Reversed DQ pins
nand_model nand_b0_2 (
	//clocks
	.Clk_We_n(b0_shared_wen_nclk[2]), //same connection to both wen/nclk
	.Clk_We2_n(b0_shared_wen_nclk[2]),
	
	//CE
	.Ce_n(b0_0_cen[4]),
	.Ce2_n(b0_1_cen[4]),
	.Ce3_n(b0_0_cen[5]),
	.Ce4_n(b0_1_cen[5]),
	
	//Ready/busy
	.Rb_n(b0_0_rb[4]),
	.Rb2_n(b0_1_rb[4]),
	.Rb3_n(b0_0_rb[5]),
	.Rb4_n(b0_1_rb[5]),
	 
	//DQ DQS
	.Dqs(b0_0_dqs), 
	//Reversed DQ
	.Dq_Io({b0_0_dq[0], b0_0_dq[1], b0_0_dq[2], b0_0_dq[3], b0_0_dq[4], b0_0_dq[5], b0_0_dq[6], b0_0_dq[7]}),
	.Dqs2(b0_1_dqs),
	.Dq_Io2({b0_1_dq[0], b0_1_dq[1], b0_1_dq[2], b0_1_dq[3], b0_1_dq[4], b0_1_dq[5], b0_1_dq[6], b0_1_dq[7]}),
	 
	//ALE CLE WR WP
	.Cle(b0_0_cle), 
	.Cle2(b0_1_cle),
   .Ale(b0_0_ale), 
	.Ale2(b0_1_ale),
	.Wr_Re_n(b0_0_wrn), 
	.Wr_Re2_n(b0_1_wrn),
	.Wp_n(b0_0_wpn), 
	.Wp2_n(b0_1_wpn)
);


//Bus 0, Chip 3. Reversed DQ pins
nand_model nand_b0_3 (
	//clocks
	.Clk_We_n(b0_shared_wen_nclk[3]), //same connection to both wen/nclk
	.Clk_We2_n(b0_shared_wen_nclk[3]),
	
	//CE
	.Ce_n(b0_0_cen[6]),
	.Ce2_n(b0_1_cen[6]),
	.Ce3_n(b0_0_cen[7]),
	.Ce4_n(b0_1_cen[7]),
	
	//Ready/busy
	.Rb_n(b0_0_rb[6]),
	.Rb2_n(b0_1_rb[6]),
	.Rb3_n(b0_0_rb[7]),
	.Rb4_n(b0_1_rb[7]),
	 
	//DQ DQS
	.Dqs(b0_0_dqs), 
	//Reversed DQ
	.Dq_Io({b0_0_dq[0], b0_0_dq[1], b0_0_dq[2], b0_0_dq[3], b0_0_dq[4], b0_0_dq[5], b0_0_dq[6], b0_0_dq[7]}),
	.Dqs2(b0_1_dqs),
	.Dq_Io2({b0_1_dq[0], b0_1_dq[1], b0_1_dq[2], b0_1_dq[3], b0_1_dq[4], b0_1_dq[5], b0_1_dq[6], b0_1_dq[7]}),
	 
	//ALE CLE WR WP
	.Cle(b0_0_cle), 
	.Cle2(b0_1_cle),
   .Ale(b0_0_ale), 
	.Ale2(b0_1_ale),
	.Wr_Re_n(b0_0_wrn), 
	.Wr_Re2_n(b0_1_wrn),
	.Wp_n(b0_0_wpn), 
	.Wp2_n(b0_1_wpn)
);

/*
//-------------------------------------------------------------
// Bus 1
//-------------------------------------------------------------
//Bus 1, Chip 0
nand_model nand_b1_0 (
	//clocks
	.Clk_We_n(b1_shared_wen_nclk[0]), //same connection to both wen/nclk
	.Clk_We2_n(b1_shared_wen_nclk[0]),
	
	//CE
	.Ce_n(b1_0_cen[0]),
	.Ce2_n(b1_1_cen[0]),
	.Ce3_n(b1_0_cen[1]),
	.Ce4_n(b1_1_cen[1]),
	
	//Ready/busy
	.Rb_n(b1_0_rb[0]),
	.Rb2_n(b1_1_rb[0]),
	.Rb3_n(b1_0_rb[1]),
	.Rb4_n(b1_1_rb[1]),
	 
	//DQ DQS
	.Dqs(b1_0_dqs), 
	.Dq_Io(b1_0_dq[7:0]), 
	.Dqs2(b1_1_dqs),
	.Dq_Io2(b1_1_dq[7:0]),
	 
	//ALE CLE WR WP
	.Cle(b1_0_cle), 
	.Cle2(b1_1_cle),
   .Ale(b1_0_ale), 
	.Ale2(b1_1_ale),
	.Wr_Re_n(b1_0_wrn), 
	.Wr_Re2_n(b1_1_wrn),
	.Wp_n(b1_0_wpn), 
	.Wp2_n(b1_1_wpn)
);

//Bus 1, Chip 1
nand_model nand_b1_1 (
	//clocks
	.Clk_We_n(b1_shared_wen_nclk[1]), //same connection to both wen/nclk
	.Clk_We2_n(b1_shared_wen_nclk[1]),
	
	//CE
	.Ce_n(b1_0_cen[2]),
	.Ce2_n(b1_1_cen[2]),
	.Ce3_n(b1_0_cen[3]),
	.Ce4_n(b1_1_cen[3]),
	
	//Ready/busy
	.Rb_n(b1_0_rb[2]),
	.Rb2_n(b1_1_rb[2]),
	.Rb3_n(b1_0_rb[3]),
	.Rb4_n(b1_1_rb[3]),
	 
	//DQ DQS
	.Dqs(b1_0_dqs), 
	.Dq_Io(b1_0_dq[7:0]), 
	.Dqs2(b1_1_dqs),
	.Dq_Io2(b1_1_dq[7:0]),
	 
	//ALE CLE WR WP
	.Cle(b1_0_cle), 
	.Cle2(b1_1_cle),
   .Ale(b1_0_ale), 
	.Ale2(b1_1_ale),
	.Wr_Re_n(b1_0_wrn), 
	.Wr_Re2_n(b1_1_wrn),
	.Wp_n(b1_0_wpn), 
	.Wp2_n(b1_1_wpn)
);

//Bus 1, Chip 2. Reversed DQ pins
nand_model nand_b1_2 (
	//clocks
	.Clk_We_n(b1_shared_wen_nclk[2]), //same connection to both wen/nclk
	.Clk_We2_n(b1_shared_wen_nclk[2]),
	
	//CE
	.Ce_n(b1_0_cen[4]),
	.Ce2_n(b1_1_cen[4]),
	.Ce3_n(b1_0_cen[5]),
	.Ce4_n(b1_1_cen[5]),
	
	//Ready/busy
	.Rb_n(b1_0_rb[4]),
	.Rb2_n(b1_1_rb[4]),
	.Rb3_n(b1_0_rb[5]),
	.Rb4_n(b1_1_rb[5]),
	 
	//DQ DQS
	.Dqs(b1_0_dqs), 
	//Reversed DQ
	.Dq_Io({b1_0_dq[0], b1_0_dq[1], b1_0_dq[2], b1_0_dq[3], b1_0_dq[4], b1_0_dq[5], b1_0_dq[6], b1_0_dq[7]}),
	.Dqs2(b1_1_dqs),
	.Dq_Io2({b1_1_dq[0], b1_1_dq[1], b1_1_dq[2], b1_1_dq[3], b1_1_dq[4], b1_1_dq[5], b1_1_dq[6], b1_1_dq[7]}),
	 
	//ALE CLE WR WP
	.Cle(b1_0_cle), 
	.Cle2(b1_1_cle),
   .Ale(b1_0_ale), 
	.Ale2(b1_1_ale),
	.Wr_Re_n(b1_0_wrn), 
	.Wr_Re2_n(b1_1_wrn),
	.Wp_n(b1_0_wpn), 
	.Wp2_n(b1_1_wpn)
);


//Bus 1, Chip 3. Reversed DQ pins
nand_model nand_b1_3 (
	//clocks
	.Clk_We_n(b1_shared_wen_nclk[3]), //same connection to both wen/nclk
	.Clk_We2_n(b1_shared_wen_nclk[3]),
	
	//CE
	.Ce_n(b1_0_cen[6]),
	.Ce2_n(b1_1_cen[6]),
	.Ce3_n(b1_0_cen[7]),
	.Ce4_n(b1_1_cen[7]),
	
	//Ready/busy
	.Rb_n(b1_0_rb[6]),
	.Rb2_n(b1_1_rb[6]),
	.Rb3_n(b1_0_rb[7]),
	.Rb4_n(b1_1_rb[7]),
	 
	//DQ DQS
	.Dqs(b1_0_dqs), 
	//Reversed DQ
	.Dq_Io({b1_0_dq[0], b1_0_dq[1], b1_0_dq[2], b1_0_dq[3], b1_0_dq[4], b1_0_dq[5], b1_0_dq[6], b1_0_dq[7]}),
	.Dqs2(b1_1_dqs),
	.Dq_Io2({b1_1_dq[0], b1_1_dq[1], b1_1_dq[2], b1_1_dq[3], b1_1_dq[4], b1_1_dq[5], b1_1_dq[6], b1_1_dq[7]}),
	 
	//ALE CLE WR WP
	.Cle(b1_0_cle), 
	.Cle2(b1_1_cle),
   .Ale(b1_0_ale), 
	.Ale2(b1_1_ale),
	.Wr_Re_n(b1_0_wrn), 
	.Wr_Re2_n(b1_1_wrn),
	.Wp_n(b1_0_wpn), 
	.Wp2_n(b1_1_wpn)
);
*/

//---------------------------------------------
// Flash controller
//---------------------------------------------
//mkFlashController u_flash_controller(
mkTopTB u_top_tb(
		.CLK_sysClkP(clk_in_p),
		.CLK_sysClkN(clk_in_n),
		//.RST_N_sysRstn(sys_resetn),

		.B_SHARED_0_WEN_NCLK(b0_shared_wen_nclk),
		.B_0_0_DQ(b0_0_dq),
		.B_0_0_DQS(b0_0_dqs),
		.B_0_0_CLE(b0_0_cle),
		.B_0_0_ALE(b0_0_ale),
		.B_0_0_WRN(b0_0_wrn),
		.B_0_0_WPN(b0_0_wpn),
		.B_0_0_CEN(b0_0_cen),
		.B_0_1_DQ(b0_1_dq),
		.B_0_1_DQS(b0_1_dqs),
		.B_0_1_CLE(b0_1_cle),
		.B_0_1_ALE(b0_1_ale),
		.B_0_1_WRN(b0_1_wrn),
		.B_0_1_WPN(b0_1_wpn),
		.B_0_1_CEN(b0_1_cen)
/*
		.B_SHARED_1_WEN_NCLK(b1_shared_wen_nclk),
		.B_1_0_DQ(b1_0_dq),
		.B_1_0_DQS(b1_0_dqs),
		.B_1_0_CLE(b1_0_cle),
		.B_1_0_ALE(b1_0_ale),
		.B_1_0_WRN(b1_0_wrn),
		.B_1_0_WPN(b1_0_wpn),
		.B_1_0_CEN(b1_0_cen),
		.B_1_1_DQ(b1_1_dq),
		.B_1_1_DQS(b1_1_dqs),
		.B_1_1_CLE(b1_1_cle),
		.B_1_1_ALE(b1_1_ale),
		.B_1_1_WRN(b1_1_wrn),
		.B_1_1_WPN(b1_1_wpn),
		.B_1_1_CEN(b1_1_cen)
		*/
	 );


//---------------------------------------------
// Simulation clock and reset
//---------------------------------------------

initial begin
	clk_in_p = 0;
	clk_in_n = 1;
	
	//reset for a bit
	//sys_resetn = 0;
	//#200
	sys_resetn = 1;
	
end

//100MHz differential clock
//can probably just assign clk_in_n=~clk_in_p ?
always begin
	#5 clk_in_p=~clk_in_p;
end
always begin
	#5 clk_in_n=~clk_in_n;
end


endmodule
