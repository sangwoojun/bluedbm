set ddr3dir ../../../../../../../bluespecpcie/dram/vc707/
set fpcaldir ../../../../../../../bluelib/src/coregen/vc707

############# DDR3 Stuff
read_ip $ddr3dir/core/ddr3_0/ddr3_0.xci
read_verilog [ glob $ddr3dir/*.v ]
read_xdc $ddr3dir/dram.xdc
############# end Flash Stuff

############# Floating Point 32-bit Stuff
read_ip $fpcaldir/fp_add32/fp_add32.xci
read_ip $fpcaldir/fp_sub32/fp_sub32.xci
read_ip $fpcaldir/fp_mult32/fp_mult32.xci
read_ip $fpcaldir/fp_div32/fp_div32.xci
read_ip $fpcaldir/fp_sqrt32/fp_sqrt32.xci
############# end Floating Point 32-bit stuff
