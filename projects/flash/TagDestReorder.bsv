import MergeN::*;

import FIFO::*;
import FIFOF::*;
import Vector::*;
import BRAM::*;
import BRAMFIFO::*;


interface TagDestReorderIfc#(numeric type destCount);
	method Action tagReady(Bit#(8) tag);
	method Action destReady(Bit#(8) dest);

	method Action tagDestReq(Bit#(8) tag, Bit#(8) dest);

	method ActionValue#(Tuple2#(Bit#(8), Bit#(8))) tagDestReady;
endinterface

module mkTagDestReorder (TagDestReorderIfc#(destCount));
	Integer dcount = valueOf(destCount);

	Vector#(destCount, Reg#(Bit#(16))) destReadyUp <- replicateM(mkReg(0));
	Vector#(destCount, Reg#(Bit#(16))) destReadyDown <- replicateM(mkReg(0));

	Vector#(destCount, FIFOF#(Bit#(8))) tagReq <- replicateM(mkSizedBRAMFIFOF(256));
	
	Merge2Ifc#(Bit#(8)) mcachedTag <- mkMerge2;
	FIFO#(Bit#(8)) cachedTagQ <- mkSizedBRAMFIFO(256);
	rule relayReadDoneTag;
		mcachedTag.deq;
		cachedTagQ.enq(mcachedTag.first);
	endrule

	MergeNIfc#(destCount,Tuple2#(Bit#(8), Bit#(8))) mready <- mkMergeN;

	Vector#(TAdd#(1,destCount), FIFO#(Bit#(8))) readyTagRelay <- replicateM(mkFIFO);
	for ( Integer i = 0; i < dcount; i=i+1 ) begin
		rule checkdestready;
			let d = readyTagRelay[i].first;
			readyTagRelay[i].deq;

			if ( tagReq[i].notEmpty && 
				destReadyUp[i]-destReadyDown[i] > 0 ) begin
				if ( tagReq[i].first == d ) begin
					mready.enq[i].enq(tuple2(d, fromInteger(i)));
					destReadyDown[i] <= destReadyDown[i] + 1;
					tagReq[i].deq;
				end else begin
					readyTagRelay[i+1].enq(d);
				end
			end else begin
				readyTagRelay[i+1].enq(d);
			end
		endrule
	end
	rule relaydq;
		cachedTagQ.deq;
		readyTagRelay[0].enq(cachedTagQ.first);
	endrule
	rule loopdq;
		readyTagRelay[dcount].deq;
		mcachedTag.enq[1].enq(readyTagRelay[dcount].first);
	endrule


	method Action tagReady(Bit#(8) tag);
		mcachedTag.enq[0].enq(tag);
		$display( "tagReady %d", tag );
	endmethod
	method Action destReady(Bit#(8) dest);
		destReadyUp[dest] <= destReadyUp[dest] + 1;
		$display( "destReady %d", dest );
	endmethod
	
	method Action tagDestReq(Bit#(8) tag, Bit#(8) dest);
		tagReq[dest].enq(tag);
		$display( "tag dest requested %d", tag, dest );
	endmethod

	method ActionValue#(Tuple2#(Bit#(8), Bit#(8))) tagDestReady;
		mready.deq;
		return mready.first;
	endmethod
endmodule
