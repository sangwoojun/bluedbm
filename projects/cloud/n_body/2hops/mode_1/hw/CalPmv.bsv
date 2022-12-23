import FIFO::*;
import FIFOF::*;
import Vector::*;

import BRAM::*;
import BRAMFIFO::*;

import FloatingPoint::*;
import Float32::*;

typedef 5 PeWaysLog;
typedef TExp#(PeWaysLog) PeWays;

Integer totalParticles = 16*1024*1024;


interface CalPmvPeIfc;
	method Action putA(Vector#(4, Bit#(32)) a);
	method Action putV(Vector#(3, Bit#(32)) v);
	method Action putP(Vector#(4, Bit#(32)) p);
	method ActionValue#(Vector#(4, Bit#(32))) resultGetPm;
	method ActionValue#(Vector#(3, Bit#(32))) resultGetV;
	method Bool resultExistPm;
	method Bool resultExistV;
endinterface
module mkCalPmvPe#(Bit#(PeWaysLog) peIdx)(CalPmvPeIfc);
	FIFO#(Vector#(4, Bit#(32))) inputAQ <- mkFIFO;
	FIFO#(Vector#(3, Bit#(32))) inputVQ <- mkFIFO;
	FIFO#(Vector#(4, Bit#(32))) inputPQ <- mkFIFO;
	FIFOF#(Vector#(4, Bit#(32))) outputPmQ <- mkFIFOF;
	FIFOF#(Vector#(3, Bit#(32))) outputVQ <- mkFIFOF;

	Vector#(9, FpPairIfc#(32)) fpAdd32 <- replicateM(mkFpAdd32);
	Vector#(3, FpPairIfc#(32)) fpMult32 <- replicateM(mkFpMult32);

	FIFO#(Vector#(4, Bit#(32))) inputPosAQ <- mkFIFO;
	FIFO#(Vector#(4, Bit#(32))) inputVelAQ <- mkFIFO;
	rule replicateA;
		inputAQ.deq;
		let d = inputAQ.first;
		inputPosAQ.enq(d);
		inputVelAQ.enq(d);
	endrule
	FIFO#(Vector#(3, Bit#(32))) inputPosVQ <- mkFIFO;
	FIFO#(Vector#(3, Bit#(32))) inputVelVQ <- mkFIFO;
	rule replicateV;
		inputVQ.deq;
		let d = inputVQ.first;
		inputPosVQ.enq(d);
		inputVelVQ.enq(d);
	endrule

	FIFO#(Bit#(32)) massIQ <- mkFIFO;
	rule calPos1;
		inputPosAQ.deq;
		let a = inputPosAQ.first;
		Bit#(32) scale = 32'b00111111000000000000000000000000;
		
		for ( Integer x = 0; x < 3; x = x + 1 ) fpMult32[x].enq(scale, a[x]);
		
		massIQ.enq(a[3]);
	endrule
	rule calPos2;
		inputPosVQ.deq;
		let v = inputPosVQ.first;
		
		for ( Integer x = 0; x < 3; x = x + 1 ) begin
			fpMult32[x].deq;
			fpAdd32[x].enq(fpMult32[x].first, v[x]);
		end
	endrule
	rule calPos3;
		inputPQ.deq;
		let p = inputPQ.first;

		for ( Integer x = 0; x < 3; x = x + 1 ) begin
			fpAdd32[x].deq;
			fpAdd32[x+3].enq(fpAdd32[x].first, p[x]);
		end
	endrule
	rule calPos4;
		Vector#(4, Bit#(32)) fr = replicate(0);
		for ( Integer x = 0; x < 3; x = x + 1 ) begin
			fpAdd32[x+3].deq;
			fr[x] = fpAdd32[x+3].first;
		end
		
		massIQ.deq;
		fr[3] = massIQ.first;

		outputPmQ.enq(fr);
	endrule

	rule calVel1;
		inputVelAQ.deq;
		inputVelVQ.deq;
		let a = inputVelAQ.first;
		let v = inputVelVQ.first;

		for ( Integer x = 0; x < 3; x = x + 1 ) fpAdd32[x+6].enq(v[x], a[x]);
	endrule
	rule calVel2;
		Vector#(3, Bit#(32)) fr = replicate(0);
		for ( Integer x = 0; x < 3; x = x + 1 ) begin
			fpAdd32[x+6].deq;
			fr[x] = fpAdd32[x+6].first;
		end

		outputVQ.enq(fr);
	endrule

	method Action putA(Vector#(4, Bit#(32)) a);
		inputAQ.enq(a);
	endmethod
	method Action putP(Vector#(4, Bit#(32)) p);
		inputPQ.enq(p);
	endmethod 
	method Action putV(Vector#(3, Bit#(32)) v);
		inputVQ.enq(v);
	endmethod
	method ActionValue#(Vector#(4, Bit#(32))) resultGetPm;
		outputPmQ.deq;
		return outputPmQ.first;
	endmethod
	method ActionValue#(Vector#(3, Bit#(32))) resultGetV;
		outputVQ.deq;
		return outputVQ.first;
	endmethod
	method Bool resultExistPm;
		return outputPmQ.notEmpty;
	endmethod
	method Bool resultExistV;
		return outputVQ.notEmpty;
	endmethod
endmodule


interface CalPmvIfc;
	method Action aIn(Vector#(4, Bit#(32)) a);
	method Action vIn(Vector#(3, Bit#(32)) v);
	method Action pIn(Vector#(4, Bit#(32)) p);
	method ActionValue#(Vector#(4, Bit#(32))) pmOut;
	method ActionValue#(Vector#(3, Bit#(32))) vOut;
endinterface
module mkCalPmv(CalPmvIfc);
	Vector#(PeWays, CalPmvPeIfc) pes;
	Vector#(PeWays, FIFO#(Vector#(4, Bit#(32)))) aInQs <- replicateM(mkFIFO);
	Vector#(PeWays, FIFO#(Vector#(3, Bit#(32)))) vInQs <- replicateM(mkFIFO);
	Vector#(PeWays, FIFO#(Vector#(4, Bit#(32)))) pInQs <- replicateM(mkFIFO);
	Vector#(PeWays, FIFO#(Vector#(4, Bit#(32)))) pmOutQs <- replicateM(mkFIFO);
	Vector#(PeWays, FIFO#(Vector#(3, Bit#(32)))) vOutQs <- replicateM(mkFIFO);

	for ( Integer i = 0; i < valueOf(PeWays); i = i + 1 ) begin
		pes[i] <- mkCalPmvPe(fromInteger(i));

		Reg#(Bit#(16)) aInIdx <- mkReg(0);
		rule forwardAccel;
			aInQs[i].deq;
			let d = aInQs[i].first;
			if ( i < (valueOf(PeWays) - 1) ) begin
				aInQs[i+1].enq(d);
			end
			Bit#(PeWaysLog) target_a = truncate(aInIdx);
			if ( target_a == fromInteger(i) ) begin
				pes[i].putA(d);
			end
		endrule
		Reg#(Bit#(16)) pInIdx <- mkReg(0);
		rule forwardPosit;
			pInQs[i].deq;
			let d = pInQs[i].first;
			if ( i < (valueOf(PeWays) - 1) ) begin
				pInQs[i+1].enq(d);
			end
			Bit#(PeWaysLog) target_p = truncate(pInIdx);
			if ( target_p == fromInteger(i) ) begin
				pes[i].putP(d);
			end
		endrule
		Reg#(Bit#(16)) vInIdx <- mkReg(0);
		rule forwardVeloc;
			vInQs[i].deq;
			let d = vInQs[i].first;
			if ( i < (valueOf(PeWays) - 1) ) begin
				vInQs[i+1].enq(d);
			end
			Bit#(PeWaysLog) target_v = truncate(vInIdx);
			if ( target_v == fromInteger(i) ) begin
				pes[i].putV(d);
			end
		endrule
		rule forwardResultPm;
			if ( pes[i].resultExistPm ) begin
				let d <- pes[i].resultGetPm;
				pmOutQs[i].enq(d);
			end else if ( i < (valueOf(PeWays) - 1) ) begin
				pmOutQs[i+1].deq;
				pmOutQs[i].enq(pmOutQs[i+1].first);
			end
		endrule
		rule forwardResultV;
			if ( pes[i].resultExistV ) begin
				let d <- pes[i].resultGetV;
				vOutQs[i].enq(d);
			end else if ( i < (valueOf(PeWays) - 1) ) begin
				vOutQs[i+1].deq;
				vOutQs[i].enq(vOutQs[i+1].first);
			end
		endrule
	end
	method Action aIn(Vector#(4, Bit#(32)) a);
		aInQs[0].enq(a);
	endmethod
	method Action vIn(Vector#(3, Bit#(32)) v);
		vInQs[0].enq(v);
	endmethod
	method Action pIn(Vector#(4, Bit#(32)) p);
		pInQs[0].enq(p);
	endmethod
	method ActionValue#(Vector#(4, Bit#(32))) pmOut;
		pmOutQs[0].deq;
		return pmOutQs[0].first;
	endmethod
	method ActionValue#(Vector#(3, Bit#(32))) vOut;
		vOutQs[0].deq;
		return vOutQs[0].first;
	endmethod
endmodule
