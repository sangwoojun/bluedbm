BSCFLAGS = -show-schedule -aggressive-conditions --wait-for-license 

BSCFLAGS_SYNTH = -bdir ./build/obj -vdir ./build/verilog/top -simdir ./build/obj -info-dir ./build -fdir ./build
BSCFLAGS_BSIM = -bdir ./bsim/obj -vdir ./bsim/verilog/top -simdir ./bsim/obj -info-dir ./bsim -fdir ./bsim
BSVPATH =../../bluespecpcie/src/:../../src/hwlib/:../../flash/src/common/:../../flash/src/model_virtex/:../../flash/src/hw_virtex/:../../flash/aurora_8b10b_fmc1/:../../flash/xilinx/:../../ddr3_v2_0/

BSIM_CPPFILES =../../bluespecpcie/src/PcieBdpi.cpp \
	../../bluespecpcie/src/ShmFifo.cpp
DEBUGFLAGS = -D BSIM


## change txdiffctrl in auroraintra to 1100



all:
	mkdir -p build/obj
	mkdir -p build/verilog/top
	bsc  $(BSCFLAGS) $(BSCFLAGS_SYNTH) -remove-dollar -p +:$(BSVPATH) -verilog -u -g mkProjectTop Top.bsv
	cp vivado-impl.tcl ./build/impl.tcl
	cd build; cd verilog/top; ../../../verilogcopy.sh; cd ../../; vivado -mode batch -source impl.tcl
	tar czf c.tgz build/
	mv c.tgz build/

bsim: HwMain.bsv Top.bsv
	mkdir -p bsim
	mkdir -p bsim/obj
	mkdir -p bsim/verilog/top
	bsc $(BSCFLAGS) $(BSCFLAGS_BSIM) $(DEBUGFLAGS) -p +:$(BSVPATH) -sim -u -g mkProjectTop_bsim Top.bsv  
	bsc $(BSCFLAGS) $(BSCFLAGS_BSIM) $(DEBUGFLAGS) -sim -e mkProjectTop_bsim -o bsim/obj/bsim bsim/obj/*.ba $(BSIM_CPPFILES) 

clean:
	rm -rf build
	rm -rf bsim

.PHONY: all

core:
	mkdir -p ../../bluespecpcie/core
	cd ../../bluespecpcie/core/ ; vivado -mode batch -source core_gen_pcie.tcl -nolog -nojournal
	cd ../../flash/ ; vivado -mode batch -source synth-aurora-intra1.tcl -nolog -nojournal 
	cd ../../flash/ ; vivado -mode batch -source synth-aurora-intra2.tcl -nolog -nojournal 
	find ../../flash/ -name "aurora_8b10b_*transceiver_wrapper.v" -exec sed -i "s/_txdiffctrl_in[ \t]\+([4'b10]\+),/_txdiffctrl_in (4'b1011),/g" '{}' \;
core_ddr3:
	mkdir -p ../../ddr3_v2_0/core
	cd ../../ddr3_v2_0/ ; vivado -mode batch -source synth-ip.tcl -nolog -nojournal 
