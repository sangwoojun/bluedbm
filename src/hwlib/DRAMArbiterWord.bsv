import FIFO::*;
import FIFOF::*;
import Vector::*;
import MergeN::*;
import DRAMController::*;


interface DRAMArbiterUserIfc;
	method Action readReq(Bit#(64) addr, Bit#(7) bytes);
	method ActionValue#(Bit#(512)) read;
	method Action write(Bit#(64) addr, Bit#(512) val, Bit#(7) bytes);
endinterface
interface DRAMArbiterIfc #(numeric type ways);
	interface Vector#(ways, DRAMArbiterUserIfc) users;
endinterface

module mkDRAMArbiter#(DRAMUserIfc dram) (DRAMArbiterIfc#(ways));

	MergeNIfc#(ways, Tuple3#(Bit#(8), Bit#(64), Bit#(7))) mreq <- mkMergeN;
	Vector#(ways, FIFO#(Bit#(512))) resQv <- replicateM(mkFIFO);

	FIFO#(Bit#(8)) reqQ <- mkSizedFIFO(256);
	rule dramReq;
		mreq.deq;
		let r = mreq.first;
		
		let src = tpl_1(r);
		let addr = tpl_2(r);
		let bytes = tpl_3(r);

		reqQ.enq(src);
		dram.readReq(addr, bytes);
	endrule

	rule dramRes;
		let d <- dram.read;

		reqQ.deq;
		let src = reqQ.first;

		resQv[src].enq(d);
	endrule

	Vector#(ways, DRAMArbiterUserIfc) users_;

	for (Integer i = 0; i < valueOf(ways); i=i+1 ) begin
		users_[i] = interface DRAMArbiterUserIfc;
		method Action readReq(Bit#(64) addr, Bit#(7) bytes);
			//mreq.enq[i].enq(tuple3(fromInteger(i), addr, bytes));
			dram.readReq(addr,bytes);
			reqQ.enq(fromInteger(i));
		endmethod
		method ActionValue#(Bit#(512)) read;
			resQv[i].deq;
			return resQv[i].first;
		endmethod
		method Action write(Bit#(64) addr, Bit#(512) val, Bit#(7) bytes);
			dram.write(addr,val,bytes);
		endmethod
		endinterface: DRAMArbiterUserIfc;
	end
	interface users = users_;
endmodule
