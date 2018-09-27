import FIFO::*;
import FIFOF::*;
import Clocks::*;
import Vector::*;

import BRAM::*;
import BRAMFIFO::*;

import ScatterN::*;
import PageSorter::*;

import SortingNetwork::*;
import MergeSorter::*;

interface InMemorySorterIfc#(numeric type vcnt, type inType, numeric type cntSz);
	// addr, words
	method ActionValue#(Tuple2#(Bit#(32),Bit#(32))) dramReadReq;
	method Action dramReadData(Bit#(512) data);

	/**
		Offset: start of the first of the 16 buffers in dram
		Count: number of tuples to be merged in each sorted block
		bufferSize: size of each 16 buffers in memory. Count can be larger
		tokenSize: granularity of tokens, to tell the host to manage double buffers
	**/
	method Action runMerge(Bit#(32) offset, Bit#(cntSz) count, Bit#(32) bufferSize, Bit#(cntSz) tokenSize);
endinterface

module mkInMemorySorter#(Bool descending) ( InMemorySorterIfc#(vcnt, inType, cntSz) )
	provisos(Bits#(inType,inTypeSz), Ord#(inType), Add#(1,a__,inTypeSz));

	Vector#(16,FIFO#(Bit#(512))) vInQ <- replicateM(mkSizedBRAMFIFO((8192/64)*2));
	Vector#(16,Reg#(Bit#(cntSz))) vCurInCnt <- replicateM(mkReg(0));
	Reg#(Bit#(cntSz)) mergeInCnt <- mkReg(0);
	MergeSorterIfc#(16, vcnt, inType) merger16 <- mkMergeSorter16(descending);

	Reg#(Bit#(cntSz)) mergedOutCnt <- mkReg(0);

	// addr, words
	method ActionValue#(Tuple2#(Bit#(32),Bit#(32))) dramReadReq;
		return ?;
	endmethod
	method Action dramReadData(Bit#(512) data);
	endmethod

	method Action runMerge(Bit#(32) offset, Bit#(cntSz) count, Bit#(32) bufferSize, Bit#(cntSz) tokenSize) if (mergedOutCnt == 0);
		mergedOutCnt <= count*16;
		mergeInCnt <= count;
		for ( Integer i = 0; i < 16; i=i+1 ) begin
			vCurInCnt[i] <= 0;
		end
	endmethod
endmodule
