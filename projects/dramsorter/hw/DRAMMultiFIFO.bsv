import FIFO::*;
import FIFOF::*;
import Clocks::*;
import Vector::*;

import BRAM::*;
import BRAMFIFO::*;

import MergeN::*;
import ScatterN::*;

import DRAMController::*;
import DRAMArbiterPage::*;

interface DRAMMultiFIFOEpIfc;
	method ActionValue#(Bit#(512)) read;
endinterface

interface DRAMMultiFIFOSrcIfc;
	method Action write(Bit#(512) data);
endinterface

interface DRAMMultiFIFOIfc#(numeric type dstCnt, numeric type srcCnt);
	method Action rcmd(Bit#(64) addr, Bit#(32) size, Bit#(TLog#(dstCnt)) dst);
	method Action wcmd(Bit#(64) addr, Bit#(32) size, Bit#(TLog#(srcCnt)) src);
	method ActionValue#(Bit#(TLog#(dstCnt))) ack;
	interface Vector#(dstCnt, DRAMMultiFIFOEpIfc) endpoints;
	interface Vector#(srcCnt, DRAMMultiFIFOSrcIfc) sources;
endinterface

module mkDRAMMultiFIFO#(DRAMPageUserIfc dram) (DRAMMultiFIFOIfc#(dstCnt, srcCnt))
	provisos(
	Log#(dstCnt, dstSz)
	,Log#(srcCnt, srcSz)
	,Add#(1, a__, dstSz)
	);
	Integer dstCount = valueOf(dstCnt);
	Integer srcCount = valueOf(srcCnt);

	Vector#(dstCnt, FIFO#(Bit#(512))) inQ <- replicateM(mkSizedBRAMFIFO(128*2)); // <- enough 2 8K pages
	Vector#(dstCnt, FIFO#(Tuple2#(Bit#(64),Bit#(32)))) cmdQ <- replicateM(mkSizedFIFO(8));
	Vector#(dstCnt, Reg#(Bit#(32))) inQup <- replicateM(mkReg(0));
	Vector#(dstCnt, Reg#(Bit#(32))) inQdown <- replicateM(mkReg(0));
	MergeNIfc#(dstCnt, Tuple3#(Bit#(dstSz),Bit#(64),Bit#(32))) mreq <- mkMergeN;
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
		rule sendReadReq ( curReadCnt > 128 && inQup[i]-inQdown[i] < 128 );
			curReadCnt <= curReadCnt - 128;
			mreq.enq[i].enq(tuple3(fromInteger(i), curReadAddr, 128));
			inQup[i] <= inQup[i] + 128;
			curReadAddr <= curReadAddr + (64*128);
		endrule
		rule sendReadReqF ( curReadCnt <= 128 && curReadCnt > 0 && inQup[i]-inQdown[i] < 128 );
			curReadCnt <= 0;
			mreq.enq[i].enq(tuple3(fromInteger(i), curReadAddr, curReadCnt));
			inQup[i] <= inQup[i] + curReadCnt;
			curReadAddr <= curReadAddr + (64*zeroExtend(curReadCnt));
			
			mack.enq[i].enq(fromInteger(i));
		endrule
	end

	Reg#(Bit#(32)) curReqCnt <- mkReg(0);
	Reg#(Bit#(64)) curReqAddr <- mkReg(0);
	Reg#(Bit#(dstSz)) curReqDst <- mkReg(0);
	
	Reg#(Bit#(srcSz)) curwreqDst <- mkReg(0);
	//Reg#(Bit#(64)) curwreqAddr <- mkReg(0);
	Reg#(Bit#(8)) curwreqCnt <- mkReg(0);


	FIFO#(Tuple2#(Bit#(dstSz),Bit#(8))) reqSrcQ <- mkSizedBRAMFIFO(256);

	rule initReadReq ( curReqCnt == 0 && curwreqCnt == 0 );
		mreq.deq;
		let r = mreq.first;
		curReqDst <= tpl_1(r);
		curReqAddr <= tpl_2(r);
		curReqCnt <= tpl_3(r);
	endrule
	rule dramReadReqL( curReqCnt >=128 );
		curReqCnt <= curReqCnt - 128;
		curReqAddr <= curReqAddr + (128*64);
		dram.cmd(curReqAddr, 128, False);
		reqSrcQ.enq(tuple2(curReqDst, 128));
	endrule
	rule dramReadReqS( curReqCnt < 128 && curReqCnt > 0 );
		curReqCnt <= 0;
		curReqAddr <= curReqAddr + (zeroExtend(curReqCnt)*64);
		dram.cmd(curReqAddr, truncate(curReqCnt), False);
	
		reqSrcQ.enq(tuple2(curReqDst, truncate(curReqCnt)));
	endrule

	ScatterNIfc#(dstCnt, Bit#(512)) scin <- mkScatterN;
	Reg#(Bit#(8)) dramReadCnt <- mkReg(0);
	rule dramReadResp;
		let d <- dram.read;
		let src = tpl_1(reqSrcQ.first);
		let cnt = tpl_2(reqSrcQ.first);

		if ( cnt <= dramReadCnt+1 ) begin
			dramReadCnt <= 0;
			reqSrcQ.deq;
		end else begin
			dramReadCnt <= dramReadCnt + 1;
		end

		scin.enq(d,src);
	endrule
	for ( Integer i = 0; i < dstCount; i=i+1 ) begin
		rule relin;
			let d <- scin.get[i].get;
			inQ[i].enq(d);
		endrule
	end


	// Write stuff

	Vector#(srcCnt, FIFO#(Tuple2#(Bit#(64),Bit#(32)))) wcmdQ <- replicateM(mkSizedFIFO(8));
	Vector#(srcCnt,Reg#(Bit#(64))) curWriteAddr <- replicateM(mkReg(0));

	Vector#(srcCnt,FIFO#(Bit#(512))) outQ <- replicateM(mkSizedBRAMFIFO(128*2));
	Vector#(srcCnt, Reg#(Bit#(32))) outQup <- replicateM(mkReg(0));
	Vector#(srcCnt, Reg#(Bit#(32))) outQdown <- replicateM(mkReg(0));

	MergeNIfc#(srcCnt, Tuple3#(Bit#(srcSz), Bit#(64), Bit#(8))) mwreq <- mkMergeN;
	for ( Integer i = 0; i < srcCount; i=i+1 ) begin
		Reg#(Bit#(32)) curWriteCnt <- mkReg(0);
		rule initWrite ( curWriteCnt == 0 );
			let cmd = wcmdQ[i].first;
			wcmdQ[i].deq;
			curWriteAddr[i] <= tpl_1(cmd);
			curWriteCnt <= tpl_2(cmd);
		endrule
		rule genWriteCmd ( curWriteCnt > 0 && outQup[i]-outQdown[i] > 128 );
			curWriteCnt <= curWriteCnt - 128;
			curWriteAddr[i] <= curWriteAddr[i] + (128*64);
			outQdown[i] <= outQdown[i] + 128;
			mwreq.enq[i].enq(tuple3(fromInteger(i),curWriteAddr[i], 128));
		endrule
		rule genWriteCmdF ( curWriteCnt > 0 && outQup[i]-outQdown[i] <= 128 && outQup[i]-outQdown[i] > 0 );
			curWriteCnt <= 0;
			curWriteAddr[i] <= curWriteAddr[i] + (zeroExtend(curWriteCnt)*64);
			outQdown[i] <= outQdown[i] + curWriteCnt;
			mwreq.enq[i].enq(tuple3(fromInteger(i),curWriteAddr[i], truncate(curWriteCnt)));
		endrule
	end
	rule initWriteCmd( curwreqCnt == 0 && curReqCnt == 0 );
		mwreq.deq;
		let src = mwreq.first;
		dram.cmd(tpl_2(src),tpl_3(src), True);
		curwreqDst <= tpl_1(src);
		//curwreqAddr <= tpl_2(src);
		curwreqCnt <= tpl_3(src);
	endrule
	rule sendWriteCmd ( curwreqCnt > 0 );
		let src = curwreqDst;
		let data = outQ[src].first;
		outQ[src].deq;
		//let addr = curwreqAddr;
		//curwreqAddr <= addr+64;
		curwreqCnt <= curwreqCnt - 1;
		dram.write(data);

		//dram.write(addr,data,7'b1111111);
	endrule



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
				outQ[i].enq(data);
			endmethod
		endinterface : DRAMMultiFIFOSrcIfc;
	end
	
	method Action rcmd(Bit#(64) addr, Bit#(32) size, Bit#(TLog#(dstCnt)) dst);
		cmdQ[dst].enq(tuple2(addr,size));
	endmethod
	method Action wcmd(Bit#(64) addr, Bit#(32) size, Bit#(TLog#(srcCnt)) src);
		wcmdQ[src].enq(tuple2(addr,size));
	endmethod
	method ActionValue#(Bit#(TLog#(dstCnt))) ack;
		mack.deq;
		return mack.first;
	endmethod
	interface endpoints = endpoints_;
	interface sources = sources_;
endmodule
