package QueryProc;

import Vector::*;
import FIFO::*;
import BRAM::*;
import BRAMFIFO::*;

import Serializer::*;
import MergeN::*;
import BurstIOArbiter::*;

import ColumnFilter::*;

typedef 8 FilterCnt;
typedef Bit#(4) QidType;

interface QueryProcIfc;
	method Action setQueryCondition(QidType qid, Bit#(32) data);

	method ActionValue#(Tuple3#(Bool,Bit#(32),Bit#(16))) dramReq; // write? offset, cnt
	method ActionValue#(Bit#(512)) dramWriteData;
	method Action dramReadData(Bit#(512) data);

	method Action flashData(Bit#(256) data, Bit#(8) tag);
	method Action setTagQid(Bit#(8) tag, QidType qid);

	method ActionValue#(Tuple2#(Bit#(32),Bit#(32))) processedElement; // key, value
endinterface

interface MultiColumnExpressionIfc;
	interface Vector#(FilterCnt, MergeEnqIfc#(Tuple2#(Bit#(512),Bit#(10)))) columns;
	method ActionValue#(Tuple2#(Bit#(32),Bit#(32))) getResult; // key, value
endinterface

interface SerializerValidIfc#(numeric type dstSz);
	method Action put(Bit#(512) data, Bit#(10) validBits);
	method ActionValue#(Bit#(dstSz)) get;
endinterface

module mkSerializerValid(SerializerValidIfc#(dstSz))
	provisos (Add#(a__, dstSz, 512), Div#(512, TDiv#(512, dstSz), dstSz));
	Integer idstSz = valueOf(dstSz);
	SerializerIfc#(512,TDiv#(512,dstSz)) ser <- mkSerializer;
	FIFO#(Bit#(10)) validBitsQ <- mkFIFO;
	Reg#(Bit#(10)) validBitsLeft <- mkReg(0);
	FIFO#(Bit#(dstSz)) outQ <- mkFIFO;
	rule filterInvalid;
		let d <- ser.get;
		if ( validBitsLeft == 0 ) begin
			validBitsQ.deq;
			let v = validBitsQ.first;

			// This assumes a new word has at least one valid data in it
			validBitsLeft <= v-fromInteger(idstSz);
			outQ.enq(d);
		end else begin
			if ( validBitsLeft >= fromInteger(idstSz) ) begin
				outQ.enq(d);
			end
			validBitsLeft <= validBitsLeft - fromInteger(idstSz);
		end

	endrule
	
	method Action put(Bit#(512) data, Bit#(10) validBits);
		ser.put(data);
		validBitsQ.enq(validBits);
	endmethod
	method ActionValue#(Bit#(dstSz)) get;
		outQ.deq;
		return outQ.first;
	endmethod
endmodule

//example for tpc-h q14
module mkColumnCalcArithExpression(MultiColumnExpressionIfc);
	Vector#(FilterCnt, FIFO#(Tuple2#(Bit#(512),Bit#(10)))) columnInQ <- replicateM(mkFIFO);
	FIFO#(Tuple2#(Bit#(32),Bit#(32))) outQ <- mkFIFO;

	SerializerValidIfc#(1) ser0 <- mkSerializerValid;
	SerializerValidIfc#(1) ser1 <- mkSerializerValid;
	SerializerValidIfc#(32) ser2 <- mkSerializerValid;
	SerializerValidIfc#(32) ser3 <- mkSerializerValid;
	SerializerValidIfc#(32) ser4 <- mkSerializerValid;
	SerializerValidIfc#(32) ser5 <- mkSerializerValid;
	SerializerValidIfc#(32) ser6 <- mkSerializerValid;
	SerializerValidIfc#(32) ser7 <- mkSerializerValid;

	rule relayFilterSer0;
		columnInQ[0].deq;
		ser0.put(tpl_1(columnInQ[0].first), tpl_2(columnInQ[0].first));
	endrule
	rule relayFilterSer1;
		columnInQ[1].deq;
		ser1.put(tpl_1(columnInQ[1].first), tpl_2(columnInQ[1].first));
	endrule
	rule relayFilterSer2;
		columnInQ[2].deq;
		ser2.put(tpl_1(columnInQ[2].first), tpl_2(columnInQ[2].first));
	endrule
	rule relayFilterSer3;
		columnInQ[3].deq;
		ser3.put(tpl_1(columnInQ[3].first), tpl_2(columnInQ[3].first));
	endrule
	rule relayFilterSer4;
		columnInQ[4].deq;
		ser4.put(tpl_1(columnInQ[4].first), tpl_2(columnInQ[4].first));
	endrule
	rule relayFilterSer5;
		columnInQ[5].deq;
		ser5.put(tpl_1(columnInQ[5].first), tpl_2(columnInQ[5].first));
	endrule
	rule relayFilterSer6;
		columnInQ[6].deq;
		ser6.put(tpl_1(columnInQ[6].first), tpl_2(columnInQ[6].first));
	endrule
	rule relayFilterSer7;
		columnInQ[7].deq;
		ser7.put(tpl_1(columnInQ[7].first), tpl_2(columnInQ[7].first));
	endrule

	// 0 is date filter, 2 is partkey, 3 is extended, 4 is discount
	rule doArith;
		let f <- ser0.get;
		let pk <- ser2.get;
		let ex <- ser3.get;
		let dc <- ser4.get;
		if ( f == 1 ) begin
			outQ.enq(tuple2(pk, ex*(1-dc)));
		end
	endrule

	Vector#(FilterCnt, MergeEnqIfc#(Tuple2#(Bit#(512),Bit#(10)))) columns_;
	for ( Integer i = 0; i < valueOf(FilterCnt); i=i+1 ) begin
		columns_[i] = interface MergeEnqIfc;
			method Action enq(Tuple2#(Bit#(512),Bit#(10)) data);
				columnInQ[i].enq(data);
			endmethod
		endinterface;
	end

	interface columns = columns_;
	method ActionValue#(Tuple2#(Bit#(32),Bit#(32))) getResult; // key, value
		outQ.deq;
		return outQ.first;
	endmethod
endmodule

(* synthesize *)
module mkQueryProc (QueryProcIfc);
	MergeNIfc#(FilterCnt, Tuple3#(Bit#(8), QidType, Bit#(32))) dramReadBurstReqM <- mkMergeN; // tag, qid, bits
	ScatterNIfc#(FilterCnt, Tuple2#(Bit#(512),Bit#(10))) dramReadDataS <- mkScatterN; // data, bits (small size because only within word)

	//////// got right order of words, do query processing (Transform, etc) and turn it into kv pairs for sort reduce
	MultiColumnExpressionIfc cexpr <- mkColumnCalcArithExpression;
	for ( Integer i = 0; i < valueOf(FilterCnt); i=i+1 ) begin
		rule relayOrderedColumnData;
			dramReadDataS.get[i].deq;
			cexpr.columns[i].enq(dramReadDataS.get[i].first);
		endrule
	end

	//////// dram read request for in the right order of page reads ////////////////////////////
	ScatterNIfc#(FilterCnt, Bit#(8)) readDoneTagS <- mkScatterN;
	ScatterNIfc#(FilterCnt, Bit#(8)) readReqTagS <- mkScatterN;
	Vector#(FilterCnt,FIFO#(Bit#(8))) readDoneTagQv <- replicateM(mkSizedBRAMFIFO(256));
	Vector#(FilterCnt,FIFO#(Bit#(8))) readReqTagOrderQv <- replicateM(mkSizedBRAMFIFO(256));
	BRAM2Port#(Bit#(8), Bit#(32)) tag2bitsMap <- mkBRAM2Server(defaultValue);
	for ( Integer i = 0; i < valueOf(FilterCnt); i=i+1 ) begin
		MergeNIfc#(2,Bit#(8)) readReadyTagM <- mkMergeN;
		rule relayReadReqTag;
			readReqTagS.get[i].deq;
			readReqTagOrderQv[i].enq(readReqTagS.get[i].first);
		endrule
		rule relayReadDoneTag;
			readDoneTagS.get[i].deq;
			readReadyTagM.enq[0].enq(readDoneTagS.get[i].first);
		endrule
		rule relayReadDoneTagM;
			readReadyTagM.deq;
			readDoneTagQv[i].enq(readReadyTagM.first);
		endrule
		FIFO#(Bit#(8)) dramReadReqTagQ <- mkFIFO;
		rule compareReadyOrder; // keep cycling through ready queue 
			readDoneTagQv[i].deq;
			let tag = readDoneTagQv[i].first;
			if ( tag == readReqTagOrderQv[i].first) begin
				readReqTagOrderQv[i].deq;

				// send to next stage -- to request DRAM read
				// first get how many words to read
				dramReadReqTagQ.enq(tag);
				tag2bitsMap.portB.request.put(BRAMRequest{
					write:False, responseOnWrite:False,
					address:tag, datain:?});
			end else begin
				readReadyTagM.enq[1].enq(tag);
			end
		endrule
		rule dramReadReqSend;
			dramReadReqTagQ.deq;
			let tag = dramReadReqTagQ.first;
			let validBits <- tag2bitsMap.portB.response.get;
			dramReadBurstReqM.enq[i].enq(tuple3(tag,fromInteger(i), validBits));
		endrule
	end



	//////// Pushing things through columnfilters and then into DRAM /////////
	Vector#(FilterCnt, ColumnFilterIfc) columnfilters = newVector();
	columnfilters[0] <- mkCompare4BLTEFilter2;
	columnfilters[1] <- mkSubStringFilter2;
	for ( Integer i = 2; i < valueOf(FilterCnt); i=i+1 ) begin
		columnfilters[i] <- mkNullColumnFilter;
	end
	ScatterNIfc#(FilterCnt, Bit#(32)) queryS <- mkScatterN;
	ScatterNIfc#(FilterCnt, Tuple2#(Bit#(256),Bit#(8))) flashDataS <- mkScatterN;

	BurstMergeNIfc#(FilterCnt, Tuple3#(Bit#(8), Bit#(4), Bit#(256)), 16) burstM <- mkBurstMergeN; // tag, qid, data
	for (Integer i = 0; i < valueOf(FilterCnt); i=i+1 ) begin
		rule rsetQueryCondition;
			queryS.get[i].deq;
			columnfilters[i].putQuery(queryS.get[i].first);
		endrule

		Reg#(Bit#(8)) pageWordCounter <- mkReg(0); // to keep track of "last", 8192/32 == 256
		FIFO#(Bit#(8)) tagBypassQ <- mkSizedFIFO(4);
		rule relayData;
			let d = flashDataS.get[i].first;
			flashDataS.get[i].deq;

			pageWordCounter <= pageWordCounter + 1;

			columnfilters[i].put(tpl_1(d), (pageWordCounter==255)?True:False);
			if ( pageWordCounter == 0 ) tagBypassQ.enq(tpl_2(d));
		endrule

		FIFO#(Bit#(256)) filteredDataQ <- mkSizedBRAMFIFO(256+16); // 16 just for elasticity
		Reg#(Bit#(8)) curTag <- mkReg(0);
		rule relayFiltered;
			let d <- columnfilters[i].get;
			filteredDataQ.enq(d);
		endrule

		Reg#(Bit#(10)) dramBurstLeft <- mkReg(0);
		rule relayFilteredBurst ( dramBurstLeft > 0 );
			let d = filteredDataQ.first;
			filteredDataQ.deq;
			burstM.enq[i].enq(tuple3(curTag, fromInteger(i), d));
			dramBurstLeft <= dramBurstLeft - 1;
		endrule
		rule relayValid (dramBurstLeft == 0);
			let v <- columnfilters[i].validBits;
			tagBypassQ.deq;
			let tag = tagBypassQ.first;


			Bit#(32) bv = (v+255)/256;
			curTag <= tag;
			dramBurstLeft <= truncate(bv);

			burstM.enq[i].burst(truncate(bv));

			// store v into map -- needed for joining later
			tag2bitsMap.portA.request.put(BRAMRequest{
				write:True, responseOnWrite:False,
				address:tag, datain:v});
		endrule
	end

	MergeNIfc#(2,Tuple3#(Bool,Bit#(32),Bit#(16))) dramBurstReqM <- mkMergeN; // for read and writes (write? offset ,words)

	////// relay dram write burst requests //////////////////////////////////////
	DeSerializerIfc#(256,2) dramDes <- mkDeSerializer;
	FIFO#(Tuple2#(Bit#(8),Bit#(4))) dramDesSkip <- mkStreamSkip(2,0);

	Reg#(Bit#(16)) burstLeft <- mkReg(0);
	Reg#(Bit#(16)) burstCnt <- mkReg(0);
	FIFO#(Bit#(512)) dramWriteDataQ <- mkFIFO;
	rule startDRAMBurst(burstLeft == 0);
		let b <- burstM.getBurst;
		burstLeft <= (b+1)/2;
		burstCnt <= 0;
	endrule
	rule relayWriteDes;
		burstM.deq;
		let d = burstM.first;
		let tag = tpl_1(d);
		let qid = tpl_2(d);
		let val = tpl_3(d);

		dramDes.put(val);
		dramDesSkip.enq(tuple2(tag,qid));
	endrule

	rule relayDRAMBurst(burstLeft > 0);
		burstLeft <= burstLeft - 1;
		burstCnt <= burstCnt + 1;
		let t_ = dramDesSkip.first;
		let tag = tpl_1(t_);
		let qid = tpl_2(t_);
		dramDesSkip.deq;
		let v <- dramDes.get;

		if ( burstCnt == 0 ) begin
			dramBurstReqM.enq[0].enq(tuple3(True, zeroExtend(tag)*128, burstLeft));
			readDoneTagS.enq(tag, zeroExtend(qid));
		end

		dramWriteDataQ.enq(v);
	endrule

	
	////// relay dram read burst requests ////////////////////////////////////////
	FIFO#(Tuple2#(QidType, Bit#(32))) dramReadQidOrderQ <- mkSizedFIFO(8); // qid, valid bits
	FIFO#(Bit#(512)) dramReadQ <- mkFIFO;
	rule relayDRAMBurstReadReq;
		dramReadBurstReqM.deq;
		let r = dramReadBurstReqM.first;
		let tag = tpl_1(r);
		let qid = tpl_2(r);
		let validBits = tpl_3(r);
		dramBurstReqM.enq[1].enq(tuple3(True, zeroExtend(tag)*128, truncate((validBits+511)/512)));
		dramReadQidOrderQ.enq(tuple2(qid, validBits));
	endrule
	Reg#(Bit#(32)) validBitsLeft <- mkReg(0);
	Reg#(QidType) readTargetQid <- mkReg(0);
	rule scatterDRAMRead;
		dramReadQ.deq;
		let d = dramReadQ.first;

		if ( validBitsLeft == 0 ) begin
			dramReadQidOrderQ.deq;
			let o = dramReadQidOrderQ.first;
			let qid = tpl_1(o);
			readTargetQid <= qid;
			let vbitsreq = tpl_2(o);

			if ( vbitsreq >= 512 ) begin
				validBitsLeft <= vbitsreq-512;
				dramReadDataS.enq(tuple2(d,fromInteger(512)),zeroExtend(qid));
			end else begin
				dramReadDataS.enq(tuple2(d,truncate(vbitsreq)),zeroExtend(qid));
				// validBitsLeft still zero
			end
		end else begin
			if ( validBitsLeft >= 512 ) begin
				validBitsLeft <= validBitsLeft - 512;
				dramReadDataS.enq(tuple2(d,fromInteger(512)),zeroExtend(readTargetQid));
			end else begin
				validBitsLeft <= 0;
				dramReadDataS.enq(tuple2(d,truncate(validBitsLeft)),zeroExtend(readTargetQid));
			end
		end
	endrule



	////// insert flash read request metadata ////////////////////////////////////
	BRAM2Port#(Bit#(8), QidType) tag2qidxMap <- mkBRAM2Server(defaultValue);
	FIFO#(Tuple2#(Bit#(256),Bit#(8))) flashInQ <- mkFIFO;
	FIFO#(Tuple2#(Bit#(256),Bit#(8))) flashDataRelayQ <- mkFIFO;
	
	rule getQidFromMap;
		flashInQ.deq; let d_ = flashInQ.first;
		let d = tpl_1(d_);
		let tag = tpl_2(d_);
		flashDataRelayQ.enq(d_);

		tag2qidxMap.portB.request.put(BRAMRequest{
			write:False, responseOnWrite:False,
			address:tag, datain:?});
	endrule

	rule relayFilterData;
		let qid <- tag2qidxMap.portB.response.get;
		let d_ = flashDataRelayQ.first;
		flashDataRelayQ.deq;
		flashDataS.enq(d_, zeroExtend(qid));
	endrule



	
	method Action setQueryCondition(QidType qid, Bit#(32) data);
		queryS.enq(data, zeroExtend(qid));
	endmethod

	method ActionValue#(Tuple3#(Bool,Bit#(32),Bit#(16))) dramReq; // write? offset, cnt
		dramBurstReqM.deq;
		return dramBurstReqM.first;
	endmethod
	method ActionValue#(Bit#(512)) dramWriteData;
		dramWriteDataQ.deq;
		return dramWriteDataQ.first;
	endmethod
	method Action dramReadData(Bit#(512) data);
		dramReadQ.enq(data);
	endmethod

	method Action flashData(Bit#(256) data, Bit#(8) tag);
		flashInQ.enq(tuple2(data,tag));
	endmethod
	method Action setTagQid(Bit#(8) tag, QidType qid);
		tag2qidxMap.portA.request.put(BRAMRequest{
			write:True, responseOnWrite:False,
			address:tag, datain:qid});
		readReqTagS.enq(tag, zeroExtend(qid));
	endmethod
	method ActionValue#(Tuple2#(Bit#(32),Bit#(32))) processedElement; // key, value
		let d <- cexpr.getResult;
		return d;
	endmethod
endmodule

endpackage: QueryProc
