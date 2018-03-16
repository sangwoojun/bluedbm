import FIFO::*;
import FIFOF::*;
import Vector::*;

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


interface CompareAndMergeIfc#(type keyType, type valType);
	method Action enq(Maybe#(Tuple2#(keyType, valType)) data1, Maybe#(Tuple2#(keyType,valType)) data2);

	method ActionValue#(Tuple2#(Maybe#(Tuple2#(keyType, valType)),Maybe#(Tuple2#(keyType, valType)))) get;
endinterface

typedef enum {
	ReducerAdd
	//ReducerFirst,
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
	method Action enq(Vector#(vcnt,Tuple2#(keyType,valType)) data);
	method ActionValue#(Vector#(vcnt, Maybe#(Tuple2#(keyType,valType)))) get;
endinterface

module mkReducerIntra4#(ReducerType rtype, Integer depth) (ReducerIntraIfc #(4,keyType, valType))
	provisos(
		Bits#(keyType,keyTypeSz), Eq#(keyType), Add#(1,a__,keyTypeSz),
		Bits#(valType,valTypeSz), Arith#(valType), Add#(1,a__,valTypeSz)
	);

	CompareAndMergeIfc#(keyType, valType) cam00 <- mkCompareAndMerge(rtype,depth);
	CompareAndMergeIfc#(keyType, valType) cam01 <- mkCompareAndMerge(rtype,depth);
	
	FIFO#(Maybe#(Tuple2#(keyType, valType))) bypassQ10 <- mkSizedFIFO(depth);
	FIFO#(Maybe#(Tuple2#(keyType, valType))) bypassQ11 <- mkSizedFIFO(depth);
	CompareAndMergeIfc#(keyType, valType) cam10 <- mkCompareAndMerge(rtype,depth);

	rule relay0;
		let r0 <- cam00.get;
		let r1 <- cam01.get;

		bypassQ10.enq(tpl_1(r0));
		bypassQ11.enq(tpl_2(r1));

		cam10.enq(tpl_2(r0), tpl_1(r1));
	endrule
	
	CompareAndMergeIfc#(keyType, valType) cam20 <- mkCompareAndMerge(rtype,depth);
	CompareAndMergeIfc#(keyType, valType) cas21 <- mkCompareAndShift(depth);

	rule relay1;
		bypassQ10.deq;
		bypassQ11.deq;
		let b0 = bypassQ10.first;
		let b1 = bypassQ11.first;
		let r0 <- cam10.get;

		cam20.enq(b0, tpl_1(r0));
		cas21.enq(tpl_2(r0), b1);
	endrule

	FIFO#(Maybe#(Tuple2#(keyType, valType))) bypassQ30 <- mkFIFO;
	FIFO#(Maybe#(Tuple2#(keyType, valType))) bypassQ31 <- mkFIFO;
	CompareAndMergeIfc#(keyType, valType) cas30 <- mkCompareAndShift(depth);

	rule relay2;
		let r0 <- cam20.get;
		let r1 <- cas21.get;
		bypassQ30.enq(tpl_1(r0));
		bypassQ31.enq(tpl_2(r1));
		cas30.enq(tpl_2(r0), tpl_1(r1));
	endrule

	method Action enq(Vector#(4,Tuple2#(keyType,valType)) data);
		cam00.enq(tagged Valid data[0], tagged Valid data[1]);
		cam01.enq(tagged Valid data[2], tagged Valid data[3]);
	endmethod
	method ActionValue#(Vector#(4, Maybe#(Tuple2#(keyType,valType)))) get;
		bypassQ30.deq;
		bypassQ31.deq;
		let b0 = bypassQ30.first;
		let b1 = bypassQ31.first;
		let r0 <- cas30.get;

		Vector#(4, Maybe#(Tuple2#(keyType,valType))) ret;
		ret[0] = b0;
		ret[1] = tpl_1(r0);
		ret[2] = tpl_2(r0);
		ret[3] = b1;

		return ret;
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
	method ActionValue#(Tuple2#(Bool,Vector#(vcnt, Maybe#(inType)))) get;
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
	method ActionValue#(Tuple2#(Bool,Vector#(vcnt, Maybe#(inType)))) get;
		Vector#(vcnt, Maybe#(inType)) retv;
		for (Integer i = 0; i < ivcnt; i=i+1 ) begin
			outQ[i].deq;
			retv[i] = outQ[i].first;
		end
		outLastQ.deq;
		return tuple2(outLastQ.first, retv);
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
