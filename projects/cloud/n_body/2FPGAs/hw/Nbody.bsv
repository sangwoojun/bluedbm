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

interface CalPositIfc;
endinterface
module mkCalPosit(CalPositIfc);
endmodule


interface CalVelocIfc;
endinterface
module mkCalVeloc(CalVelocIfc);
endmodule


interface CalAccelPeIfc;
	method Action putOperandI(Vector#(4, Bit#(32)) i);
	method Action putOperandJ(Vector#(4, Bit#(32)) j);
	method ActionValue#(Vector#(4, Bit#(32))) resultGet;
	method Bool resultExist;
endinterface
module mkCalAccelPe#(Bit#(PeWaysLog) peIdx) (CalAccelPeIfc);
	FIFO#(Vector#(4, Bit#(32))) inputIQ <- mkFIFO;
	FIFO#(Vector#(4, Bit#(32))) inputJQ <- mkFIFO;
	
	FpPairIfc#(32) fpSub32 <- mkFpSub32;
	FpPairIfc#(32) fpAdd32 <- mkFpAdd32;
	FpPairIfc#(32) fpMult32 <- mkFpMult32;
	FpPairIfc#(32) fpDiv32 <- mkFpDiv32;
	FpPairIfc#(32) fpSqrt32 <- mkFpSqrt32;

	FIFO#(Vector#(4, Bit#(32))) tmpResult1Q <- mkFIFO;
	FIFO#(Vector#(4, Bit#(32))) subResultQ <- mkFIFO;
	rule commonSub;
		inputIQ.deq;
		inputJQ.deq;
		Vector#(4, Bit#(32)) out1 = replicateM(0);
		Vector#(4, Bit#(32)) out2 = replicateM(0);
		Vector#(4, Bit#(32)) i = inputIQ.first;
		Vector#(4, Bit#(32)) j = inputJQ.first;
		// tmpResult1Q
		for ( Integer x = 0; x < 3; x = x + 1 ) out1[x] = fpSub32(j[x], i[x]);
		out1[3] = j[3]; // Mass J
		// subResultQ
		out2[0] = out1[0];
		out2[1] = out1[1];
		out2[2] = out1[2];
		out3[3] = i[3]; // Mass I
		
		tmpResult1Q.enq(out1);
		subResultQ.enq(out2);
	endrule
	FIFO#(Vector#(2, Bit#(32))) tmpResult2Q <- mkFIFO;
	rule denominatorMod;
		tmpResult1Q.deq;
		Vector#(2, Bit#(32)) out = replicateM(0);
		Vector#(3, Bit#(32)) m = replicateM(0);
		Vector#(4, Bit#(32)) s = tmpResult1Q.first;

		for ( Integer x = 0; x < 3; x = x + 1 ) m[x] = fpMult32(s[x], s[x]);
		Bit#(32) m2 = m[0] + m[1] + m[2];
		Bit#(32) m3 = fpSqrt32(m2);
		out[0] = m3;
		out[1] = s[3]; // Mass

		tmpResult2Q.enq(out);
	endrule
	FIFO#(Vector#(2, Bit#(32))) tmpResult3Q <- mkFIFO;
	rule denominatorPow;
		tmpResult2Q.deq;
		Vector#(2, Bit#(32)) p = replicateM(0);
		Vector#(2, Bit#(32)) m = tmpResult2Q.first;
		
		Bit#(32) p2 = fpMult32(m[0], m[0]);
		Bit#(32) p3 = fpMult32(p2, m[0]);
		p[0] = p3;
		p[1] = m[1];

		tmpResult3Q.enq(p);
	endrule
	FIFO#(Bit#(32)) tmpResult4Q <- mkFIFO;
	rule devider;
		tmpResult3Q.deq;
		Vector#(2, Bit#(32)) p = tmpResult3Q.first;
		
		Bit#(32) g = 32b'00111100100000000000000000000000;
		Bit#(32) gm = fpMult32(g, p[1]);
		Bit#(32) d = fpDiv32(gm, p[0]);
	
		tmpResult4Q.enq(d);
	endrule
	FIFOF#(Vector#(4, Bit#(32))) outputAQ <- mkFIFOF;
	rule calAccelResult;
		subResultQ.deq;
		tmpResult4Q.deq;
		Vector#(4, Bit#(32)) finalResult = replicateM(0);
		Vector#(4, Bit#(32)) s = subResultQ.first;
		Bit#(32) d = tmpResult4Q.first;

		for ( Integer x = 0; x < 3; x = x + 1 ) finalResult[x] = fpMult32(d, s[x]);
		finalResult[3] = s[3];

		outputAQ.enq(finalResult);
	endrule

	method Action putOperandI(Vector#(4, Bit#(32)) i);
		inputIQ.enq(i);
	endmethod
	method Action putOperandJ(Vector#(4, Bit#(32)) j);
		inputJQ.enq(j);
	endmethod
	method ActionValue#(Vector#(4, Bit#(32))) resultGet;
		outputAQ.deq;
		return outputAQ.first;
	endmethod
	method Bool resultExist;
		return outputAQ.notEmpty;
	endmethod
endmodule
interface CalAccelIfc;
	method Action iIn(Vector#(4, Bit#(32)) dataI);
	method Action jIn(Vector#(4, Bit#(32)) dataJ);
	method ActionValue#(Vector#(4, Bit#(32))) aOut;
endinterface
module mkCalAccel(CalAccelIfc);
	Vector#(PeWays, PeIfc) pes;
	Vector#(PeWays, FIFO#(Vector#(4, Bit#(32)))) iInQs <- replicateM(mkFIFO);
	Vector#(PeWays, FIFO#(Vector#(4, Bit#(32)))) jInQs <- replicateM(mkFIFO);
	Vector#(PeWays, FIFO#(Vector#(4, Bit#(32)))) aOutQs <- replicateM(mkFIFO);

	for ( Integer x = 0; x < valueOf(PeWays); x = x + 1 ) begin
		pes[x] <- mkCalAccelPe(fromInteger(x));

		rule forwardOperandI;
			iInQs[x].deq;
			let d = iInQs[x].first;
			if ( x < (valueOf(PeWays) - 1) ) begin
				iInQs[x+1].enq(d);
			end
			pes[x].putOperandI(d);
		endrule
		Reg#(Bit#(24)) jInIdx <- mkReg(0);
		rule forwardOperandJ;
			jInQs[x].deq;
			let d = jInQs[x].first;
			if ( x < (valueOf(PeWays) - 1) ) begin
				jInQs[x+1].enq(d);
			end
			Bit#(PeWaysLog) target_j = truncate(jInIdx);
			if ( target_j == fromInteger(x) ) begin
				pes[x].putOperandB(d);
			end
		endrule
		rule forwardResultA;
			if ( pes[x].resultExist ) begin
				let d <- pes[x].resultGet;
				aOutQs[x].enq(d);
			end else if ( x < (valueOf(PeWays)-1) ) begin
				aOutQs[x+1].deq;
				aOutQs[x].enq(aOutQs[x+1].first);
			end
		endrule
	end

	Vector#(4, Reg#(Bit#(32))) accBuffer <- replicateM(mkReg(0));
	FIFO#(Vector#(4, Bit#(32))) aOutQ <- mkSizedBRAMFIFO(64);
	Reg#(Bit#(PeWaysLog)) accCnt <- mkReg(0);
	rule accResultA;
		Vector#(4, Bit#(32)) p = replicateM(0);
		if ( accCnt == valueOf(PeWays) ) begin
			aOutQ.enq(accBuffer);
			accCnt <= 0;
		end else begin
			aOutQs[0].deq;
			let d = aOutQs[0].first;
			let v = accBuffer;

			p[0] = v[0] + d[0];
			p[1] = v[1] + d[1];
			p[2] = v[2] + d[2];
			p[3] = d[3];

			accBuffer <= p;
			accCnt <= accCnt + 1;
		end
	endrule
	
	method Action iIn(Vector#(4, Bit#(32)) dataI);
		iInQs[0].enq(dataI);
	endmethod
	method Action jIn(Vector#(4, Bit#(32)) dataJ);
		jInQs[0].enq(dataJ);
	endmethod
	method ActionValue#(Vector#(4, Bit#(32))) aOut;
		aOutQ.deq;
		return aOutQ.first;
	endmethod
endmodule

interface NbodyIfc;
	method Action dataPMIn(Vector#(4, Bit#(32)) originDataPM, Bit#(24) inputPMIdx);
	method Action dataVIn(Vector#(3, Bit#(32)) originDataV, Bit#(24) inputVIdx);
	method ActionValue#(Vector#(4, Bit#(32))) dataOutPM;
	method ActionValue#(Vector#(3, Bit#(32))) dataOutV;
endinterface

module mkNbody(NbodyIfc);
	FIFO#(Tuple2#(Vector#(4, Bit#(32)), Bit#(24))) dataPMQ <- mkFIFO;
	FIFO#(Tuple2#(Vector#(3, Bit#(32)), Bit#(24))) dataVQ <- mkFIFO;
	FIFO#(Vector#(4, Bit#(32))) resultOutPMQ <- mkFIFO;
	FIFO#(Vector#(3, Bit#(32))) resultOutVQ <- mkFIFO;

	CalAccelIfc calAcc <- mkCalAccel;
	CalVelocIfc calVel <- mkCalVeloc;

	FIFOF#(Vector#(4, Bit#(32))) relayDataPMIQ <- mkSizedFIFOF(64);
	Reg#(Bit#(24)) relayDataPMCnt <- mkReg(0);
	Reg#(Bool) relayDataPMI <- mkReg(True);
	rule relayDataPMJ;
		dataPMQ.deq;
		Vector#(4, Bit#(32)) p = tpl_1(dataPMQ.first);
		Bit#(24) idx = tpl_2(dataPMQ.first);

		if ( relayDataPMI ) begin
			if ( relayDataPMIQ.notFull ) begin
				if ( relayDataPMCnt == idx ) begin
					if ( relayDataPMCnt == (fromInteger(totalParticles) - 1) ) begin
						relayDataPMCnt <= 0;
						relayDataPMI <= False;
					end else begin
						relayDataPMCnt <= relayDataPMCnt + 1;
					end
					relayDataPMIQ.enq(p);
				end
			end
		end
		calAcc.jIn(p);
	endrule
	rule relayDataPMJ(relayDataPMIQ.notEmpty);
		relayDataPMIQ.deq;
		Vector#(4, Bit#(32)) p = relayDataPMIQ.first;

		calAcc.iIn(p);
	endrule
	FIFOF#(Tuple2#(Vector#(4, Bit#(32)), Bit#(24))) recvAccelValuesQ <- mkSizedFIFOF(64);
	rule recvAccelValues;
		let d <- calAcc.aOut;
	endrule
	method Action dataPMIn(Vector#(4, Bit#(32)) originDataPM, Bit#(24) inputPMIdx);
		dataPMQ.enq(tuple2(originDataPM, inputPMIdx));
	endmethod
	method Action dataVIn(Vector#(3, Bit#(32)) originDataV, Bit#(24) inputVIdx);
		dataVQ.enq(tuple2(originDataV, inputVIdx));
	endmethod
	method ActionValue#(Vector#(4, Bit#(32))) dataOutPM;
		resultOutPMQ.deq;
		return resultOutPMQ.first;
	endmethod
	method ActionValue#(Vector#(3, Bit#(32))) dataOutV;
		resultOutVQ.deq;
		return resultOutVQ.first;
	endmethod
endmodule


interface ComPos;
endinterface

module mkComPos#() ();
endmodule


interface ComVel;
endinterface

module mkComVel#() ();
endmodule