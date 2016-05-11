import DRAMArbiter::*;

interface AcceleratorReaderIfc;
	method Action dataIn(Bit#(512) d);
	method Action cmdIn(Bit#(32) header, Bit#(128) cmd);

	method ActionValue#(Bit#(128)) resOut;
endinterface

module mkNullAcceleratorReader (AcceleratorReaderIfc);
	method Action dataIn(Bit#(512) d);
	endmethod
	method Action cmdIn(Bit#(32) header, Bit#(128) cmd);
	endmethod

	method ActionValue#(Bit#(128)) resOut if ( False );
		return ?;
	endmethod
endmodule

module mkDRAMWriterAccel#(DRAMArbiterUserIfc dram) (AcceleratorReaderIfc);
	Reg#(Bit#(64)) dramOutOff <- mkReg(16*1024*1024);

	method Action dataIn(Bit#(512) d);
		dram.write(dramOutOff, d, 64);
		dramOutOff <= dramOutOff + 64;
	endmethod
	method Action cmdIn(Bit#(32) header, Bit#(128) cmd_);
		Bit#(32) cmd = truncate(cmd_>>(32*3));
		Bit#(32) off = truncate(cmd_);
		dramOutOff <= zeroExtend(off);
	endmethod

	method ActionValue#(Bit#(128)) resOut if ( False );
		return ?;
	endmethod
endmodule
