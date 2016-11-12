import FIFO::*;
import FIFOF::*;
import Clocks::*;
import Vector::*;

interface LinearCongruentialIfc#(numeric type numSz);
	method Action seed(Bit#(numSz) seed);
	method ActionValue#(Bit#(numSz)) next;
endinterface

module mkLinearCongruential (LinearCongruentialIfc#(numSz))
	provisos(Add#(__a,numSz,64));
	Bit#(64) m = 6364136223846793005;
	Bit#(64) c = 1442695040888963407;
	
	Reg#(Bit#(numSz)) cur <- mkReg(1);
	FIFO#(Bit#(numSz)) genQ <- mkFIFO;
	rule nextGen;
		let ncur = cur * truncate(m) + truncate(c);
		genQ.enq(ncur);
		cur <= ncur;
	endrule

	method Action seed(Bit#(numSz) seedv);
		cur <= seedv;
	endmethod
	method ActionValue#(Bit#(numSz)) next;
		genQ.deq;
		return genQ.first;
	endmethod
endmodule
