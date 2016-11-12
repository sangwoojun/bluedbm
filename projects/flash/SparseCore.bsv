import FIFO::*;
import FIFOF::*;
import Clocks::*;
import Vector::*;

import BRAM::*;
import BRAMFIFO::*;

import MergeN::*;
import Split4Width::*;
import AcceleratorReader::*;

interface SteppingRegisterIfc#(numeric type sz, type itype);
	method itype get;
	method Action step;
	method Action init;
	method Action set(Bit#(sz) addr, itype val);
endinterface

module mkSteppingRegister(SteppingRegisterIfc#(sz,itype))
	provisos(
		Bits#(itype, itypeSz)
		);


	BRAM2Port#(Bit#(sz), itype) regbuffer <- mkBRAM2Server(defaultValue); 
	Reg#(Bit#(sz)) curoff <- mkReg(0);
	
	Reg#(Bit#(4)) epoch <- mkReg(0);
	FIFO#(Bit#(4)) epochQ <- mkFIFO;

	rule sendReadReq;
		regbuffer.portA.request.put(BRAMRequest{
			write:False, responseOnWrite:False,
			address:curoff,
			datain:?
		});
		epochQ.enq(epoch);
		curoff <= curoff + 1;
	endrule

	FIFO#(Tuple2#(Bit#(4), itype)) resQ <- mkFIFO;
	rule getReadResp;
		let d <- regbuffer.portA.response.get();
		let e = epochQ.first;
		epochQ.deq;
		resQ.enq(tuple2(e, d));
	endrule

	rule flushStaleRead ( tpl_1(resQ.first) != epoch );
		resQ.deq;
	endrule

	method itype get if (tpl_1(resQ.first) == epoch);
		return tpl_2(resQ.first);
	endmethod
	method Action step;
		resQ.deq;
	endmethod
	method Action init;
		epoch <= epoch + 1;
		curoff <= 0;
	endmethod
	method Action set(Bit#(sz) addr, itype val);
		regbuffer.portB.request.put(BRAMRequest{
			write:True, responseOnWrite:False,
			address: addr, datain:val
		});
	endmethod
endmodule


interface DocDecoderIfc;
	method Action enq(Bit#(512) data);

	method Action deq;
	method Tuple3#(Bit#(32), Bit#(24), Bit#(8)) first;
endinterface

module mkDocDecoder (DocDecoderIfc);
	Split4WidthIfc#(128) split <- mkSplit4Width;
	Split4WidthIfc#(32) split32 <- mkSplit4WidthReverse;

	rule feedSplit32;
		split.deq;
		let v = split.first;
		split32.enq(v);
	endrule

	Reg#(Bit#(32)) curDocId <- mkReg(0);

	FIFO#(Tuple3#(Bit#(32), Bit#(24), Bit#(8))) outQ <- mkFIFO;
	rule proc;
		split32.deq;
		Bit#(32) v = split32.first;

		Bit#(1) flag = truncate(v>>31);
		if ( flag == 0 ) begin
			Bit#(23) word = truncate(v>>8);
			Bit#(8) cnt = truncate(v);
			outQ.enq(tuple3(curDocId, zeroExtend(word), cnt));
		end else begin
			Bit#(31) docid = truncate(v);
			curDocId <= zeroExtend(docid);
		end
	endrule


	method Action enq(Bit#(512) data);
		split.enq(data);
	endmethod

	method Action deq;
		outQ.deq;
	endmethod
	method Tuple3#(Bit#(32), Bit#(24), Bit#(8)) first;
		return outQ.first;
	endmethod
endmodule

interface DocDistIfc;
	method Action queryIn(Bit#(16) idx, Bit#(24) key, Bit#(8) val);

	method Action dataIn(Bit#(512) data);
	method ActionValue#(Tuple2#(Bit#(32), Bit#(32))) docDist;
endinterface

module mkDocDist ( DocDistIfc );
	SteppingRegisterIfc#(8, Tuple2#(Bit#(24),Bit#(8))) sreg <- mkSteppingRegister;
	DocDecoderIfc decoder <- mkDocDecoder;

	Reg#(Bit#(32)) lastDocId <- mkReg(0);

	FIFO#(Tuple3#(Bit#(32), Bit#(8), Bit#(8))) matchQ <- mkFIFO;

	rule compare;
		let r = decoder.first;
		Bit#(32) docid = tpl_1(r);
		Bit#(24) word = tpl_2(r);
		Bit#(8) cnt = tpl_3(r);

		let q = sreg.get;
		Bit#(24) qword = tpl_1(q);
		Bit#(8) qcnt = tpl_2(q);
		//$display( "Decoded %d %d %d -- %d %d ", docid, word, cnt, qword, qcnt );

		if ( lastDocId != docid ) begin
			lastDocId <= docid;
			sreg.init;
		end else begin
			if ( qword == word ) begin
				decoder.deq;
				sreg.step;
				matchQ.enq(tuple3(docid, cnt, qcnt));
				$display( "matched %d %d", docid, word );
			end
			if ( qword < word ) begin
				sreg.step;
				//$display( "sreg step %d %d", qword, word );
			end
			if (qword > word ) begin
				decoder.deq;
			end
		end
	endrule

	FIFO#(Tuple2#(Bit#(32), Bit#(32))) doutQ <- mkSizedFIFO(16);
	Reg#(Bit#(32)) lastCalcDoc <- mkReg(0);
	Reg#(Bit#(32)) curDistMult <- mkReg(0);
	Reg#(Bit#(32)) curDistASum <- mkReg(0);
	Reg#(Bit#(32)) curDistBSum <- mkReg(0);
	rule docalc;
		let d = matchQ.first;
		matchQ.deq;
		Bit#(32) did = tpl_1(d);
		Bit#(8) cnt = tpl_2(d);
		Bit#(8) qcnt = tpl_3(d);
		if ( lastCalcDoc == did ) begin
			curDistMult <= curDistMult + zeroExtend(cnt)*zeroExtend(qcnt);
			curDistASum <= curDistASum + zeroExtend(cnt)*zeroExtend(cnt);
			curDistBSum <= curDistBSum + zeroExtend(qcnt)*zeroExtend(qcnt);
		end else begin
			let ddist = curDistMult/(curDistASum+curDistBSum);
			doutQ.enq(tuple2(lastCalcDoc, ddist));
			$display("matched %d %d %d", did, cnt, qcnt );

			lastCalcDoc <= did;
			curDistMult <= zeroExtend(cnt)*zeroExtend(qcnt);
			curDistASum <= zeroExtend(cnt)*zeroExtend(cnt);
			curDistBSum <= zeroExtend(qcnt)*zeroExtend(qcnt);
		end

	endrule

	rule flussgdf;
		doutQ.deq;
	endrule

	method Action queryIn(Bit#(16) idx, Bit#(24) key, Bit#(8) val);
		$display( "queryIn %d %d %d", idx, key, val);
		sreg.set(truncate(idx), tuple2(key,val));
	endmethod

	method Action dataIn(Bit#(512) data);
		decoder.enq(data);
	endmethod

	method ActionValue#(Tuple2#(Bit#(32), Bit#(32))) docDist;
		doutQ.deq;
		return doutQ.first;
	endmethod
endmodule

module mkDocDistAccel(AcceleratorReaderIfc);
	DocDistIfc sc <- mkDocDist;
	FIFO#(Bit#(128)) outQ <- mkFIFO;

	rule relayColOut;
		let r <- sc.docDist;
		let cidx = tpl_1(r);
		let val = tpl_2(r);
		$display("VM result %d %d", cidx, val);
		if ( val < 1024 ) begin
			outQ.enq({0,cidx,val});
		end
	endrule

	method Action dataIn(Bit#(512) d);
		sc.dataIn(d);
	endmethod

	method Action cmdIn(Bit#(32) header, Bit#(128) cmd_);
		let d = cmd_;
		
		Bit#(16) idx = truncate(d);
		Bit#(24) key = truncate(d>>32);
		Bit#(8) val = truncate(d>>64);
		sc.queryIn(idx, key, val);
	endmethod

	method ActionValue#(Bit#(128)) resOut;
		outQ.deq;
		return outQ.first;
	endmethod
endmodule
