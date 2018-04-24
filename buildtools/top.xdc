create_clock -name clk_250mhz -period 4 [get_pins clk_gen_pll/CLKOUT0]
create_clock -name clk_125mhz -period 8 [get_pins clk_gen_pll/CLKOUT1]
create_clock -name clk_200mhz -period 5 [get_pins clk_gen_pll/CLKOUT2]

#set_clock_groups -asynchronous -group {clk_125mhz} -group {clk_200mhz}
#set_clock_groups -asynchronous -group {clk_250mhz} -group {clk_200mhz}
#set_clock_groups -asynchronous -group {clk_250mhz} -group {clk_125mhz}
