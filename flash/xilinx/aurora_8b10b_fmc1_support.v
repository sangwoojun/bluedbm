///////////////////////////////////////////////////////////////////////////////
// (c) Copyright 1995-2014 Xilinx, Inc. All rights reserved.
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
///////////////////////////////////////////////////////////////////////////////

 `timescale 1 ns / 10 ps

(* core_generation_info = "aurora_8b10b_fmc1,aurora_8b10b_v10_2,{user_interface=AXI_4_Streaming,backchannel_mode=Sidebands,c_aurora_lanes=4,c_column_used=right,c_gt_clock_1=GTXQ5,c_gt_clock_2=None,c_gt_loc_1=X,c_gt_loc_10=X,c_gt_loc_11=X,c_gt_loc_12=X,c_gt_loc_13=X,c_gt_loc_14=X,c_gt_loc_15=X,c_gt_loc_16=X,c_gt_loc_17=X,c_gt_loc_18=X,c_gt_loc_19=X,c_gt_loc_2=X,c_gt_loc_20=X,c_gt_loc_21=1,c_gt_loc_22=2,c_gt_loc_23=3,c_gt_loc_24=4,c_gt_loc_25=X,c_gt_loc_26=X,c_gt_loc_27=X,c_gt_loc_28=X,c_gt_loc_29=X,c_gt_loc_3=X,c_gt_loc_30=X,c_gt_loc_31=X,c_gt_loc_32=X,c_gt_loc_33=X,c_gt_loc_34=X,c_gt_loc_35=X,c_gt_loc_36=X,c_gt_loc_37=X,c_gt_loc_38=X,c_gt_loc_39=X,c_gt_loc_4=X,c_gt_loc_40=X,c_gt_loc_41=X,c_gt_loc_42=X,c_gt_loc_43=X,c_gt_loc_44=X,c_gt_loc_45=X,c_gt_loc_46=X,c_gt_loc_47=X,c_gt_loc_48=X,c_gt_loc_5=X,c_gt_loc_6=X,c_gt_loc_7=X,c_gt_loc_8=X,c_gt_loc_9=X,c_lane_width=4,c_line_rate=44000,c_nfc=false,c_nfc_mode=IMM,c_refclk_frequency=275000,c_simplex=false,c_simplex_mode=TX,c_stream=true,c_ufc=false,flow_mode=None,interface_mode=Streaming,dataflow_config=Duplex}" *)
module aurora_8b10b_fmc1_support
 (
 
input   [0:127]    s_axi_tx_tdata,
 
input              s_axi_tx_tvalid,
output             s_axi_tx_tready,

 
output  [0:127]    m_axi_rx_tdata,
 
output             m_axi_rx_tvalid,



    // GT Serial I/O
input   [0:3]      rxp,
input   [0:3]      rxn,

output  [0:3]      txp,
output  [0:3]      txn,

    // GT Reference Clock Interface
input              gt_refclk1_i,

    // Error Detection Interface
output             hard_err,
output             soft_err,
    // Status
output  [0:3]      lane_up,
output             channel_up,



    // Clock Compensation Control Interface
//input              warn_cc,
//input              do_cc,

    // System Interface
output              user_clk_out,
input               gt_reset,
input               reset,

input              power_down,
input   [2:0]      loopback,
output             tx_lock,

input              init_clk_in,
output             tx_resetdone_out,
output             rx_resetdone_out,
output             link_reset_out,
output             sys_reset_out,

    //DRP Ports
input              drpclk_in,
input   [8:0]      drpaddr_in, 
input              drpen_in, 
input   [15:0]     drpdi_in, 
output             drprdy_out, 
output  [15:0]     drpdo_out, 
input              drpwe_in, 
input   [8:0]      drpaddr_in_lane1, 
input              drpen_in_lane1, 
input   [15:0]     drpdi_in_lane1, 
output             drprdy_out_lane1, 
output  [15:0]     drpdo_out_lane1, 
input              drpwe_in_lane1, 
input   [8:0]      drpaddr_in_lane2, 
input              drpen_in_lane2, 
input   [15:0]     drpdi_in_lane2, 
output             drprdy_out_lane2, 
output  [15:0]     drpdo_out_lane2, 
input              drpwe_in_lane2, 
input   [8:0]      drpaddr_in_lane3, 
input              drpen_in_lane3, 
input   [15:0]     drpdi_in_lane3, 
output             drprdy_out_lane3, 
output  [15:0]     drpdo_out_lane3, 
input              drpwe_in_lane3, 


output             pll_not_locked_out

 );

 `define DLY #1

 //*********************************Main Body of Code**********************************

