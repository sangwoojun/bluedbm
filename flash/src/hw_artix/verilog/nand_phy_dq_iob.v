//NOTE: frame alignment of ISERDES is undetermined 
// ISERDES Timing parameters are in Artix data sheet: 
// http://www.xilinx.com/support/documentation/data_sheets/ds181_Artix_7_Data_Sheet.pdf
// ISERDES timing diagrams are in UG471 (Select io) 


`timescale 1ns/1ps

module nand_phy_dq_iob #
  (
   // Following parameters are for 32-bit component design (for ML561 Reference
   // board design). Actual values may be different. Actual parameters values
   // are passed from design top module mig_36_1 module. Please refer to
   // the mig_36_1 module for actual values.
   parameter HIGH_PERFORMANCE_MODE = "TRUE",
   parameter IODELAY_GRP           = "IODELAY_NAND",
	parameter IDELAY_TAP 			  = 0
   )
  (
	input  clk0,
   input  clk90,
	input	 rst0,
   input  rst90,
   //input  dlyinc,
   //input  dlyce,
   //input  dlyrst,
   input  dq_oe_n,
	input  dq_iddr_rst,
   input  dqs,
   input  wr_data_rise,
   input  wr_data_fall,
   output reg rd_data_rise,
   output reg rd_data_fall,
	output rd_data_comb, 
   inout  ddr_dq,

	//calibration
	output reg calib_dq_rise_0,
	output reg calib_dq_rise_90,
	output reg calib_dq_rise_180,
	output reg calib_dq_rise_270,
	input calib_clk0_sel

   );

  wire    dq_in;
  wire    dq_oe_n_r;
  wire    dq_out;
  //wire    iserdes_clk;
  //wire    iserdes_clkb;
  reg rd_data_rise_buf = 0;
  reg rd_data_fall_buf = 0;
  reg doutR_0 = 0;
  reg doutR_180 = 0;
  reg doutR_180_sync = 0;
  reg doutF_0 = 0;
  reg doutF_180 = 0;
  reg calib_dq_rise_0_sync = 0;
  reg calib_dq_rise_90_sync = 0;
  reg calib_dq_rise_180_sync = 0;
  reg calib_dq_rise_270_sync = 0;
  wire dq_iddr_r, dq_iddr_f;


//Synchronize write data from clk0 to clk90 domain. clk0 -> clk180 -> clk90
//This way setup time is at least 5ns
wire clk180;
reg wr_data_rise_r1;
reg wr_data_rise_r2;
reg wr_data_fall_r1;
reg wr_data_fall_r2;

assign clk180 = ~clk0;
always @ (posedge clk180)
begin
	wr_data_rise_r1 <= wr_data_rise;
	wr_data_fall_r1 <= wr_data_fall;
end

always @ (posedge clk90)
begin
	wr_data_rise_r2 <= wr_data_rise_r1;
	wr_data_fall_r2 <= wr_data_fall_r1;
end

//Synchronize OE_n from clk0 to clk90. clk0 -> clk180 -> clk90
reg dq_oe_n_r1;
reg dq_oe_n_r2;
always @ (posedge clk180)
begin
	dq_oe_n_r1 <= dq_oe_n;
end

always @ (posedge clk90)
begin
	dq_oe_n_r2 <= dq_oe_n_r1;
end


  // on a write, rising edge of DQS corresponds to rising edge of CLK180
  // (aka falling edge of CLK0 -> rising edge DQS). We also know:
  //  1. data must be driven 1/4 clk cycle before corresponding DQS edge
  //  2. first rising DQS edge driven on falling edge of CLK0
  //  3. rising data must be driven 1/4 cycle before falling edge of CLK0
  //  4. therefore, rising data driven on rising edge of CLK90
  (* KEEP = "TRUE" *)
  ODDR #
    (
     .SRTYPE("SYNC"),
     .DDR_CLK_EDGE("SAME_EDGE")
     )
    u_oddr_dq
      (
       .Q  (dq_out),
       .C  (clk90),
       .CE (1'b1),
       .D1 (wr_data_rise_r2),
       .D2 (wr_data_fall_r2),
       .R  (1'b0),
       .S  (1'b0)
       );

  // make sure output is tri-state during reset (DQ_OE_N_R = 1)
  (* KEEP = "TRUE" *)
  (* IOB = "FORCE" *) FDPE u_tri_state_dq
    (
     .D    (dq_oe_n_r2),
     .PRE  (rst90),
     .C    (clk90),
     .Q    (dq_oe_n_r),
     .CE   (1'b1)
     ) /* synthesis syn_useioff = 1 */;

	(* KEEP = "TRUE" *)
  IOBUF u_iobuf_dq
    (
     .I  (dq_out),
     .T  (dq_oe_n_r),
     .IO (ddr_dq),
     .O  (dq_in)
     );


(* IODELAY_GROUP = IODELAY_GRP *) IDELAYE2 #(
   .CINVCTRL_SEL("FALSE"),          // Enable dynamic clock inversion (FALSE, TRUE)
   .DELAY_SRC("IDATAIN"),           // Delay input (IDATAIN, DATAIN)
   .HIGH_PERFORMANCE_MODE("TRUE"), // Reduced jitter ("TRUE"), Reduced power ("FALSE")
   //.IDELAY_TYPE("VARIABLE"),           // FIXED, VARIABLE, VAR_LOAD, VAR_LOAD_PIPE
   .IDELAY_TYPE("FIXED"),           // FIXED, VARIABLE, VAR_LOAD, VAR_LOAD_PIPE
   .IDELAY_VALUE(IDELAY_TAP),                // Input delay tap setting (0-31)
   .PIPE_SEL("FALSE"),              // Select pipelined mode, FALSE, TRUE
   .REFCLK_FREQUENCY(200.0),        // IDELAYCTRL clock input frequency in MHz (190.0-210.0).
   .SIGNAL_PATTERN("CLOCK")          // DATA, CLOCK input signal
)
u_idelay_dq (
   .CNTVALUEOUT(), // 5-bit output: Counter value output
   .DATAOUT(dq_idelay),         // 1-bit output: Delayed data output
   .C(clk90),                     // 1-bit input: Clock input
   .CE(/*dlyce*/),                   // 1-bit input: Active high enable increment/decrement input
   .CINVCTRL(),       // 1-bit input: Dynamic clock inversion input
   .CNTVALUEIN(),   // 5-bit input: Counter value input
   .DATAIN(),           // 1-bit input: Internal delay data input
   .IDATAIN(dq_in),         // 1-bit input: Data input from the I/O
   .INC(/*dlyinc*/),                 // 1-bit input: Increment / Decrement tap delay input
   .LD(),                   // 1-bit input: Load IDELAY_VALUE input
   .LDPIPEEN(),       // 1-bit input: Enable PIPELINE register to load data input
   .REGRST(/*dlyrst*/)            // 1-bit input: Active-high reset tap-delay input
);



//IDDR reset register buffer. High at power up
 FDCPE u_ff_dq_iddr_rst
    (
     .Q   (dq_iddr_rst_r),
     .C   (clk0),
     .CE  (1'b1),
     .CLR (1'b0),
     .D   (dq_iddr_rst),
     .PRE (rst0)
     );


(* KEEP = "TRUE" *)
IDDR #(
   .DDR_CLK_EDGE("OPPOSITE_EDGE"), // "OPPOSITE_EDGE", "SAME_EDGE" 
                                   //    or "SAME_EDGE_PIPELINED" 
   .INIT_Q1(1'b0), // Initial value of Q1: 1'b0 or 1'b1
   .INIT_Q2(1'b0), // Initial value of Q2: 1'b0 or 1'b1
   .SRTYPE("ASYNC") // Set/Reset type: "SYNC" or "ASYNC" 
) IDDR_inst (
   .Q1(dq_iddr_r), // 1-bit output for positive edge of clock 
   .Q2(dq_iddr_f), // 1-bit output for negative edge of clock
   .C(dqs),   // 1-bit clock input
   .CE(~dq_iddr_rst_r), // 1-bit clock enable input
   .D(dq_idelay),   // 1-bit DDR data input
   .R(rst0),// | dq_iddr_rst_r),   // 1-bit reset
   .S(1'd0)    // 1-bit set
);

assign rd_data_comb = dq_in;



//Synchronize read data from DQS domain to clk0 domain
//We tolerate setup/hold violations here. At least one
// of these clock edges will capture correct data without
// timing violations
always @ (posedge clk0)
begin
	doutR_0 <= dq_iddr_r;
	doutF_180 <= dq_iddr_f;
	doutR_180 <= doutR_180_sync;
end

always @ (negedge clk0)
begin
	doutR_180_sync <= dq_iddr_r;
	doutF_0 <= dq_iddr_f;
end

always @ (posedge clk0)
begin
	rd_data_fall_buf <= (calib_clk0_sel==1) ? doutF_0 : doutF_180;
	rd_data_rise_buf <= (calib_clk0_sel==1) ? doutR_0 : doutR_180;
	//Add a set of buffer registers so # of stages is the same as 
	// # calibration regs
	rd_data_fall <= rd_data_fall_buf;
	rd_data_rise <= rd_data_rise_buf;

end

//For calibration, also examine data at clk90 edges
reg doutR_90;
reg doutR_270;

always @ (posedge clk90)
begin
	//if (rst90) begin
	//	doutR_90 <= 0;
	//end else begin
		doutR_90 <= dq_iddr_r;
	//end
end

always @ (negedge clk90)
begin
	//if (rst90) begin
	//	doutR_270 <= 0;
	//end else begin
		doutR_270 <= dq_iddr_r;
	//end
end


//Examine all 4 registers for calibration 
// For signals at 0, 90, 180 phases, we capture using clk0
// For signal at 270 phase, we capture using clk180
// Min setup time is 5ns
always @ (posedge clk0)
begin
	calib_dq_rise_0_sync <= doutR_0;
	calib_dq_rise_90_sync <= doutR_90; 
	calib_dq_rise_180_sync <= doutR_180_sync;
end 

always @ (posedge clk180)
begin
	calib_dq_rise_270_sync <= doutR_270;
end

//sync all to clk0 domain
always @ (posedge clk0)
begin
	calib_dq_rise_0 <= calib_dq_rise_0_sync;
	calib_dq_rise_90 <= calib_dq_rise_90_sync;  
	calib_dq_rise_180 <= calib_dq_rise_180_sync;
	calib_dq_rise_270 <= calib_dq_rise_270_sync;
end



/*

  // equalize delays to avoid delta-delay issues
  assign  iserdes_clk  = dqs;
  assign  iserdes_clkb = ~dqs;

(* KEEP = "TRUE" *)
ISERDESE2 #(
   .DATA_RATE("DDR"),           // DDR, SDR
   .DATA_WIDTH(4),              // Parallel data width (2-8,10,14)
   .DYN_CLKDIV_INV_EN("FALSE"), // Enable DYNCLKDIVINVSEL inversion (FALSE, TRUE)
   .DYN_CLK_INV_EN("FALSE"),    // Enable DYNCLKINVSEL inversion (FALSE, TRUE)
   // INIT_Q1 - INIT_Q4: Initial value on the Q outputs (0/1)
   .INIT_Q1(1'b0),
   .INIT_Q2(1'b0),
   .INIT_Q3(1'b0),
   .INIT_Q4(1'b0),
   .INTERFACE_TYPE("MEMORY"),   // MEMORY, MEMORY_DDR3, MEMORY_QDR, NETWORKING, OVERSAMPLE
   .IOBDELAY("IFD"),           // NONE, BOTH, IBUF, IFD
   .NUM_CE(2),                  // Number of clock enables (1,2)
   .OFB_USED("FALSE"),          // Select OFB path (FALSE, TRUE)
   .SERDES_MODE("MASTER"),      // MASTER, SLAVE
   // SRVAL_Q1 - SRVAL_Q4: Q output values when SR is used (0/1)
   .SRVAL_Q1(1'b0),
   .SRVAL_Q2(1'b0),
   .SRVAL_Q3(1'b0),
   .SRVAL_Q4(1'b0) 
)
ISERDESE2_inst (
   .O(),                       // 1-bit output: Combinatorial output
   // Q1 - Q8: 1-bit (each) output: Registered data outputs
   .Q1(rd_data_fall_test),
   .Q2(rd_data_rise_test),
   .Q3(),
   .Q4(),
   .Q5(),
   .Q6(),
   .Q7(),
   .Q8(),
   // SHIFTOUT1-SHIFTOUT2: 1-bit (each) output: Data width expansion output ports
   .SHIFTOUT1(),
   .SHIFTOUT2(),
   .BITSLIP(1'b0),           // 1-bit input: The BITSLIP pin performs a Bitslip operation synchronous to
                                // CLKDIV when asserted (active High). Subsequently, the data seen on the Q1
                                // to Q8 output ports will shift, as in a barrel-shifter operation, one
                                // position every time Bitslip is invoked (DDR operation is different from
                                // SDR).

   // CE1, CE2: 1-bit (each) input: Data register clock enable inputs
   .CE1(1'd1),
   .CE2(1'd1),
   .CLKDIVP(),           // 1-bit input: TBD
   // Clocks: 1-bit (each) input: ISERDESE2 clock input ports
   .CLK(iserdes_clk),                   // 1-bit input: High-speed clock
   .CLKB(iserdes_clkb),                 // 1-bit input: High-speed secondary clock
   .CLKDIV(clk0),             // 1-bit input: Divided clock
   .OCLK(clk0),                 // 1-bit input: High speed output clock used when INTERFACE_TYPE="MEMORY"
   // Dynamic Clock Inversions: 1-bit (each) input: Dynamic clock inversion pins to switch clock polarity
   .DYNCLKDIVSEL(), // 1-bit input: Dynamic CLKDIV inversion
   .DYNCLKSEL(),       // 1-bit input: Dynamic CLK/CLKB inversion
   // Input Data: 1-bit (each) input: ISERDESE2 data input ports
   .D(),                       // 1-bit input: Data input
   .DDLY(dq_idelay),                 // 1-bit input: Serial data from IDELAYE2
   .OFB(),                   // 1-bit input: Data feedback from OSERDESE2
   .OCLKB(~clk0),               // 1-bit input: High speed negative edge output clock
   .RST(rst0),                   // 1-bit input: Active high asynchronous reset
   // SHIFTIN1-SHIFTIN2: 1-bit (each) input: Data width expansion input ports
   .SHIFTIN1(),
   .SHIFTIN2() 
);

*/






/*
  // equalize delays to avoid delta-delay issues
  assign  iserdes_clk  = dqs;
  assign  iserdes_clkb = ~dqs;

(* KEEP = "TRUE" *)
ISERDESE2 #(
   .DATA_RATE("DDR"),           // DDR, SDR
   .DATA_WIDTH(4),              // Parallel data width (2-8,10,14)
   .DYN_CLKDIV_INV_EN("FALSE"), // Enable DYNCLKDIVINVSEL inversion (FALSE, TRUE)
   .DYN_CLK_INV_EN("FALSE"),    // Enable DYNCLKINVSEL inversion (FALSE, TRUE)
   // INIT_Q1 - INIT_Q4: Initial value on the Q outputs (0/1)
   .INIT_Q1(1'b0),
   .INIT_Q2(1'b0),
   .INIT_Q3(1'b0),
   .INIT_Q4(1'b0),
   .INTERFACE_TYPE("MEMORY"),   // MEMORY, MEMORY_DDR3, MEMORY_QDR, NETWORKING, OVERSAMPLE
   .IOBDELAY("IFD"),           // NONE, BOTH, IBUF, IFD
   .NUM_CE(2),                  // Number of clock enables (1,2)
   .OFB_USED("FALSE"),          // Select OFB path (FALSE, TRUE)
   .SERDES_MODE("MASTER"),      // MASTER, SLAVE
   // SRVAL_Q1 - SRVAL_Q4: Q output values when SR is used (0/1)
   .SRVAL_Q1(1'b0),
   .SRVAL_Q2(1'b0),
   .SRVAL_Q3(1'b0),
   .SRVAL_Q4(1'b0) 
)
ISERDESE2_inst (
   .O(rd_data_comb),                       // 1-bit output: Combinatorial output
   // Q1 - Q8: 1-bit (each) output: Registered data outputs
   .Q1(rd_data_fall_90),
   .Q2(rd_data_rise_90),
   .Q3(),
   .Q4(),
   .Q5(),
   .Q6(),
   .Q7(),
   .Q8(),
   // SHIFTOUT1-SHIFTOUT2: 1-bit (each) output: Data width expansion output ports
   .SHIFTOUT1(),
   .SHIFTOUT2(),
   .BITSLIP(1'b0),           // 1-bit input: The BITSLIP pin performs a Bitslip operation synchronous to
                                // CLKDIV when asserted (active High). Subsequently, the data seen on the Q1
                                // to Q8 output ports will shift, as in a barrel-shifter operation, one
                                // position every time Bitslip is invoked (DDR operation is different from
                                // SDR).

   // CE1, CE2: 1-bit (each) input: Data register clock enable inputs
   .CE1(1'd1),
   .CE2(1'd1),
   .CLKDIVP(),           // 1-bit input: TBD
   // Clocks: 1-bit (each) input: ISERDESE2 clock input ports
   .CLK(iserdes_clk),                   // 1-bit input: High-speed clock
   .CLKB(iserdes_clkb),                 // 1-bit input: High-speed secondary clock
   .CLKDIV(clk90),             // 1-bit input: Divided clock
   .OCLK(clk90),                 // 1-bit input: High speed output clock used when INTERFACE_TYPE="MEMORY"
   // Dynamic Clock Inversions: 1-bit (each) input: Dynamic clock inversion pins to switch clock polarity
   .DYNCLKDIVSEL(), // 1-bit input: Dynamic CLKDIV inversion
   .DYNCLKSEL(),       // 1-bit input: Dynamic CLK/CLKB inversion
   // Input Data: 1-bit (each) input: ISERDESE2 data input ports
   .D(dq_in),                       // 1-bit input: Data input
   .DDLY(dq_idelay),                 // 1-bit input: Serial data from IDELAYE2
   .OFB(),                   // 1-bit input: Data feedback from OSERDESE2
   .OCLKB(~clk90),               // 1-bit input: High speed negative edge output clock
   .RST(rst90),                   // 1-bit input: Active high asynchronous reset
   // SHIFTIN1-SHIFTIN2: 1-bit (each) input: Data width expansion input ports
   .SHIFTIN1(),
   .SHIFTIN2() 
);
*/


endmodule
