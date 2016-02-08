//takes in the system clock and generates various shifted clocks 
//and synchronized resets for the NAND PHY
//also instantiates idelayctrl

module nand_infrastructure #
	(
   parameter IODELAY_GRP           = "IODELAY_NAND"
	)
 (
   input  sys_clk_p,
   input  sys_clk_n,

   output clk0,
   output clk90,

	
   input  sys_rst_n,
   
   output rstn0,
   output rstn90

	//debug control
//	inout [35:0] dbg_ctrl_0,
//	inout [35:0] dbg_ctrl_1,
//	inout [35:0] dbg_ctrl_2,
//	inout [35:0] dbg_ctrl_3,
//	inout [35:0] dbg_ctrl_4,
//	inout [35:0] dbg_ctrl_5,
//	inout [35:0] dbg_ctrl_6,
//	inout [35:0] dbg_ctrl_7
//inout [35:0] dbg_ctrl_8,
//inout [35:0] dbg_ctrl_9,
//inout [35:0] dbg_ctrl_10,
//inout [35:0] dbg_ctrl_11,
//inout [35:0] dbg_ctrl_12,
//inout [35:0] dbg_ctrl_13,
//inout [35:0] dbg_ctrl_14,
//inout [35:0] dbg_ctrl_15
);
  //***************************************************************************
  // IODELAY Group Name: Replication and placement of IDELAYCTRLs will be
  // handled automatically by software tools if IDELAYCTRLs have same refclk,
  // reset and rdy nets. Designs with a unique RESET will commonly create a
  // unique RDY. Constraint IODELAY_GROUP is associated to a set of IODELAYs
  // with an IDELAYCTRL. The parameter IODELAY_GRP value can be any string.
  //***************************************************************************
//localparam IODELAY_GRP = "IODELAY_NAND";
localparam RST_SYNC_NUM = 25;

wire idelay_ctrl_rdy;
wire locked;
wire clk200;
wire rst200;
wire rst0;
wire rst90;
reg [RST_SYNC_NUM-1:0]     rst0_sync_r /* synthesis syn_maxfan = 20 */;
reg [RST_SYNC_NUM-1:0]     rst200_sync_r /* synthesis syn_maxfan = 20 */;
reg [RST_SYNC_NUM-1:0]     rst90_sync_r /* synthesis syn_maxfan = 20 */;

  //***************************************************************************
 // Note: differential system clock input need to have internal termination off
 // Externally terminated, IOSTANDARD of LVDS_25 specified in ucf
 // http://www.xilinx.com/support/answers/43989.htm
 // http://forums.xilinx.com/t5/7-Series-FPGAs/LVDS-in-HR-banks/td-p/206709
  //***************************************************************************

//instantiate MMCM from coregen
//generates a 100Mhz 90deg shifted clock, a 200MHz clock (for idelayctrl ref clk)
//puts all clocks on global clock network using BUFG
  clk_wiz_v3_6 mmcm_gen
   (// Clock in ports
    .CLK_IN1_P(sys_clk_p),    // IN
    .CLK_IN1_N(sys_clk_n),    // IN
    // Clock out ports
    .CLK_0(clk0),     // OUT
    .CLK_90(clk90),     // OUT
    .CLK_200(clk200),     // OUT
    // Status and control signals
    .RESET(~sys_rst_n),// IN; ml: is this active high?
    .LOCKED(locked));      // OUT


//some reset synchronization copied from Virtex 5 DDR controller
//not sure if its needed 
  //***************************************************************************
  // Reset synchronization
  // NOTES:
  //   1. shut down the whole operation if the PLL/ DCM hasn't yet locked (and
  //      by inference, this means that external SYS_RST_IN has been asserted -
  //      PLL/DCM deasserts LOCKED as soon as SYS_RST_IN asserted)
  //   2. In the case of all resets except rst200, also assert reset if the
  //      IDELAY master controller is not yet ready
  //   3. asynchronously assert reset. This was we can assert reset even if
  //      there is no clock (needed for things like 3-stating output buffers).
  //      reset deassertion is synchronous.
  //***************************************************************************

  assign rst_tmp = ~sys_rst_n | ~locked | ~idelay_ctrl_rdy;

  // synthesis attribute max_fanout of rst0_sync_r is 20
  always @(posedge clk0 or posedge rst_tmp)
    if (rst_tmp)
      rst0_sync_r <= {RST_SYNC_NUM{1'b1}};
    else
      // logical left shift by one (pads with 0)
      rst0_sync_r <= rst0_sync_r << 1;

  // synthesis attribute max_fanout of rst90_sync_r is 20
  always @(posedge clk90 or posedge rst_tmp)
    if (rst_tmp)
      rst90_sync_r <= {RST_SYNC_NUM{1'b1}};
    else
      rst90_sync_r <= rst90_sync_r << 1;

  // make sure CLK200 doesn't depend on IDELAY_CTRL_RDY, else chicken n' egg
   // synthesis attribute max_fanout of rst200_sync_r is 20
  always @(posedge clk200 or negedge locked)
    if (!locked)
      rst200_sync_r <= {RST_SYNC_NUM{1'b1}};
    else
      rst200_sync_r <= rst200_sync_r << 1;


  assign rst0   = rst0_sync_r[RST_SYNC_NUM-1]; //set to MSB
  assign rst90  = rst90_sync_r[RST_SYNC_NUM-1];
  assign rst200 = rst200_sync_r[RST_SYNC_NUM-1];

	assign rstn0 = ~rst0;
	assign rstn90 = ~rst90;

//instantiate idelayctrl

   (* IODELAY_GROUP = IODELAY_GRP *) IDELAYCTRL u_idelayctrl
     (
      .RDY(idelay_ctrl_rdy),
      .REFCLK(clk200),
      .RST(rst200)
      );

//Instantiate chipscope ICON
//	chipscope_icon icon_0 (
//		.CONTROL0(dbg_ctrl_0), // INOUT BUS [35:0]
//		.CONTROL1(dbg_ctrl_1), // INOUT BUS [35:0]
//		.CONTROL2(dbg_ctrl_2), // INOUT BUS [35:0]
//		.CONTROL3(dbg_ctrl_3), // INOUT BUS [35:0]
//		.CONTROL4(dbg_ctrl_4), // INOUT BUS [35:0]
//		.CONTROL5(dbg_ctrl_5), // INOUT BUS [35:0]
//		.CONTROL6(dbg_ctrl_6), // INOUT BUS [35:0]
//		.CONTROL7(dbg_ctrl_7) // INOUT BUS [35:0]
//	) /* synthesis syn_noprune=1 */;
//
//	chipscope_icon_bscan1 icon_1 (
//		.CONTROL0(dbg_ctrl_8), // INOUT BUS [35:0]
//		.CONTROL1(dbg_ctrl_9), // INOUT BUS [35:0]
//		.CONTROL2(dbg_ctrl_10), // INOUT BUS [35:0]
//		.CONTROL3(dbg_ctrl_11), // INOUT BUS [35:0]
//		.CONTROL4(dbg_ctrl_12), // INOUT BUS [35:0]
//		.CONTROL5(dbg_ctrl_13), // INOUT BUS [35:0]
//		.CONTROL6(dbg_ctrl_14), // INOUT BUS [35:0]
//		.CONTROL7(dbg_ctrl_15) // INOUT BUS [35:0]
//	) /* synthesis syn_noprune=1 */;

endmodule

