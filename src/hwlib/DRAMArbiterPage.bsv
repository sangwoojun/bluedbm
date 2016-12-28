import FIFO::*;
import FIFOF::*;
import Vector::*;
import MergeN::*;
import DRAMController::*;

import BRAMFIFO::*;

interface DRAMPageUserIfc;
	method Action cmd(Bit#(64) addr, Bit#(8) words, Bool write);
	method ActionValue#(Bit#(512)) read;
	method Action write(Bit#(512) data);
endinterface

interface DRAMArbiterPageIfc #(numeric type ways);
	interface Vector#(ways, DRAMPageUserIfc) users;
endinterface

module mkDRAMArbiterPage#(DRAMUserIfc dram) (DRAMArbiterPageIfc#(ways))
	provisos( Add#(1, a__, TLog#(ways)));

	Vector#(ways, FIFO#(Tuple2#(Bit#(64), Bit#(8)))) wcmdQ <- replicateM(mkFIFO);
	Vector#(ways, FIFO#(Tuple2#(Bit#(64), Bit#(8)))) rcmdQ <- replicateM(mkFIFO);
	Vector#(ways, FIFO#(Bit#(512))) wdataQ <- replicateM(mkSizedBRAMFIFO(256));
	Vector#(ways, FIFO#(Bit#(512))) rdataQ <- replicateM(mkSizedBRAMFIFO(256));
	Vector#(ways, Reg#(Bit#(8))) routCnt <- replicateM(mkReg(0));
	Vector#(ways, Reg#(Bit#(8))) winCnt <- replicateM(mkReg(0));
	Vector#(ways, Reg#(Bit#(8))) rinCnt <- replicateM(mkReg(0));
	Vector#(ways, Reg#(Bit#(8))) woutCnt <- replicateM(mkReg(0));

	Reg#(Bit#(8)) curReadCnt <- mkReg(0);
	Reg#(Bit#(64)) curReadAddr <- mkReg(0);
	Reg#(Bit#(8)) curWriteCnt <- mkReg(0);
	Reg#(Bit#(64)) curWriteAddr <- mkReg(0);
	Reg#(Bit#(TLog#(ways))) curActiveWay <- mkReg(0);
	for ( Integer i = 0; i < valueOf(ways); i=i+1 ) begin

		rule initRead ( curReadCnt == 0 && curWriteCnt == 0 && rinCnt[i]-routCnt[i] <= 128 );
			rcmdQ[i].deq;
			let addr = tpl_1(rcmdQ[i].first);
			let cnt = tpl_2(rcmdQ[i].first);
			curReadCnt <= cnt;
			curReadAddr <= addr;
			curActiveWay <= fromInteger(i);
		endrule
		rule initReadWrite ( curReadCnt == 0 && curWriteCnt == 0 && winCnt[i]-woutCnt[i] >= 128 );
			wcmdQ[i].deq;
			let addr = tpl_1(wcmdQ[i].first);
			let cnt = tpl_2(wcmdQ[i].first);
			curWriteCnt <= cnt;
			curWriteAddr <= addr;
			curActiveWay <= fromInteger(i);
		endrule
	end

	FIFO#(Bit#(TLog#(ways))) readWayQ <- mkSizedBRAMFIFO(200); //125 should be enough
	rule readCmd ( curReadCnt > 0 );
		curReadCnt <= curReadCnt - 1;
		curReadAddr <= curReadAddr + 64;
		dram.readReq(curReadAddr, 7'b1111111);
		readWayQ.enq(curActiveWay);
	endrule
	rule readResp;
		readWayQ.deq;
		let w = readWayQ.first;
		let d <- dram.read;
		rdataQ[w].enq(d);
		rinCnt[w] <= rinCnt[w] + 1;
	endrule

	rule writeCmd ( curWriteCnt > 0 );
		curWriteCnt <= curWriteCnt - 1;
		curWriteAddr <= curWriteAddr + 64;
		dram.write(curWriteAddr, wdataQ[curActiveWay].first, 7'b1111111);
		wdataQ[curActiveWay].deq;
		woutCnt[curActiveWay] <= woutCnt[curActiveWay] + 1;
	endrule

	Vector#(ways, DRAMPageUserIfc) users_;
	for (Integer i=0; i < valueOf(ways); i=i+1 ) begin
		users_[i] = interface DRAMPageUserIfc;
			method Action cmd(Bit#(64) addr, Bit#(8) words, Bool write);
				if ( write ) begin
					wcmdQ[i].enq(tuple2(addr,words));
				end else begin
					rcmdQ[i].enq(tuple2(addr,words));
				end
			endmethod
			method ActionValue#(Bit#(512)) read;
				routCnt[i] <= routCnt[i] + 1;
				rdataQ[i].deq;
				return rdataQ[i].first;
			endmethod
			method Action write(Bit#(512) data);
				wdataQ[i].enq(data);
				winCnt[i] <= winCnt[i] + 1;
			endmethod
		endinterface : DRAMPageUserIfc;
	end
	interface users = users_;
endmodule
