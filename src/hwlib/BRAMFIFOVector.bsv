
/*
Note:
The semantics of this FIFO implementation is somewhat different from normal FIFOs.
(1) enq may fire even when it is full. In which case the request will be queued.
(2) deqReq may fire when FIFO is empty. This will also be queued until there is data.
*/

import BRAM::*;
import FIFO::*;
import FIFOF::*;
import Vector::*;

interface BRAMFIFOVectorIfc#(numeric type vlog, numeric type fifosize, type fifotype);
	method Action enq(fifotype data, Bit#(vlog) idx);
	method Action reqDeq(Bit#(vlog) idx);
	method ActionValue#(fifotype) respDeq;
	method Bit#(TAdd#(1,TLog#(fifosize))) getDataCount(Bit#(vlog) idx);
	method ActionValue#(Bit#(vlog)) getReadyIdx;
	method Action startBurst(Bit#(TAdd#(1,TLog#(fifosize))) burstCount, Bit#(vlog) idx);
endinterface

module mkBRAMFIFOVector#(Integer thresh) (BRAMFIFOVectorIfc#(vlog, fifosize, fifotype))
	provisos (
		Literal#(fifotype), 
		Bits#(fifotype, fifotypesz)
		);
	
	Integer fifoSize = valueOf(fifosize);

	Vector#(TExp#(vlog), Reg#(Bit#(TAdd#(1,TLog#(fifosize))))) enqTotal <- replicateM(mkReg(0));
	//including all eventual deqs when burst starts
	Vector#(TExp#(vlog), Reg#(Bit#(TAdd#(1,TLog#(fifosize))))) deqTotal <- replicateM(mkReg(0)); 
	Vector#(TExp#(vlog), Reg#(Bit#(TAdd#(1,TLog#(fifosize))))) deqCurrent <- replicateM(mkReg(0)); 

	BRAM2Port#(Bit#(TAdd#(vlog,TAdd#(1,TLog#(fifosize)))), fifotype) fifoBuffer <- mkBRAM2Server(defaultValue); 

	Vector#(TExp#(vlog), Reg#(Bit#(TAdd#(1,TLog#(fifosize))))) headpointer <- replicateM(mkReg(0));
	Vector#(TExp#(vlog), Reg#(Bit#(TAdd#(1,TLog#(fifosize))))) tailpointer <- replicateM(mkReg(0));
	/*
	function Bool isEmpty(Bit#(vlog) idx);
		Bool res = False;
		if ( enqTotal[idx] == deqCurrent[idx] ) res = True;

		//if ( headpointer[idx] == tailpointer[idx] ) res = True;

		return res;
	endfunction
	*/
	function Bool isFull(Bit#(vlog) idx);
		Bool res = False;

		let head1 = headpointer[idx]+1;
		if ( head1 >= fromInteger(fifoSize) ) head1 = 0;

		if ( head1 == tailpointer[idx] ) res = True;

		return res;
	endfunction

	function Bit#(TAdd#(1,TLog#(fifosize))) dataCount(Bit#(vlog) idx);
		let enqt = enqTotal[idx];
		let deqt = deqTotal[idx];
		let diff = enqt - deqt;

		return diff;
	endfunction

	FIFO#(Bool) fakeQ0 <- mkFIFO;
	FIFO#(Bool) fakeQ1 <- mkFIFO;
	
	FIFO#(Bit#(vlog)) readyIdxQ <- mkSizedFIFO(32);

	FIFO#(Tuple2#(fifotype, Bit#(vlog))) enqQ <- mkSizedFIFO(1);
	FIFO#(Bit#(vlog)) deqQ <- mkSizedFIFO(4);

	rule applyenq;
		let cmdd = enqQ.first;
		let idx = tpl_2(cmdd);
		let data = tpl_1(cmdd);
		
		if ( !isFull( idx ) ) begin
			enqQ.deq;
			let head1 = headpointer[idx]+1;
			if ( head1 >= fromInteger(fifoSize) ) head1 = 0;
			headpointer[idx] <= head1;

			fifoBuffer.portB.request.put(BRAMRequest{write:True, responseOnWrite:False, address:zeroExtend(idx)*fromInteger(fifoSize)+zeroExtend(headpointer[idx]), datain:data});
		end
	endrule

	//isEmpty no longer required because of enqTotal and deqTotal checks
	// adding isEmpty will make this rule conflict with applyenq
	rule applydeq;
		let idx = deqQ.first;
		deqQ.deq;

		let tail1 = tailpointer[idx]+1;
		if ( tail1 >= fromInteger(fifoSize) ) tail1 = 0;
		tailpointer[idx] <= tail1;

		fifoBuffer.portA.request.put(
			BRAMRequest{
			write:False, 
			responseOnWrite:?, 
			address:zeroExtend(idx)*fromInteger(fifoSize)+zeroExtend(tailpointer[idx]), 
			datain:?});
	endrule


	// No guards here. All safety checking is done in applyenq
	method Action enq(fifotype data, Bit#(vlog) idx); 
		if ( dataCount(idx) + 1 == fromInteger(thresh*2) ) fakeQ1.deq;

		enqQ.enq(tuple2(data,idx));
		enqTotal[idx] <= enqTotal[idx] + 1;

		if ( dataCount(idx)+1 == fromInteger(thresh) 
			) begin
			readyIdxQ.enq(idx);
		end
	endmethod
	
	method Bit#(TAdd#(1,TLog#(fifosize))) getDataCount(Bit#(vlog) idx);
		return dataCount(idx);
	endmethod

	method Action reqDeq(Bit#(vlog) idx);
		if ( deqTotal[idx] == deqCurrent[idx] ) fakeQ0.deq;
		deqCurrent[idx] <= deqCurrent[idx] + 1;

		deqQ.enq(idx);
	endmethod

	method ActionValue#(fifotype) respDeq;
		let v <- fifoBuffer.portA.response.get();
		return v;
	endmethod

	method ActionValue#(Bit#(vlog)) getReadyIdx;
		readyIdxQ.deq;
		return readyIdxQ.first;
	endmethod

	// No guards here. safety checking must be done in user code
	// i.e. Only call when getReadyIdx returned
	method Action startBurst(Bit#(TAdd#(1,TLog#(fifosize))) burstCount, Bit#(vlog) idx);
		deqTotal[idx] <= deqTotal[idx] + burstCount;
	endmethod
endmodule
