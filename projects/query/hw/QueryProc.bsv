package QueryProc;

import Vector::*;
import FIFO::*;
import BRAM::*;
import BRAMFIFO::*;

import Serializer::*;
import MergeN::*;

import ColumnFilter::*;

typedef 4 FilterCnt;
typedef Bit#(4) QidType;

interface QueryProcIfc;
	method Action setQueryCondition(QidType qid, Bit#(32) data);

	method ActionValue#(Tuple3#(Bool,Bit#(32),Bit#(512))) dramReq;
	method Action dramReadData(Bit#(512) data);

	method Action flashData(Bit#(256) data, Bit#(8) tag);
	method Action setTagQid(Bit#(8) tag, QidType qid);
endinterface

module mkQueryProc (QueryProcIfc);
	Vector#(FilterCnt, ColumnFilterIfc) columnfilters = newVector();
	columnfilters[0] <- mkCompare4BLTEFilter2;
	columnfilters[1] <- mkSubStringFilter2;
	columnfilters[2] <- mkNullColumnFilter;
	columnfilters[3] <- mkNullColumnFilter;
	ScatterNIfc#(FilterCnt, Bit#(32)) queryS <- mkScatterN;
	ScatterNIfc#(FilterCnt, Tuple2#(Bit#(256),Bit#(8))) flashDataS <- mkScatterN;

	BurstMergeNIfc#(FilterCnt, Tuple2#(Bit#(8),Bit#(256)), 10) burstM <- mkBurstMergeN;
	for (Integer i = 0; i < valueOf(FilterCnt); i=i+1 ) begin
		rule rsetQueryCondition;
			queryS.get[i].deq;
			columnfilters[i].putQuery(queryS.get[i].first);
		endrule

		Reg#(Bit#(8)) pageWordCounter <- mkReg(0); // too keep track of "last", 8192/32 == 256
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
			burstM.enq[i].enq(tuple2(curTag,d));
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

			// TODO store v into map -- needed for joining later
		endrule
	end

	DeSerializerIfc#(256,2) dramDes <- mkDeSerializer;
	FIFO#(Bit#(8)) dramDesSkip <- mkStreamSkip(2,0);

	Reg#(Bit#(10)) burstLeft <- mkReg(0);
	Reg#(Bit#(32)) burstOffset <- mkReg(0);
	rule startDRAMBurst(burstLeft == 0);
		let b <- burstM.getBurst;
		burstLeft <= (b+1)/2;
		burstOffset <= 0;
	endrule
	FIFO#(Bit#(512)) dramWriteData <- mkFIFO;
	FIFO#(Tuple2#(Bit#(32),Bit#(512))) dramWriteReqQ <- mkFIFO;
	rule relayWriteDes;
		burstM.deq;
		let d = burstM.first;
		let tag = tpl_1(d);
		let val = tpl_2(d);
		dramDes.put(val);
		dramDesSkip.enq(tag);
	endrule
	rule relayDRAMBurst(burstLeft > 0);
		burstLeft <= burstLeft - 1;
		burstOffset <= burstOffset + 1;
		let tag = dramDesSkip.first;
		dramDesSkip.deq;
		let v <- dramDes.get;

		dramWriteReqQ.enq(tuple2(zeroExtend(tag)*128+burstOffset,v));
	endrule


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

	method ActionValue#(Tuple3#(Bool,Bit#(32),Bit#(512))) dramReq;
		dramWriteReqQ.deq;
		let d = dramWriteReqQ.first;
		return tuple3(False, tpl_1(d), tpl_2(d));
	endmethod
	method Action dramReadData(Bit#(512) data);
	endmethod

	method Action flashData(Bit#(256) data, Bit#(8) tag);
		flashInQ.enq(tuple2(data,tag));
	endmethod
	method Action setTagQid(Bit#(8) tag, QidType qid);
		tag2qidxMap.portA.request.put(BRAMRequest{
			write:True, responseOnWrite:False,
			address:tag, datain:qid});
	endmethod
endmodule

endpackage: QueryProc
