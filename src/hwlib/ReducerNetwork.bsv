import FIFO::*;
import FIFOF::*;
import Vector::*;
//import SpecialFIFOs::*;

import MergeSorter::*;

import BRAMFIFO::*;

import Float32::*;

interface ReducerIfc#(type valType);
	method Action enq(valType val1, valType val2);
	method ActionValue#(valType) get;
endinterface

module mkReducerAdd(ReducerIfc#(valType))
	provisos(Bits#(valType,valTypeSz), Arith#(valType), Add#(32,a__,valTypeSz));

	FIFO#(valType) resQ <- mkFIFO;

	method Action enq(valType val1, valType val2);
		resQ.enq(val1+val2);
	endmethod
	method ActionValue#(valType) get;
		resQ.deq;
		return resQ.first;
	endmethod
endmodule

module mkReducerFloatMult(ReducerIfc#(valType))
	provisos(Bits#(valType,valTypeSz), Arith#(valType), Add#(32,a__,valTypeSz));

	//FIFO#(Bit#(32)) resQ <- mkSizedFIFO(8);
	FIFO#(Bit#(32)) resQ <- mkFIFO;
	FpPairIfc fp_mult32 <- mkFpMult32;
	rule getv;
		fp_mult32.deq;
		resQ.enq(fp_mult32.first);
	endrule

	method Action enq(valType val1, valType val2);
		fp_mult32.enq(truncate(pack(val1)),truncate(pack(val2)));
	endmethod
	method ActionValue#(valType) get;
		resQ.deq;
		return unpack(zeroExtend(resQ.first));
	endmethod
endmodule

module mkReducerFirst(ReducerIfc#(valType))
	provisos(Bits#(valType,valTypeSz), Arith#(valType), Add#(32,a__,valTypeSz));
	FIFO#(valType) resQ <- mkFIFO;

	method Action enq(valType val1, valType val2);
		resQ.enq(val1);
	endmethod
	method ActionValue#(valType) get;
		resQ.deq;
		return resQ.first;
	endmethod
endmodule

module mkReducerAddMC(ReducerIfc#(valType))
	provisos(Bits#(valType,valTypeSz), Arith#(valType), Add#(32,a__,valTypeSz));
	FIFO#(Tuple2#(valType,valType)) inQ <- mkFIFO;
	FIFO#(valType) resQ <- mkFIFO;
	Reg#(Bit#(16)) cyclesUp <- mkReg(0);
	Reg#(Bit#(16)) cyclesDn <- mkReg(0);
	rule redcycle(cyclesUp-cyclesDn >0);
		cyclesDn <= cyclesDn + 1;
	endrule
	rule addvl(cyclesUp-cyclesDn==0);
		inQ.deq;
		resQ.enq(tpl_1(inQ.first)+tpl_2(inQ.first));
	endrule

	method Action enq(valType val1, valType val2) if ( cyclesUp-cyclesDn == 0 );
		inQ.enq(tuple2(val1,val2));
		cyclesUp <= cyclesUp + 8;
	endmethod
	method ActionValue#(valType) get;
		resQ.deq;
		return resQ.first;
	endmethod
endmodule

interface CompareAndMergeIfc#(type keyType, type valType);
	method Action enq(Maybe#(Tuple2#(keyType, valType)) data1, Maybe#(Tuple2#(keyType,valType)) data2);

	method ActionValue#(Tuple2#(Maybe#(Tuple2#(keyType, valType)),Maybe#(Tuple2#(keyType, valType)))) get;
endinterface

typedef enum {
	ReducerAdd,
	ReducerFloatMult,
	ReducerFirst
} ReducerType deriving(Eq);

module mkCompareAndShift#(Integer depth) (CompareAndMergeIfc#(keyType,valType))
	provisos(
		Bits#(keyType,keyTypeSz), Eq#(keyType), Add#(1,a__,keyTypeSz),
		Bits#(valType,valTypeSz), Arith#(valType), Add#(32,b__,valTypeSz)
	);
	
	FIFO#(Maybe#(Tuple2#(keyType, valType))) bypassQ1 <- mkSizedFIFO(depth);
	FIFO#(Maybe#(Tuple2#(keyType, valType))) bypassQ2 <- mkSizedFIFO(depth);
	
	method Action enq(Maybe#(Tuple2#(keyType, valType)) data1, Maybe#(Tuple2#(keyType,valType)) data2);
		if ( isValid(data1) ) begin
			bypassQ1.enq(data1);
			bypassQ2.enq(data2);
		end else begin
			bypassQ1.enq(data2); 
			bypassQ2.enq(tagged Invalid);
		end
	endmethod

	method ActionValue#(Tuple2#(Maybe#(Tuple2#(keyType, valType)),Maybe#(Tuple2#(keyType, valType)))) get;
		bypassQ1.deq;
		bypassQ2.deq;
		return tuple2(bypassQ1.first, bypassQ2.first);
	endmethod
endmodule


module mkCompareAndMerge#(ReducerType rtype, Integer depth) (CompareAndMergeIfc#(keyType,valType))
	provisos(
		Bits#(keyType,keyTypeSz), Eq#(keyType), Add#(1,a__,keyTypeSz),
		Bits#(valType,valTypeSz), Arith#(valType), Add#(32,b__,valTypeSz)
	);

	ReducerIfc#(valType) reducer;
	if ( rtype == ReducerAdd ) begin
		reducer <- mkReducerAdd;
	end else if ( rtype == ReducerFloatMult ) begin
		reducer <- mkReducerFloatMult;
	end else begin
		reducer <- mkReducerFirst;
	end

	FIFO#(Maybe#(keyType)) fromReducerQ <- mkSizedFIFO(depth);

	FIFO#(Maybe#(Tuple2#(keyType, valType))) bypassQ1 <- mkSizedFIFO(depth);
	FIFO#(Maybe#(Tuple2#(keyType, valType))) bypassQ2 <- mkSizedFIFO(depth);
	
	method Action enq(Maybe#(Tuple2#(keyType, valType)) data1, Maybe#(Tuple2#(keyType,valType)) data2);
		if (isValid(data1) && isValid(data2) ) begin
			let d1 = fromMaybe(?,data1);
			let d2 = fromMaybe(?,data2);
			if ( tpl_1(d1) == tpl_1(d2) ) begin
				reducer.enq(tpl_2(d1), tpl_2(d2));
				fromReducerQ.enq(tagged Valid tpl_1(d1));
			end else begin
				bypassQ1.enq(data1);
				bypassQ2.enq(data2);
				fromReducerQ.enq(tagged Invalid);
			end
		end else begin
			if ( isValid(data1) ) begin
				bypassQ1.enq(data1);
				bypassQ2.enq(tagged Invalid);
				fromReducerQ.enq(tagged Invalid);
			end
			else begin
				bypassQ1.enq(data2);
				bypassQ2.enq(tagged Invalid);
				fromReducerQ.enq(tagged Invalid);
			end
		end
	endmethod

	method ActionValue#(Tuple2#(Maybe#(Tuple2#(keyType, valType)),Maybe#(Tuple2#(keyType, valType)))) get;
		fromReducerQ.deq;
		let f = fromReducerQ.first;
		if ( isValid(f) ) begin
			let rv <- reducer.get;
			let rk = fromMaybe(?,f);
			let rp1 = tagged Valid tuple2(rk,rv);
			let rp2 = tagged Invalid;
			return tuple2(rp1,rp2);
		end else begin
			bypassQ1.deq;
			bypassQ2.deq;
			return tuple2(bypassQ1.first, bypassQ2.first);
		end
	endmethod
endmodule

interface StreamReducerIntraIfc#(numeric type vcnt, type keyType, type valType);
	method Action enq(Maybe#(Vector#(vcnt,Maybe#(Tuple2#(keyType,valType)))) data);
	method ActionValue#(Maybe#(Vector#(vcnt, Maybe#(Tuple2#(keyType,valType))))) get;
endinterface

module mkReducerIntra2#(ReducerType rtype, Integer depth) (StreamReducerIntraIfc #(vcnt,keyType, valType))
	provisos(
		Bits#(keyType,keyTypeSz), Eq#(keyType), Add#(1,a__,keyTypeSz),
		Bits#(valType,valTypeSz), Arith#(valType), Add#(32,b__,valTypeSz),
		Bits#(Vector#(vcnt, Maybe#(Tuple2#(keyType,valType))), tuplemvSz)
	);
	
	CompareAndMergeIfc#(keyType, valType) cam00 <- mkCompareAndMerge(rtype,depth);
	FIFO#(Bool) lastQ0 <- mkSizedFIFO(depth);
	FIFO#(Maybe#(Vector#(vcnt, Maybe#(Tuple2#(keyType,valType))))) outQ <- mkFIFO;

	rule recvmerged;
		Bool last = lastQ0.first;
		lastQ0.deq;

		if ( last ) begin
			outQ.enq(tagged Invalid);
		end else begin
			let r0 <- cam00.get;
			Vector#(vcnt, Maybe#(Tuple2#(keyType,valType))) ov = ?;
			ov[0] = tpl_1(r0);
			ov[1] = tpl_2(r0);
			outQ.enq(tagged Valid ov);
		end
	endrule

	method Action enq(Maybe#(Vector#(vcnt,Maybe#(Tuple2#(keyType,valType)))) data_);
		if ( isValid(data_) ) begin
			let data = fromMaybe(?,data_);
			cam00.enq(data[0], data[1]);
			lastQ0.enq(False);
		end else begin
			lastQ0.enq(True);
		end
	endmethod
	method ActionValue#(Maybe#(Vector#(vcnt, Maybe#(Tuple2#(keyType,valType))))) get;
		outQ.deq;
		return outQ.first;
	endmethod
endmodule

interface ReducerIntraIfc#(numeric type vcnt, type keyType, type valType);
	method Action enq(Vector#(vcnt,Maybe#(Tuple2#(keyType,valType))) data, Bool last);
	method ActionValue#(Tuple2#(Vector#(vcnt, Maybe#(Tuple2#(keyType,valType))),Bool)) get;
endinterface

module mkReducerIntra4#(ReducerType rtype, Integer depth) (ReducerIntraIfc #(4,keyType, valType))
	provisos(
		Bits#(keyType,keyTypeSz), Eq#(keyType), Add#(1,a__,keyTypeSz),
		Bits#(valType,valTypeSz), Arith#(valType), Add#(32,a__,valTypeSz)
	);

	CompareAndMergeIfc#(keyType, valType) cam00 <- mkCompareAndMerge(rtype,depth);
	CompareAndMergeIfc#(keyType, valType) cam01 <- mkCompareAndMerge(rtype,depth);
	FIFO#(Bool) lastQ0 <- mkSizedFIFO(depth);
	
	FIFO#(Maybe#(Tuple2#(keyType, valType))) bypassQ10 <- mkSizedFIFO(depth);
	FIFO#(Maybe#(Tuple2#(keyType, valType))) bypassQ11 <- mkSizedFIFO(depth);
	CompareAndMergeIfc#(keyType, valType) cam10 <- mkCompareAndMerge(rtype,depth);
	FIFO#(Bool) lastQ1 <- mkSizedFIFO(depth);

	rule relay0;
		let r0 <- cam00.get;
		let r1 <- cam01.get;

		bypassQ10.enq(tpl_1(r0));
		bypassQ11.enq(tpl_2(r1));

		cam10.enq(tpl_2(r0), tpl_1(r1));
		
		lastQ0.deq;
		lastQ1.enq(lastQ0.first);
	endrule
	
	CompareAndMergeIfc#(keyType, valType) cam20 <- mkCompareAndMerge(rtype,depth);
	CompareAndMergeIfc#(keyType, valType) cas21 <- mkCompareAndShift(depth);
	FIFO#(Bool) lastQ2 <- mkSizedFIFO(depth);

	rule relay1;
		bypassQ10.deq;
		bypassQ11.deq;
		let b0 = bypassQ10.first;
		let b1 = bypassQ11.first;
		let r0 <- cam10.get;

		cam20.enq(b0, tpl_1(r0));
		cas21.enq(tpl_2(r0), b1);
		
		lastQ1.deq;
		lastQ2.enq(lastQ1.first);
	endrule

	FIFO#(Maybe#(Tuple2#(keyType, valType))) bypassQ30 <- mkFIFO;
	FIFO#(Maybe#(Tuple2#(keyType, valType))) bypassQ31 <- mkFIFO;
	CompareAndMergeIfc#(keyType, valType) cas30 <- mkCompareAndShift(depth);
	FIFO#(Bool) lastQ3 <- mkSizedFIFO(depth);

	rule relay2;
		let r0 <- cam20.get;
		let r1 <- cas21.get;
		bypassQ30.enq(tpl_1(r0));
		bypassQ31.enq(tpl_2(r1));
		cas30.enq(tpl_2(r0), tpl_1(r1));

		lastQ2.deq;
		lastQ3.enq(lastQ2.first);
	endrule

	//method Action enq(Vector#(4,Tuple2#(keyType,valType)) data);
	method Action enq(Vector#(vcnt,Maybe#(Tuple2#(keyType,valType))) data, Bool last);
		cam00.enq(data[0], data[1]);
		cam01.enq(data[2], data[3]);
		lastQ0.enq(last);
		//cam00.enq(tagged Valid data[0], tagged Valid data[1]);
		//cam01.enq(tagged Valid data[2], tagged Valid data[3]);
	endmethod
	method ActionValue#(Tuple2#(Vector#(4, Maybe#(Tuple2#(keyType,valType))),Bool)) get;
		bypassQ30.deq;
		bypassQ31.deq;
		lastQ3.deq;
		let b0 = bypassQ30.first;
		let b1 = bypassQ31.first;
		let r0 <- cas30.get;

		Vector#(4, Maybe#(Tuple2#(keyType,valType))) ret;
		ret[0] = b0;
		ret[1] = tpl_1(r0);
		ret[2] = tpl_2(r0);
		ret[3] = b1;

		return tuple2(ret,lastQ3.first);
	endmethod
endmodule

/*
module mkReducerIntra#(ReducerType rtype, Integer depth) (ReducerIntraIfc#(vcnt, inType))
	provisos(Bits#(inType,inTypeSz), Ord#(inType), Add#(1,a__,inTypeSz));
	
	method Action enq(Vector#(vcnt,inType) data);
	endmethod
	method ActionValue#(Vector#(vcnt, Maybe#(inType))) get;
		return ?;
	endmethod
endmodule
*/

interface StreamingVectorAlignerIfc#(numeric type vcnt, type inType);
	method Action enq(Maybe#(Vector#(vcnt, Maybe#(inType))) data);
	method ActionValue#(Maybe#(Vector#(vcnt, Maybe#(inType)))) get;
endinterface

module mkStreamingVectorAligner (StreamingVectorAlignerIfc#(vcnt, inType))
	provisos(Bits#(inType,inTypeSz), Add#(1,a__,inTypeSz));
	Integer iVcnt = valueOf(vcnt);
	
	method Action enq(Maybe#(Vector#(vcnt, Maybe#(inType))) data);
	endmethod
	method ActionValue#(Maybe#(Vector#(vcnt, Maybe#(inType)))) get;
		return ?;
	endmethod
endmodule


interface VectorAlignerIfc#(numeric type vcnt, type inType);
	method Action enq(Vector#(vcnt, Maybe#(inType)) data, Bool last);
	method ActionValue#(Tuple2#(Vector#(vcnt, Maybe#(inType)),Bool)) get;
endinterface

module mkVectorAligner4 (VectorAlignerIfc#(4, inType))
	provisos(Bits#(inType,inTypeSz), Add#(1,a__,inTypeSz));
	Integer ivcnt = 4;

	Vector#(4, FIFO#(Maybe#(inType))) inQ <- replicateM(mkSizedFIFO(4));
	FIFO#(Bit#(8)) inCntQ <- mkFIFO;
	FIFO#(Bool) lastQ <- mkFIFO;
	FIFO#(Bool) flushQ <- mkSizedFIFO(8);
	FIFO#(Bool) flushLastQ <- mkSizedFIFO(8);
	
	Reg#(Bit#(8)) nextOff <- mkReg(0);

	FIFO#(Bit#(8)) shiftCntQ <- mkFIFO;

	rule startshift;
		inCntQ.deq;
		let cnt = inCntQ.first;

		let islast = lastQ.first;
		lastQ.deq;

		shiftCntQ.enq(nextOff);
		
		$display( "startshift %d %d %s", nextOff, cnt, islast?"last":"not" );

		if ( islast ) begin
			nextOff <= 0;
			
			let noff = nextOff+cnt;

			if ( noff >= fromInteger(ivcnt) ) begin
				flushQ.enq(True);
				flushLastQ.enq(True);
			end else begin
				flushQ.enq(False);
				flushLastQ.enq(True);
			end
		end else begin
			let noff = nextOff+cnt;
			if ( noff >= fromInteger(ivcnt) ) begin
				nextOff <= noff-fromInteger(ivcnt);
				flushQ.enq(True);
				flushLastQ.enq(False);
			end else begin
				nextOff <= noff;
				flushQ.enq(False);
				flushLastQ.enq(False);
			end
		end

	endrule

	Vector#(4, FIFO#(Maybe#(inType))) shQ0 <- replicateM(mkFIFO);
	FIFO#(Bit#(8)) shiftCntQ0 <- mkFIFO;
	Vector#(4, FIFO#(Maybe#(inType))) shQ1 <- replicateM(mkFIFO);
	FIFO#(Bit#(8)) shiftCntQ1 <- mkFIFO;
	Vector#(4, FIFOF#(Maybe#(inType))) shQ2 <- replicateM(mkFIFOF);

	rule doshift0;
		shiftCntQ.deq;
		let cnt = shiftCntQ.first;

		$display( "shift0" );

		if ( cnt > 0 ) begin
			for ( Integer i = 0; i < ivcnt; i=i+1 ) begin
				inQ[i].deq;
				shQ0[(i+1)%ivcnt].enq(inQ[i].first);
			end
			shiftCntQ0.enq(cnt-1);
		end else begin
			for ( Integer i = 0; i < ivcnt; i=i+1 ) begin
				inQ[i].deq;
				shQ0[i].enq(inQ[i].first);
			end
			shiftCntQ0.enq(0);
		end
	endrule

	rule doshift1;
		shiftCntQ0.deq;
		let cnt = shiftCntQ0.first;
		$display( "shift1" );

		if ( cnt > 0 ) begin
			for ( Integer i = 0; i < ivcnt; i=i+1 ) begin
				shQ0[i].deq;
				shQ1[(i+1)%ivcnt].enq(shQ0[i].first);
			end
			shiftCntQ1.enq(cnt-1);
		end else begin
			for ( Integer i = 0; i < ivcnt; i=i+1 ) begin
				shQ0[i].deq;
				shQ1[i].enq(shQ0[i].first);
			end
			shiftCntQ1.enq(0);
		end
	endrule

	FIFO#(Bool) flushNowQ <- mkFIFO;
	FIFO#(Bool) lastNowQ <- mkFIFO;
	rule doshift2;
		shiftCntQ1.deq;
		let cnt = shiftCntQ1.first;
		$display( "shift2" );

		if ( cnt > 0 ) begin
			for ( Integer i = 0; i < ivcnt; i=i+1 ) begin
				shQ1[i].deq;
				let d = shQ1[i].first;
				if (isValid(d)) begin
					shQ2[(i+1)%ivcnt].enq(d);
				end
			end
		end else begin
			for ( Integer i = 0; i < ivcnt; i=i+1 ) begin
				shQ1[i].deq;
				let d = shQ1[i].first;
				if (isValid(d)) begin
					shQ2[i].enq(d);
				end
			end
		end

		flushQ.deq;
		flushLastQ.deq;
		let nflush = flushQ.first;
		let nlast = flushLastQ.first;
		if ( nflush || nlast ) begin
			flushNowQ.enq(nflush);
			lastNowQ.enq(nlast);
		end
		$display( "Enq flushnow last" );
	endrule

	Vector#(4, FIFO#(Maybe#(inType))) outQ <- replicateM(mkFIFO);
	FIFO#(Bool) outLastQ <- mkFIFO;
	Reg#(Bool) isFirstOut <- mkReg(False);
	rule outputres( !isFirstOut );
		flushNowQ.deq;
		lastNowQ.deq;

		let nflush = flushNowQ.first;
		let nlast = lastNowQ.first;


		if ( !nflush && nlast ) begin
			outLastQ.enq(True);
		end
		else begin
			outLastQ.enq(False);
		end

		if ( nflush && nlast ) begin
			isFirstOut <= True;
		end
		
		$display( "output1" );
		
		for ( Integer i = 0; i < ivcnt; i=i+1 ) begin
			if ( shQ2[i].notEmpty ) begin
				shQ2[i].deq;
				outQ[i].enq(shQ2[i].first);
			end
			else begin
				outQ[i].enq(tagged Invalid);
			end
		end
	endrule
	rule outputres2 (isFirstOut);
		isFirstOut <= False;
		
		$display( "output2" );
		outLastQ.enq(True);
		
		for ( Integer i = 0; i < ivcnt; i=i+1 ) begin
			if ( shQ2[i].notEmpty ) begin
				shQ2[i].deq;
				outQ[i].enq(shQ2[i].first);
			end
			else begin
				outQ[i].enq(tagged Invalid);
			end
		end
	endrule

	method Action enq(Vector#(vcnt, Maybe#(inType)) data, Bool last);
		Integer validcnt = 0;
		for (Integer i = 0; i < ivcnt; i=i+1 ) begin
			if ( isValid(data[i]) ) validcnt = validcnt + 1;
			inQ[i].enq(data[i]);
		end
		inCntQ.enq(fromInteger(validcnt));
		lastQ.enq(last);
	endmethod
	method ActionValue#(Tuple2#(Vector#(vcnt, Maybe#(inType)),Bool)) get;
		Vector#(vcnt, Maybe#(inType)) retv;
		for (Integer i = 0; i < ivcnt; i=i+1 ) begin
			outQ[i].deq;
			retv[i] = outQ[i].first;
		end
		outLastQ.deq;
		return tuple2(retv,outLastQ.first);
	endmethod
endmodule

/*

module mkVertexAligner (vcnt, inType)
	provisos(Bits#(inType,inTypeSz), Add#(1,a__,inTypeSz));
	Integer ivcnt = valueOf(vcnt);
	
	Vector#(vcnt, FIFO#(Maybe#(inType))) inQ <- replicateM(mkFIFO);
	FIFO#(Bit#(8)) inCntQ <- mkFIFO;

	Vector#(vcnt, FIFO#(Maybe#(inType))) alignedQ <- replicateM(mkSizedFIFO(4));
	FIFO#(Bool) lastQ <- mkSizedFIFO(4);

	Reg#(Bit#(8)) nextOff <- mkReg(0);

	FIFO#(Bit#(8)) shiftCntQ <- mkFIFO;

	rule startshift;
		inCntQ.deq;
		let cnt = inCntQ.first;
		let shcnt = nextOff;
		nextOff <= (nextOff + cnt)%ivcnt;

		shiftCntQ.enq(shcnt);
	endrule

	for (Integer shi = 0; shi < ivcnt-1; shi=shi+1 ) begin
		rule doshift;
			if ( shi==0 ) begin
				
			end else begin
			end
		endrule
	end

	




	method Action enq(Vector#(vcnt, Maybe#(inType) data, Bool last);
		Integer validcnt = 0;
		for (Integer i = 0; i < ivcnt; i=i+1 ) begin
			if ( isValid(data[i]) ) validcnt = validcnt + 1;
			inQ[i].enq(data[i]);
		end
		inCntQ.enq(fromInteger(validcnt));
	endmethod
	method ActionValue#(Tuple2#(Bool,Vector#(vcnt, Maybe#(inType)))) get;
		lastQ.deq;
		Vector#(vcnt, Maybe#(inType)) retv;
		for (Integer i = 0; i < ivcnt; i=i+1 ) begin
			alignedQ[i].deq;
			retv[i] = alignedQ[i].first;
		end
		return tuple2(lastQ.first, retv);
	endmethod
endmodule
*/

/*
interface ReducerLoopIfc#(numeric type vcnt, type keyType, type valType);
	method Action enq(Vector#(vcnt, Maybe#(Tuple2#(keyType,valType))) data, Bool last);
	method ActionValue#(Tuple2#(Vector#(vcnt, Maybe#(Tuple2#(keyType,valType))),Bool last)) get;
endinterface
*/

interface CheckUniqueIfc#(numeric type vcnt, type keyType, type valType);
	method Action enq(Vector#(vcnt, Maybe#(Tuple2#(keyType,valType))) data, Bool last);
	method ActionValue#(Tuple3#(Vector#(vcnt, Maybe#(Tuple2#(keyType,valType))),Bool,Bool)) get;
endinterface

module mkCheckUnique (CheckUniqueIfc#(vcnt, keyType, valType))
	provisos(
		Bits#(keyType,keyTypeSz), Eq#(keyType), Add#(1,a__,keyTypeSz),
		Bits#(valType,valTypeSz), Arith#(valType), Add#(1,a__,valTypeSz)
	);

	Integer ivcnt = valueOf(vcnt);

	Vector#(vcnt,FIFO#(Vector#(vcnt, Maybe#(Tuple2#(keyType,valType))))) inQ <- replicateM(mkFIFO);
	Vector#(vcnt,FIFO#(Bool)) lastQ <- replicateM(mkFIFO);
	Vector#(vcnt,FIFO#(Bool)) nuniqueQ <- replicateM(mkFIFO);

	for ( Integer ii = 0; ii < ivcnt-1; ii=ii+1 ) begin
		rule relaycheck;
			inQ[ii].deq;
			lastQ[ii].deq;
			nuniqueQ[ii].deq;
			let d = inQ[ii].first;
			let last = lastQ[ii].first;
			let nunique = nuniqueQ[ii].first;


			lastQ[ii+1].enq(last);
			inQ[ii+1].enq(d);

			if ( isValid(d[ii]) && isValid(d[ii+1]) && tpl_1(fromMaybe(?,d[ii])) != tpl_1(fromMaybe(?,d[ii+1]))) begin
				nuniqueQ[ii+1].enq(True);
			end else begin
				nuniqueQ[ii+1].enq(nunique);
			end
		endrule
	end

	method Action enq(Vector#(vcnt, Maybe#(Tuple2#(keyType,valType))) data, Bool last);
		inQ[0].enq(data);
		lastQ[0].enq(last);
		nuniqueQ[0].enq(False);
	endmethod
	method ActionValue#(Tuple3#(Vector#(vcnt, Maybe#(Tuple2#(keyType,valType))),Bool,Bool)) get;
		inQ[ivcnt-1].deq;
		lastQ[ivcnt-1].deq;
		nuniqueQ[ivcnt-1].deq;

		return tuple3(inQ[ivcnt-1].first,lastQ[ivcnt-1].first,nuniqueQ[ivcnt-1].first);
	endmethod
endmodule
/*
module mkReducerLoop4#(ReducerType rtype, Integer rdepth, Integer bcnt) (ReducerIntraIfc#(4, keyType, valType))
	provisos(
		Bits#(keyType,keyTypeSz), Eq#(keyType), Add#(1,a__,keyTypeSz),
		Bits#(valType,valTypeSz), Arith#(valType), Add#(1,a__,valTypeSz),
		Add#(1, b__, TAdd#(valTypeSz, valTypeSz))
	);

	Integer ivcnt = 4;// valueOf(vcnt);

	FIFO#(Tuple2#(Vector#(4, Maybe#(Tuple2#(keyType,valType))),Bool)) bufferQ <- mkSizedBRAMFIFO(bcnt);
	FIFO#(Tuple2#(Vector#(4, Maybe#(Tuple2#(keyType,valType))),Bool)) outQ <- mkFIFO;

	ReducerIntraIfc#(4,keyType,valType) rin <- mkReducerIntra4(rtype, rdepth);
	VectorAlignerIfc#(4, Tuple2#(keyType,valType)) aligner <- mkVectorAligner4;
	CheckUniqueIfc#(4,keyType,valType) checkunique <- mkCheckUnique;

	Reg#(Bit#(16)) inqcntUp <- mkReg(0);
	Reg#(Bit#(16)) inqcntDn <- mkReg(0);

	//FIFO#(Bool) rinLastQ <- mkSizedFIFO(
	rule insreducer;
		let r_ = bufferQ.first;
		bufferQ.deq;
		rin.enq(tpl_1(r_), tpl_2(r_));
	endrule

	rule insaligner;
		let r_ <- rin.get;
		aligner.enq(tpl_1(r_), tpl_2(r_));
	endrule

	rule getaligned;
		let r_ <- aligner.get;
		let data = tpl_1(r_);
		let last = tpl_2(r_);

		checkunique.enq(data,last);
	endrule

	Reg#(Bit#(16)) loopRemain <- mkReg(0);
	FIFOF#(Tuple2#(Vector#(4, Maybe#(Tuple2#(keyType,valType))),Bool)) loopQ <- mkFIFOF;

	rule getcheck ( loopRemain == 0 );
		let r_ <- checkunique.get;
		let data = tpl_1(r_);
		let last = tpl_2(r_);
		let nunique = tpl_3(r_);
		$display( "unique out?" );

		if ( nunique == False ) begin
			outQ.enq(tuple2(data,last));
			inqcntDn <= inqcntDn + 1;
		end else begin
			loopRemain <= (inqcntUp- inqcntDn)-1;
			loopQ.enq(tuple2(data,last));
		end
	endrule

	rule doloop ( loopRemain > 0 );
		let r_ <- checkunique.get;
		let data = tpl_1(r_);
		let last = tpl_2(r_);
		let nunique = tpl_3(r_);
			
		loopQ.enq(tuple2(data,last));

		loopRemain <= loopRemain - 1;
	endrule
	rule doloop2;
		loopQ.deq;
		bufferQ.enq(loopQ.first);
	endrule

	//method Action enq(Vector#(vcnt, Maybe#(Tuple2#(keyType,valType))) data, Bool last) if ( inqcntUp-inqcntDn < fromInteger(bcnt) );
	method Action enq(Vector#(4, Maybe#(Tuple2#(keyType,valType))) data, Bool last) if ( loopRemain == 0 && !loopQ.notEmpty );
		inqcntUp <= inqcntUp + 1;
		bufferQ.enq(tuple2(data,last));
	endmethod
	method ActionValue#(Tuple2#(Vector#(4, Maybe#(Tuple2#(keyType,valType))),Bool)) get;
		outQ.deq;
		return outQ.first;
	endmethod
endmodule
*/

/*
interface ReducerInterIfc#(numeric type vcnt, type keyType, type valType);
	method Action enq(Vector#(vcnt, Maybe#(Tuple2#(keyType,valType))) data, Bool last);
	method ActionValue#(Vector#(vcnt, Maybe#(Tuple2#(keyType,valType)))) get;
endinterface

module mkReducerInter (ReducerInterIfc#(vcnt, keyType, valType))
	provisos(
		Bits#(keyType,keyTypeSz), Eq#(keyType), Add#(1,a__,keyTypeSz),
		Bits#(valType,valTypeSz), Arith#(valType), Add#(1,a__,valTypeSz)
	);

	Integer ivcnt = valueOf(vcnt);

	Reg#(Maybe#(Vector#(vcnt, Maybe#(Tuple2#(keyType,valType))))) cache1 <- mkReg(tagged Invalid);
	//Reg#(Maybe#Vector#(vcnt, Maybe#(Tuple2#(keyType,valType))))) cache2 <- mkReg(tagged Invalid);
	
	FIFO#(Tuple#(Vector#(vcnt, Maybe#(Tuple2#(keyType,valType))),Bool)) inQ <- mkFIFO;

	rule initc(!isValid(cache1));
		inQ.deq;
		let inv = tpl_1(inQ.first);
		cache1 <= tagged Valid inv;
	endrule
	
	FIFO#(Tuple#(Vector#(TMul#(vcnt,2), Maybe#(Tuple2#(keyType,valType))),keyType)) outQ <- mkFIFO;

	rule proct(isValid(cache1));
		inQ.deq;
		let inv = inQ.first;

		let cv = fromMaybe(?, cache1);


		if ( isValid(cv[ivcnt-1]) && isValid(inv[ivcnt-1]) 
			&& fromMaybe(?,tpl_1(cv[ivcnt-1]))==fromMaybe(?,tpl_1(inv[ivcnt-1]))) begin
			// stop, loop

		end else begin
			keyType nk = tpl_1(cv[ivcnt-1]);
			outQ.enq({cv,inv}, nk);
			Vector#(vcnt, Maybe#(Tuple2#(keyType,valType))) nc;
			for ( Integer i = 0; i < ivcnt; i=i+1 ) begin
				if ( isValid(inv[i]) && fromMaybe(?,inv[i]) != nk ) begin
					nc[i] = inv[i];
				end else begin
					nc[i] = tagged Invalid;
				end
			end
		end
	endrule


	method Action enq(Vector#(vcnt, Maybe#(Tuple2#(keyType,valType))) data, Bool last);
		inQ.enq(tuple2(data,last))
	endmethod
	method ActionValue#(Vector#(vcnt, Maybe#(Tuple2#(keyType,valType)))) get;
		return ?;
	endmethod
endmodule
*/




/*
interface ReducerUnitIfc#(type keyType, type valType);
	method Action enq(keyType key, valType val, Bool last);
	method Action getToken;
	method Action putToken;
	method Tuple3#(keyType,valType,Bool) first;
	method Action deq;
endinterface

module mkReducerUnit#(ReducerType rtype, Bool lastunit, Integer index) (ReducerUnitIfc#(keyType,valType))
	provisos(
		Bits#(keyType,keyTypeSz), Eq#(keyType), Add#(1,a__,keyTypeSz),
		Bits#(valType,valTypeSz), Arith#(valType), Add#(1,a__,valTypeSz)
	);
	
	ReducerIfc#(valType) reducer;
	if ( rtype == ReducerAdd ) begin
		reducer <- mkReducerAddMC;
	end else if ( rtype == ReducerFloatMult ) begin
		reducer <- mkReducerFloatMult;
	end else begin
		reducer <- mkReducerFirst;
	end

	FIFO#(Tuple3#(keyType,valType,Bool)) inQ <- mkFIFO;
	FIFO#(Tuple3#(keyType,valType,Bool)) outQ <- mkFIFO;
	FIFO#(Bool) tokenInQ <- mkSizedFIFO(4);
	FIFOF#(Bool) tokenOutQ <- mkSizedFIFOF(4);
	
	Reg#(Maybe#(Tuple3#(keyType,valType,Bool))) curval <- mkReg(tagged Invalid);
	Reg#(Bool) inflight <- mkReg(False);
	Reg#(Bool) islast <- mkReg(False);
	rule procin(!islast && !inflight);
		tokenInQ.deq;
		inQ.deq;
		let d_ = inQ.first;

		let cd = fromMaybe(?,curval);

		if ( !isValid(curval) ) begin
			curval <= tagged Valid d_;
		end else if ( tokenOutQ.notEmpty && !lastunit ) begin
			outQ.enq(cd);
			curval <= tagged Valid d_;
			tokenOutQ.deq;
		end else if (tpl_1(cd) == tpl_1(d_) )  begin
			reducer.enq(tpl_2(cd), tpl_2(d_));
			inflight <= True;
		end else begin
			outQ.enq(cd);
			curval <= tagged Valid d_;
			tokenOutQ.deq;
		end
		islast <= tpl_3(d_);
	endrule

	rule recvreduce(inflight);
		inflight <= False;
		let rv <- reducer.get;
		let cd = fromMaybe(?,curval);
		curval <= tagged Valid tuple3(tpl_1(cd), rv, islast);
		$display("reduced %d", index);
	endrule

	rule flushlast(islast && !inflight);
		let cd = fromMaybe(?,curval);
		if ( isValid(curval) ) begin
			outQ.enq(cd);
			curval <= tagged Invalid;
			tokenOutQ.deq;
		end
	endrule




	method Action enq(keyType key, valType val, Bool last);
		inQ.enq(tuple3(key,val,last));
		//$display( "enq %d", index );

	endmethod
	method Action getToken; // This unit has space
		tokenInQ.enq(True);
	endmethod
	method Action putToken; // Next unit has space
		tokenOutQ.enq(True);
	endmethod
	method Tuple3#(keyType,valType,Bool) first;
		return outQ.first;
	endmethod
	method Action deq;
		//$display( "deq %d", index );
		outQ.deq;
	endmethod

endmodule
*/

interface StreamReducerIfc#(type keyType, type valType);
	method Action enq(Maybe#(Tuple2#(keyType, valType)) data);
	method ActionValue#(Maybe#(Tuple2#(keyType,valType))) get;
endinterface

//TODO problem if stream is shorter than stripecnt
module mkStripedReducer#(Integer stripecnt) (StreamReducerIfc#(Bit#(32),Bit#(32)));
	//Integer stripecnt = 8;

	Reg#(Bit#(32)) cycles <- mkReg(0);
	rule inccycles;
		cycles <= cycles + 1;
	endrule

	ReducerIfc#(Bit#(32)) reducer <- mkReducerFloatMult;
	//ReducerIfc#(Bit#(32)) reducer <- mkReducerAdd;
	FIFO#(Bit#(32)) reducedQ <- mkSizedFIFO(stripecnt);
	rule relayReduced;
		let v <- reducer.get;
		reducedQ.enq(v);
	endrule


	FIFO#(Tuple2#(Bit#(32),Maybe#(Bit#(32)))) stripeQ <- mkSizedFIFO(stripecnt*2);
	//Reg#(Bit#(8)) stripeQIn <- mkReg(0);
	Reg#(Bit#(8)) stripeQOut <- mkReg(0);

	FIFO#(Maybe#(Tuple2#(Bit#(32),Bit#(32)))) inQ <- mkFIFO;
	FIFO#(Maybe#(Tuple2#(Bit#(32),Bit#(32)))) outQ <- mkFIFO;

	Reg#(Bit#(8)) initCnt <- mkReg(0);

	Reg#(Bool) flushing <- mkReg(False);
	rule primein(!flushing && initCnt < fromInteger(stripecnt));
		let data = inQ.first;
		inQ.deq;

		let sd = fromMaybe(?, data);

		initCnt <= initCnt + 1;
		stripeQ.enq(tuple2(tpl_1(sd), tagged Valid tpl_2(sd)));
		// FIXME: error if stream is shorter than latency
	endrule

	rule procin(!flushing && initCnt >= fromInteger(stripecnt));
		inQ.deq;
		let inv = fromMaybe(?,inQ.first);
		Bool valid = isValid(inQ.first);

		
		if ( valid ) begin
			stripeQ.deq;
			let stv = stripeQ.first;
			let stvv = fromMaybe(?,tpl_2(stv));
			if ( !isValid(tpl_2(stv)) ) begin
				stvv = reducedQ.first;
				reducedQ.deq;
			end

			if ( tpl_1(inv) == tpl_1(stv) ) begin
				stripeQ.enq(tuple2(tpl_1(inv),tagged Invalid));
				reducer.enq(tpl_2(inv), stvv);
			end else begin
				stripeQ.enq(tuple2(tpl_1(inv),tagged Valid tpl_2(inv)));
				outQ.enq(tagged Valid tuple2(tpl_1(stv), stvv));
			end
		
		end else begin
			flushing <= True;
		end

	endrule

	rule flush(flushing && stripeQOut < fromInteger(stripecnt)); 
		stripeQ.deq;
		stripeQOut <= stripeQOut + 1;

		let stv = stripeQ.first;
		let stvv = fromMaybe(?,tpl_2(stv));
		if ( !isValid(tpl_2(stv)) ) begin
			stvv = reducedQ.first;
			reducedQ.deq;
		end
		outQ.enq(tagged Valid tuple2(tpl_1(stv), stvv));
	endrule

	rule  flushdone(flushing && stripeQOut >= fromInteger(stripecnt));
		outQ.enq(tagged Invalid);
		flushing <= False;
		stripeQOut <= 0;
		$display("Flushdone!");
	endrule


	method Action enq(Maybe#(Tuple2#(Bit#(32), Bit#(32))) data) if ( !flushing );
		//let data = tpl_1(data_);
		//let last = tpl_2(data_);
		
		/*
		let sd = fromMaybe(?, data);

		if ( initCnt < fromInteger(stripecnt) ) begin
			initCnt <= initCnt + 1;
			stripeQ.enq(tuple2(tpl_1(sd), tagged Valid tpl_2(sd)));
			// FIXME: error if stream is shorter than latency
		end else begin
			inQ.enq(data);
		end
		*/
			
		inQ.enq(data);
		
	endmethod
	method ActionValue#(Maybe#(Tuple2#(Bit#(32),Bit#(32)))) get;
		outQ.deq;

		return outQ.first; //tuple2(outQ.first, lastOutQ.first);
	endmethod
endmodule


interface MergeReduceIfc#(type keyType, type valType);
	method Action enq1(Maybe#(Tuple2#(keyType, valType)) data);
	method Action enq2(Maybe#(Tuple2#(keyType, valType)) data);
	method ActionValue#(Maybe#(Tuple2#(keyType, valType))) get;
endinterface

module mkMergeSortReducer#(Integer latency) (MergeReduceIfc#(Bit#(32), Bit#(32)));

	ReducerIfc#(Bit#(32)) reducer <- mkReducerFloatMult;
	FIFO#(Maybe#(Tuple2#(Bit#(32), Maybe#(Bit#(32))))) bypassQ <- mkSizedFIFO(latency);
	FIFO#(Maybe#(Tuple2#(Bit#(32), Bit#(32)))) inQ1 <- mkFIFO;
	FIFO#(Maybe#(Tuple2#(Bit#(32), Bit#(32)))) inQ2 <- mkFIFO;
	//Reg#(Bool) done1 <- mkReg(False);
	//Reg#(Bool) done2 <- mkReg(False);
	
	FIFO#(Maybe#(Tuple2#(Bit#(32), Bit#(32)))) outQ <- mkFIFO;


	rule comparein;
		let d1_ = inQ1.first;
		let d2_ = inQ2.first;
		Bool valid1 = isValid(d1_);
		Bool valid2 = isValid(d2_);
		let d1 = fromMaybe(?,d1_);
		let d2 = fromMaybe(?,d2_);

		let k1 = tpl_1(d1);
		let k2 = tpl_1(d2);
		if ( valid1 && valid2 ) begin
			if ( k1 == k2 ) begin
				let nv = tuple2(k1, tagged Invalid);
				bypassQ.enq( tagged Valid nv );
				reducer.enq(tpl_2(d1), tpl_2(d2));
				inQ1.deq;
				inQ2.deq;

			end else if ( k1 < k2 ) begin
				let nv = tuple2(k1, tagged Valid tpl_2(d1));
				bypassQ.enq( tagged Valid nv );
				inQ1.deq;
			end else begin
				let nv = tuple2(k2, tagged Valid tpl_2(d2));
				bypassQ.enq( tagged Valid nv );
				inQ2.deq;
			end
		end else if ( valid1 && !valid2 ) begin
			let nv = tuple2(k1, tagged Valid tpl_2(d1));
			bypassQ.enq( tagged Valid nv );
			inQ1.deq;
		end else if ( !valid1 && valid2 )begin
			let nv = tuple2(k2, tagged Valid tpl_2(d2));
			bypassQ.enq( tagged Valid nv );
			inQ2.deq;
		end else begin
			inQ1.deq;
			inQ2.deq;
			bypassQ.enq( tagged Invalid );
		end
	endrule


	rule recvred;
		bypassQ.deq;
		let v_ = bypassQ.first;
		Bool valid = isValid(v_);
		let v = fromMaybe(?,v_);

		if ( !valid ) begin
			outQ.enq(tagged Invalid);
		end else begin
			let mv = tpl_2(v);
			let k = tpl_1(v);

			let ov = fromMaybe(?,mv);
			if ( !isValid(mv) ) begin
				ov <- reducer.get;
			end

			let nv = tuple2(k,ov);
			outQ.enq(tagged Valid nv);
		end
	endrule

	method Action enq1(Maybe#(Tuple2#(Bit#(32), Bit#(32))) data);
		inQ1.enq(data);
	endmethod
	method Action enq2(Maybe#(Tuple2#(Bit#(32), Bit#(32))) data);
		inQ2.enq(data);
	endmethod
	method ActionValue#(Maybe#(Tuple2#(Bit#(32), Bit#(32)))) get;
		outQ.deq;
		return outQ.first;
	endmethod
endmodule

module mkSingleReducer8 (StreamReducerIfc#(Bit#(32), Bit#(32)));
	StreamReducerIfc#(Bit#(32),Bit#(32)) striped <- mkStripedReducer(8);
	Vector#(4,MergeReduceIfc#(Bit#(32),Bit#(32))) mrr0 <- replicateM(mkMergeSortReducer(8));
	Vector#(2,MergeReduceIfc#(Bit#(32),Bit#(32))) mrr1 <- replicateM(mkMergeSortReducer(8));
	MergeReduceIfc#(Bit#(32),Bit#(32)) mrr2 <- mkMergeSortReducer(8);

	
	Reg#(Bit#(4)) stdest <- mkReg(0);
	rule distributestripe;
		let nv <- striped.get;
		Bool valid = isValid(nv);
		let inv = fromMaybe(?,nv);
		if ( !valid ) begin
			for ( Integer i = 0; i < 4; i=i+1 ) begin
				mrr0[i].enq1(tagged Invalid);
				mrr0[i].enq2(tagged Invalid);
			end
			stdest <= 0;
		end else begin
			if ( stdest[0] == 0 ) begin
				mrr0[stdest/2].enq1(nv);
			end else begin
				mrr0[stdest/2].enq2(nv);
			end
			stdest <= (stdest + 1)%8;
		end
	endrule

	for ( Integer i = 0; i < 4; i=i+1 ) begin
		rule relay0;
			let v <- mrr0[i].get;
			if ( i%2 == 0 ) begin
				mrr1[i/2].enq1(v);
			end else begin
				mrr1[i/2].enq2(v);
			end
		endrule
	end
	for ( Integer i = 0; i < 2; i=i+1 ) begin
		rule relay1;
			let v <- mrr1[i].get;
			if ( i%2 == 0 ) begin
				mrr2.enq1(v);
			end else begin
				mrr2.enq2(v);
			end
		endrule
	end


	method Action enq(Maybe#(Tuple2#(Bit#(32), Bit#(32))) data);
		striped.enq(data);
	endmethod
	method ActionValue#(Maybe#(Tuple2#(Bit#(32),Bit#(32)))) get;
		let nv <- mrr2.get;
		return nv;
	endmethod
endmodule

interface MultiReducerIfc#(numeric type vcnt, type keyType, type valType);
	method Action enq1(Maybe#(Vector#(vcnt, Tuple2#(keyType, valType))) data);
	method Action enq2(Maybe#(Vector#(vcnt, Tuple2#(keyType, valType))) data);
	method ActionValue#(Maybe#(Vector#(vcnt, Tuple2#(keyType, valType)))) get;
endinterface



module mkMultiReducer#(Integer latency) (MultiReducerIfc#(vcnt, Bit#(32), Bit#(32)))
	provisos(
	Bits#(Vector#(vcnt,Tuple2#(Bit#(32),Bit#(32))), tuplevSz),
	Bits#(Vector#(vcnt,Maybe#(Tuple2#(Bit#(32),Bit#(32)))), tuplemvSz)
	);

	StreamVectorMergerIfc#(vcnt, Bit#(32), Bit#(32)) merger <- mkStreamVectorMerger(False);
	Integer iVcnt = valueOf(vcnt);

	Reg#(Maybe#(Vector#(vcnt,Tuple2#(Bit#(32),Bit#(32))))) buffer <- mkReg(tagged Invalid);
	Reg#(Bit#(2)) bufferType <- mkReg(0);
	//Reg#(Maybe#(Vector#(vcnt,Tuple2#(Bit#(32),Bit#(32))))) buffer2 <- mkReg(tagged Invalid);
	
	ReducerIfc#(Bit#(32)) reducer <- mkReducerFloatMult;
	FIFO#(Bit#(32)) reducedQ <- mkSizedFIFO(latency);
	rule relayreduced;
		let r <- reducer.get;
		reducedQ.enq(r);
	endrule

	FIFO#(Maybe#(Vector#(vcnt,Tuple2#(Bit#(32),Bit#(32))))) inQ <- mkSizedFIFO(latency+1);
	FIFO#(Bit#(2)) inTypeQ <- mkSizedFIFO(latency+1);

	Reg#(Bool) flushing <- mkReg(False);
	rule getmerger(!flushing);
		let r <- merger.get;
		buffer <= r;

		if ( !isValid(r) ) begin
			flushing <= True;
		end

		Bit#(2) inQType = bufferType;
		Bit#(2) bufferTypeNext = 0;
		if ( isValid(r) && isValid(buffer) ) begin
			Vector#(vcnt,Tuple2#(Bit#(32),Bit#(32))) d1 = fromMaybe(?, r); // later
			Vector#(vcnt,Tuple2#(Bit#(32),Bit#(32))) d2 = fromMaybe(?, buffer); // first
			Tuple2#(Bit#(32),Bit#(32)) firstLast = d2[iVcnt-1];
			Tuple2#(Bit#(32),Bit#(32)) laterFirst = d1[0];

			if ( tpl_1(firstLast) == tpl_1(laterFirst) ) begin
				reducer.enq(tpl_2(firstLast),tpl_2(laterFirst));
				inQType = inQType | 2'b10;
				bufferTypeNext = bufferTypeNext | 2'b01;
			end
		end
		bufferType <= bufferTypeNext;
		inQ.enq(buffer);
		inTypeQ.enq(inQType);
	endrule

	Reg#(Bit#(1)) flushStep <- mkReg(0);
	rule flushmgerger(flushing && flushStep == 0);
		bufferType <= 0;
		flushStep <= 1;
		
		inQ.enq(buffer);
		inTypeQ.enq(bufferType);
	endrule
	rule flushmgerger2(flushing && flushStep == 1);
		flushing <= False;
		flushStep <= 0;

		inQ.enq(tagged Invalid);
		inTypeQ.enq(0);
	endrule

			
	FIFO#(Maybe#(Vector#(vcnt, Maybe#(Tuple2#(Bit#(32),Bit#(32)))))) internalReduceQ <- mkFIFO;

	rule relayReduced;
		let inv_ = inQ.first;
		inQ.deq;
		let intype = inTypeQ.first;
		inTypeQ.deq;

		if ( isValid(inv_) ) begin

			let inv = fromMaybe(?, inv_);

			Vector#(vcnt, Maybe#(Tuple2#(Bit#(32),Bit#(32)))) iv;


			if ( (intype | 2'b01) > 0 ) begin // ignore first
				iv[0] = tagged Invalid;
			end else begin
				iv[0] = tagged Valid inv[0];
			end
			
			if ( (intype | 2'b10) > 0 ) begin // reduced 'later'
				reducedQ.deq;
				iv[iVcnt-1] = tagged Valid tuple2(tpl_1(inv[iVcnt-1]),reducedQ.first);
			end else begin
				iv[iVcnt-1] = tagged Valid inv[iVcnt-1];
			end

			for ( Integer i = 1; i < iVcnt-1; i=i+1 ) begin
				iv[i] = tagged Valid inv[i];
			end
			internalReduceQ.enq(tagged Valid iv);

		end else begin
			internalReduceQ.enq(tagged Invalid);
		end
	endrule
	
	StreamReducerIntraIfc#(vcnt,Bit#(32),Bit#(32)) sr;
	if ( iVcnt == 2 ) begin
		sr <- mkReducerIntra2(ReducerFloatMult, 8);
	end

	rule pushIntraReduce;
		let inv_ = internalReduceQ.first;
		internalReduceQ.deq;
		sr.enq(inv_);
	endrule

	method Action enq1(Maybe#(Vector#(vcnt, Tuple2#(Bit#(32), Bit#(32)))) data);
		merger.enq1(data);
	endmethod
	method Action enq2(Maybe#(Vector#(vcnt, Tuple2#(Bit#(32), Bit#(32)))) data);
		merger.enq2(data);
	endmethod
	method ActionValue#(Maybe#(Vector#(vcnt, Tuple2#(Bit#(32), Bit#(32))))) get;
		//FIXME should be aligned!
		let r <- sr.get;
		return ?;
	endmethod
endmodule
