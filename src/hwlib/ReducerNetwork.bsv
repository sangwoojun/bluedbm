import FIFO::*;
import FIFOF::*;
import Vector::*;

import BRAMFIFO::*;

import Float32::*;

interface ReducerIfc#(type valType);
	method Action enq(valType val1, valType val2);
	method ActionValue#(valType) get;
endinterface

module mkReducerAdd(ReducerIfc#(valType))
	provisos(Bits#(valType,valTypeSz), Arith#(valType), Add#(1,a__,valTypeSz));

	FIFO#(valType) resQ <- mkFIFO;

	method Action enq(valType val1, valType val2);
		resQ.enq(val1+val2);
	endmethod
	method ActionValue#(valType) get;
		resQ.deq;
		return resQ.first;
	endmethod
endmodule

module mkReducerFloatMult(ReducerIfc#(Bit#(32)));

	FIFO#(Bit#(32)) resQ <- mkSizedFIFO(8);
	FpPairIfc fp_mult32 <- mkFpMult32;
	rule getv;
		fp_mult32.deq;
		resQ.enq(fp_mult32.first);
	endrule

	method Action enq(Bit#(32) val1, Bit#(32) val2);
		fp_mult32.enq(val1,val2);
	endmethod
	method ActionValue#(Bit#(32)) get;
		resQ.deq;
		return resQ.first;
	endmethod
endmodule

module mkReducerFirst(ReducerIfc#(valType))
	provisos(Bits#(valType,valTypeSz), Arith#(valType), Add#(1,a__,valTypeSz));
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
	provisos(Bits#(valType,valTypeSz), Arith#(valType), Add#(1,a__,valTypeSz));
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
		Bits#(valType,valTypeSz), Arith#(valType), Add#(1,a__,valTypeSz)
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
		Bits#(valType,valTypeSz), Arith#(valType), Add#(1,a__,valTypeSz)
	);

	ReducerIfc#(valType) reducer;
	if ( rtype == ReducerAdd ) begin
		reducer <- mkReducerAdd;
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

interface ReducerIntraIfc#(numeric type vcnt, type keyType, type valType);
	method Action enq(Vector#(vcnt,Maybe#(Tuple2#(keyType,valType))) data, Bool last);
	method ActionValue#(Tuple2#(Vector#(vcnt, Maybe#(Tuple2#(keyType,valType))),Bool)) get;
endinterface

module mkReducerIntra4#(ReducerType rtype, Integer depth) (ReducerIntraIfc #(4,keyType, valType))
	provisos(
		Bits#(keyType,keyTypeSz), Eq#(keyType), Add#(1,a__,keyTypeSz),
		Bits#(valType,valTypeSz), Arith#(valType), Add#(1,a__,valTypeSz)
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

interface VertexAlignerIfc#(numeric type vcnt, type inType);
	method Action enq(Vector#(vcnt, Maybe#(inType)) data, Bool last);
	method ActionValue#(Tuple2#(Vector#(vcnt, Maybe#(inType)),Bool)) get;
endinterface

module mkVertexAligner4 (VertexAlignerIfc#(4, inType))
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
	VertexAlignerIfc#(4, Tuple2#(keyType,valType)) aligner <- mkVertexAligner4;
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

interface StripedReducerIfc#(type keyType, type valType);
	method Action enq(Tuple2#(keyType, valType) data, Bool last);
	method ActionValue#(Tuple2#(Tuple2#(keyType,valType),Bool)) get;
endinterface

//TODO tag last
module mkStripedReducer#(Integer stripecnt) (StripedReducerIfc#(Bit#(32),Bit#(32)));
	//Integer stripecnt = 8;

	ReducerIfc#(Bit#(32)) reducer <- mkReducerFloatMult;
	//ReducerIfc#(Bit#(32)) reducer <- mkReducerAdd;
	FIFO#(Bit#(32)) reducedQ <- mkSizedFIFO(stripecnt);
	rule relayReduced;
		let v <- reducer.get;
		reducedQ.enq(v);
	endrule


	FIFO#(Tuple2#(Bit#(32),Maybe#(Bit#(32)))) stripeQ <- mkSizedFIFO(stripecnt+1);
	//Reg#(Bit#(8)) stripeQIn <- mkReg(0);
	Reg#(Bit#(8)) stripeQOut <- mkReg(0);

	FIFO#(Tuple2#(Bit#(32),Bit#(32))) inQ <- mkFIFO;
	FIFO#(Bool) lastQ <- mkFIFO;

	FIFO#(Tuple2#(Bit#(32),Bit#(32))) outQ <- mkFIFO;
	FIFO#(Bool) lastOutQ <- mkFIFO;

	Reg#(Bit#(8)) initCnt <- mkReg(0);

	Reg#(Bool) flushing <- mkReg(False);
	rule procin(!flushing);
		inQ.deq;
		let inv = inQ.first;
		lastQ.deq;
		let last = lastQ.first;

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
			outQ.enq(tuple2(tpl_1(stv), stvv));
			lastOutQ.enq(False);
		end

		if ( last ) flushing <= True;
	endrule

	rule flushdone(flushing); 
		stripeQ.deq;
		stripeQOut <= stripeQOut + 1;

		Bool lasto = False;
		if ( stripeQOut + 1 >= fromInteger(stripecnt) ) begin
			flushing <= False;
			lasto = True;
		end

		let stv = stripeQ.first;
		let stvv = fromMaybe(?,tpl_2(stv));
		if ( !isValid(tpl_2(stv)) ) begin
			stvv = reducedQ.first;
			reducedQ.deq;
		end
		outQ.enq(tuple2(tpl_1(stv), stvv));
		lastOutQ.enq(lasto);
	endrule


	method Action enq(Tuple2#(Bit#(32), Bit#(32)) data, Bool last);
		if ( initCnt < fromInteger(stripecnt) ) begin
			initCnt <= initCnt + 1;
			stripeQ.enq(tuple2(tpl_1(data), tagged Valid tpl_2(data)));
		end else begin
			inQ.enq(data);
			lastQ.enq(last);
		end
	endmethod
	method ActionValue#(Tuple2#(Tuple2#(Bit#(32),Bit#(32)),Bool)) get;
		outQ.deq;
		lastOutQ.deq;

		return tuple2(outQ.first, lastOutQ.first);
	endmethod
endmodule


