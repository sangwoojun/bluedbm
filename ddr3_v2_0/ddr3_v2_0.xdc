#create_clock -name ddr3_refclk -period 5 [get_pins host_sys_clk_200mhz_buf/O] 
create_generated_clock -name ddr3_usrclk -source clk_gen_pll_CLKOUT2 -multiply_by 5 -divide_by 5 [get_pins *ddr3_ctrl/CLK]

set_clock_groups -asynchronous -group {clk_gen_pll_CLKOUT1} -group {ddr3_usrclk}
set_clock_groups -asynchronous -group {clk_gen_pll_CLKOUT1} -group {ddr3_refclk}
set_clock_groups -asynchronous -group {clk_gen_pll_CLKOUT1} -group {clk_pll_i}

set_false_path -from [get_pins -of_objects [get_cells -hier -filter {NAME =~ *ddr3_ctrl_user_reset_n/*}] -hier -filter {NAME=~ *C}]
set_false_path -from [get_pins -of_objects [get_cells -hier -filter {NAME =~ *ddr3_ctrl_user_reset_n/*}] -hier -filter {NAME=~ *C}]
