.DEFAULT_GOAL := hw
.PHONY: hw

ROOT=$(realpath ../../../)
BUILDTOOLS=$(realpath $(ROOT)/buildtools)

include $(BUILDTOOLS)/Makefile.base

#BSC_DEFINES = -D USE_DRAM -D USE_FLASH
BSC_DEFINES = -D USE_DRAM

hw:
	mkdir -p build/obj
	mkdir -p build/verilog/top
	bsc  $(BSCFLAGS) $(BSCFLAGS_SYNTH) $(BSC_DEFINES) -remove-dollar -p +:$(BSVPATH) -verilog -u -g mkProjectTop $(BUILDTOOLS)/bsv/Top.bsv
	cp $(BUILDTOOLS)/vivado-impl.tcl ./build/impl.tcl
	cd build; cd verilog/top; $(BUILDTOOLS)/verilogcopy.sh; cd ../../; vivado -mode batch -source impl.tcl
	tar czf c.tgz build/
	mv c.tgz build/

bsim: HwMain.bsv $(BUILDTOOLS)/bsv/Top.bsv
	mkdir -p bsim
	mkdir -p bsim/obj
	mkdir -p bsim/verilog/top
	bsc $(BSCFLAGS) $(BSCFLAGS_BSIM) $(BSC_DEFINES) -p +:$(BSVPATH) -sim -u -g mkProjectTop_bsim $(BUILDTOOLS)/bsv/Top.bsv  
	bsc $(BSCFLAGS) $(BSCFLAGS_BSIM) $(BSC_DEFINES) -sim -e mkProjectTop_bsim -o bsim/obj/bsim bsim/obj/*.ba $(BSIM_CPPFILES) 

clean:
	rm -rf build
	rm -rf bsim

