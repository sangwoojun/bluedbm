
#BSCFLAGS = -show-schedule -aggressive-conditions --wait-for-license -bdir $(DTOP)/obj -vdir $(DTOP)/verilog/top -simdir $(DTOP)/obj  -D TimeStamp=1402968878 
#BSCFLAGS = -show-schedule --wait-for-license -bdir ./build/obj -vdir ./build/verilog/top -simdir ./build/obj -info-dir ./build
BSCFLAGS = -show-schedule -aggressive-conditions --wait-for-license -bdir ./build/obj -vdir ./build/verilog/top -simdir ./build/obj -info-dir ./build
 
BSVPATH = ../xilinx/aurora_8b10b/:../../src/lib:

all:
	mkdir -p build/obj
	mkdir -p build/verilog/top
	bsc  $(BSCFLAGS) -remove-dollar -p +:$(BSVPATH) -verilog -u -g mkControllerTop Top.bsv
	cp vivado-impl.tcl ./build/impl.tcl
	cp program.tcl ./build/program.tcl
	cd build; cd verilog/top; ../../../verilogcopy.sh; cd ../../; vivado -mode batch -source impl.tcl
	tar czf c.tgz build/
	mv c.tgz build/

clean:
	rm -rf build
	
# vivado -mode batch -source mkpcietop-impl.tcl
