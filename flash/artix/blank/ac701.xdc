## Sysclk in different location in new board
# b0
#set_property LOC E5 [get_ports { CLK_sys_clk_p }]
#set_property LOC D5 [get_ports { CLK_sys_clk_n }]

# b1
set_property LOC AA4 [get_ports { CLK_sys_clk_p }]
set_property LOC AB4 [get_ports { CLK_sys_clk_n }]
# b2
#set_property LOC C19 [get_ports { CLK_sys_clk_p }]
#set_property LOC D19 [get_ports { CLK_sys_clk_n }]
# b3
#set_property LOC U21 [get_ports { CLK_sys_clk_p }]
#set_property LOC V21 [get_ports { CLK_sys_clk_n }]

#set_property IOSTANDARD LCMOS18 [get_ports { CLK_sys_clk_* }]
set_property IOSTANDARD LVDS_25 [get_ports { CLK_sys_clk_* }]

#set_property LOC U4 [get_ports { RST_N_cpu_reset }]
#set_property IOSTANDARD LVCMOS25 [get_ports { RST_N_cpu_reset }]
#set_property PULLUP     true        [get_ports { RST_N_cpu_reset }]



### GTP Stuff

## Clock mux U4 doesn't exist on new board...
# set_property LOC B26 [get_ports { sfp_mgt_clk_sel[0] }]
# set_property LOC C24 [get_ports { sfp_mgt_clk_sel[1] }]
# set_property IOSTANDARD LVCMOS25 [get_ports { sfp_mgt_clk_sel[*] }]
# set_property LOC A24 [get_ports { pcie_mgt_clk_sel[0] }]
# set_property LOC C26 [get_ports { pcie_mgt_clk_sel[1] }]
# set_property IOSTANDARD LVCMOS25 [get_ports { pcie_mgt_clk_sel[*] }]

### I2C Stuff

# set_property LOC K25 [get_ports { i2c_pins_sda }]
# set_property LOC N18 [get_ports { i2c_pins_scl }]
# set_property IOSTANDARD LVCMOS33 [get_ports { i2c_pins_* }]


### LEDs

# set_property LOC M26 [get_ports {leds[0]}]
# set_property LOC T24 [get_ports {leds[1]}]
# set_property LOC T25 [get_ports {leds[2]}]
# set_property LOC R26 [get_ports {leds[3]}]
# 
# set_property IOSTANDARD LVCMOS33 [get_ports {leds[0]}]
# set_property IOSTANDARD LVCMOS33 [get_ports {leds[1]}]
# set_property IOSTANDARD LVCMOS33 [get_ports {leds[2]}]
# set_property IOSTANDARD LVCMOS33 [get_ports {leds[3]}]
# 
# set_property SLEW SLOW [get_ports leds]
# set_property DRIVE 12 [get_ports leds]
# set_property IOSTANDARD LVCMOS33    [get_ports { leds[*] }]

set_property LOC F5 [get_ports {leds[0]}]
set_property LOC G5 [get_ports {leds[1]}]
set_property LOC F4 [get_ports {leds[2]}]
set_property LOC G4 [get_ports {leds[3]}]
set_property IOSTANDARD LVCMOS18    [get_ports { leds[*] }]
