import FIFO::*;
import FIFOF::*;
import Clocks::*;
import Vector::*;

interface AddOperatorIfc#(type resultType);
	method Action enq(resultType d1, resultType d2);
	method resultType first;
	method Action deq;
endinterface

interface MultOperatorIfc#(type edgeType, type nodeType, type resultType);
	method Action enq(edgeType e, nodeType n);
	method resultType first;
	method Action deq;
endinterface



/**
Breadth - First - Search
*/


module mkBFSAdd(AddOperatorIfc#(Bool));
	FIFO#(Bool) resQ <- mkFIFO;

	method Action enq(Bool d1, Bool d2);
		resQ.enq(d1||d2);
	endmethod
	method Bool first;
		return resQ.first;
	endmethod
	method Action deq;
		resQ.deq;
	endmethod
endmodule

module mkBFSMult(MultOperatorIfc#(edgeType, nodeType, Bool));
	FIFO#(Bool) resQ <- mkFIFO;

	method Action enq(edgeType e, nodeType n);
		resQ.enq(True);
	endmethod
	method Bool first;
		return resQ.first;
	endmethod
	method Action deq;
		resQ.deq;
	endmethod
endmodule