//----------  Wire declarations
//------------------{
//____________________________COMMON PORTS ;_______________________________{
//    ------------------------- Common Block - QPLL Ports ------------------------
wire                      gt0_qplllock_i;
wire                      gt0_qpllrefclklost_i;
wire                      gt0_qpllreset_i;
wire                      gt_qpllclk_quad6_i;
wire                      gt_qpllrefclk_quad6_i;
//____________________________COMMON PORTS ;_______________________________}
//------------------}

wire               tx_out_clk_i;
wire               user_clk_i;
wire               sync_clk_i;
wire               pll_not_locked_i;
wire               tx_lock_i;

wire               init_clk_i;
wire               tx_resetdone_i;
wire               rx_resetdone_i;
wire               link_reset_i;
wire               system_reset_i;
wire               gt_reset_i;


   
//--- Instance of GT differential buffer ---------//
/*
 IBUFDS_GTE2 IBUFDS_GTE2_CLK1
 (
 .I(gt_refclk1_p),
 .IB(gt_refclk1_n),
 .CEB(1'b0),
 .O(gt_refclk1_i),
 .ODIV2()
 );
*/


    // Instantiate a clock module for clock division.
    aurora_8b10b_fmc1_CLOCK_MODULE clock_module_i
    (
        .INIT_CLK_IN(init_clk_in),
        .INIT_CLK_O(init_clk_i),
        .GT_CLK(tx_out_clk_i),
        .GT_CLK_LOCKED(tx_lock_i),
        .USER_CLK(user_clk_i),
        .SYNC_CLK(sync_clk_i),
        .PLL_NOT_LOCKED(pll_not_locked_i)
    );

  //  outputs
  assign user_clk_out          =  user_clk_i;
  assign pll_not_locked_out    =  pll_not_locked_i;
  assign tx_lock               =  tx_lock_i;
  assign tx_resetdone_out      =  tx_resetdone_i;
  assign rx_resetdone_out      =  rx_resetdone_i;
  assign link_reset_out        =  link_reset_i;


    aurora_8b10b_fmc1_SUPPORT_RESET_LOGIC support_reset_logic_i
    (
        .RESET(reset),
        .USER_CLK(user_clk_i),
        .INIT_CLK_IN(init_clk_i),
        .GT_RESET_IN(gt_reset),
        .SYSTEM_RESET(system_reset_i),
        .GT_RESET_OUT(gt_reset_i)
    );

//------ instance of _gt_common_wrapper ---{
aurora_8b10b_fmc1_gt_common_wrapper gt_common_support
(
//____________________________COMMON PORTS ,_______________________________{
.gt_qpllclk_quad6_i     (gt_qpllclk_quad6_i   ),
.gt_qpllrefclk_quad6_i  (gt_qpllrefclk_quad6_i),
    //-------------------- Common Block  - Ref Clock Ports ---------------------
    .gt0_gtrefclk0_common_in ( gt_refclk1_i ),

    //----------------------- Common Block - QPLL Ports ------------------------
    .gt0_qplllock_out       (gt0_qplllock_i       ),
    .gt0_qplllockdetclk_in  (init_clk_i                      ),
    .gt0_qpllrefclklost_out (gt0_qpllrefclklost_i ),
    .gt0_qpllreset_in ( gt0_qpllreset_i )
//____________________________COMMON PORTS ,_______________________________}
);


//------ instance of _gt_common_wrapper ---}

