`timescale 1ns/1ps

module nand_phy_dqs_iob #
  (
   //parameter DQS_GATE_EN           = 1,
	parameter DQS_NET_DELAY			  = 1.0, //TODO FUnctional simulation only!!
   parameter HIGH_PERFORMANCE_MODE = "TRUE",
   parameter IODELAY_GRP           = "IODELAY_NAND",
	parameter IDELAY_TAP 			  = 20
   )
  (
   input        clk0,
   input        clk90,
   input        rst0,
   input	[4:0]  dlyval_dqs,
   input        dlyld_dqs,
   input        dqs_oe_n,
   input        dqs_rst_n,
   inout        ddr_dqs,

   output [4:0] dlyvalout_dqs,
   output       delayed_dqs
   );

  wire          clk180;
  wire          dqs_bufio;
  
  wire          dqs_ibuf;
  wire          dqs_idelay;
  wire          dqs_oe_n_r;
  reg           dqs_rst_n_r /* synthesis syn_maxfan = 1 syn_preserve = true */;
  reg           dqs_rst_n_r2 /* synthesis syn_maxfan = 1 syn_preserve = true */;
  wire          dqs_out;

  assign        clk180 = ~clk0;

	reg	[4:0] dlyval_sync_r1;
	reg	[4:0] dlyval_sync_r2;
	reg	dlyld_sync_r1, dlyld_sync_r2;

//Synchronize delay adjustment from clk0 -> clk180 -> clk90
always @ (posedge clk180) 
begin
	dlyval_sync_r1 <= dlyval_dqs;
	dlyld_sync_r1 <= dlyld_dqs;
end

always @ (posedge clk90)
begin
	dlyval_sync_r2 <= dlyval_sync_r1;
	dlyld_sync_r2 <= dlyld_sync_r1;
end


/* DQS Gating
DQS gating calibration is required for DDR2 memories as they use differential DQS lines with on-die 
termination (ODT) and do not have on board pull-up or pull-down resistors on the DQS lines. During a 
read operation, if a DQS line is not driven, a high impedance value can propagate through the DDR 
controller and can be misinterpreted as an access. Therefore, the DQS signals should be gated internally 
and used only when needed. This is done by the DQS calibration procedure.
http://cache.freescale.com/files/dsp/doc/app_note/AN3992.pdf
*/
//For NAND, we shouldn't need DQS gating because we have pull up/down resistors on the DQS line
//We DON'T have pullup/down resistors! Forgot to add them. 
//Options: either rework the board by adding these resistors, or gate DQS in
//hardware. 
//[OK] Added PULL DOWN RESISTORS. 

//replaced IODELAY with 7 series IDELAYE2
(* IODELAY_GROUP = IODELAY_GRP *) IDELAYE2 #(
   .CINVCTRL_SEL("FALSE"),          // Enable dynamic clock inversion (FALSE, TRUE)
   .DELAY_SRC("IDATAIN"),           // Delay input (IDATAIN, DATAIN)
   .HIGH_PERFORMANCE_MODE("TRUE"), // Reduced jitter ("TRUE"), Reduced power ("FALSE")
   .IDELAY_TYPE("FIXED"),           // FIXED, VARIABLE, VAR_LOAD, VAR_LOAD_PIPE //TODO: ml testing
   //.IDELAY_TYPE("VAR_LOAD"),           // FIXED, VARIABLE, VAR_LOAD, VAR_LOAD_PIPE
   .IDELAY_VALUE(IDELAY_TAP),                // Input delay tap setting (0-31)
   .PIPE_SEL("FALSE"),              // Select pipelined mode, FALSE, TRUE
   .REFCLK_FREQUENCY(200.0),        // IDELAYCTRL clock input frequency in MHz (190.0-210.0).
   .SIGNAL_PATTERN("CLOCK")          // DATA, CLOCK input signal
)
u_idelay_dqs (
   .CNTVALUEOUT(dlyvalout_dqs), // 5-bit output: Counter value output
   .DATAOUT(dqs_idelay),         // 1-bit output: Delayed data output
   .C(clk90),                     // 1-bit input: Clock input
   .CE(1'b0),                   // 1-bit input: Active high enable increment/decrement input
   .CINVCTRL(),       // 1-bit input: Dynamic clock inversion input
   .CNTVALUEIN(dlyval_sync_r2),   // 5-bit input: Counter value input
   .DATAIN(),           // 1-bit input: Internal delay data input
   .IDATAIN(dqs_ibuf),         // 1-bit input: Data input from the I/O
   .INC(/*dlyinc_dqs*/),                 // 1-bit input: Increment / Decrement tap delay input
   .LD(dlyld_sync_r2),                   // 1-bit input: Load IDELAY_VALUE input
   .LDPIPEEN(),       // 1-bit input: Enable PIPELINE register to load data input
   .REGRST(/*dlyrst_dqs*/)            // 1-bit input: Active-high reset tap-delay input
);

/*
  BUFIO u_bufio_dqs
    (
     .I  (dqs_idelay),
     .O  (dqs_bufio)
     );
*/

//pass DQS to regional clock buffer to clock ISERDESE2 capturing DQ
BUFR #(
   .BUFR_DIVIDE("BYPASS"), // Values: "BYPASS, 1, 2, 3, 4, 5, 6, 7, 8"
   .SIM_DEVICE("7SERIES")  // Must be set to "7SERIES"
)
u_bufr_dqs (
   .O(dqs_bufio),     // 1-bit output: Clock output port
   .CE(1'b1),   // 1-bit input: Active high, clock enable input
   .CLR(1'b0), // 1-bit input: ACtive high reset input
   .I(dqs_idelay)      // 1-bit input: Clock buffer input driven by an IBUFG, MMCM or local interconnect
);


//ml: testing if we don't use a bufio; bufios dont exist on non CC pins
//assign dqs_bufio = dqs_idelay; 

	//Insert an assignment delay for functional simulation. IDELAY is not
	//modeled in functional sims. 
	//For timing simulation, do not use assignment delay
	//TODO FIXME remove this for post implementation sim
	//`ifndef XIL_TIMING
	//		assign delayed_dqs = dqs_bufio;
	//`else
			assign #(DQS_NET_DELAY) delayed_dqs = dqs_bufio;
	//`endif

  //***************************************************************************
  // DQS output-side resources
  //***************************************************************************

  // synthesis attribute max_fanout of dqs_rst_n_r is 1
  // synthesis attribute keep of dqs_rst_n_r is "true"
  always @(posedge clk180)
  begin
    dqs_rst_n_r <= dqs_rst_n;
    dqs_rst_n_r2 <= dqs_rst_n_r;
 end

  ODDR #
    (
     .SRTYPE("SYNC"),
     .DDR_CLK_EDGE("OPPOSITE_EDGE")
     )
    u_oddr_dqs
      (
       .Q  (dqs_out),
       .C  (clk180),
       .CE (1'b1),
       .D1 (dqs_rst_n_r2),      // keep output deasserted for write preamble
       .D2 (1'b0),
       .R  (1'b0),
       .S  (1'b0)
       );

  (* IOB = "FORCE" *) FDP u_tri_state_dqs
    (
     .D   (dqs_oe_n),
     .Q   (dqs_oe_n_r),
     .C   (clk180),
     .PRE (rst0)
     ) /* synthesis syn_useioff = 1 */;

  //***************************************************************************

  // use either single-ended (for DDR1) or differential (for DDR2) DQS input


      IOBUF u_iobuf_dqs
        (
         .O   (dqs_ibuf),
         .IO  (ddr_dqs),
         .I   (dqs_out),
         .T   (dqs_oe_n_r)
         );


endmodule
