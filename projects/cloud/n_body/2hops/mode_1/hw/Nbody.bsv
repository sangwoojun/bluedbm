import FIFO::*;
import FIFOF::*;
import Vector::*;

import BRAM::*;
import BRAMFIFO::*;

import FloatingPoint::*;
import Float32::*;

import CalAccel::*;
import CalPmv::*;

typedef 5 PeWaysLog;
typedef TExp#(PeWaysLog) PeWays;

Integer totalParticles = 16*1024*1024;

interface NbodyIfc;
	method Action dataPmIn(Vector#(4, Bit#(32)) originDataPm, Bit#(32) inputPmIdx);
	method Action dataVIn(Vector#(3, Bit#(32)) originDataV);
	method ActionValue#(Vector#(4, Bit#(32))) dataOutPm;
	method ActionValue#(Vector#(3, Bit#(32))) dataOutV;
endinterface
module mkNbody(NbodyIfc);
	FIFO#(Tuple2#(Vector#(4, Bit#(32)), Bit#(32))) dataPmQ <- mkFIFO;
	FIFO#(Vector#(3, Bit#(32))) dataVQ <- mkFIFO;
	FIFO#(Vector#(4, Bit#(32))) resultOutPmQ <- mkFIFO;
	FIFO#(Vector#(3, Bit#(32))) resultOutVQ <- mkFIFO;

	CalAccelIfc calAcc <- mkCalAccel;
	CalPmvIfc calPmv <- mkCalPmv;

	FIFOF#(Vector#(4, Bit#(32))) relayDataPmIQ <- mkSizedFIFOF(256);
	FIFO#(Vector#(4, Bit#(32))) pInQ <- mkSizedBRAMFIFO(256);
	Reg#(Bit#(32)) relayDataPmJCnt <- mkReg(0);
	Reg#(Bool) relayDataPmIOn <- mkReg(True);
	rule relayDataPmJ;
		dataPmQ.deq;
		Vector#(4, Bit#(32)) p = tpl_1(dataPmQ.first);
		Bit#(32) idx = tpl_2(dataPmQ.first);

		if ( relayDataPmIOn ) begin
			if ( relayDataPmIQ.notFull ) begin
				if ( relayDataPmJCnt == idx ) begin
					if ( relayDataPmJCnt == (fromInteger(totalParticles) - 1) ) begin
						relayDataPmJCnt <= 0;
						relayDataPmIOn <= False;
					end else begin
						relayDataPmJCnt <= relayDataPmJCnt + 1;
					end
					relayDataPmIQ.enq(p);
					pInQ.enq(p);
				end
			end
		end
		calAcc.jIn(p);
	endrule
	Reg#(Vector#(4, Bit#(32))) relayDataPmIBuffer <- mkReg(replicate(0));
	Reg#(Bit#(32)) relayDataPmICnt <- mkReg(0);
	rule relayDataPmI( relayDataPmIQ.notEmpty );
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
			relayDataPmICnt <= relayDataPmICnt + 1;
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
	method Action dataPmIn(Vector#(4, Bit#(32)) originDataPm, Bit#(32) inputPmIdx);
		dataPmQ.enq(tuple2(originDataPm, inputPmIdx));
	endmethod
	method Action dataVIn(Vector#(3, Bit#(32)) originDataV);
		dataVQ.enq(originDataV);
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

