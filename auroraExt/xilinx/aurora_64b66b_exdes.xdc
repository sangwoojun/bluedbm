##################################################################################
##
## Project:  Aurora 64B/66B
## Company:  Xilinx
##
##
##
## (c) Copyright 2008 - 2014 Xilinx, Inc. All rights reserved.
##
## This file contains confidential and proprietary information
## of Xilinx, Inc. and is protected under U.S. and
## international copyright and other intellectual property
## laws.
##
## DISCLAIMER
## This disclaimer is not a license and does not grant any
## rights to the materials distributed herewith. Except as
## otherwise provided in a valid license issued to you by
## Xilinx, and to the maximum extent permitted by applicable
## law: (1) THESE MATERIALS ARE MADE AVAILABLE "AS IS" AND
## WITH ALL FAULTS, AND XILINX HEREBY DISCLAIMS ALL WARRANTIES
## AND CONDITIONS, EXPRESS, IMPLIED, OR STATUTORY, INCLUDING
## BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, NON-
## INFRINGEMENT, OR FITNESS FOR ANY PARTICULAR PURPOSE; and
## (2) Xilinx shall not be liable (whether in contract or tort,
## including negligence, or under any other theory of
## liability) for any loss or damage of any kind or nature
## related to, arising under or in connection with these
## materials, including for any direct, or any indirect,
## special, incidental, or consequential loss or damage
## (including loss of data, profits, goodwill, or any type of
## loss or damage suffered as a result of any action brought
## by a third party) even if such damage or loss was
## reasonably foreseeable or Xilinx had been advised of the
## possibility of the same.
##
## CRITICAL APPLICATIONS
## Xilinx products are not designed or intended to be fail-
## safe, or for use in any application requiring fail-safe
## performance, such as life-support or safety devices or
## systems, Class III medical devices, nuclear facilities,
## applications related to the deployment of airbags, or any
## other applications that could lead to death, personal
## injury, or severe property or environmental damage
## (individually and collectively, "Critical
## Applications"). Customer assumes the sole risk and
## liability of any use of Xilinx products in Critical
## Applications, subject only to applicable laws and
## regulations governing limitations on product liability.
##
## THIS COPYRIGHT NOTICE AND DISCLAIMER MUST BE RETAINED AS
## PART OF THIS FILE AT ALL TIMES.
##
###################################################################################################
##
##  aurora_64b66b_exdes
##
##  Description: This is the example design constraints file for a 1 lane Aurora
##               core.
##               This is example design xdc.
##               Note: User need to set proper IO standards for the LOC's mentioned below.
###################################################################################################

## XDC generated for xc7vx485t-ffg1761-2 device
 
## Quad117
set_property LOC K7 [get_ports CLK_aurora_quad117_gtx_clk_n_v]
set_property LOC K8 [get_ports CLK_aurora_quad117_gtx_clk_p_v]

