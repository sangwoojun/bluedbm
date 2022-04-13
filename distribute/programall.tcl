open_hw_manager
connect_hw_server
open_hw_target {localhost:3121/xilinx_tcf/Digilent/210203A7E2C3A} 

set vc707fpga1 [lindex [get_hw_devices] 2]

set file ./vc707/hw/mkProjectTop.bit
set_property PROGRAM.FILE $file $vc707fpga1
puts "fpga is $vc707fpga1, bit file size is [exec ls -sh $file], PROGRAM BEGIN"
program_hw_devices -verbose $vc707fpga1
refresh_hw_device $vc707fpga1
close_hw_target {localhost:3121/xilinx_tcf/Digilent/210203A7E2C3A} 

open_hw_target {localhost:3121/xilinx_tcf/Digilent/210203AE47E1A}

set vc707fpga2 [lindex [get_hw_devices] 1] 

set file ./vc707/hw/mkProjectTop.bit
set_property PROGRAM.FILE $file $vc707fpga2
puts "fpga is $vc707fpga2, bit file size is [exec ls -sh $file], PROGRAM BEGIN"
program_hw_devices -verbose $vc707fpga2
refresh_hw_device $vc707fpga2
