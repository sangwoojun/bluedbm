package SubString;

import Vector::*;
import FIFO::*;
import GetPut::*;
import BoolMergeNet::*;

// input data needs to be aligned to qlen
// data width is the same as qlen for simplicity
interface SubStringFindAlignedIfc#(numeric type qlen);
	method Action queryString(Bit#(TMul#(qlen, 8)) data); // qlen characters
	method Action dataString(Bit#(TMul#(qlen, 8)) data, Bool last); // qlen characters
	method ActionValue#(Tuple2#(Bool, Maybe#(Bool))) found;
endinterface

(*synthesize*)
module mkSubStringFindAligned8(SubStringFindAlignedIfc#(8));
	let m_ <- mkSubStringFindAligned;
	return m_;
endmodule

module mkSubStringFindAligned(SubStringFindAlignedIfc#(qlen))
	provisos(Mul#(qlen, 8, qsz), Mul#(qsz,2,dsz));
	Integer iqlen = valueOf(qlen);

	Vector#(qlen, FIFO#(Bit#(qsz))) queryQ <- replicateM(mkFIFO);
	Vector#(qlen, FIFO#(Bit#(dsz))) dataQ <- replicateM(mkFIFO);
	Vector#(TAdd#(1,qlen), FIFO#(Tuple3#(Bool, Bool, Bool))) foundQ <- replicateM(mkFIFO); // found, done, last

	FIFO#(Tuple2#(Bool, Maybe#(Bool))) outQ <- mkFIFO; // last, Maybe#(found)

	for ( Integer idx = 0; idx < iqlen; idx=idx+1 ) begin
		Reg#(Bit#(qsz)) query <- mkReg(0);
		rule loadq;
			queryQ[idx].deq;
			let q = queryQ[idx].first;
			query <= q;

			if ( idx < iqlen-1 ) queryQ[idx+1].enq(q);
		endrule

		Reg#(Bit#(32)) procCnt <- mkReg(0);

		rule procd;
			dataQ[idx].deq;
			let d = dataQ[idx].first;
			if ( idx < iqlen-1 ) dataQ[idx+1].enq(d>>8);

			Bit#(qlen) charmatch = 0;
			for ( Integer i = 0; i < iqlen; i=i+1 ) begin
				Bit#(8) ci = d[(i*8)+7:(i*8)];
				Bit#(8) qi = query[(i*8)+7:(i*8)];
				if ( qi == 0 || ci == qi ) charmatch[i] = 1;
				else charmatch[i] = 0;
			end

			Bit#(1) stringmatch = reduceAnd(charmatch)[0];

			foundQ[idx].deq;
			let f_ = foundQ[idx].first;
			let foundb = tpl_1(f_);
			let doneb = tpl_2(f_);
			let lastv = tpl_3(f_);

			procCnt <= procCnt + 1;


			Bool foundh = False;
			if ( stringmatch == 1 || foundb ) foundh = True;

			Bool doneh = False;
			if ( d[7:0] == 0 || doneh ) doneh = True;

			foundQ[idx+1].enq(tuple3(foundh, doneh, lastv));
		endrule
	end

	Reg#(Bool) foundBefore <- mkReg(False);
	rule collectFound;
		foundQ[iqlen].deq;
		let f_ = foundQ[iqlen].first;
		let foundb = tpl_1(f_);
		let doneb = tpl_2(f_);
		let lastv = tpl_3(f_);

		Bool foundHere = foundBefore || foundb;


		if ( lastv || doneb ) begin
			foundBefore <= False;
			if ( doneb ) begin
				outQ.enq(tuple2(lastv, tagged Valid foundHere));
			end else begin
				outQ.enq(tuple2(lastv, tagged Invalid));
			end
		end else foundBefore <= foundHere;
	endrule








	Reg#(Bit#(32)) pushCnt <- mkReg(0);

	Reg#(Maybe#(Bit#(qsz))) lastBuffer <- mkReg(tagged Invalid);
	Reg#(Bool) flushLast <- mkReg(False);
	rule doFlushLast(flushLast);
		flushLast <= False;
		dataQ[0].enq({-1, fromMaybe(?,lastBuffer)});
		foundQ[0].enq(tuple3(False,False,True));
		lastBuffer <= tagged Invalid;
		pushCnt <= pushCnt + 1;
	endrule

	method Action queryString(Bit#(qsz) data); // qlen characters
		queryQ[0].enq(data);
	endmethod
	method Action dataString(Bit#(qsz) data, Bool last) if ( !flushLast ); // qlen characters
		if ( isValid(lastBuffer) ) begin
			dataQ[0].enq({data, fromMaybe(?,lastBuffer)});
			foundQ[0].enq(tuple3(False,False,False));
		end
		lastBuffer <= tagged Valid data;
		pushCnt <= pushCnt + 1;

		if ( last ) flushLast <= True;
	endmethod
	method ActionValue#(Tuple2#(Bool, Maybe#(Bool))) found;
		outQ.deq;
		return outQ.first;
	endmethod
endmodule

interface SubStringFindIfc#(numeric type querysize);
	method Action queryString(Bit#(TMul#(querysize, 8)) data); // querysize characters
	method Action inputString(Bit#(8) char); // end of string denominated by \0
	method ActionValue#(Bool) found;
endinterface

module mkSubStringFind(SubStringFindIfc#(querysize)) 
	provisos(Add#(1,a__,querysize));
	Integer qlen = valueOf(querysize);

	Vector#(querysize, Reg#(Bit#(8))) query <- replicateM(mkReg(0));
	Vector#(querysize, FIFO#(Bit#(8))) charQ <- replicateM(mkFIFO);
	BoolMergeNetIfc#(querysize) bm <- mkBoolAndNet;
	FIFO#(Bool) isNullQ <- mkSizedFIFO(valueOf(TLog#(querysize))*2+1); // 2 cycles per merge stage

	for ( Integer i = 0; i < qlen; i=i+1 ) begin
		rule compchar;
			let c = charQ[i].first;
			charQ[i].deq;
			if ( i < qlen-1 ) charQ[i+1].enq(c);
			else isNullQ.enq(c==0);

			let qc = query[i];

			if ( (qc & c) == qc ) bm.puts[i].put(True);
			else bm.puts[i].put(False);
		endrule
	end

	FIFO#(Bool) foundQ <- mkFIFO;
	Reg#(Bool) curFound <- mkReg(False);
	rule collectResult;
		let d <- bm.get;
		let last = isNullQ.first;
		isNullQ.deq;

		let cf = curFound || d;

		if ( last ) begin
			foundQ.enq(cf);
			curFound <= False;
		end else begin
			curFound <= cf;
		end
	endrule


	method Action queryString(Bit#(TMul#(querysize, 8)) data); // querysize characters
		for ( Integer i = 0; i < qlen; i=i+1 )  begin
			query[i] <= data[(i*8)+7:(i*8)];
		end
	endmethod
	method Action inputString(Bit#(8) char); // end of string denominated by \0
		charQ[0].enq(char);
	endmethod
	method ActionValue#(Bool) found;
		foundQ.deq;
		return foundQ.first;
	endmethod
endmodule

endpackage: SubString
