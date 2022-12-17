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
	method Actonn putP(Vector#(4, Bit#(32)) p);
	method ActionValue#(Vector#(4, Bit#(32))) resultGetPm;
	method ActionValue#(Vector#(3, Bit#(32))) resultGetV;
	method Bool resultExistPm;
	method Bool resultExistV;
endinterface
module mkCalPmvPe(CalPmvPeIfc);
	FIFO#(Vector#(4, Bit#(32))) inputAQ <- mkFIFO;
	FIFO#(Vector#(3, Bit#(32))) inputVQ <- mkFIFO;
	FIFO#(Vector#(4, Bit#(32))) inputPQ <- mkFIFO;
	FIFOF#(Vector#(4, Bit#(32))) outputPmQ <- mkFIFOF;
	FIFOF#(Vector#(3, Bit#(32))) outputVQ <- mkFIFOF;

	FpPairIfc#(32) fpSub32 <- mkFpSub32;
	FpPairIfc#(32) fpAdd32 <- mkFpAdd32;
	FpPairIfc#(32) fpMult32 <- mkFpMult32;
	FpPairIfc#(32) fpDiv32 <- mkFpDiv32;
	FpPairIfc#(32) fpSqrt32 <- mkFpSqrt32;
	
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
	rule calPos;
		inputPosAQ.deq;
		inputPosVQ.deq;
		inputPQ.deq;
		let a = inputPosAQ.first;
		let v = inputPosVQ.first;
		let p = inputPQ.first;
		Vector#(3, Bit#(32)) tmpResult1 = replicateM(0);
		Vector#(3, Bit#(32)) tmpResult2 = replicateM(0);
		Vector#(4, Bit#(32)) finalResult = replicateM(0);

		Bit#(32) scale = 32b'00111111000000000000000000000000;
		tmpResult1[0] = fpMult32(scale, a[0]);
		tmpResult1[1] = fpMult32(scale, a[1]);
		tmpResult1[2] = fpMult32(scale, a[2]);

		tmpResult2[0] = fpAdd32(tmpResult[0], v[0]);
		tmpResult2[1] = fpAdd32(tmpResult[1], v[1]);
		tmpResult2[2] = fpAdd32(tmpResult[2], v[2]);

		finalResult[0] = fpAdd32(tmpResult2[0], p[0]);
		finalResult[1] = fpAdd32(tmpResult2[1], p[1]);
		finalResult[2] = fpAdd32(tmpResult2[2], p[2]);
		finalResult[3] = a[3];

		outputPmQ.enq(finalResult);
	endrule
	rule calVel;
		inputVelAQ.deq;
		inputVelVQ.deq;
		let a = inputVelAQ.first;
		let v = inputVelVQ.first;

		Vector#(3, Bit#(32)) finalResult = replicateM(0);
		finalResult[0] = fpAdd32(v[0], a[0]);
		finalResult[1] = fpAdd32(v[1], a[1]);
		finalResult[2] = fpAdd32(v[2], a[2]);

		outputVQ.enq(finalResult);
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
		rule forwardAccel;
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
	Vector#(PeWays, CalAccelPeIfc) pes;
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
	FIFO#(Vector#(4, Bit#(32))) aOutQ <- mkSizedBRAMFIFO(256);
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
	method Action dataPmIn(Vector#(4, Bit#(32)) originDataPm, Bit#(24) inputPmIdx);
	method Action dataVIn(Vector#(3, Bit#(32)) originDataV, Bit#(24) inputVIdx);
	method ActionValue#(Vector#(4, Bit#(32))) dataOutPm;
	method ActionValue#(Vector#(3, Bit#(32))) dataOutV;
endinterface
module mkNbody(NbodyIfc);
	FIFO#(Tuple2#(Vector#(4, Bit#(32)), Bit#(24))) dataPmQ <- mkFIFO;
	FIFO#(Tuple2#(Vector#(3, Bit#(32)), Bit#(24))) dataVQ <- mkFIFO;
	FIFO#(Vector#(4, Bit#(32))) resultOutPmQ <- mkFIFO;
	FIFO#(Vector#(3, Bit#(32))) resultOutVQ <- mkFIFO;

	CalAccelIfc calAcc <- mkCalAccel;
	CalPmvIfc calPmv <- mkCalPmv;

	FIFOF#(Vector#(4, Bit#(32))) relayDataPmIQ <- mkSizedFIFOF(256);
	FIFO#(Vector#(4, Bit#(32))) pInQ <- mkSizedBRAMFIFO(256);
	Reg#(Bit#(24)) relayDataPmCnt <- mkReg(0);
	Reg#(Bool) relayDataPmI <- mkReg(True);
	rule relayDataPmJ;
		dataPmQ.deq;
		Vector#(4, Bit#(32)) p = tpl_1(dataPmQ.first);
		Bit#(24) idx = tpl_2(dataPmQ.first);

		if ( relayDataPmI ) begin
			if ( relayDataPmIQ.notFull ) begin
				if ( relayDataPmCnt == idx ) begin
					if ( relayDataPmCnt == (fromInteger(totalParticles) - 1) ) begin
						relayDataPmCnt <= 0;
						relayDataPmI <= False;
					end else begin
						relayDataPmCnt <= relayDataPmCnt + 1;
					end
					relayDataPmIQ.enq(p);
					pInQ.enq(p);
				end
			end
		end
		calAcc.jIn(p);
	endrule
	Vector#(4, Reg#(Bit#(32))) relayDataPmIBuffer <- replicateM(mkReg(0));
	rule relayDataPmI(relayDataPmIQ.notEmpty);
		if ( relayDataPmICnt != 0 ) begin
			let p = relayDataPmIBuffer;
			calAcc.iIn(p);
			if ( relayDataPmICnt == 524287 ) begin
				relayDataPmICnt <= 0;
			end else begin
				relayDataPmICnt <= relayDataPmICnt + 1;
			end
		end else begin
			relayDataPmIQ.deq;
			Vector#(4, Bit#(32)) p = relayDataPmIQ.first;
			relayDataPmIBuffer <= p;
			calAcc.iIn(p);
		end
	endrule
	rule relayDataA;
		let d <- calAcc.aOut;
		calPmv.aIn(d);
	endrule
	rule relayDataV;
		dataVQ.deq;
		let d = dataVQ.first;
		calPmv.vIn(d);
	endrule
	rule relayDataP;
		pInQ.deq;
		let p = pInQ.first;
		calPmv.pIn(p);
	endrule
	rule recvResultPm;
		let res <- calPmv.pmOut;
		resultOutPmQ.enq(res);
	endrule
	rule recvResultV;
		let res <- calPmv.vOut;
		resultOutVQ.enq(res);
	endrule
	method Action dataPmIn(Vector#(4, Bit#(32)) originDataPm, Bit#(24) inputPmIdx);
		dataPmQ.enq(tuple2(originDataPm, inputPmIdx));
	endmethod
	method Action dataVIn(Vector#(3, Bit#(32)) originDataV, Bit#(24) inputVIdx);
		dataVQ.enq(tuple2(originDataV, inputVIdx));
	endmethod
	method ActionValue#(Vector#(4, Bit#(32))) dataOutPm;
		resultOutPmQ.deq;
		return resultOutPmQ.first;
	endmethod
	method ActionValue#(Vector#(3, Bit#(32))) dataOutV;
		resultOutVQ.deq;
		return resultOutVQ.first;
	endmethod
endmodule

