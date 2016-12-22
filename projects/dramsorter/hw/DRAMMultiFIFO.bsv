import FIFO::*;
import FIFOF::*;
import Clocks::*;
import Vector::*;

import BRAM::*;
import BRAMFIFO::*;

import MergeN::*;

import DRAMController::*;
import DRAMArbiter::*;

interface DRAMMultiFIFOEpIfc;
	method ActionValue#(Bit#(512)) read;
endinterface

interface DRAMMultiFIFOSrcIfc;
	method Action write(Bit#(512) data);
endinterface

interface DRAMMultiFIFOIfc#(numeric type dstCnt, numeric type srcCnt);
	method Action rcmd(Bit#(64) addr, Bit#(32) size, Bit#(TLog#(dstCnt)) dst);
	method Action wcmd(Bit#(64) addr, Bit#(TLog#(srcCnt) src);
	method ActionValue#(Bit#(TLog#(dstCnt))) ack;
	interface Vector#(dstCnt, DRAMMultiFIFOEpIfc) endpoints;
	interface Vector#(srcCnt, DRAMMultiFIFOSrcIfc) sources;
endinterface

module mkDRAMMultiFIFO#(DRAMArbiterUserIfc dram) (DRAMMultiFIFOIfc#(dstCnt, srcCnt))
	provisos(
	Log#(dstCnt, dstSz)
	,Add#(1, a__, dstSz)
	);
	Integer dstCount = valueOf(dstCnt);
	Integer srcCount = valueOf(srcCnt);

	Vector#(dstCnt, FIFO#(Bit#(512))) inQ <- replicateM(mkSizedBRAMFIFO(32)); // <- enough assuming 16 byte words downstream
	Vector#(dstCnt, FIFO#(Tuple2#(Bit#(64),Bit#(32)))) cmdQ <- replicateM(mkSizedFIFO(8));
	Vector#(dstCnt, Reg#(Bit#(8))) inQup <- replicateM(mkReg(0));
	Vector#(dstCnt, Reg#(Bit#(8))) inQdown <- replicateM(mkReg(0));
	MergeNIfc#(dstCnt, Tuple2#(Bit#(dstSz),Bit#(64))) mreq <- mkMergeN;
	MergeNIfc#(dstCnt, Bit#(dstSz)) mack <- mkMergeN;

	for ( Integer i = 0; i < dstCount; i=i+1 ) begin
		Reg#(Bit#(32)) curReadCnt <- mkReg(0);
		Reg#(Bit#(64)) curReadAddr <- mkReg(0);
		rule initRead ( curReadCnt == 0 );
			let cmd = cmdQ[i].first;
			cmdQ[i].deq;
			curReadAddr <= tpl_1(cmd);
			curReadCnt <= tpl_2(cmd);
		endrule
		rule sendReadReq ( curReadCnt > 0 && inQup[i]-inQdown[i]<32 );
			curReadCnt <= curReadCnt - 1;
			inQup[i] <= inQup[i] + 1;
			curReadAddr <= curReadAddr + 64;
			mreq.enq[i].enq(tuple2(fromInteger(i), curReadAddr));
			if ( curReadCnt <= 1 ) mack.enq[i].enq(fromInteger(i));

		endrule
	end

	FIFO#(Bit#(dstSz)) reqSrcQ <- mkSizedBRAMFIFO(256);
	rule dramReadReq;
		mreq.deq;
		let r = mreq.first;
		dram.readReq(tpl_2(r), 7'b1111111);
		reqSrcQ.enq(tpl_1(r));
	endrule
	rule dramReadResp;
		let d <- dram.read;
		let src = reqSrcQ.first;
		reqSrcQ.deq;

		inQ[src].enq(d);
	endrule


	// Write stuff

	Vector#(srcCnt, FIFO#(Bit#(64))) wcmdQ <- replicateM(mkSizedFIFO(8));
	for ( Integer i = 0; i < srcCount; i=i+1 ) begin
		rule initWrite;
		endrule
	end



	Vector#(dstCnt, DRAMMultiFIFOEpIfc) endpoints_;
	for (Integer i = 0; i < dstCount; i=i+1) begin
		endpoints_[i] = interface DRAMMultiFIFOEpIfc;
			method ActionValue#(Bit#(512)) read;
				inQdown[i] <= inQdown[i] + 1;
				inQ[i].deq;
				return inQ[i].first;
			endmethod
		endinterface : DRAMMultiFIFOEpIfc;
	end
	Vector#(srcCnt, DRAMMultiFIFOSrcIfc) sources_;
	for ( Integer i = 0; i < srcCount; i=i+1 ) begin
		sources_[i] = interface DRAMMultiFIFOSrcIfc;
			method Action write(Bit#(512) data);
			endmethod
		endinterface : DRAMMultiFIFOSrcIfc;
	end
	
	method Action rcmd(Bit#(64) addr, Bit#(32) size, Bit#(TLog#(dstCnt)) dst);
		cmdQ[dst].enq(tuple2(addr,size));
	endmethod
	method Action wcmd(Bit#(64) addr, Bit#(TLog#(srcCnt) src);
		wcmdQ[src].enq(addr);
	endmethod
	method ActionValue#(Bit#(TLog#(dstCnt))) ack;
		mack.deq;
		return mack.first;
	endmethod
	interface endpoints = endpoints_;
	interface sources = sources_;
endmodule