set_false_path -from [get_cells -hier -filter {NAME =~ *auroraQuad_0/rst50/*}]
#set_false_path -to [get_pins -hier -filter {NAME =~ *auroraExt119/auroraExt_*_outPacketQ/*/CLR}]
#set_false_path -to [get_pins -hier -filter {NAME =~ *auroraExt119/auroraExt_*_outPacketQ/*/PRE}]
set_false_path -to [get_pins -hier -filter {NAME =~ *auroraQuad_0/rst50/*/CLR}]

## Quad119
set_property LOC A9 [get_ports CLK_aurora_quad119_gtx_clk_n_v]
set_property LOC A10 [get_ports CLK_aurora_quad119_gtx_clk_p_v]

set_false_path -from [get_cells -hier -filter {NAME =~ *auroraQuad_1/rst50/*}]
#set_false_path -to [get_pins -hier -filter {NAME =~ *auroraExt119/auroraExt_*_outPacketQ/*/CLR}]
#set_false_path -to [get_pins -hier -filter {NAME =~ *auroraExt119/auroraExt_*_outPacketQ/*/PRE}]
set_false_path -to [get_pins -hier -filter {NAME =~ *auroraQuad_1/rst50/*/CLR}]

## Board constraint (50MHz clk)
create_clock -name aurora_117_init_clk_i -period 20.0 [get_pins *auroraQuad_0/auroraExt117ClockDiv/clockdiv4/cntr_reg[1]/Q]
create_clock -name aurora_119_init_clk_i -period 20.0 [get_pins *auroraQuad_1/auroraExt119ClockDiv/clockdiv4/cntr_reg[1]/Q]

## Ref clks
create_clock -name GTXQ0_left_117_i -period 1.600 [get_pins *auroraQuad_0/auroraExt_gtx_clk/O]
create_clock -name GTXQ0_left_119_i -period 1.600 [get_pins *auroraQuad_1/auroraExt_gtx_clk/O]

## Aurora clks
create_clock -name TS_117_user_clk_i_all -period 6.400 [get_pins *auroraQuad_0/auroraExtImport/aurora_64b66b_block_i/clock_module_i/user_clk_net_i/O]
create_clock -name TS_117_sync_clk_i_all -period 3.200 [get_pins *auroraQuad_0/auroraExtImport/aurora_64b66b_block_i/clock_module_i/sync_clock_net_i/O]
create_clock -name TS_119_user_clk_i_all -period 6.400 [get_pins *auroraQuad_1/auroraExtImport/aurora_64b66b_block_i/clock_module_i/user_clk_net_i/O]
create_clock -name TS_119_sync_clk_i_all -period 3.200 [get_pins *auroraQuad_1/auroraExtImport/aurora_64b66b_block_i/clock_module_i/sync_clock_net_i/O]

## CDC from 50Mhz "board clk" to aurora user clk
# 117
set_false_path -from [get_clocks aurora_117_init_clk_i] -to [get_clocks TS_117_user_clk_i_all]
set_false_path -from [get_clocks TS_117_user_clk_i_all] -to [get_clocks aurora_117_init_clk_i]
set_false_path -from [get_clocks aurora_117_init_clk_i] -to [get_clocks TS_117_sync_clk_i_all]
set_false_path -from [get_clocks TS_117_sync_clk_i_all] -to [get_clocks aurora_117_init_clk_i]

set_max_delay -from [get_clocks pcie_clk_125mhz] -to [get_clocks aurora_117_init_clk_i] -datapath_only 8.0
set_max_delay -from [get_clocks aurora_117_init_clk_i] -to [get_clocks pcie_clk_125mhz] -datapath_only 8.0

# 119
set_false_path -from [get_clocks aurora_119_init_clk_i] -to [get_clocks TS_119_user_clk_i_all]
set_false_path -from [get_clocks TS_119_user_clk_i_all] -to [get_clocks aurora_119_init_clk_i]
set_false_path -from [get_clocks aurora_119_init_clk_i] -to [get_clocks TS_119_sync_clk_i_all]
set_false_path -from [get_clocks TS_119_sync_clk_i_all] -to [get_clocks aurora_119_init_clk_i]

set_max_delay -from [get_clocks pcie_clk_125mhz] -to [get_clocks aurora_119_init_clk_i] -datapath_only 8.0
set_max_delay -from [get_clocks aurora_119_init_clk_i] -to [get_clocks pcie_clk_125mhz] -datapath_only 8.0

## CDC from pcie 125Mhz clk to aurora user clk
# 117
set_max_delay -from [get_clocks pcie_clk_125mhz] -to [get_clocks TS_117_user_clk_i_all] -datapath_only 8.0
set_max_delay -from [get_clocks TS_117_user_clk_i_all] -to [get_clocks pcie_clk_125mhz] -datapath_only 8.0

# 119
set_max_delay -from [get_clocks pcie_clk_125mhz] -to [get_clocks TS_119_user_clk_i_all] -datapath_only 8.0
set_max_delay -from [get_clocks TS_119_user_clk_i_all] -to [get_clocks pcie_clk_125mhz] -datapath_only 8.0


######################################## Quad 119
################ 24
set_false_path -to [get_pins -hier *aurora_64b66b_X1Y24_cdc_to*/D]
set_property LOC GTXE2_CHANNEL_X1Y24 [get_cells  *auroraQuad_1/auroraExtImport/aurora_64b66b_block_i/aurora_64b66b_X1Y24_i/inst/aurora_64b66b_X1Y24_wrapper_i/aurora_64b66b_X1Y24_multi_gt_i/aurora_64b66b_X1Y24_gtx_inst/gtxe2_i]


set_property LOC E2 [get_ports { aurora_119_0_TXP }]
set_property LOC E1 [get_ports { aurora_119_0_TXN }]
set_property LOC D8 [get_ports { aurora_119_0_rxp_i }]
set_property LOC D7 [get_ports { aurora_119_0_rxn_i }]
	
################# 25
set_false_path -to [get_pins -hier *aurora_64b66b_X1Y25_cdc_to*/D]
set_property LOC GTXE2_CHANNEL_X1Y25 [get_cells  *auroraQuad_1/auroraExtImport/aurora_64b66b_block_i/aurora_64b66b_X1Y25_i/inst/aurora_64b66b_X1Y25_wrapper_i/aurora_64b66b_X1Y25_multi_gt_i/aurora_64b66b_X1Y25_gtx_inst/gtxe2_i]


set_property LOC D4 [get_ports { aurora_119_1_TXP }]
set_property LOC D3 [get_ports { aurora_119_1_TXN }]
set_property LOC C6 [get_ports { aurora_119_1_rxp_i }]
set_property LOC C5 [get_ports { aurora_119_1_rxn_i }]

################# 26
set_false_path -to [get_pins -hier *aurora_64b66b_X1Y26_cdc_to*/D]
set_property LOC GTXE2_CHANNEL_X1Y26 [get_cells  *auroraQuad_1/auroraExtImport/aurora_64b66b_block_i/aurora_64b66b_X1Y26_i/inst/aurora_64b66b_X1Y26_wrapper_i/aurora_64b66b_X1Y26_multi_gt_i/aurora_64b66b_X1Y26_gtx_inst/gtxe2_i]


set_property LOC C2 [get_ports { aurora_119_2_TXP }]
set_property LOC C1 [get_ports { aurora_119_2_TXN }]
set_property LOC B8 [get_ports { aurora_119_2_rxp_i }]
set_property LOC B7 [get_ports { aurora_119_2_rxn_i }]

################# 27
set_false_path -to [get_pins -hier *aurora_64b66b_X1Y27_cdc_to*/D]
set_property LOC GTXE2_CHANNEL_X1Y27 [get_cells  *auroraQuad_1/auroraExtImport/aurora_64b66b_block_i/aurora_64b66b_X1Y27_i/inst/aurora_64b66b_X1Y27_wrapper_i/aurora_64b66b_X1Y27_multi_gt_i/aurora_64b66b_X1Y27_gtx_inst/gtxe2_i]


set_property LOC B4 [get_ports { aurora_119_3_TXP }]
set_property LOC B3 [get_ports { aurora_119_3_TXN }]
set_property LOC A6 [get_ports { aurora_119_3_rxp_i }]
set_property LOC A5 [get_ports { aurora_119_3_rxn_i }]


######################################## Quad 117
set_false_path -to [get_pins -hier *aurora_64b66b_X1Y16_cdc_to*/D]
set_property LOC GTXE2_CHANNEL_X1Y16 [get_cells  *auroraQuad_0/auroraExtImport/aurora_64b66b_block_i/aurora_64b66b_X1Y16_i/inst/aurora_64b66b_X1Y16_wrapper_i/aurora_64b66b_X1Y16_multi_gt_i/aurora_64b66b_X1Y16_gtx_inst/gtxe2_i]


set_property LOC N2 [get_ports { aurora_117_0_TXP }]
set_property LOC N1 [get_ports { aurora_117_0_TXN }]
set_property LOC P8 [get_ports { aurora_117_0_rxp_i }]
set_property LOC P7 [get_ports { aurora_117_0_rxn_i }]
	
################# 17
set_false_path -to [get_pins -hier *aurora_64b66b_X1Y17_cdc_to*/D]
set_property LOC GTXE2_CHANNEL_X1Y17 [get_cells  *auroraQuad_0/auroraExtImport/aurora_64b66b_block_i/aurora_64b66b_X1Y17_i/inst/aurora_64b66b_X1Y17_wrapper_i/aurora_64b66b_X1Y17_multi_gt_i/aurora_64b66b_X1Y17_gtx_inst/gtxe2_i]


set_property LOC M4 [get_ports { aurora_117_1_TXP }]
set_property LOC M3 [get_ports { aurora_117_1_TXN }]
set_property LOC N6 [get_ports { aurora_117_1_rxp_i }]
set_property LOC N5 [get_ports { aurora_117_1_rxn_i }]

################# 18
set_false_path -to [get_pins -hier *aurora_64b66b_X1Y18_cdc_to*/D]
set_property LOC GTXE2_CHANNEL_X1Y18 [get_cells  *auroraQuad_0/auroraExtImport/aurora_64b66b_block_i/aurora_64b66b_X1Y18_i/inst/aurora_64b66b_X1Y18_wrapper_i/aurora_64b66b_X1Y18_multi_gt_i/aurora_64b66b_X1Y18_gtx_inst/gtxe2_i]


set_property LOC L2 [get_ports { aurora_117_2_TXP }]
set_property LOC L1 [get_ports { aurora_117_2_TXN }]
set_property LOC L6 [get_ports { aurora_117_2_rxp_i }]
set_property LOC L5 [get_ports { aurora_117_2_rxn_i }]

################# 19
set_false_path -to [get_pins -hier *aurora_64b66b_X1Y19_cdc_to*/D]
set_property LOC GTXE2_CHANNEL_X1Y19 [get_cells  *auroraQuad_0/auroraExtImport/aurora_64b66b_block_i/aurora_64b66b_X1Y19_i/inst/aurora_64b66b_X1Y19_wrapper_i/aurora_64b66b_X1Y19_multi_gt_i/aurora_64b66b_X1Y19_gtx_inst/gtxe2_i]


set_property LOC K4 [get_ports { aurora_117_3_TXP }]
set_property LOC K3 [get_ports { aurora_117_3_TXN }]
set_property LOC J6 [get_ports { aurora_117_3_rxp_i }]
set_property LOC J5 [get_ports { aurora_117_3_rxn_i }]
