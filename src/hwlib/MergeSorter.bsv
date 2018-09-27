import FIFO::*;
import FIFOF::*;
import Clocks::*;
import Vector::*;

import ScatterN::*;

import SortingNetwork::*;

interface StreamVectorMergerIfc#(numeric type vcnt, type keyType, type valType);
	method Action enq1(Maybe#(Vector#(vcnt,Tuple2#(keyType,valType))) data);
	method Action enq2(Maybe#(Vector#(vcnt,Tuple2#(keyType,valType))) data);
	method ActionValue#(Maybe#(Vector#(vcnt,Tuple2#(keyType,valType)))) get;
endinterface

module mkStreamVectorMerger#(Bool descending) (StreamVectorMergerIfc#(vcnt, keyType, valType))
	provisos(
		Bits#(keyType,keyTypeSz), Eq#(keyType), Ord#(keyType), Add#(1,a__,keyTypeSz),
		Bits#(valType,valTypeSz), Ord#(valType), Add#(1,b__,valTypeSz)
	);
	
	FIFO#(Maybe#(Vector#(vcnt,Tuple2#(keyType,valType)))) inQ1 <- mkFIFO;
	FIFO#(Maybe#(Vector#(vcnt,Tuple2#(keyType,valType)))) inQ2 <- mkFIFO;
	FIFO#(Maybe#(Vector#(vcnt,Tuple2#(keyType,valType)))) outQ <- mkFIFO;

	Reg#(Vector#(vcnt,Tuple2#(keyType,valType))) abuf <- mkReg(?);
	Reg#(Maybe#(Bool)) append1 <- mkReg(tagged Invalid);
	Reg#(Tuple2#(keyType,valType)) atail <- mkReg(?);

	rule lastInvalid (!isValid(inQ1.first) && !isValid(inQ2.first));
		inQ1.deq;
		inQ2.deq;
		outQ.enq(tagged Invalid);
	endrule
	
	rule ff1 (isValid(inQ1.first) && !isValid(inQ2.first));
		
		if ( isValid(append1) ) begin
			append1 <= tagged Invalid;
			outQ.enq(tagged Valid abuf);
		end else begin
			inQ1.deq;
			outQ.enq(inQ1.first);
		end
	endrule
	rule ff2 (!isValid(inQ1.first) && isValid(inQ2.first));
		
		if ( isValid(append1) ) begin
			append1 <= tagged Invalid;
			outQ.enq(tagged Valid abuf);
		end else begin
			inQ2.deq;
			outQ.enq(inQ2.first);
		end
	endrule

	//Reg#(Vector#(vcnt,inType)) topReg <- mkReg(?);
	//Reg#(Vector#(vcnt,inType)) botReg <- mkReg(?);
	Reg#(Tuple2#(keyType,valType)) tailReg1 <- mkReg(?);
	Reg#(Tuple2#(keyType,valType)) tailReg2 <- mkReg(?);
	Reg#(Bit#(1)) mergestate <- mkReg(0);

	rule doMerge ( isValid(inQ1.first) && isValid(inQ2.first) );
		Integer count = valueOf(vcnt);

		let d1_ = inQ1.first;
		let d1 = fromMaybe(?,d1_);
		//Bool valid1 = isValid(d1_);
		let d2_ = inQ2.first;
		let d2 = fromMaybe(?,d2_);
		//Bool valid2 = isValid(d2_);

		
		let tail1 = d1[count-1];
		let tail2 = d2[count-1];
		if ( isValid(append1) ) begin
			let is1 = fromMaybe(?, append1);
			if ( is1 ) begin
				d1 = abuf;
				tail1 = atail;
				inQ2.deq;
			end else begin
				d2 = abuf;
				tail2 = atail;
				inQ1.deq;
			end
		end else begin
			inQ1.deq;
			inQ2.deq;
		end

		let cleaned = halfCleanKV(d1,d2,descending);

		let top = tpl_1(cleaned);
		let bot = tpl_2(cleaned);
		//tailReg1 <= tail1;
		//tailReg2 <= tail2;
		//mergestate <= 1;

		// I don't think sortBitonic is needed?
		// (half cleaners only need bitonic seq)
		// in that case, we don't need two stages to merge
		abuf <= sortBitonicKV(bot, descending); 
		//abuf <= bot; 
		//let tail1 = tailReg1;
		//let tail2 = tailReg2;

		if ( descending ) begin
			if ( tail1 >= tail2 ) begin
				append1 <= tagged Valid False;
				atail <= tail2;
			end else begin
				append1 <= tagged Valid True;
				atail <= tail1;
			end
		end else begin
			if ( tail2 >= tail1 ) begin
				append1 <= tagged Valid False;
				atail <= tail2;
			end else begin
				append1 <= tagged Valid True;
				atail <= tail1;
			end
		end

		//$display( "doMerge" );
		//TODO outQ must be pushed through a sorting network
		//it is only bitonic!
		outQ.enq(tagged Valid top);
		//mergestate <= 0;
	endrule


	//TODO input MUST be sorted!
	method Action enq1(Maybe#(Vector#(vcnt,Tuple2#(keyType,valType))) data);
		inQ1.enq(data);
	endmethod
	method Action enq2(Maybe#(Vector#(vcnt,Tuple2#(keyType,valType))) data);
		inQ2.enq(data);
	endmethod

	//TODO outQ must be pushed through a sorting network
	//it is only bitonic!
	method ActionValue#(Maybe#(Vector#(vcnt,Tuple2#(keyType,valType)))) get;
		outQ.deq;
		return outQ.first;
	endmethod
endmodule

interface VectorMergerIfc#(numeric type vcnt, type inType, numeric type cntSz);
	method Action enq1(Vector#(vcnt,inType) data);
	method Action enq2(Vector#(vcnt,inType) data);
	method Action runMerge(Bit#(cntSz) count);
	method ActionValue#(Vector#(vcnt,inType)) get;
endinterface

module mkVectorMerger#(Bool descending) (VectorMergerIfc#(vcnt, inType, cntSz))
	provisos(Bits#(inType,inTypeSz), Ord#(inType), Add#(1,a__,inTypeSz));
	
	Reg#(Bit#(cntSz)) mCountTotal <- mkReg(0);
	Reg#(Bit#(cntSz)) mCount1 <- mkReg(0);
	Reg#(Bit#(cntSz)) mCount2 <- mkReg(0);

	FIFO#(Vector#(vcnt,inType)) inQ1 <- mkFIFO;
	FIFO#(Vector#(vcnt,inType)) inQ2 <- mkFIFO;
	FIFO#(Vector#(vcnt,inType)) outQ <- mkFIFO;

	Reg#(Vector#(vcnt,inType)) abuf <- mkReg(?);
	Reg#(Maybe#(Bool)) append1 <- mkReg(tagged Invalid);
	Reg#(inType) atail <- mkReg(?);
	
	rule ff1 (mCount1 > 0 && mCount2 == 0);
		
		if ( isValid(append1) ) begin
			append1 <= tagged Invalid;
			outQ.enq(abuf);
		end else begin
			inQ1.deq;
			outQ.enq(inQ1.first);
		end
		mCountTotal <= mCountTotal - 1;
		mCount1 <= mCount1 - 1;
	endrule
	rule ff2 (mCount1 == 0 && mCount2 > 0);
		
		if ( isValid(append1) ) begin
			append1 <= tagged Invalid;
			outQ.enq(abuf);
		end else begin
			inQ2.deq;
			outQ.enq(inQ2.first);
		end
		mCountTotal <= mCountTotal - 1;
		mCount2 <= mCount2 - 1;
	endrule

	//Reg#(Vector#(vcnt,inType)) topReg <- mkReg(?);
	//Reg#(Vector#(vcnt,inType)) botReg <- mkReg(?);
	Reg#(inType) tailReg1 <- mkReg(?);
	Reg#(inType) tailReg2 <- mkReg(?);
	Reg#(Bit#(1)) mergestate <- mkReg(0);

	rule doMerge (mCount1 > 0 && mCount2 > 0 ); // && mergestate == 0 );
		Integer count = valueOf(vcnt);

		let d1 = inQ1.first;
		let d2 = inQ2.first;
		
		let tail1 = d1[count-1];
		let tail2 = d2[count-1];
		if ( isValid(append1) ) begin
			let is1 = fromMaybe(?, append1);
			if ( is1 ) begin
				d1 = abuf;
				tail1 = atail;
				inQ2.deq;
			end else begin
				d2 = abuf;
				tail2 = atail;
				inQ1.deq;
			end
		end else begin
			inQ1.deq;
			inQ2.deq;
		end


		let cleaned = halfClean(d1,d2,descending);

		let top = tpl_1(cleaned);
		let bot = tpl_2(cleaned);
		//tailReg1 <= tail1;
		//tailReg2 <= tail2;
		//mergestate <= 1;

		// I don't think sortBitonic is needed?
		// (half cleaners only need bitonic seq)
		// in that case, we don't need two stages to merge
		abuf <= sortBitonic(bot, descending); 
		//abuf <= bot; 
		//let tail1 = tailReg1;
		//let tail2 = tailReg2;

		if ( descending ) begin
			if ( tail1 >= tail2 ) begin
				append1 <= tagged Valid False;
				atail <= tail2;
				mCount1 <= mCount1 - 1;
			end else begin
				append1 <= tagged Valid True;
				atail <= tail1;
				mCount2 <= mCount2 - 1;
			end
		end else begin
			if ( tail2 >= tail1 ) begin
				append1 <= tagged Valid False;
				atail <= tail2;
				mCount1 <= mCount1 - 1;
			end else begin
				append1 <= tagged Valid True;
				atail <= tail1;
				mCount2 <= mCount2 - 1;
			end
		end
		mCountTotal <= mCountTotal - 1;

		//$display( "doMerge" );
		//TODO outQ must be pushed through a sorting network
		//it is only bitonic!
		outQ.enq(top);
		//mergestate <= 0;
	endrule


	//TODO input MUST be sorted!
	method Action enq1(Vector#(vcnt,inType) data);
		inQ1.enq(data);
	endmethod
	method Action enq2(Vector#(vcnt,inType) data);
		inQ2.enq(data);
	endmethod

	method Action runMerge(Bit#(cntSz) count) if ( mCountTotal == 0);
		mCountTotal <= count * 2;
		mCount1 <= count;
		mCount2 <= count;
	endmethod

	//TODO outQ must be pushed through a sorting network
	//it is only bitonic!
	method ActionValue#(Vector#(vcnt,inType)) get;
		outQ.deq;
		return outQ.first;
	endmethod
endmodule






interface MergeSorterEpIfc#(numeric type vcnt, type inType);
	method Action enq(Vector#(vcnt, inType) data);
endinterface

interface MergeSorterIfc#(numeric type inCnt, numeric type vcnt, type inType);
	interface Vector#(inCnt, MergeSorterEpIfc#(vcnt, inType)) enq;
	method Action runMerge(Bit#(42) count);
	method ActionValue#(Vector#(vcnt, inType)) get;
endinterface

module mkMergeSorter16#(Bool descending) (MergeSorterIfc#(16, vcnt, inType))
	provisos(Bits#(inType,inTypeSz), Ord#(inType), Add#(1,a__,inTypeSz));


	FIFO#(Bit#(42)) runMergeQ <- mkFIFO;
	FIFO#(Bit#(42)) runMerge2Q <- mkFIFO;
	Vector#(8, VectorMergerIfc#(vcnt, inType, 42)) merge0 <- replicateM(mkVectorMerger(descending));
	rule setRunMerge0;
		runMergeQ.deq;
		let v = runMergeQ.first;
		for ( Integer i = 0; i < 8; i=i+1 ) begin
			merge0[i].runMerge(v);
		end
		runMerge2Q.enq(v*2);
	endrule
	Vector#(4, VectorMergerIfc#(vcnt, inType, 42)) merge1 <- replicateM(mkVectorMerger(descending));
	Vector#(2, VectorMergerIfc#(vcnt, inType, 42)) merge2 <- replicateM(mkVectorMerger(descending));
	VectorMergerIfc#(vcnt, inType, 42) merge3 <- mkVectorMerger(descending);
	rule setRunMerge1;
		runMerge2Q.deq;
		let v = runMerge2Q.first;
		for ( Integer i = 0; i < 4; i=i+1 ) begin
			merge1[i].runMerge(v);
		end
		merge2[0].runMerge(v*2);
		merge2[1].runMerge(v*2);
		merge3.runMerge(v*4);
	endrule


	Vector#(16, MergeSorterEpIfc#(vcnt, inType)) enq_;
	for ( Integer i = 0; i < 16; i=i+1 ) begin
		enq_[i] = interface MergeSorterEpIfc;
			method Action enq(Vector#(vcnt, inType) data);
				if ( i%2 == 0 ) begin
					merge0[i/2].enq1(data);
				end else begin
					merge0[i/2].enq2(data);
				end
			endmethod
		endinterface: MergeSorterEpIfc;
	end

	interface enq = enq_;
	method Action runMerge(Bit#(42) count);
		runMergeQ.enq(count);
	endmethod
	method ActionValue#(Vector#(vcnt, inType)) get;
		let d <- merge3.get;
		return d;
	endmethod

endmodule

