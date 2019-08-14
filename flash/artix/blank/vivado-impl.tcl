
# NOTE: typical usage would be "vivado -mode tcl -source create_mkPcieTop_batch.tcl" 
#
# STEP#0: define output directory area.
#
set outputDir ./hw
file mkdir $outputDir
#
# STEP#1: setup design sources and constraints
#
#source board.tcl

set partname {xc7a200tfbg676-2}

read_verilog [ glob {verilog/top/*.v} ]

set_property part $partname [current_project]

read_verilog [ glob {../*.v} ]
read_xdc {../ac701.xdc}


# STEP#2: run synthesis, report utilization and timing estimates, write checkpoint design
#
synth_design -name mkControllerTop -top mkControllerTop -part $partname -flatten rebuilt

write_checkpoint -force $outputDir/mkcontrollertop_post_synth
report_timing_summary -verbose  -file $outputDir/mkcontrollertop_post_synth_timing_summary.rpt
report_timing -sort_by group -max_paths 100 -path_type summary -file $outputDir/mkcontrollertop_post_synth_timing.rpt
report_utilization -verbose -file $outputDir/mkcontrollertop_post_synth_utilization.txt
report_datasheet -file $outputDir/mkcontrollertop_post_synth_datasheet.txt
write_verilog -force $outputDir/mkcontrollertop_netlist.v
write_debug_probes -force probes.ltx
#report_power -file $outputDir/mkcontrollertop_post_synth_power.rpt

#
# STEP#3: run placement and logic optimization, report utilization and timing estimates, write checkpoint design
#


opt_design
# power_opt_design
place_design
phys_opt_design
write_checkpoint -force $outputDir/mkcontrollertop_post_place
report_timing_summary -file $outputDir/mkcontrollertop_post_place_timing_summary.rpt
#
# STEP#4: run router, report actual utilization and timing, write checkpoint design, run drc, write verilog and xdc out
#
route_design
write_checkpoint -force $outputDir/mkcontrollertop_post_route
report_timing_summary -file $outputDir/mkcontrollertop_post_route_timing_summary.rpt
report_timing -sort_by group -max_paths 100 -path_type summary -file $outputDir/mkcontrollertop_post_route_timing.rpt
report_clock_utilization -file $outputDir/mkcontrollertop_clock_util.rpt
report_utilization -file $outputDir/mkcontrollertop_post_route_util.rpt
report_datasheet -file $outputDir/mkcontrollertop_post_route_datasheet.rpt
#report_power -file $outputDir/mkcontrollertop_post_route_power.rpt
#report_drc -file $outputDir/mkcontrollertop_post_imp_drc.rpt
#write_verilog -force $outputDir/mkcontrollertop_impl_netlist.v
write_xdc -no_fixed_only -force $outputDir/mkcontrollertop_impl.xdc
#
# STEP#5: generate a bitstream
# 
write_bitstream -force -bin_file $outputDir/mkControllerTop.bit
