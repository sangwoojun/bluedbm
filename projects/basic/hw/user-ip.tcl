set ddr3dir ../../../../bluespecpcie/dram/vc707/
set flashdir ../../../../flash/

############# DDR3 Stuff
read_ip $ddr3dir/core/ddr3_0/ddr3_0.xci
read_verilog [ glob $ddr3dir/*.v ]
read_xdc $ddr3dir/dram.xdc
############# end Flash Stuff

############# Flash Stuff
read_ip $flashdir/virtex/core/aurora_8b10b_fmc1/aurora_8b10b_fmc1.xci
read_ip $flashdir/virtex/core/aurora_8b10b_fmc2/aurora_8b10b_fmc2.xci
read_verilog [ glob $flashdir/virtex/src/*.v ]
read_xdc $flashdir/virtex/src/aurora_8b10b_exdes.xdc
############# end Flash Stuff
