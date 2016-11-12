import FIFO::*;
import FIFOF::*;
import Clocks::*;
import Vector::*;

interface CompareAndSwapIfc#(type inType);
	interface Vector#(2,FIFO#(inType)) ifc;
endinterface
module mkCompareAndSwap#(Bool descending) (CompareAndSwapIfc#(inType))
	provisos(
	Bits#(inType, inTypeSz)
	, Ord#(inType)
	);
	

	Vector#(2,FIFO#(inType)) inQ <- replicateM(mkFIFO);
	Vector#(2,FIFO#(inType)) outQ <- replicateM(mkFIFO);

	rule doCAS;
		let d1 = inQ[0].first;
		let d2 = inQ[1].first;
		inQ[0].deq;
		inQ[1].deq;
		if ( descending ) begin
			if ( d1 >= d2 ) begin
				outQ[0].enq(d1);
				outQ[1].enq(d2);
			end else begin
				outQ[0].enq(d2);
				outQ[1].enq(d1);
			end
		end else begin
			if ( d2 >= d1 ) begin
				outQ[0].enq(d1);
				outQ[1].enq(d2);
			end else begin
				outQ[0].enq(d2);
				outQ[1].enq(d1);
			end
		end
	endrule

	Vector#(2,FIFO#(inType)) ifc_;
	for (Integer i = 0; i < 2; i = i +1 ) begin
		ifc_[i] = interface FIFO#(inType);
			method inType first();
				return outQ[i].first;
			endmethod
			method Action clear();
				inQ[i].clear;
				outQ[i].clear;
			endmethod
			method Action enq(inType data);
				inQ[i].enq(data);
			endmethod
			method Action deq;
				outQ[i].deq;
			endmethod
		endinterface: FIFO;
	end

	interface ifc = ifc_;
endmodule

interface SortingNetworkIfc#(type inType, numeric type keyCount);
	method Action enq(Vector#(keyCount, inType) data);
	method ActionValue#(Vector#(keyCount, inType)) get;
endinterface

module mkSortingNetwork3#(Bool descending) (SortingNetworkIfc#(inType, 3))
	provisos(
		Bits#(Vector::Vector#(3, inType), inVSz),
		Bits#(inType,inTypeSz), Ord#(inType), Add#(1,a__,inTypeSz)
	);

	CompareAndSwapIfc#(inType) s0c01 <- mkCompareAndSwap(descending);
	FIFO#(inType) s0f2 <- mkSizedFIFO(4);
	FIFO#(inType) s1f0 <- mkSizedFIFO(4);
	CompareAndSwapIfc#(inType) s1c12 <- mkCompareAndSwap(descending);
	CompareAndSwapIfc#(inType) s2c01 <- mkCompareAndSwap(descending);
	FIFO#(inType) s2f2 <- mkSizedFIFO(4);

	CompareAndSwapIfc#(inType) ss <- mkCompareAndSwap(descending);

	rule stage1;
		let d0 = s0c01.ifc[0].first;
		let d1 = s0c01.ifc[1].first;
		let d2 = s0f2.first;
		s0c01.ifc[0].deq;
		s0c01.ifc[1].deq;
		s0f2.deq;

		s1f0.enq(d0);
		s1c12.ifc[0].enq(d1);
		s1c12.ifc[1].enq(d2);
	endrule

	rule stage2;
		let d0 = s1f0.first;
		let d1 = s1c12.ifc[0].first;
		let d2 = s1c12.ifc[1].first;
		s1f0.deq;
		s1c12.ifc[0].deq;
		s1c12.ifc[1].deq;

		s2c01.ifc[0].enq(d0);
		s2c01.ifc[1].enq(d1);
		s2f2.enq(d2);
	endrule

	method Action enq(Vector#(3, inType) data);
		let d0 = data[0];
		let d1 = data[1];
		let d2 = data[2];
		s0c01.ifc[0].enq(d0);
		s0c01.ifc[1].enq(d1);
		s0f2.enq(d2);
	endmethod
	method ActionValue#(Vector#(3, inType)) get;
		s2c01.ifc[0].deq;
		s2c01.ifc[1].deq;
		s2f2.deq;

		Vector#(3, inType) data;
		data[0] = s2c01.ifc[0].first;
		data[1] = s2c01.ifc[1].first;
		data[2] = s2f2.first;

		return data;
	endmethod
endmodule
/*
module mkSortingNetwork#(Bool descending) (SortingNetworkIfc#(inType, keyCount))
	provisos(
		Bits#(Vector::Vector#(keyCount, inType), inVSz)
		Bits#(inType,inTypeSz), Ord#(inType), Add#(1,a__,inTypeSz)
	);

	method Action enq(Vector#(keyCount, inType) data);
	endmethod
	method ActionValue#(Vector#(keyCount, inType)) get;
	endmethod
endmodule
*/


