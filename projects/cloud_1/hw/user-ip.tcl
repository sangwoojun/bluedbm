set ddr3dir ../../../../bluespecpcie/dram/vc707/
set flashdir ../../../../flash/
set auroraextdir ../../../../auroraExt/

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

############# AuroraExt Stuff
read_ip $auroraextdir/core/aurora_64b66b_X1Y24/aurora_64b66b_X1Y24.xci
read_ip $auroraextdir/core/aurora_64b66b_X1Y25/aurora_64b66b_X1Y25.xci
read_ip $auroraextdir/core/aurora_64b66b_X1Y26/aurora_64b66b_X1Y26.xci
read_ip $auroraextdir/core/aurora_64b66b_X1Y27/aurora_64b66b_X1Y27.xci
read_ip $auroraextdir/core/aurora_64b66b_X1Y16/aurora_64b66b_X1Y16.xci
read_ip $auroraextdir/core/aurora_64b66b_X1Y17/aurora_64b66b_X1Y17.xci
read_ip $auroraextdir/core/aurora_64b66b_X1Y18/aurora_64b66b_X1Y18.xci
read_ip $auroraextdir/core/aurora_64b66b_X1Y19/aurora_64b66b_X1Y19.xci
read_verilog [ glob $auroraextdir/xilinx/*.v ]
read_xdc $auroraextdir/xilinx/aurora_64b66b_exdes.xdc
############# end AuroraExt Stuff
