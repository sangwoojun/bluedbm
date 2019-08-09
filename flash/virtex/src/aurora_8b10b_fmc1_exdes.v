///////////////////////////////////////////////////////////////////////////////
// (c) Copyright 2008 Xilinx, Inc. All rights reserved.
//
// This file contains confidential and proprietary information
// of Xilinx, Inc. and is protected under U.S. and
// international copyright and other intellectual property
// laws.
//
// DISCLAIMER
// This disclaimer is not a license and does not grant any
// rights to the materials distributed herewith. Except as
// otherwise provided in a valid license issued to you by
// Xilinx, and to the maximum extent permitted by applicable
// law: (1) THESE MATERIALS ARE MADE AVAILABLE "AS IS" AND
// WITH ALL FAULTS, AND XILINX HEREBY DISCLAIMS ALL WARRANTIES
// AND CONDITIONS, EXPRESS, IMPLIED, OR STATUTORY, INCLUDING
// BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, NON-
// INFRINGEMENT, OR FITNESS FOR ANY PARTICULAR PURPOSE; and
// (2) Xilinx shall not be liable (whether in contract or tort,
// including negligence, or under any other theory of
// liability) for any loss or damage of any kind or nature
// related to, arising under or in connection with these
// materials, including for any direct, or any indirect,
// special, incidental, or consequential loss or damage
// (including loss of data, profits, goodwill, or any type of
// loss or damage suffered as a result of any action brought
// by a third party) even if such damage or loss was
// reasonably foreseeable or Xilinx had been advised of the
// possibility of the same.
//
// CRITICAL APPLICATIONS
// Xilinx products are not designed or intended to be fail-
// safe, or for use in any application requiring fail-safe
// performance, such as life-support or safety devices or
// systems, Class III medical devices, nuclear facilities,
// applications related to the deployment of airbags, or any
// other applications that could lead to death, personal
// injury, or severe property or environmental damage
// (individually and collectively, "Critical
// Applications"). Customer assumes the sole risk and
// liability of any use of Xilinx products in Critical
// Applications, subject only to applicable laws and
// regulations governing limitations on product liability.
//
// THIS COPYRIGHT NOTICE AND DISCLAIMER MUST BE RETAINED AS
// PART OF THIS FILE AT ALL TIMES.
//
//
///////////////////////////////////////////////////////////////////////////////
//
//  AURORA_EXAMPLE
//
//  Aurora Generator
//
//
//  Description: Sample Instantiation of a 4 4-byte lane module.
//               Only tests initialization in hardware.
//
//        

