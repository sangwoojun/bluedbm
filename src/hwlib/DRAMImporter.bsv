`ifdef BSIM
import DDR3Sim::*;
`endif
import XilinxVC707DDR3::*;
import Xilinx       :: *;
import XilinxCells ::*;
import Clocks :: *;
import DefaultValue    :: *;

import FIFO::*;

typedef Bit#(29) DDR3Address;
typedef Bit#(64) ByteEn;
typedef Bit#(512) DDR3Data;

interface DRAM_User;
	method Action request(Bit#(32) addr, Bit#(512) data, Bool write);
	method ActionValue#(Bit#(512)) read_data;
endinterface
interface DRAM_Import;
	interface DRAM_User user;
`ifndef BSIM
	interface DDR3_Pins_VC707 ddr3;
`endif
endinterface

(* synthesize *)
module mkDRAMImport#(Clock clk200, Reset rst200) (DRAM_Import);


`ifndef BSIM
	DDR3_Configure ddr3_cfg = defaultValue;
	ddr3_cfg.reads_in_flight = 2;   // adjust as needed
	//ddr3_cfg.reads_in_flight = 24;   // adjust as needed
	//ddr3_cfg.fast_train_sim_only = False; // adjust if simulating
	DDR3_Controller_VC707 ddr3_ctrl <- mkDDR3Controller_VC707(ddr3_cfg, clk200, clocked_by clk200, reset_by rst200);

	// ddr3_ctrl.user needs to connect to user logic and should use ddr3clk and ddr3rstn
	DDR3_User_VC707 ddr3_ctrl_user = ddr3_ctrl.user;
`else
   let ddr3_ctrl_user <- mkDDR3Simulator;
`endif
	
	Clock curClk <- exposeCurrentClock;
	Reset curRst <- exposeCurrentReset;
	
	Clock ddr3clk = ddr3_ctrl_user.clock;
	Reset ddr3rstn = ddr3_ctrl_user.reset_n;
	
	SyncFIFOIfc#(Tuple3#(Bit#(32), Bit#(512), Bool)) cmdQ <- mkSyncFIFO(2, curClk, curRst, ddr3clk);
	SyncFIFOIfc#(Bit#(512)) dataQ <-mkSyncFIFO(8, ddr3clk,ddr3rstn, curClk);
	FIFO#(Bool) dramThrottleQ <- mkSizedFIFO(8);

	rule execCommand;
		let cmd = cmdQ.first;
		let addr = tpl_1(cmd);
		let data = tpl_2(cmd);
		let write = tpl_3(cmd);
		Bit#(64) mask = ~64'h0;
		
		if ( write ) begin
			ddr3_ctrl_user.request(truncate(addr<<3), mask, data);
		end else begin
			ddr3_ctrl_user.request(truncate(addr<<3), 0, ?);
		end
		cmdQ.deq;
	endrule

	rule flushData;
			let d <- ddr3_ctrl_user.read_data;
			dataQ.enq(d);
	endrule

interface DRAM_User user;
	method Action request(Bit#(32) addr, Bit#(512) data, Bool write);
		cmdQ.enq(tuple3(addr, data, write));
		if ( !write ) dramThrottleQ.enq(True);

	endmethod
	method ActionValue#(Bit#(512)) read_data;
		dramThrottleQ.deq;

		dataQ.deq;
		return dataQ.first;
	endmethod
endinterface
`ifndef BSIM
interface DDR3_Pins_VC707 ddr3 = ddr3_ctrl.ddr3;
`endif
endmodule
