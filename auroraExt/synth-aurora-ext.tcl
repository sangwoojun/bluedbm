proc genAurora {corename propertyList} {
	set coredir "./core"
	file mkdir $coredir
	if [file exists ./$coredir/$corename] {
		file delete -force ./$coredir/$corename
	}

	create_project -name local_synthesized_ip -in_memory -part xc7vx485tffg1761-2
	set_property board_part xilinx.com:vc707:part0:1.0 [current_project]
	create_ip -name aurora_64b66b -version 12.0 -vendor xilinx.com -library ip -module_name $corename -dir ./$coredir
	set_property -dict $propertyList [get_ips $corename]

	generate_target {instantiation_template} [get_files ./$coredir/$corename/$corename.xci]
	generate_target all [get_files  ./$coredir/$corename/$corename.xci]
	create_ip_run [get_files -of_objects [get_fileset sources_1] ./$coredir/$corename/$corename.xci]
	generate_target {Synthesis} [get_files  ./$coredir/$corename/$corename.xci]
	read_ip ./$coredir/$corename/$corename.xci
	synth_ip [get_ips $corename]
}

genAurora "aurora_64b66b_X1Y24" [list CONFIG.C_AURORA_LANES {1} CONFIG.C_LINE_RATE {10.0} CONFIG.C_REFCLK_FREQUENCY {625.000} CONFIG.interface_mode {Streaming} CONFIG.C_GT_LOC_25 {1} CONFIG.C_GT_LOC_1 {X} CONFIG.drp_mode {Native}]

genAurora "aurora_64b66b_X1Y25" [list CONFIG.C_AURORA_LANES {1} CONFIG.C_LINE_RATE {10.0} CONFIG.C_REFCLK_FREQUENCY {625.000} CONFIG.interface_mode {Streaming} CONFIG.C_GT_LOC_26 {1} CONFIG.C_GT_LOC_1 {X} CONFIG.drp_mode {Native}]

genAurora "aurora_64b66b_X1Y26" [list CONFIG.C_AURORA_LANES {1} CONFIG.C_LINE_RATE {10.0} CONFIG.C_REFCLK_FREQUENCY {625.000} CONFIG.interface_mode {Streaming} CONFIG.C_GT_LOC_27 {1} CONFIG.C_GT_LOC_1 {X} CONFIG.drp_mode {Native}]

genAurora "aurora_64b66b_X1Y27" [list CONFIG.C_AURORA_LANES {1} CONFIG.C_LINE_RATE {10.0} CONFIG.C_REFCLK_FREQUENCY {625.000} CONFIG.interface_mode {Streaming} CONFIG.C_GT_LOC_28 {1} CONFIG.C_GT_LOC_1 {X} CONFIG.drp_mode {Native}]

genAurora "aurora_64b66b_X1Y16" [list CONFIG.C_AURORA_LANES {1} CONFIG.C_LINE_RATE {10.0} CONFIG.C_REFCLK_FREQUENCY {625.000} CONFIG.interface_mode {Streaming} CONFIG.C_GT_LOC_17 {1} CONFIG.C_GT_LOC_1 {X} CONFIG.drp_mode {Native}]

genAurora "aurora_64b66b_X1Y17" [list CONFIG.C_AURORA_LANES {1} CONFIG.C_LINE_RATE {10.0} CONFIG.C_REFCLK_FREQUENCY {625.000} CONFIG.interface_mode {Streaming} CONFIG.C_GT_LOC_18 {1} CONFIG.C_GT_LOC_1 {X} CONFIG.drp_mode {Native}]

genAurora "aurora_64b66b_X1Y18" [list CONFIG.C_AURORA_LANES {1} CONFIG.C_LINE_RATE {10.0} CONFIG.C_REFCLK_FREQUENCY {625.000} CONFIG.interface_mode {Streaming} CONFIG.C_GT_LOC_19 {1} CONFIG.C_GT_LOC_1 {X} CONFIG.drp_mode {Native}]

genAurora "aurora_64b66b_X1Y19" [list CONFIG.C_AURORA_LANES {1} CONFIG.C_LINE_RATE {10.0} CONFIG.C_REFCLK_FREQUENCY {625.000} CONFIG.interface_mode {Streaming} CONFIG.C_GT_LOC_20 {1} CONFIG.C_GT_LOC_1 {X} CONFIG.drp_mode {Native}]


