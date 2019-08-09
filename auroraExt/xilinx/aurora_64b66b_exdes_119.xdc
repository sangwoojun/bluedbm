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
 ##  aurora_64b66b_X1Y24_exdes
 ##
 ##  Description: This is the example design constraints file for a 1 lane Aurora
 ##               core.
 ##               This is example design xdc.
 ##               Note: User need to set proper IO standards for the LOC's mentioned below.
 ###################################################################################################

################################################################################
 
 	# Shared across cores
	set_property LOC A10 [get_ports aurora_quad119_gtx_clk_p_v]
	set_property LOC A9 [get_ports aurora_quad119_gtx_clk_n_v]

	#create_clock -name TS_aurora119_init_clk_i -period 8.0 [get_pins host_ep7/CLK_epClock125]

	set_false_path -from [get_cells -hier -filter {NAME =~ *auroraExt119/rst50/*}]
	#set_false_path -to [get_pins -hier -filter {NAME =~ *auroraExt119/auroraExt_*_outPacketQ/*/CLR}]
	#set_false_path -to [get_pins -hier -filter {NAME =~ *auroraExt119/auroraExt_*_outPacketQ/*/PRE}]
	set_false_path -to [get_pins -hier -filter {NAME =~ *auroraExt119/rst50/*/CLR}]

	#set_false_path -to [get_pins -hier -filter {NAME =~ */auroraExtImport/aurora_64b66b_block_i/gen_code_reset_logic[?].support_reset_logic_i/reset_debounce_r_reg[0]/S}]

	#"Board constraint" 50MHz clk
	#create_clock -name aurora_init_clk_i -period 20.0 [get_pins *auroraExtClockDiv5_slowbuf/O]
	create_clock -name aurora_init_clk_i -period 20.0 [get_pins *auroraExtClockDiv5/CLK_slowClock]

	#Ref clk
	create_clock -name GTXQ0_left_119_i -period 1.600	 [get_pins *auroraExt119/auroraExt_gtx_clk/O]
	
	#Aurora clks
	create_clock -name TS_user_clk_i_all -period 6.400	 [get_pins -hier -filter {NAME =~ *aurora_64b66b_block_i/clock_module_i/user_clk_net_i/O}]
	create_clock -name TS_sync_clk_i_all -period 3.200	 [get_pins -hier -filter {NAME =~ *aurora_64b66b_block_i/clock_module_i/sync_clock_net_i/O}]
	
	#CDC from 50MHz "board clk" to aurora user clk
	set_false_path -from [get_clocks aurora_init_clk_i] -to [get_clocks TS_user_clk_i_all]
	set_false_path -from [get_clocks TS_user_clk_i_all] -to [get_clocks aurora_init_clk_i]
	set_false_path -from [get_clocks aurora_init_clk_i] -to [get_clocks TS_sync_clk_i_all]
	set_false_path -from [get_clocks TS_sync_clk_i_all] -to [get_clocks aurora_init_clk_i]

set_max_delay -from [get_clocks clk_125mhz] -to [get_clocks aurora_init_clk_i] -datapath_only 8.0
set_max_delay -from [get_clocks aurora_init_clk_i] -to [get_clocks clk_125mhz] -datapath_only 8.0




	#CDC from pcie 125MHz clk to aurora user clk. Should be read after vc707.xdc
