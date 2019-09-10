package ColumnFilter;

import Vector::*;
import FIFO::*;

// in bluedbm
import SubString::*;

// in bluelib
import Serializer::*;

interface ColumnFilterBoolIfc;
	method Action put(Bit#(256) d1, Bit#(256) d2);
	method ActionValue#(Bit#(256)) get;
	method Action putQuery(Bit#(32) data);
endinterface

module mkColumnFilterBool (ColumnFilterBoolIfc);
	Vector#(2,Reg#(Bool)) srcNeg <- replicateM(mkReg(False));
	Reg#(Bool) joinRel <- mkReg(False); // False: OR, True: AND. Add more when needed later
	FIFO#(Bit#(256)) inQ <- mkFIFO;

	method Action put(Bit#(256) d1, Bit#(256) d2);
		if ( srcNeg[0] ) d1 = ~d1;
		if ( srcNeg[1] ) d2 = ~d2;
		let j = case (joinRel)
			True: return d1&d2;
			False: return d1|d2;
		endcase;
		inQ.enq(j);
	endmethod
	method ActionValue#(Bit#(256)) get;
		inQ.deq;
		return inQ.first;
	endmethod
	method Action putQuery(Bit#(32) data);
		srcNeg[0] <= (data[0]==0?False:True);
		srcNeg[1] <= (data[1]==0?False:True);
		joinRel <= (data[2]==0?False:True);
	endmethod
endmodule

interface ColumnFilterIfc;
	method Action putQuery(Bit#(32) data);
	method Action put(Bit#(256) data, Bool last);
	method ActionValue#(Bit#(256)) get;
	method ActionValue#(Bit#(32)) validBits;
endinterface

module mkNullColumnFilter (ColumnFilterIfc);
	FIFO#(Bit#(256)) inQ <- mkFIFO;
	Reg#(Bit#(32)) validBitCounter <- mkReg(0);
	FIFO#(Bit#(32)) validBitQ <- mkFIFO;
	method Action putQuery(Bit#(32) data);
	endmethod
	method Action put(Bit#(256) data, Bool last);
		inQ.enq(data);
		if ( last ) begin
			validBitCounter <= 0;
			validBitQ.enq(validBitCounter+256);
		end else begin
			validBitCounter <= validBitCounter + 256;
		end
	endmethod
	method ActionValue#(Bit#(256)) get if ( False);
		inQ.deq;
		return inQ.first;
	endmethod
	method ActionValue#(Bit#(32)) validBits if ( False );
		validBitQ.deq;
		return validBitQ.first;
	endmethod
endmodule

module mkCompare4BLTEFilter (ColumnFilterIfc); // less than or equal, 4 byte values
	Reg#(Bit#(32)) query <- mkReg(0);
	FIFO#(Tuple2#(Bit#(256), Bool)) inQ <- mkFIFO;
	DeSerializerIfc#(8,32) resultDes <- mkDeSerializer;

	Reg#(Bit#(5)) outputInternalOffset <- mkReg(0); // 5 bits for 32 elements
	Reg#(Bit#(5)) outputPaddingCounter <- mkReg(0); // 5 bits for 32 elements
	Reg#(Bit#(32)) validBitCounter <- mkReg(0);
	FIFO#(Bit#(32)) validBitQ <- mkFIFO;
	rule padd ( outputPaddingCounter > 0 );
		outputPaddingCounter <= outputPaddingCounter + 1;
		resultDes.put(8'hff);
	endrule
	rule procd ( outputPaddingCounter == 0 );
		inQ.deq;
		let d_ = inQ.first;
		let d = tpl_1(d_);
		let last = tpl_2(d_);

		Bit#(8) filterResult = 0;

		Bit#(4) bitCount = 0;
		for (Integer i = 0; i < 8; i=i+1 ) begin
			Bit#(32) sd = d[(i*32)+31:(i*32)];
			if ( sd >= query ) begin
				filterResult[i] = 1;
				bitCount = bitCount + 1;
			end
		end
		resultDes.put(filterResult);
		let nbits = validBitCounter + zeroExtend(bitCount);

		if ( last ) begin
			outputPaddingCounter <= outputInternalOffset + 1;
			validBitCounter <= 0;
			outputInternalOffset <= 0;
			validBitQ.enq(nbits);
		end else begin
			validBitCounter <= nbits;
			outputInternalOffset <= outputInternalOffset + 1;
		end
	endrule


	method Action putQuery(Bit#(32) data);
		query <= data;
	endmethod
	method Action put(Bit#(256) data, Bool last);
		inQ.enq(tuple2(data, last));
	endmethod
	method ActionValue#(Bit#(256)) get;
		let v <- resultDes.get;
		return v;
	endmethod
	method ActionValue#(Bit#(32)) validBits;
		validBitQ.deq;
		return validBitQ.first;
	endmethod
endmodule

module mkCompare4BLTEFilter2(ColumnFilterIfc);
	Vector#(2,ColumnFilterIfc) filters <- replicateM(mkCompare4BLTEFilter);
	Reg#(Bit#(2)) querydirection <- mkReg(0);

	ColumnFilterBoolIfc bjoin <- mkColumnFilterBool;
	rule joinresult;
		let d1 <- filters[0].get;
		let d2 <- filters[1].get;
		bjoin.put(d1,d2);
	endrule
	
	method Action putQuery(Bit#(32) data);
		if ( querydirection == 0 ) filters[0].putQuery(data);
		else if ( querydirection == 1 ) filters[1].putQuery(data);
		else bjoin.putQuery(data);

		if ( querydirection >= 2 ) querydirection <= 0;
		else querydirection <= querydirection + 1;
	endmethod
	method Action put(Bit#(256) data, Bool last);
		filters[0].put(data,last);
		filters[1].put(data,last);
	endmethod
	method ActionValue#(Bit#(256)) get;
		let b <- bjoin.get;
		return b;
	endmethod
	method ActionValue#(Bit#(32)) validBits;
		let d1 <- filters[0].validBits;
		let d2 <- filters[1].validBits;
		let d = (d1<d2)?d1:d2;
		return d;
	endmethod
endmodule

module mkSubStringFilter (ColumnFilterIfc);
	SubStringFindAlignedIfc#(8) stringFilter <- mkSubStringFindAligned;
	DeSerializerIfc#(32,2) queryDes <- mkDeSerializer;
	SerializerIfc#(256,4) dataSer <- mkSerializer;
	FIFO#(Bool) dataSerLast <- mkStreamSerializeLast(4);

	rule relayQuery;
		let q <- queryDes.get;
		stringFilter.queryString(q);
	endrule

	rule relayData;
		let d <- dataSer.get;
		let l = dataSerLast.first;
		dataSerLast.deq;
		stringFilter.dataString(d,l);
	endrule

	DeSerializerIfc#(1,256) outDes <- mkDeSerializer;
	Reg#(Bit#(8)) outDesCounter <- mkReg(0);
	Reg#(Bit#(8)) outDesPaddingCounter <- mkReg(0);
	Reg#(Bit#(32)) outBitCounter <- mkReg(0);
	FIFO#(Bit#(32)) validBitQ <- mkFIFO;
	rule desPadding (outDesPaddingCounter > 0);
		outDesPaddingCounter <= outDesPaddingCounter + 1;
		outDes.put(0);
	endrule
	rule getResult (outDesPaddingCounter == 0);
		let r_ <- stringFilter.found;
		let last = tpl_1(r_);
		let mfound = tpl_2(r_);

		if ( isValid(mfound) ) begin
			outDes.put(fromMaybe(?,mfound)?1:0);
			if ( last ) begin
				outBitCounter <= 0;
				outDesCounter <= 0;
				validBitQ.enq(outBitCounter+1);
				outDesPaddingCounter <= outDesCounter+1;
			end else begin
				outDesCounter <= outDesCounter + 1;
				outBitCounter <= outBitCounter + 1;
			end
		end else if ( last ) begin
			outBitCounter <= 0;
			outDesCounter <= 0;
			validBitQ.enq(outBitCounter);
			outDesPaddingCounter <= outDesCounter;
		end
	endrule


	method Action putQuery(Bit#(32) data);
		queryDes.put(data);
	endmethod
	method Action put(Bit#(256) data, Bool last);
		dataSer.put(data);
		dataSerLast.enq(last);
	endmethod
	method ActionValue#(Bit#(256)) get;
		let r <- outDes.get;
		return r;
	endmethod
	method ActionValue#(Bit#(32)) validBits;
		validBitQ.deq;
		return validBitQ.first;
	endmethod
endmodule

module mkSubStringFilter2 (ColumnFilterIfc);
	Vector#(2,ColumnFilterIfc) filters <- replicateM(mkSubStringFilter);
	Reg#(Bit#(2)) querydirection <- mkReg(0);

	ColumnFilterBoolIfc bjoin <- mkColumnFilterBool;
	rule joinresult;
		let d1 <- filters[0].get;
		let d2 <- filters[1].get;
		bjoin.put(d1,d2);
	endrule
	
	method Action putQuery(Bit#(32) data);
		if ( querydirection == 0 ) filters[0].putQuery(data);
		else if ( querydirection == 1 ) filters[1].putQuery(data);
		else bjoin.putQuery(data);

		if ( querydirection >= 2 ) querydirection <= 0;
		else querydirection <= querydirection + 1;
	endmethod
	method Action put(Bit#(256) data, Bool last);
		filters[0].put(data,last);
		filters[1].put(data,last);
	endmethod
	method ActionValue#(Bit#(256)) get;
		let b <- bjoin.get;
		return b;
	endmethod
	method ActionValue#(Bit#(32)) validBits;
		let d1 <- filters[0].validBits;
		let d2 <- filters[1].validBits;
		let d = (d1<d2)?d1:d2;
		return d;
	endmethod
endmodule

endpackage: ColumnFilter
