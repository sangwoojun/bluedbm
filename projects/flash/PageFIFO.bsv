import BRAM::*;
import BRAMFIFO::*;
import FIFO::*;
import FIFOF::*;
import Vector::*;

interface PageFIFOIfc;
	method Action enq(Bit#(512) data);
	method Bit#(512) first;
	method Action deq;

	method ActionValue#(Bool) req;
endinterface

module mkPageFIFO#(Integer pages) (PageFIFOIfc);
	FIFO#(Bit#(512)) outQ <- mkFIFO;
	FIFO#(Bit#(512)) inQ <- mkSizedBRAMFIFO(128+pages*128); // two 8k pages

	Reg#(Bit#(8)) splitcount <- mkReg(0);
	Reg#(Bit#(512)) splitbuf <- mkReg(0);

	Reg#(Bit#(16)) datain <- mkReg(0);
	Reg#(Bit#(16)) dataout <- mkReg(0);

/*
	rule splitQ;
		if ( splitcount == 0 ) begin
			inQ.deq;
			let d = inQ.first;

			splitcount <= 3;
			outQ.enq(d[511:384]);
			splitbuf <= (d<<128);
			
			dataout <= dataout + 1;
		end else begin
			splitcount <= splitcount - 1;
			outQ.enq(splitbuf[511:384]);
			splitbuf <= (splitbuf<<128);
		end
	endrule
	*/
	rule relayq;
		inQ.deq;
		outQ.enq(inQ.first);
		dataout <= dataout + 1;
	endrule


	method Action enq(Bit#(512) data);
		inQ.enq(data);
	endmethod
	method Bit#(512) first;
		return outQ.first;
	endmethod
	method Action deq;
		outQ.deq;
	endmethod
	method ActionValue#(Bool) req() if ( datain-dataout < 128*fromInteger(pages) );
		datain <= datain + 128;
		return True;
	endmethod
endmodule