###########set_max_delay -from [get_clocks -of_objects [get_pins host_ep7/clkgen_pll/CLKOUT0]] -to [get_clocks TS_user_clk_i_all] -datapath_only 8.0
###########set_max_delay -from [get_clocks TS_user_clk_i_all] -to [get_clocks -of_objects [get_pins host_ep7/clkgen_pll/CLKOUT0]] -datapath_only 8.0
set_max_delay -from [get_clocks clk_125mhz] -to [get_clocks TS_user_clk_i_all] -datapath_only 8.0
set_max_delay -from [get_clocks TS_user_clk_i_all] -to [get_clocks clk_125mhz] -datapath_only 8.0

	#set_max_delay -from [get_clocks TS_aurora119_init_clk_i] -to [get_clocks TS_user_clk_i_all]
	#set_max_delay -from [get_clocks TS_user_clk_i_all] -to [get_clocks TS_aurora119_init_clk_i]
	#set_max_delay -from [get_clocks aurora_init_clk_i] -to [get_clocks TS_aurora119_init_clk_i]
	#set_max_delay -from [get_clocks TS_aurora119_init_clk_i] -to [get_clocks aurora_init_clk_i]

	
	#set_false_path -from [get_clocks TS_aurora119_init_clk_i] -to [get_clocks TS_user_clk_i_all]
	#set_false_path -from [get_clocks TS_user_clk_i_all] -to [get_clocks TS_aurora119_init_clk_i]


	#set_false_path -from [get_clocks aurora_init_clk_i] -to [get_clocks TS_aurora119_init_clk_i]
	#set_false_path -from [get_clocks TS_aurora119_init_clk_i] -to [get_clocks aurora_init_clk_i]

	
	#set_false_path -from [get_clocks clkgen_pll_CLKOUT0_1] -to [get_clocks TS_aurora119_init_clk_i]
	#set_false_path -from [get_clocks clkgen_pll_CLKOUT0_1] -to [get_clocks aurora_init_clk_i]



#set_property LOC MMCME2_ADV_X1Y6 [get_cells -hier -filter { NAME =~ *auroraExt119/auroraExtImport/aurora_64b66b_block_i/clock_module_i/mmcm_adv_inst }]

#startgroup
#create_pblock pblock_auroraExtImport119
#resize_pblock pblock_auroraExtImport119 -add {SLICE_X136Y300:SLICE_X221Y349 DSP48_X12Y120:DSP48_X19Y139 RAMB18_X9Y120:RAMB18_X14Y139 RAMB36_X9Y60:RAMB36_X14Y69}
#add_cells_to_pblock pblock_auroraExtImport119 [get_cells -hier -filter { NAME =~ *auroraExt119/auroraExtImport/*}]
#endgroup

######################################## Quad 119
################ 24
	# User Clock Contraint: the value is selected based on the line rate of the module
	#create_clock -name TS_user_clk_i_24 -period 6.400	 [get_pins portalTop_hwmain_auroraExt119/auroraExtImport/aurora_64b66b_block_i/clock_module_i/user_clk_net_i/O]
	#create_clock -name TS_sync_clk_i_24 -period 3.200	 [get_pins portalTop_hwmain_auroraExt119/auroraExtImport/aurora_64b66b_block_i/clock_module_i/sync_clock_net_i/O]

	# create_clock -name TS_user_clk_i_24 -period 6.400	 [get_pins portalTop_hwmain_auroraExt119/auroraExtImport/aurora_64b66b_block_i/gen_code_clock_module[0].clock_module_i/user_clk_net_i/O]

	# SYNC Clock Constraint
	# create_clock -name TS_sync_clk_i_24 -period 3.200	 [get_pins portalTop_hwmain_auroraExt119/auroraExtImport/aurora_64b66b_block_i/gen_code_clock_module[0].clock_module_i/sync_clock_net_i/O]

	set_false_path -to [get_pins -hier *aurora_64b66b_X1Y24_cdc_to*/D]
   set_property LOC GTXE2_CHANNEL_X1Y24 [get_cells -hierarchical -regexp {.*auroraExt119/auroraExtImport/aurora_64b66b_block_i/aurora_64b66b_X1Y24_i/inst/aurora_64b66b_X1Y24_wrapper_i/aurora_64b66b_X1Y24_multi_gt_i/aurora_64b66b_X1Y24_gtx_inst/gtxe2_i}]


 set_property LOC E2 [get_ports { aurora_ext_0_TXP }]
 set_property LOC E1 [get_ports { aurora_ext_0_TXN }]
 set_property LOC D8 [get_ports { aurora_ext_0_rxp_i }]
 set_property LOC D7 [get_ports { aurora_ext_0_rxn_i }]
	
