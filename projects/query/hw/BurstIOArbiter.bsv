package BurstIOArbiter;

import Vector::*;
import FIFO::*;

import MergeN::*;

interface BurstIOEndpointIfc#(type t);
	method Action burstWrite(Bit#(32) offset, Bit#(16) words);
	method Action burstRead(Bit#(32) offset, Bit#(16) words);
	method ActionValue#(t) getData;
	method Action putData(t data);
endinterface

interface BurstIOArbiterIfc#(numeric type n, type t);
	interface Vector#(n, BurstIOEndpointIfc#(t)) eps;

	method ActionValue#(Tuple3#(Bool, Bit#(32), Bit#(16))) getBurstReq; // Write? Offset, Words
	method ActionValue#(t) getData;
	method Action putData(t data);
endinterface

module mkBurstIOArbiter (BurstIOArbiterIfc#(n,t))
	provisos(Bits#(t, tSz), Log#(n,nLg), Add#(1,nLg,nSz),
		Add#(nSz,a__,8));

	Vector#(n, BurstIOEndpointIfc#(t)) eps_;

	BurstIOMergeNIfc#(n,t,32,16) writeM <- mkBurstIOMergeN;
	MergeNIfc#(2,Tuple3#(Bool, Bit#(32), Bit#(16))) rwM <- mkMergeN;
	rule relayWriteBurst;
		let b <- writeM.getBurst;
		rwM.enq[0].enq(tuple3(True, tpl_1(b), tpl_2(b)));
	endrule

	MergeNIfc#(n,Tuple3#(Bit#(32),Bit#(16),Bit#(nSz))) readM <- mkMergeN;
	FIFO#(Tuple2#(Bit#(nSz),Bit#(16))) readOrdQ <- mkSizedFIFO(4); //dst, count
	rule relayReadBurst;
		readM.deq;
		let b = readM.first;
		rwM.enq[1].enq(tuple3(False,tpl_1(b),tpl_2(b)));
		readOrdQ.enq(tuple2(tpl_3(b),tpl_2(b)));
	endrule

	ScatterNIfc#(n,t) readS <- mkScatterN;

	for ( Integer i = 0; i < valueOf(n); i=i+1 ) begin
		eps_[i] = interface BurstIOEndpointIfc;
			method Action burstWrite(Bit#(32) offset, Bit#(16) words);
				writeM.enq[i].burst(offset,words);
			endmethod
			method Action burstRead(Bit#(32) offset, Bit#(16) words);
				readM.enq[i].enq(tuple3(offset,words,fromInteger(i)));
			endmethod
			method ActionValue#(t) getData;
				readS.get[i].deq;
				return readS.get[i].first;
			endmethod
			method Action putData(t data);
				writeM.enq[i].enq(data);
			endmethod
		endinterface;
	end

	FIFO#(t) inQ <- mkFIFO;
	Reg#(Bit#(nSz)) curReadDst <- mkReg(0);
	Reg#(Bit#(16)) curReadLeft <- mkReg(0);
	rule procIn;
		inQ.deq;
		let in = inQ.first;
		if ( curReadLeft == 0 ) begin
			readOrdQ.deq;
			let r = readOrdQ.first;
			let dst = tpl_1(r);
			curReadDst <= dst;
			curReadLeft <= tpl_2(r)-1;
			readS.enq(in,zeroExtend(dst));
		end else begin
			curReadLeft <= curReadLeft - 1;
			readS.enq(in,zeroExtend(curReadDst));
		end
	endrule

	interface eps = eps_;
	method ActionValue#(Tuple3#(Bool, Bit#(32), Bit#(16))) getBurstReq; // Write? Offset, Words
		rwM.deq;
		return rwM.first;
	endmethod
	method ActionValue#(t) getData;
		writeM.deq;
		return writeM.first;
	endmethod
	method Action putData(t data);
		inQ.enq(data);
	endmethod
endmodule

endpackage: BurstIOArbiter
