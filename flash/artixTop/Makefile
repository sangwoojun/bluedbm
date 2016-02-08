ROOT_DIR := $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))

BSC_FLAGS = -keep-fires -show-schedule -aggressive-conditions -wait-for-license
BUILD_DIR = build
V_DIR = $(BUILD_DIR)/verilog
B_DIR = $(BUILD_DIR)/obj

COMMON_BSV_PATH	= ../src/common

#Synthesizable hardware controller + flash chips
TOP_HW 				= mkTopArtix
TOP_HW_PATH			= ../src/hw_artix/TopArtix.bsv
TOP_HW_BSV_PATH 	= $(COMMON_BSV_PATH):../src/hw_artix:../src/hw_artix/ECC:../../src/lib:../xilinx/aurora_8b10b
TOP_HW_XDC			= ../../xilinx/constraints/artix_hw_8buses.xdc ../../xilinx/aurora_8b10b/aurora_8b10b_exdes.xdc

#Synthesizable controller model using RegFile
TOP_MODEL 			= mkTopArtixModel
TOP_MODEL_PATH 	= ../src/model_artix/TopArtixModel.bsv
TOP_MODEL_BSV_PATH= $(COMMON_BSV_PATH):../src/model_artix:../../src/lib:../xilinx/aurora_8b10b
TOP_MODEL_XDC		= ../../xilinx/constraints/artix_model.xdc ../../xilinx/aurora_8b10b/aurora_8b10b_exdes.xdc

#Synthesizable testbench + hardware controller + flash chips
TOP_HW_TB			= mkTopTB
TOP_HW_TB_PATH		= ../src/hw_artix/tb/TopTB.bsv
TOP_HW_TB_BSV_PATH= $(COMMON_BSV_PATH):../src/hw_artix:../src/hw_artix/ECC:../../src/lib
TOP_HW_TB_XDC			= ../../xilinx/constraints/artix_hw_8buses.xdc

#Verilog simulation testbench + hardware controller + nand verilog model
#SIM_FLAGS			= -D NAND_SIM
TOP_SIM_TB			= mkTopTB
TOP_SIM_TB_PATH	= ../src/hw_artix/tb/TopTB.bsv
TOP_SIM_TB_BSV_PATH = $(COMMON_BSV_PATH):../src/hw_artix:../src/hw_artix/ECC:../../src/lib


default: clean compile_hw
hw: compile_hw
model: clean compile_model
tb: clean compile_hw_tb
tb_sim: clean compile_sim_tb

.PHONY: compile_hw
compile_hw: MSG = \>\>\> Compiling HARDWARE CONTROLLER \<\<\<
compile_hw: TOP_MODULE=$(TOP_HW)
compile_hw: TOP_PATH=$(TOP_HW_PATH)
compile_hw: BSV_PATH=$(TOP_HW_BSV_PATH)
compile_hw: XDC_FILES=$(TOP_HW_XDC)
compile_hw: compile implement

.PHONY: compile_model
compile_model: MSG = \>\>\> Compiling CONTROLLER MODEL \<\<\<
compile_model: TOP_MODULE=$(TOP_MODEL)
compile_model: TOP_PATH=$(TOP_MODEL_PATH)
compile_model: BSV_PATH=$(TOP_MODEL_BSV_PATH)
compile_model: XDC_FILES=$(TOP_MODEL_XDC)
compile_model: compile implement

.PHONY: compile_hw_tb
compile_hw_tb: MSG = \>\>\> Compiling HARDWARE TESTBENCH + CONTROLLER \<\<\<
compile_hw_tb: TOP_MODULE=$(TOP_HW_TB)
compile_hw_tb: TOP_PATH=$(TOP_HW_TB_PATH)
compile_hw_tb: BSV_PATH=$(TOP_HW_TB_BSV_PATH)
compile_hw_tb: XDC_FILES=$(TOP_HW_TB_XDC)
compile_hw_tb: compile implement

.PHONY: compile_sim_tb
compile_sim_tb: MSG = \>\>\> Compiling SIMULATION TESTBENCH + CONTROLLER \<\<\<
compile_sim_tb: TOP_MODULE=$(TOP_SIM_TB)
compile_sim_tb: TOP_PATH=$(TOP_SIM_TB_PATH)
compile_sim_tb: BSV_PATH=$(TOP_SIM_TB_BSV_PATH)
compile_sim_tb: BSC_FLAGS += -D NAND_SIM
compile_sim_tb: compile

compile:
	@echo $(MSG)
	@echo $(TOP_MODULE)
	@echo $(TOP_PATH)
	mkdir -p $(V_DIR)
	mkdir -p $(B_DIR)
	bsc -u $(BSC_FLAGS) -verilog -vdir $(V_DIR) -bdir $(B_DIR) -info-dir $(B_DIR) -simdir $(B_DIR) -p +:$(BSV_PATH) -g $(TOP_MODULE) $(TOP_PATH)
	cd $(V_DIR); $(ROOT_DIR)/verilogcopy.sh; cd $(ROOT_DIR)
	@echo $(MSG)...DONE

implement:
	cp $(ROOT_DIR)/vivado-impl.tcl $(BUILD_DIR)/impl.tcl
	cd $(BUILD_DIR); vivado -mode batch -source impl.tcl -tclargs $(TOP_MODULE) $(XDC_FILES)

clean:
	rm -rf build




