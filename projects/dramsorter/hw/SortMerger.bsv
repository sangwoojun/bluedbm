import FIFO::*;
import FIFOF::*;
import Clocks::*;
import Vector::*;

import BRAM::*;
import BRAMFIFO::*;

import MergeN::*;

import DRAMMultiFIFO::*;

import VectorPacker::*;

// All data and ack is done via DRAMMultiFIFO
interface SortMergerIfc#(numeric type srcCnt, numeric type dstCnt, type dtype, numeric type packcnt);
	method Action cmdsrc(Bit#(TLog#(srcCnt)) src, Bit#(32) cnt);
endinterface

module mkSortMerger#(Vector#(srcCnt, DRAMMultiFIFOEpIfc) fifos, Vector#(dstCnt, DRAMMultiFIFOSrcIfc) outs) (SortMergerIfc#(srcCnt, dstCnt, dtype, packcnt));

	method Action cmdsrc(Bit#(TLog#(srcCnt)) src, Bit#(32) cnt);
	endmethod
endmodule

interface SortMergerSliceUpIfc#(type dtype);
	method Action enq(dtype dat);
	method Action cnt(Bit#(32) cnt);
endinterface
interface SortMergerSliceIfc#(type dtype);
	interface Vector#(2,SortMergerSliceUpIfc#(dtype)) enq;
	method ActionValue#(Bit#(32)) tcnt;
	method dtype first;
	method Action deq;
endinterface

module mkSortMergerSlice#(Bool descending) (SortMergerSliceIfc#(dtype))
	provisos(Bits#(dtype,dtypeSz), Ord#(dtype), Add#(1,a__,dtypeSz));


	Vector#(2,FIFO#(Bit#(32))) cntQ <- replicateM(mkFIFO);
	FIFO#(Bit#(32)) tcntQ <- mkFIFO;
	Vector#(2, Reg#(Bit#(32))) curCnt <- replicateM(mkReg(0));
	Vector#(2,FIFO#(dtype)) dinQ <- replicateM(mkFIFO);
	FIFO#(dtype) doutQ <- mkFIFO;

	rule startNewMerge;
		let c1 = cntQ[0].first;
		let c2 = cntQ[1].first;
		curCnt[0] <= c1;
		curCnt[1] <= c2;
		cntQ[0].deq;
		cntQ[1].deq;
		tcntQ.enq( c1+c2 );
	endrule

	rule ff1 ( curCnt[0] > 0 && curCnt[1] == 0 );
		curCnt[0] <= curCnt[0] -1;
		dinQ[0].deq;
		let d = dinQ[0].first;
		doutQ.enq(d);
	endrule
	rule ff2 ( curCnt[0] == 0 && curCnt[1] > 0 );
		curCnt[1] <= curCnt[1] -1;
		dinQ[1].deq;
		let d = dinQ[1].first;
		doutQ.enq(d);
	endrule
	rule doMerge;
		let d1 = dinQ[0].first;
		let d2 = dinQ[1].first;
		if ( descending ) begin
			if ( d1 > d2 ) begin
				doutQ.enq(d1);
				dinQ[0].deq;
				curCnt[0] <= curCnt[0] -1;
			end else begin
				doutQ.enq(d2);
				dinQ[1].deq;
				curCnt[1] <= curCnt[1] -1;
			end
		end else begin
			if ( d1 > d2 ) begin
				doutQ.enq(d2);
				dinQ[1].deq;
				curCnt[1] <= curCnt[1] -1;
			end else begin
				doutQ.enq(d1);
				dinQ[0].deq;
				curCnt[0] <= curCnt[0] -1;
			end
		end
	endrule

	Vector#(2,SortMergerSliceUpIfc#(dtype)) enq_;
	for ( Integer i = 0; i < 2; i=i+1 ) begin
		enq_[i] = interface SortMergerSliceUpIfc#(dtype);
			method Action enq(dtype dat);
				dinQ[i].enq(dat);
			endmethod
			method Action cnt(Bit#(32) c);
				cntQ[i].enq(c);
			endmethod
		endinterface : SortMergerSliceUpIfc;
	end
	interface enq = enq_;
	method ActionValue#(Bit#(32)) tcnt;
		tcntQ.deq;
		return tcntQ.first;
	endmethod
	method dtype first;
		return doutQ.first;
	endmethod
	method Action deq;
		doutQ.deq;
	endmethod
endmodule





module mkSortMerger16#(Vector#(16, DRAMMultiFIFOEpIfc) fifos, Vector#(1, DRAMMultiFIFOSrcIfc) outs, Bool descending) (SortMergerIfc#(16, 1, dtype, packcnt))
	provisos(Bits#(dtype,dtypeSz)
	, Ord#(dtype)
	, Literal#(dtype)
	, Add#(1, a__, dtypeSz)
	, Add#(b__, dtypeSz, 512));

	Vector#(8,SortMergerSliceIfc#(dtype)) mlayer1 <- replicateM(mkSortMergerSlice(descending));

	
	for ( Integer i = 0; i < 16; i=i+1 ) begin
		VectorUnpackerIfc#(512, packcnt, dtype) unpacker <- mkVectorUnpacker;
		rule relayDin;
			let d <- fifos[i].read;
			unpacker.enq(d);
		endrule
		VectorSerializerIfc#(packcnt, dtype) vser <- mkVectorSerializer;
		rule ser;
			let d = unpacker.first;
			unpacker.deq;
			vser.enq(d);
		endrule
		rule inj;
			vser.deq;
			let d = vser.first;
			mlayer1[i/2].enq[i%2].enq(d);
		endrule
	end
	
	Vector#(4,SortMergerSliceIfc#(dtype)) mlayer2 <- replicateM(mkSortMergerSlice(descending));
	for ( Integer i = 0; i < 8; i=i+1 ) begin
		rule relay;
			let d = mlayer1[i].first;
			mlayer1[i].deq;
			mlayer2[i/2].enq[i%2].enq(d);
		endrule
		rule relaycnt;
			let d <- mlayer1[i].tcnt;
			mlayer2[i/2].enq[i%2].cnt(d);
		endrule
	end
	Vector#(2,SortMergerSliceIfc#(dtype)) mlayer3 <- replicateM(mkSortMergerSlice(descending));
	for ( Integer i = 0; i < 4; i=i+1 ) begin
		rule relay;
			let d = mlayer2[i].first;
			mlayer2[i].deq;
			mlayer3[i/2].enq[i%2].enq(d);
		endrule
		rule relaycnt;
			let d <- mlayer2[i].tcnt;
			mlayer3[i/2].enq[i%2].cnt(d);
		endrule
	end
	Vector#(1,SortMergerSliceIfc#(dtype)) mlayer4 <- replicateM(mkSortMergerSlice(descending));
	for ( Integer i = 0; i < 2; i=i+1 ) begin
		rule relay;
			let d = mlayer3[i].first;
			mlayer3[i].deq;
			mlayer4[i/2].enq[i%2].enq(d);
		endrule
		rule relaycnt;
			let d <- mlayer3[i].tcnt;
			mlayer4[i/2].enq[i%2].cnt(d);
		endrule
	end

	rule flushcnt;
		let d <- mlayer4[0].tcnt;
	endrule
	VectorDeserializerIfc#(packcnt,dtype) des <- mkVectorDeserializer;
	rule getmerged;
		mlayer4[0].deq;
		let md = mlayer4[0].first;
		des.enq(md);
	endrule
	VectorPackerIfc#(packcnt,dtype,512) packer <- mkVectorPacker;
	rule getdes;
		des.deq;
		let d = des.first;
		packer.enq(d);
	endrule
	rule senddramw;
		packer.deq;
		let d = packer.first;
		outs[0].write(d);
	endrule

	method Action cmdsrc(Bit#(TLog#(16)) src, Bit#(32) cnt);
		mlayer1[src>>1].enq[src[0]].cnt(cnt);
	endmethod
endmodule