################# 25
	# create_clock -name TS_user_clk_i_25 -period 6.400	 [get_pins portalTop_hwmain_auroraExt119/auroraExtImport/aurora_64b66b_block_i/gen_code_clock_module[1].clock_module_i/user_clk_net_i/O]

	# SYNC Clock Constraint
	# create_clock -name TS_sync_clk_i_25 -period 3.200	 [get_pins portalTop_hwmain_auroraExt119/auroraExtImport/aurora_64b66b_block_i/gen_code_clock_module[1].clock_module_i/sync_clock_net_i/O]

	set_false_path -to [get_pins -hier *aurora_64b66b_X1Y25_cdc_to*/D]
   set_property LOC GTXE2_CHANNEL_X1Y25 [get_cells -hierarchical -regexp {.*auroraExt119/auroraExtImport/aurora_64b66b_block_i/aurora_64b66b_X1Y25_i/inst/aurora_64b66b_X1Y25_wrapper_i/aurora_64b66b_X1Y25_multi_gt_i/aurora_64b66b_X1Y25_gtx_inst/gtxe2_i}]

 set_property LOC D4 [get_ports { aurora_ext_1_TXP }]
 set_property LOC D3 [get_ports { aurora_ext_1_TXN }]
 set_property LOC C6 [get_ports { aurora_ext_1_rxp_i }]
 set_property LOC C5 [get_ports { aurora_ext_1_rxn_i }]
################# 26
	# create_clock -name TS_user_clk_i_26 -period 6.400	 [get_pins portalTop_hwmain_auroraExt119/auroraExtImport/aurora_64b66b_block_i/gen_code_clock_module[2].clock_module_i/user_clk_net_i/O]

	# SYNC Clock Constraint
	# create_clock -name TS_sync_clk_i_26 -period 3.200	 [get_pins portalTop_hwmain_auroraExt119/auroraExtImport/aurora_64b66b_block_i/gen_code_clock_module[2].clock_module_i/sync_clock_net_i/O]

	set_false_path -to [get_pins -hier *aurora_64b66b_X1Y26_cdc_to*/D]
   set_property LOC GTXE2_CHANNEL_X1Y26 [get_cells -hierarchical -regexp {.*auroraExt119/auroraExtImport/aurora_64b66b_block_i/aurora_64b66b_X1Y26_i/inst/aurora_64b66b_X1Y26_wrapper_i/aurora_64b66b_X1Y26_multi_gt_i/aurora_64b66b_X1Y26_gtx_inst/gtxe2_i}]

 set_property LOC C2 [get_ports { aurora_ext_2_TXP }]
 set_property LOC C1 [get_ports { aurora_ext_2_TXN }]
 set_property LOC B8 [get_ports { aurora_ext_2_rxp_i }]
 set_property LOC B7 [get_ports { aurora_ext_2_rxn_i }]

################# 27
	# create_clock -name TS_user_clk_i_27 -period 6.400	 [get_pins portalTop_hwmain_auroraExt119/auroraExtImport/aurora_64b66b_block_i/gen_code_clock_module[3].clock_module_i/user_clk_net_i/O]

	# SYNC Clock Constraint
	# create_clock -name TS_sync_clk_i_27 -period 3.200	 [get_pins portalTop_hwmain_auroraExt119/auroraExtImport/aurora_64b66b_block_i/gen_code_clock_module[3].clock_module_i/sync_clock_net_i/O]

	set_false_path -to [get_pins -hier *aurora_64b66b_X1Y27_cdc_to*/D]
   set_property LOC GTXE2_CHANNEL_X1Y27 [get_cells -hierarchical -regexp {.*auroraExt119/auroraExtImport/aurora_64b66b_block_i/aurora_64b66b_X1Y27_i/inst/aurora_64b66b_X1Y27_wrapper_i/aurora_64b66b_X1Y27_multi_gt_i/aurora_64b66b_X1Y27_gtx_inst/gtxe2_i}]


 set_property LOC B4 [get_ports { aurora_ext_3_TXP }]
 set_property LOC B3 [get_ports { aurora_ext_3_TXN }]
 set_property LOC A6 [get_ports { aurora_ext_3_rxp_i }]
 set_property LOC A5 [get_ports { aurora_ext_3_rxn_i }]

###### CDC in RESET_LOGIC from INIT_CLK to USER_CLK ##############
set_max_delay -from [get_clocks auroraI_init_clk_i] -to [get_clocks auroraI_user_clk_i] -datapath_only 9.091
set_max_delay -from [get_clocks aurora_init_clk_i] -to [get_clocks auroraI_user_clk_i] -datapath_only 9.091
