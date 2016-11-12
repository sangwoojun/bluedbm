import FIFO::*;
import FIFOF::*;
import Clocks::*;
import Vector::*;

import BRAM::*;
import BRAMFIFO::*;

interface PageMergeSorterIfc#(type inType, numeric type tupleCount);
	method Action enq1(Vector#(tupleCount, inType) data);
	method Action enq2(Vector#(tupleCount, inType) data);
	method ActionValue#(Vector#(tupleCount, inType)) get;
endinterface
