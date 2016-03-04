set coredir "./"
set corename "aurora_8b10b_fmc1"

file mkdir $coredir
if [file exists ./$coredir/$corename] {
	file delete -force ./$coredir/$corename
}

create_project -name local_synthesized_ip -in_memory -part xc7vx485tffg1761-2
set_property board_part xilinx.com:vc707:part0:1.0 [current_project]
create_ip -name aurora_8b10b -version 11.* -vendor xilinx.com -library ip -module_name $corename -dir ./$coredir
set_property -dict [list CONFIG.C_AURORA_LANES {4} CONFIG.C_LANE_WIDTH {4} CONFIG.C_LINE_RATE {4.4} CONFIG.C_REFCLK_FREQUENCY {275.000} CONFIG.Interface_Mode {Streaming} CONFIG.C_GT_LOC_24 {4} CONFIG.C_GT_LOC_23 {3} CONFIG.C_GT_LOC_22 {2} CONFIG.C_GT_LOC_21 {1} CONFIG.C_GT_LOC_1 {X}] [get_ips $corename]

generate_target {instantiation_template} [get_files ./$coredir/$corename/$corename.xci]
generate_target all [get_files  ./$coredir/$corename/$corename.xci]
create_ip_run [get_files -of_objects [get_fileset sources_1] ./$coredir/$corename/$corename.xci]
generate_target {Synthesis} [get_files  ./$coredir/$corename/$corename.xci]
read_ip ./$coredir/$corename/$corename.xci
synth_ip [get_ips $corename]

#connectal_synth_ip aurora_8b10b 10.2 aurora_8b10b_fmc1 [list CONFIG.C_AURORA_LANES {4} CONFIG.C_LANE_WIDTH {4} CONFIG.C_LINE_RATE {4.4} CONFIG.C_REFCLK_FREQUENCY {275.000} CONFIG.Interface_Mode {Streaming} CONFIG.C_GT_LOC_24 {4} CONFIG.C_GT_LOC_23 {3} CONFIG.C_GT_LOC_22 {2} CONFIG.C_GT_LOC_21 {1} CONFIG.C_GT_LOC_1 {X}]