//----- Instance of _xci -----[
aurora_8b10b_fmc1 aurora_8b10b_fmc1_i
     (
        // AXI TX Interface
       .s_axi_tx_tdata               (s_axi_tx_tdata),
       .s_axi_tx_tvalid              (s_axi_tx_tvalid),
       .s_axi_tx_tready              (s_axi_tx_tready),

        // AXI RX Interface
       .m_axi_rx_tdata               (m_axi_rx_tdata),
       .m_axi_rx_tvalid              (m_axi_rx_tvalid),


        // GT Serial I/O
       .rxp                          (rxp),
       .rxn                          (rxn),
       .txp                          (txp),
       .txn                          (txn),

        // GT Reference Clock Interface
       .gt_refclk1                   (gt_refclk1_i),
        // Error Detection Interface

        // Error Detection Interface
       .hard_err                     (hard_err),
       .soft_err                     (soft_err),

        // Status
       .channel_up                   (channel_up),
       .lane_up                      (lane_up),



        // Clock Compensation Control Interface
       //.warn_cc                      (warn_cc),
       //.do_cc                        (do_cc),

        // System Interface
       .user_clk                     (user_clk_i),
       .sync_clk                     (sync_clk_i),
       .reset                        (system_reset_i),
       .power_down                   (power_down),
       .loopback                     (loopback),
       .gt_reset                     (gt_reset_i),
       .tx_lock                      (tx_lock_i),
       .init_clk_in                  (init_clk_i),
       .pll_not_locked               (pll_not_locked_i),
       .tx_resetdone_out             (tx_resetdone_i),
       .rx_resetdone_out             (rx_resetdone_i),
       .link_reset_out               (link_reset_i),
       .drpclk_in                    (drpclk_in),
       .drpaddr_in                   (drpaddr_in),
       .drpen_in                     (drpen_in),
       .drpdi_in                     (drpdi_in),
       .drprdy_out                   (drprdy_out),
       .drpdo_out                    (drpdo_out),
       .drpwe_in                     (drpwe_in),
       .drpaddr_in_lane1                   (drpaddr_in_lane1),
       .drpen_in_lane1                     (drpen_in_lane1),
       .drpdi_in_lane1                     (drpdi_in_lane1),
       .drprdy_out_lane1                   (drprdy_out_lane1),
       .drpdo_out_lane1                    (drpdo_out_lane1),
       .drpwe_in_lane1                     (drpwe_in_lane1),
       .drpaddr_in_lane2                   (drpaddr_in_lane2),
       .drpen_in_lane2                     (drpen_in_lane2),
       .drpdi_in_lane2                     (drpdi_in_lane2),
       .drprdy_out_lane2                   (drprdy_out_lane2),
       .drpdo_out_lane2                    (drpdo_out_lane2),
       .drpwe_in_lane2                     (drpwe_in_lane2),
       .drpaddr_in_lane3                   (drpaddr_in_lane3),
       .drpen_in_lane3                     (drpen_in_lane3),
       .drpdi_in_lane3                     (drpdi_in_lane3),
       .drprdy_out_lane3                   (drprdy_out_lane3),
       .drpdo_out_lane3                    (drpdo_out_lane3),
       .drpwe_in_lane3                     (drpwe_in_lane3),

//------------------{
//_________________COMMON PORTS _______________________________{
//    ------------------------- Common Block - QPLL Ports ------------------------
.gt0_qplllock_in        (gt0_qplllock_i),
.gt0_qpllrefclklost_in  (gt0_qpllrefclklost_i),
.gt0_qpllreset_out      (gt0_qpllreset_i),
.gt_qpllclk_quad6_in (gt_qpllclk_quad6_i ),
.gt_qpllrefclk_quad6_in (gt_qpllrefclk_quad6_i ),
//____________________________COMMON PORTS ,_______________________________}
//------------------}

       .sys_reset_out                (sys_reset_out),
       .tx_out_clk                   (tx_out_clk_i)

     );
//----- Instance of _xci -----]



 endmodule 
