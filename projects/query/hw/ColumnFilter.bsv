package ColumnFilter;

import Vector::*;
import FIFO::*;

// in bluedbm
import SubString::*;

// in bluelib
import Serializer::*;

interface ColumnFilterIfc;
	method Action putQuery(Bit#(32) data);
	method Action put(Bit#(256) data, Bool last);
	method ActionValue#(Bit#(256)) get;
	method ActionValue#(Bit#(32)) validBits;
endinterface

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
	method Action putQuery(Bit#(32) data);
	endmethod
	method Action put(Bit#(256) data, Bool last);
	endmethod
	method ActionValue#(Bit#(256)) get;
		return ?;
	endmethod
	method ActionValue#(Bit#(32)) validBits;
		return ?;
	endmethod
endmodule

endpackage: ColumnFilter