`timescale 1 ns / 1 ps
(* core_generation_info = "aurora_8b10b_fmc1,aurora_8b10b_v10_2,{user_interface=AXI_4_Streaming,backchannel_mode=Sidebands,c_aurora_lanes=4,c_column_used=right,c_gt_clock_1=GTXQ5,c_gt_clock_2=None,c_gt_loc_1=X,c_gt_loc_10=X,c_gt_loc_11=X,c_gt_loc_12=X,c_gt_loc_13=X,c_gt_loc_14=X,c_gt_loc_15=X,c_gt_loc_16=X,c_gt_loc_17=X,c_gt_loc_18=X,c_gt_loc_19=X,c_gt_loc_2=X,c_gt_loc_20=X,c_gt_loc_21=1,c_gt_loc_22=2,c_gt_loc_23=3,c_gt_loc_24=4,c_gt_loc_25=X,c_gt_loc_26=X,c_gt_loc_27=X,c_gt_loc_28=X,c_gt_loc_29=X,c_gt_loc_3=X,c_gt_loc_30=X,c_gt_loc_31=X,c_gt_loc_32=X,c_gt_loc_33=X,c_gt_loc_34=X,c_gt_loc_35=X,c_gt_loc_36=X,c_gt_loc_37=X,c_gt_loc_38=X,c_gt_loc_39=X,c_gt_loc_4=X,c_gt_loc_40=X,c_gt_loc_41=X,c_gt_loc_42=X,c_gt_loc_43=X,c_gt_loc_44=X,c_gt_loc_45=X,c_gt_loc_46=X,c_gt_loc_47=X,c_gt_loc_48=X,c_gt_loc_5=X,c_gt_loc_6=X,c_gt_loc_7=X,c_gt_loc_8=X,c_gt_loc_9=X,c_lane_width=4,c_line_rate=44000,c_nfc=false,c_nfc_mode=IMM,c_refclk_frequency=275000,c_simplex=false,c_simplex_mode=TX,c_stream=true,c_ufc=false,flow_mode=None,interface_mode=Streaming,dataflow_config=Duplex}" *)
(* DowngradeIPIdentifiedWarnings="yes" *)
module aurora_8b10b_fmc1_exdes #
(
     parameter   USE_CHIPSCOPE        = 0,
     parameter   USE_CORE_TRAFFIC     = 1
)
(
	RX_DATA,
	rx_en,
	rx_rdy,

	TX_DATA,
	tx_en,
	tx_rdy,

	USER_CLK,
	USER_RST,
	USER_RST_N,

	RESET_N,
    // User IO
    HARD_ERR,
    SOFT_ERR,
    ERR_COUNT,

    LANE_UP,
    CHANNEL_UP,
//    INIT_CLK_P,
//    INIT_CLK_N,
//    DRP_CLK_IN,
    GT_RESET_N,

//    GTXQ5_P,
//    GTXQ5_N,
	INIT_CLK_IN,
	GTX_CLK,
    // GT I/O
    RXP,
    RXN,
    TXP,
    TXN
);


//***********************************Port Declarations*******************************
	output [0:127] RX_DATA;
	input rx_en;
	output rx_rdy;

	input [0:127] TX_DATA;
	input tx_en;
	output tx_rdy;

	output USER_CLK;
	output USER_RST;
	output USER_RST_N;
    // User I/O
input              RESET_N;
//input              INIT_CLK_P;
//input              INIT_CLK_N;
//input              DRP_CLK_IN;
input              GT_RESET_N;
output             HARD_ERR;
output             SOFT_ERR;
output  [0:7]      ERR_COUNT;


output  [0:3]      LANE_UP;
output             CHANNEL_UP;
    // Clocks
//input              GTXQ5_P;
//input              GTXQ5_N;
input INIT_CLK_IN;
input GTX_CLK;

// wjun
	reg [0:127] RX_DATA_delay;
	reg        rx_rdy_delay;

	wire RESET;
	assign RESET = ~RESET_N;
	assign DRP_CLK_IN = INIT_CLK_IN;
	wire GT_RESET_IN;
	assign GT_RESET_IN = ~GT_RESET_N;
	assign USER_CLK = user_clk_i;
	assign USER_RST = system_reset_i;
	assign USER_RST_N = !system_reset_i;
	
	assign tx_src_rdy_n_i = !tx_en;
	assign tx_rdy = (!tx_dst_rdy_n_i) && channel_up_i && !system_reset_i;
	assign tx_d_i = TX_DATA;
	
	assign RX_DATA = RX_DATA_delay;
	assign rx_rdy = rx_rdy_delay;

	always @ (posedge user_clk_i) begin
		rx_rdy_delay <=  !system_reset_i && channel_up_i && !rx_src_rdy_n_i;
		RX_DATA_delay <= rx_d_i;
	end

    // GT Serial I/O
input   [0:3]      RXP;
input   [0:3]      RXN;
output  [0:3]      TXP;
output  [0:3]      TXN;

//**************************External Register Declarations****************************
reg                HARD_ERR;
reg                SOFT_ERR;
reg     [0:7]      ERR_COUNT;    
reg     [0:3]      LANE_UP;
reg                CHANNEL_UP;
//********************************Wire Declarations**********************************
    // Stream TX Interface
(* mark_debug = "true" *) wire    [0:127]    tx_d_i;
wire               tx_src_rdy_n_i;
wire               tx_dst_rdy_n_i;
    // Stream RX Interface
wire    [0:127]    rx_d_i;
wire               rx_src_rdy_n_i;

    // Error Detection Interface
(* mark_debug = "true" *)wire               hard_err_i;
(* mark_debug = "true" *)wire               soft_err_i;
    // Status
(* mark_debug = "true" *)wire               channel_up_i;
(* mark_debug = "true" *)reg                channel_up_r;
(* mark_debug = "true" *)wire    [0:3]      lane_up_i;
    // Clock Compensation Control Interface
wire               warn_cc_i;
    // System Interface
//(* mark_debug = "true" *)wire               pll_not_locked_i;
wire               user_clk_i;
wire               reset_i;
wire               power_down_i;
wire    [2:0]      loopback_i;
wire               tx_lock_i;
(* mark_debug = "true" *)wire               link_reset_i;
(* mark_debug = "true" *)wire               tx_resetdone_i;
(* mark_debug = "true" *)wire               rx_resetdone_i;
(* KEEP = "TRUE" *) wire               init_clk_i;
wire    [8:0]     daddr_in_i;
wire              dclk_in_i;
wire              den_in_i;
wire    [15:0]    di_in_i;
wire              drdy_out_unused_i;
wire    [15:0]    drpdo_out_unused_i;
wire              dwe_in_i;
wire    [8:0]     daddr_in_lane1_i;
wire              dclk_in_lane1_i;
wire              den_in_lane1_i;
wire    [15:0]    di_in_lane1_i;
wire              drdy_out_lane1_unused_i;
wire    [15:0]    drpdo_out_lane1_unused_i;
wire              dwe_in_lane1_i;
wire    [8:0]     daddr_in_lane2_i;
wire              dclk_in_lane2_i;
wire              den_in_lane2_i;
wire    [15:0]    di_in_lane2_i;
wire              drdy_out_lane2_unused_i;
wire    [15:0]    drpdo_out_lane2_unused_i;
wire              dwe_in_lane2_i;
wire    [8:0]     daddr_in_lane3_i;
wire              dclk_in_lane3_i;
wire              den_in_lane3_i;
wire    [15:0]    di_in_lane3_i;
wire              drdy_out_lane3_unused_i;
wire    [15:0]    drpdo_out_lane3_unused_i;
wire              dwe_in_lane3_i;


(* mark_debug = "true" *)wire               gt_reset_i; 
(* mark_debug = "true" *)wire               system_reset_i;
(* mark_debug = "true" *)wire               sysreset_vio_i;
(* mark_debug = "true" *)wire               gtreset_vio_i;
wire               gtreset_vio_o;
(* mark_debug = "true" *)wire    [2:0]      loopback_vio_i;
wire    [2:0]      loopback_vio_o;
    //Frame check signals
(* mark_debug = "true" *)  wire    [0:7]      err_count_i;


    wire [35:0] icon_to_vio_i;
    wire [15:0] sync_out_i;

(* mark_debug = "true" *)    wire        lane_up_i_i;
(* mark_debug = "true" *)    wire        tx_lock_i_i;
    wire        lane_up_reduce_i;
    wire        rst_cc_module_i;

wire               tied_to_ground_i;
wire    [0:127]    tied_to_gnd_vec_i;
    // TX AXI PDU I/F wires
wire    [0:127]    tx_data_i;
wire               tx_tvalid_i;
wire               tx_tready_i;

    // RX AXI PDU I/F wires
wire    [0:127]    rx_data_i;
wire               rx_tvalid_i;

   //SLACK Registers
   reg    [0:3]      lane_up_r;
   reg    [0:3]      lane_up_r2;
//*********************************Main Body of Code**********************************

  //SLACK registers
  always @ (posedge user_clk_i)
  begin
    lane_up_r    <=  lane_up_i;
    lane_up_r2   <=  lane_up_r;
  end

  assign lane_up_reduce_i  = &lane_up_r2;
  assign rst_cc_module_i   = !lane_up_reduce_i;


//____________________________Register User I/O___________________________________
// Register User Outputs from core.

    always @(posedge user_clk_i)
    begin
        HARD_ERR      <=  hard_err_i;
        SOFT_ERR      <=  soft_err_i;
        ERR_COUNT       <=  err_count_i;
        LANE_UP         <=  lane_up_i;
        CHANNEL_UP      <=  channel_up_i;
    end

//____________________________Tie off unused signals_______________________________

    // System Interface
    assign          tied_to_ground_i        = 1'b0;
    assign  tied_to_gnd_vec_i   =   128'd0;
    assign  power_down_i        =   1'b0;

    always @(posedge user_clk_i)
        channel_up_r      <=  channel_up_i;

assign  daddr_in_i  =  9'h0;
assign  den_in_i    =  1'b0;
assign  di_in_i     =  16'h0;
assign  dwe_in_i    =  1'b0;
assign  daddr_in_lane1_i  =  9'h0;
assign  den_in_lane1_i    =  1'b0;
assign  di_in_lane1_i     =  16'h0;
assign  dwe_in_lane1_i    =  1'b0;
assign  daddr_in_lane2_i  =  9'h0;
assign  den_in_lane2_i    =  1'b0;
assign  di_in_lane2_i     =  16'h0;
assign  dwe_in_lane2_i    =  1'b0;
assign  daddr_in_lane3_i  =  9'h0;
assign  den_in_lane3_i    =  1'b0;
assign  di_in_lane3_i     =  16'h0;
assign  dwe_in_lane3_i    =  1'b0;
//___________________________Module Instantiations_________________________________

    aurora_8b10b_fmc1_support aurora_module_i
    (
        // AXI TX Interface
        .s_axi_tx_tdata(tx_data_i),
        .s_axi_tx_tvalid(tx_tvalid_i),
        .s_axi_tx_tready(tx_tready_i),

        // AXI RX Interface
        .m_axi_rx_tdata(rx_data_i),
        .m_axi_rx_tvalid(rx_tvalid_i),
        // V5 Serial I/O
        .rxp(RXP),
        .rxn(RXN),
        .txp(TXP),
        .txn(TXN),
        // GT Reference Clock Interface
        .gt_refclk1_i(GTX_CLK),
        // Error Detection Interface
        .hard_err(hard_err_i),
        .soft_err(soft_err_i),


        // Status
        .channel_up(channel_up_i),
        .lane_up(lane_up_i),
        // Clock Compensation Control Interface
        //.warn_cc(warn_cc_i),
        //.do_cc(do_cc_i),
        // System Interface
        .user_clk_out(user_clk_i),
        .reset(reset_i),
        .sys_reset_out(system_reset_i),
        .power_down(power_down_i),
        .loopback(loopback_vio_o),
        .gt_reset(gtreset_vio_o),
        .tx_lock(tx_lock_i),
        //.pll_not_locked_out(pll_not_locked_i),
        .pll_not_locked_out(),
	.tx_resetdone_out(tx_resetdone_i),
	.rx_resetdone_out(rx_resetdone_i),
        .init_clk_in(INIT_CLK_IN),
        .drpclk_in  (DRP_CLK_IN),
.drpaddr_in  (daddr_in_i),
.drpen_in    (den_in_i),
.drpdi_in     (di_in_i),
.drprdy_out  (drdy_out_unused_i),
.drpdo_out (drpdo_out_unused_i),
.drpwe_in    (dwe_in_i),
.drpaddr_in_lane1  (daddr_in_lane1_i),
.drpen_in_lane1    (den_in_lane1_i),
.drpdi_in_lane1     (di_in_lane1_i),
.drprdy_out_lane1  (drdy_out_lane1_unused_i),
.drpdo_out_lane1 (drpdo_out_lane1_unused_i),
.drpwe_in_lane1    (dwe_in_lane1_i),
.drpaddr_in_lane2  (daddr_in_lane2_i),
.drpen_in_lane2    (den_in_lane2_i),
.drpdi_in_lane2     (di_in_lane2_i),
.drprdy_out_lane2  (drdy_out_lane2_unused_i),
.drpdo_out_lane2 (drpdo_out_lane2_unused_i),
.drpwe_in_lane2    (dwe_in_lane2_i),
.drpaddr_in_lane3  (daddr_in_lane3_i),
.drpen_in_lane3    (den_in_lane3_i),
.drpdi_in_lane3     (di_in_lane3_i),
.drprdy_out_lane3  (drdy_out_lane3_unused_i),
.drpdo_out_lane3 (drpdo_out_lane3_unused_i),
.drpwe_in_lane3    (dwe_in_lane3_i),

        .link_reset_out(link_reset_i)
    );


    aurora_8b10b_STANDARD_CC_MODULE standard_cc_module_i
    (
        .RESET(rst_cc_module_i),
        // Clock Compensation Control Interface
        .WARN_CC(warn_cc_i),
        .DO_CC(do_cc_i),
        // System Interface
        .USER_CLK(user_clk_i)
    );

generate
 if (USE_CORE_TRAFFIC==1)
 begin : traffic

    //_____________________________ TX AXI SHIM _______________________________
    aurora_8b10b_LL_TO_AXI_EXDES #
    (
       .DATA_WIDTH(128),
       .USE_4_NFC (0),
       .STRB_WIDTH(16),
       .REM_WIDTH (4)
    )

    frame_gen_ll_to_axi_pdu_i
    (
     // LocalLink input Interface
     .LL_IP_DATA(tx_d_i),
     .LL_IP_SOF_N(),
     .LL_IP_EOF_N(),
     .LL_IP_REM(),
     .LL_IP_SRC_RDY_N(tx_src_rdy_n_i),
     .LL_OP_DST_RDY_N(tx_dst_rdy_n_i),

     // AXI4-S output signals
     .AXI4_S_OP_TVALID(tx_tvalid_i),
     .AXI4_S_OP_TDATA(tx_data_i),
     .AXI4_S_OP_TKEEP(),
     .AXI4_S_OP_TLAST(),
     .AXI4_S_IP_TREADY(tx_tready_i)
    );

/*
    //Connect a frame generator to the TX User interface
    aurora_8b10b_fmc1_FRAME_GEN frame_gen_i
    (
        // User Interface
        .TX_D(tx_d_i), 
        .TX_SRC_RDY_N(tx_src_rdy_n_i),
        .TX_DST_RDY_N(tx_dst_rdy_n_i),


        // System Interface
        .USER_CLK(user_clk_i),      
        .RESET(system_reset_i),
        .CHANNEL_UP(channel_up_r)
    );
*/
    //_____________________________ RX AXI SHIM _______________________________
    aurora_8b10b_AXI_TO_LL_EXDES #
    (
       .DATA_WIDTH(128),
       .STRB_WIDTH(16),
       .REM_WIDTH (4)
    )
    frame_chk_axi_to_ll_pdu_i
    (
     // AXI4-S input signals
     .AXI4_S_IP_TX_TVALID(rx_tvalid_i),
     .AXI4_S_IP_TX_TREADY(),
     .AXI4_S_IP_TX_TDATA(rx_data_i),
     .AXI4_S_IP_TX_TKEEP(),
     .AXI4_S_IP_TX_TLAST(),

     // LocalLink output Interface
     .LL_OP_DATA(rx_d_i),
     .LL_OP_SOF_N(),
     .LL_OP_EOF_N() ,
     .LL_OP_REM() ,
     .LL_OP_SRC_RDY_N(rx_src_rdy_n_i),
     .LL_IP_DST_RDY_N(1'b0),

     // System Interface
     .USER_CLK(user_clk_i),      
     .RESET(system_reset_i),
     .CHANNEL_UP(channel_up_r)
     );
/*
    aurora_8b10b_fmc1_FRAME_CHECK frame_check_i
    (
        // User Interface
        .RX_D(rx_d_i), 
        .RX_SRC_RDY_N(rx_src_rdy_n_i),

        // System Interface
        .USER_CLK(user_clk_i),      
        .RESET(system_reset_i),
        .CHANNEL_UP(channel_up_r),
        .ERR_COUNT(err_count_i)
    );   
 */
 end //end USE_CORE_TRAFFIC=1 block
 else
 begin: no_traffic
     //define traffic generation modules here
 end //end USE_CORE_TRAFFIC=0 block

endgenerate //End generate for USE_CORE_TRAFFIC


generate
if (USE_CHIPSCOPE==1)
begin : chipscope1


assign lane_up_i_i = &lane_up_i;
assign tx_lock_i_i = tx_lock_i;

  //-----------------------------------------------------------------
  //  VIO core instance
  //-----------------------------------------------------------------
vio_7series i_vio 
(
  .clk(INIT_CLK_IN), // input CLK
  .probe_in0(channel_up_r), // input [0 : 0] PROBE_IN0
  .probe_in1(lane_up_i_i), // input [0 : 0] PROBE_IN1
  .probe_in2(tx_lock_i_i), // input [0 : 0] PROBE_IN2
  .probe_out0(sysreset_vio_i), // output [0 : 0] PROBE_OUT0
  .probe_out1(gtreset_vio_i), // output [0 : 0] PROBE_OUT1
  .probe_out2(loopback_vio_i) // output [2 : 0] PROBE_OUT2
);

  //-----------------------------------------------------------------
  //  ILA core instance
  //-----------------------------------------------------------------
  /*
ila_7series i_ila (
  .clk(user_clk_i), // input CLK
  .probe0({lane_up_i_i,channel_up_r,pll_not_locked_i,tx_lock_i_i,hard_err_i,soft_err_i,1'b0,tx_resetdone_i,rx_resetdone_i,link_reset_i,14'd0,err_count_i,rx_d_i[0:15],tx_d_i[0:15]}) // input [63 : 0] PROBE0
);
*/

end //end USE_CHIPSCOPE=1 generate section
else
begin : no_chipscope1
                                                                                                                                                                      
end

 if (USE_CHIPSCOPE==1)
 begin : chipscope2
     // Shared VIO Outputs
 assign  reset_i =   RESET | sysreset_vio_i;
 assign  gtreset_vio_o =   GT_RESET_IN | gtreset_vio_i;
 assign  loopback_vio_o =   3'b000 | loopback_vio_i;
 end //end USE_CHIPSCOPE=1 block
 else
 begin: no_chipscope2
 assign  reset_i =   RESET;
 assign  gtreset_vio_o =   GT_RESET_IN;
 assign  loopback_vio_o =   3'b000;
 end //end USE_CHIPSCOPE=0 block

endgenerate //End generate for USE_CHIPSCOPE


endmodule
 
