package MergeSortReducerSingle;
import FIFO::*;
import FIFOF::*;
import Clocks::*;
import Vector::*;

interface MergeSortReducerSingleEPIfc#(type keyType, type valType);
	method Action enq(keyType key, valType val, Bool last);
endinterface

interface MergeSortReducerSingleIfc#(numeric type inCnt, type keyType, type valType);
	interface Vector#(inCnt, MergeSortReducerSingleEPIfc#(keyType, valType)) enq;
	method ActionValue#(Tuple3#(keyType, valType, Bool)) get; // inType, last
endinterface

module mkMergeSortReducerSingle (MergeSortReducerSingleIfc#(n,k,v))
	provisos(
		Bits#(k,kSz), Eq#(k), Ord#(k), Add#(1,a__,kSz),
		Bits#(v,vSz), Add#(1,b__,vSz), Arith#(v)
	);
	FIFO#(Tuple3#(k,v,Bool)) outQ <- mkFIFO;
	Vector#(n, MergeSortReducerSingleEPIfc#(k,v)) enq_;

	if ( valueOf(n) == 1 ) begin
		enq_[0] = interface MergeSortReducerSingleEPIfc;
			method Action enq(k key, v val, Bool last);
				outQ.enq(tuple3(key,val,last));
			endmethod
		endinterface;
	end else if ( valueOf(n) == 2) begin
		Vector#(2, FIFO#(Tuple3#(k,v,Bool))) inQ <- replicateM(mkFIFO);
		FIFO#(Tuple3#(k,v,Bool)) midQ <- mkFIFO;
		Vector#(2,Reg#(Bool)) inDone <- replicateM(mkReg(False));
		rule merge (inDone[0] == False && inDone[1] == False);
			let d0 = inQ[0].first;
			let d1 = inQ[1].first;

			if ( tpl_1(d0) < tpl_1(d1) ) begin
				midQ.enq(tuple3(tpl_1(d0), tpl_2(d0), False));
				inQ[0].deq;
				inDone[0] <= tpl_3(d0);
			end else begin
				midQ.enq(tuple3(tpl_1(d1), tpl_2(d1), False));
				inQ[1].deq;
				inDone[1] <= tpl_3(d1);
			end
		endrule
		rule ff0 (inDone[0] == False && inDone[1] == True );
			let d0 = inQ[0].first;
			inQ[0].deq;
			if ( tpl_3(d0) ) begin
				midQ.enq(tuple3(tpl_1(d0), tpl_2(d0), True));
				inDone[1] <= False;
			end else begin
				midQ.enq(tuple3(tpl_1(d0), tpl_2(d0), False));
			end
		endrule
		rule ff1 (inDone[0] == True && inDone[1] == False );
			let d1 = inQ[1].first;
			inQ[1].deq;
			if ( tpl_3(d1) ) begin
				midQ.enq(tuple3(tpl_1(d1), tpl_2(d1), True));
				inDone[0] <= False;
			end else begin
				midQ.enq(tuple3(tpl_1(d1), tpl_2(d1), False));
			end
		endrule

		Reg#(Maybe#(Tuple2#(k,v))) lastVal <- mkReg(tagged Invalid);
		Reg#(Bool) flushLast <- mkReg(False);
		rule flushLastR (flushLast == True);
			flushLast <= False;
			let l = fromMaybe(?,lastVal);
			outQ.enq(tuple3(tpl_1(l), tpl_2(l), True));
			lastVal <= tagged Invalid;
		endrule
		rule reduce (flushLast == False);
			let r = midQ.first;
			midQ.deq;
			if (isValid(lastVal)) begin
				let l = fromMaybe(?,lastVal);
				if ( tpl_1(l) == tpl_1(r) ) begin
					if ( tpl_3(r) ) begin
						outQ.enq(tuple3(tpl_1(l), tpl_2(l)+tpl_2(r), True));
						lastVal <= tagged Invalid;
					end else begin
						lastVal <= tagged Valid tuple2(tpl_1(r),tpl_2(r));
						outQ.enq(tuple3(tpl_1(l), tpl_2(l), False));
					end
				end else begin
					outQ.enq(tuple3(tpl_1(l), tpl_2(l), False));
					lastVal <= tagged Valid tuple2(tpl_1(r),tpl_2(r));
					if ( tpl_3(r) ) begin
						// send lastVal, but at next cycle send r
						flushLast <= True;
					end
				end
			end else begin
				if ( tpl_3(r) ) begin
					outQ.enq(r);
				end else begin
					lastVal <= tagged Valid tuple2(tpl_1(r),tpl_2(r));
				end
			end
		endrule
		

		enq_[0] = interface MergeSortReducerSingleEPIfc;
			method Action enq(k key, v val, Bool last);
				inQ[0].enq(tuple3(key,val,last));
			endmethod
		endinterface;
		enq_[1] = interface MergeSortReducerSingleEPIfc;
			method Action enq(k key, v val, Bool last);
				inQ[1].enq(tuple3(key,val,last));
			endmethod
		endinterface;
	end else begin
		Vector#(2,MergeSortReducerSingleIfc#(TDiv#(n,2),k,v)) ma <- replicateM(mkMergeSortReducerSingle);
		MergeSortReducerSingleIfc#(2,k,v) m0 <- mkMergeSortReducerSingle;
		rule feed0;
			let r <- ma[0].get;
			m0.enq[0].enq(tpl_1(r),tpl_2(r),tpl_3(r));
		endrule
		rule feed1;
			let r <- ma[1].get;
			m0.enq[1].enq(tpl_1(r),tpl_2(r),tpl_3(r));
		endrule
		rule relayOut;
			let r <- m0.get;
			outQ.enq(r);
		endrule
		for ( Integer i = 0; i < valueOf(n); i=i+1 ) begin
			enq_[i] = interface MergeSortReducerSingleEPIfc;
				method Action enq(k key, v val, Bool last);
					if ( i < valueOf(n)/2 ) begin
						ma[0].enq[i].enq(key, val, last);
					end else begin
						ma[1].enq[i-(valueOf(n)/2)].enq(key,val,last);
					end
				endmethod
			endinterface;
		end
	end

	interface enq = enq_;
	method ActionValue#(Tuple3#(k,v,Bool)) get; // inType, last
		outQ.deq;
		return outQ.first;
	endmethod
endmodule

endpackage: MergeSortReducerSingle
