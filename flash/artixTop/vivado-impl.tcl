
# NOTE: typical usage would be "vivado -mode tcl -source create_mkPcieTop_batch.tcl" 
#
# STEP#0: define output directory area.
#a
#puts [lindex $argv 2]

set i 0
set xdclist {}
if { $::argc < 2 } {
	puts "ERROR: Num arguments incorrect"
	exit 1
} else {
	foreach arg $argv {
		puts "argument: $arg"
		if {$i == 0} {
			set topModule $arg
		} else {
			lappend xdclist $arg
		}
		incr i	
	}
}


puts "Implementing top module: $topModule"
puts "xdc files:"

foreach xdc $xdclist {
	puts $xdc
}

#foreach arg $argv{
#set topModule [lindex $argv 0]
#puts "Implementing top module: $topModule"




set outputDir ./hw
file mkdir $outputDir
#
# STEP#1: setup design sources and constraints
#
#source board.tcl

set partname {xc7a200tfbg676-2}

read_verilog [ glob {verilog/*.v} ]
read_verilog [ glob {../../src/common/verilog/*.v} ]
read_verilog [ glob {../../src/hw_artix/verilog/*.v} ]
read_verilog [ glob {../../src/model_artix/verilog/*.v} ]

set_property part $partname [current_project]

read_ip ../../xilinx/vio_7series/vio_7series.xci
generate_target {Synthesis} [get_files ../../xilinx/vio_7series/vio_7series.xci]

read_ip ../../xilinx/ila_7series/ila_7series.xci
generate_target {Synthesis} [get_files ../../xilinx/ila_7series/ila_7series.xci]

read_ip ../../xilinx/vio_0/vio_0.xci
generate_target {Synthesis} [get_files ../../xilinx/vio_0/vio_0.xci]

read_ip ../../xilinx/ila_0/ila_0.xci
generate_target {Synthesis} [get_files ../../xilinx/ila_0/ila_0.xci]

############# Aurora stuff (6.6)
#read_verilog [ glob {../../xilinx/aurora_8b10b_X0Y4_66/*.v} ]
#generate_target {Synthesis} [get_files ../../xilinx/aurora_8b10b_X0Y4_66/aurora_8b10b_X0Y4/aurora_8b10b_X0Y4.xci]
#read_ip ../../xilinx/aurora_8b10b_X0Y4_66/aurora_8b10b_X0Y4/aurora_8b10b_X0Y4.xci
#read_xdc {../../xilinx/aurora_8b10b_X0Y4_66/aurora_8b10b_X0Y4_exdes.xdc}
############## end Aurora stuff
############# Aurora stuff
read_verilog [ glob {../../xilinx/aurora_8b10b/*.v} ]
read_ip ../../xilinx/aurora_8b10b/aurora_8b10b/aurora_8b10b.xci
generate_target {Synthesis} [get_files ../../xilinx/aurora_8b10b/aurora_8b10b/aurora_8b10b.xci]
############## end Aurora stuff

############## Raw gtp stuff
#read_verilog [ glob {../../xilinx/gtp_rawcc/*.v} ]
#generate_target {Synthesis} [get_files ../../xilinx/gtp_rawcc/gtp_raw0/gtp_raw0.xci]
#read_ip ../../xilinx/gtp_rawcc/gtp_raw0/gtp_raw0.xci
#read_xdc {../../xilinx/gtp_rawcc/gtp_raw0_exdes.xdc}
############## end Raw gtp stuff

############# Aurora stuff
# read_verilog [ glob {../../xilinx/aurora_TX/*.v} ]
# generate_target {Synthesis} [get_files ../../xilinx/aurora_TX/aurora_TX/aurora_TX.xci]
# read_ip ../../xilinx/aurora_TX/aurora_TX/aurora_TX.xci
# read_xdc {../../xilinx/aurora_TX/aurora_TX_exdes.xdc}
############## end Aurora stuff

#NOTE: order of XDC is important!
#get xdc files from arg
foreach xdc $xdclist {
	puts "adding xdc file: $xdc"
	read_xdc $xdc
}


#read_xdc {../../xilinx/constraints/.xdc}
#read_xdc {../../xilinx/aurora_8b10b/aurora_8b10b_exdes.xdc}


# STEP#2: run synthesis, report utilization and timing estimates, write checkpoint design
#
synth_design -name $topModule -top $topModule -part $partname -flatten rebuilt

write_checkpoint -force $outputDir/mkProjectTop_post_synth
report_timing_summary -verbose  -file $outputDir/mkProjectTop_post_synth_timing_summary.rpt
report_timing -sort_by group -max_paths 100 -path_type summary -file $outputDir/mkProjectTop_post_synth_timing.rpt
report_utilization -verbose -file $outputDir/mkProjectTop_post_synth_utilization.txt
report_datasheet -file $outputDir/mkProjectTop_post_synth_datasheet.txt
write_verilog -force $outputDir/mkProjectTop_netlist.v
write_debug_probes -force probes.ltx
#report_power -file $outputDir/mkProjectTop_post_synth_power.rpt

#
# STEP#3: run placement and logic optimization, report utilization and timing estimates, write checkpoint design
#


opt_design
# power_opt_design
place_design
phys_opt_design
write_checkpoint -force $outputDir/mkProjectTop_post_place
report_timing_summary -file $outputDir/mkProjectTop_post_place_timing_summary.rpt
#
# STEP#4: run router, report actual utilization and timing, write checkpoint design, run drc, write verilog and xdc out
#
route_design
write_checkpoint -force $outputDir/mkProjectTop_post_route
report_timing_summary -file $outputDir/mkProjectTop_post_route_timing_summary.rpt
report_timing -sort_by group -max_paths 100 -path_type summary -file $outputDir/mkProjectTop_post_route_timing.rpt
report_clock_utilization -file $outputDir/mkProjectTop_clock_util.rpt
report_utilization -file $outputDir/mkProjectTop_post_route_util.rpt
report_datasheet -file $outputDir/mkProjectTop_post_route_datasheet.rpt
#report_power -file $outputDir/mkProjectTop_post_route_power.rpt
#report_drc -file $outputDir/mkProjectTop_post_imp_drc.rpt
#write_verilog -force $outputDir/mkProjectTop_impl_netlist.v
write_xdc -no_fixed_only -force $outputDir/mkProjectTop_impl.xdc
#
# STEP#5: generate a bitstream
# 
write_bitstream -force -bin_file $outputDir/mkProjectTop.bit
