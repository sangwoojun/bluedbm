connect_hw_server
open_hw_target 
set artixfpga1 [lindex [get_hw_devices] 0] 
set artixfpga2 [lindex [get_hw_devices] 1] 
set vc707fpga [lindex [get_hw_devices] 2] 

set file ./build/hw/mkProjectTop.bit
set_property PROGRAM.FILE $file $vc707fpga
puts "fpga is $vc707fpga, bit file size is [exec ls -sh $file], PROGRAM BEGIN"
program_hw_devices $vc707fpga

set file ./mkTopArtix.bit
set_property PROGRAM.FILE $file $artixfpga1
puts "fpga is $artixfpga1, bit file size is [exec ls -sh $file], PROGRAM BEGIN"
program_hw_devices $artixfpga

set file ./mkTopArtix.bit
set_property PROGRAM.FILE $file $artixfpga2
puts "fpga is $artixfpga2, bit file size is [exec ls -sh $file], PROGRAM BEGIN"
program_hw_devices $artixfpga2
