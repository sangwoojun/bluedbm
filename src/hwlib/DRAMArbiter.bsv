import FIFO::*;
import FIFOF::*;
import Vector::*;
import MergeN::*;
import DRAMController::*;


interface DRAMArbiterUserIfc;
	method Action cmd(Bit#(64) addr, Bit#(32) words, Bool write);
	method ActionValue#(Bit#(512)) read;
	method Action write(Bit#(512) data);
endinterface
interface DRAMArbiterIfc #(numeric type ways);
	interface Vector#(ways, DRAMArbiterUserIfc) users;
endinterface

module mkDRAMArbiter#(DRAMUserIfc dram) (DRAMArbiterIfc#(ways));

	MergeNIfc#(ways, Tuple4#(Bit#(8), Bit#(64), Bit#(32), Bool)) mreq <- mkMergeN;
	Vector#(ways, FIFO#(Bit#(512))) resQv <- replicateM(mkSizedFIFO(8));
	Vector#(ways, FIFO#(Bit#(512))) writeQv <- replicateM(mkSizedFIFO(8));

	FIFO#(Bit#(8)) reqQ <- mkSizedFIFO(256);

	Reg#(Bit#(32)) curWordLeft <- mkReg(0);
	Reg#(Bit#(8)) curSrc <- mkReg(0);
	Reg#(Bit#(64)) curAddr <- mkReg(0);
	Reg#(Bool) curCmdIsWrite <- mkReg(?);
	rule dramReq ( curWordLeft == 0 );
		mreq.deq;
		let r = mreq.first;
		
		let src = tpl_1(r);
		let addr = tpl_2(r);
		let words = tpl_3(r);
		let write = tpl_4(r);

		if ( words > 0 ) begin
			curWordLeft <= words - 1;
			curAddr <= addr + 64;
			curCmdIsWrite <= write;
			curSrc <= src;
		end

		if ( write) begin
			dram.write(addr, writeQv[src].first, 7'b1000000);
			writeQv[src].deq;
			//dram.write(addr, 0,7'b1000000);
			//$display("DRAM write req from %d %x %x", src, addr, words);
		end else begin
			dram.readReq(addr, 7'b1000000);
			reqQ.enq(src);
			//$display("DRAM read req from %d %x %x", src, addr, words);
		end
	endrule

	rule doWrite(curCmdIsWrite == True && curWordLeft > 0);
		$display("sending DRAM write req %x", curAddr);
		dram.write(curAddr, writeQv[curSrc].first, 7'b1000000);
		writeQv[curSrc].deq;
		curAddr <= curAddr + 64;
		curWordLeft <= curWordLeft - 1;
		//dram.write(curAddr, 0,7'b1000000);
	endrule

	rule doRead(curCmdIsWrite == False && curWordLeft > 0);
		//$display("sending DRAM read req %x", curAddr);
		dram.readReq(curAddr, 7'b1000000);
		reqQ.enq(curSrc);
		curAddr <= curAddr + 64;
		curWordLeft <= curWordLeft - 1;
	endrule

	rule dramRes;
		let d <- dram.read;
		//$display("receiving DRAM read resp %x", d);

		reqQ.deq;
		let src = reqQ.first;

		resQv[src].enq(d);
	endrule

	Vector#(ways, DRAMArbiterUserIfc) users_;

	for (Integer i = 0; i < valueOf(ways); i=i+1 ) begin
		users_[i] = interface DRAMArbiterUserIfc;
		method Action cmd(Bit#(64) addr, Bit#(32) words, Bool write);
			mreq.enq[i].enq(tuple4(fromInteger(i), addr, words, write));
		endmethod
		method ActionValue#(Bit#(512)) read;
			resQv[i].deq;
			return resQv[i].first;
		endmethod
		method Action write(Bit#(512) data);
			writeQv[i].enq(data);
		endmethod
		endinterface: DRAMArbiterUserIfc;
	end
	interface users = users_;
endmodule
