import FIFO::*;
import FIFOF::*;
import Clocks::*;
import Vector::*;

import BRAM::*;
import BRAMFIFO::*;

interface MergeSorterIfc#(type itype);
	method Action enq1(Maybe#(itype) data);
	method Action enq2(Maybe#(itype) data);
	method Maybe#(itype) first;
	method Action deq;
endinterface

module mkMergeSorter#(Bool descending) (MergeSorterIfc#(itype))
	provisos(
	Ord#(itype), Bits#(Maybe#(itype),itypem),
	Bits#(itype,itypeSz)
	);

	FIFO#(Maybe#(itype)) inQ1 <- mkFIFO;
	FIFO#(Maybe#(itype)) inQ2 <- mkFIFO;

	FIFO#(Maybe#(itype)) outQ <- mkFIFO;
	FIFO#(itype) midQ1 <- mkFIFO;
	FIFO#(itype) midQ2 <- mkFIFO;

	rule merge;
		let d1 = inQ1.first;
		let d2 = inQ2.first;
		let i1 = fromMaybe(?,d1);
		let i2 = fromMaybe(?,d2);

		// all done!
		if ( !isValid(d1) && !isValid(d2) ) begin
			inQ1.deq;
			inQ2.deq;
			outQ.enq(tagged Invalid);
		end
		else if ( !isValid(d1) ) begin
			inQ2.deq;
			outQ.enq(d2);
		end
		else if ( !isValid(d2) ) begin
			inQ1.deq;
			outQ.enq(d1);
		end
		else begin
			if ( i1 > i2 ) begin
				if ( descending ) begin
					inQ1.deq;
					outQ.enq(d1);
				end else begin
					inQ2.deq;
					outQ.enq(d2);
				end
			end else begin
				if ( descending ) begin
					inQ2.deq;
					outQ.enq(d2);
				end else begin
					inQ1.deq;
					outQ.enq(d1);
				end
			end

		end
	endrule

	method Action enq1(Maybe#(itype) data);
		inQ1.enq(data);
	endmethod
	method Action enq2(Maybe#(itype) data);
		inQ2.enq(data);
	endmethod
	method Maybe#(itype) first;
		return outQ.first;
	endmethod
	method Action deq;
		outQ.deq;
	endmethod
endmodule

/*
datSz layout:
valid[1],data[len-1]
*/

interface BulkMergeSorterEnqIfc#(numeric type inSz);
	method Action enq(Bit#(inSz) data);
endinterface

interface BulkMergeSorterIfc#(numeric type inSz, numeric type datSz);
	interface Vector#(2,BulkMergeSorterEnqIfc#(inSz)) enq;

	method ActionValue#(Bit#(1)) stat; // FIXME probably needs more bits
	method Bit#(inSz) first;
	method Action deq;
endinterface

module mkBulkMergeSorter#(Bool descending, Integer bufsize, Integer bufcount) (BulkMergeSorterIfc#(inSz,datSz))
	provisos( Add#(1, a__, inSz));

	MergeSorterIfc#(Bit#(datSz)) sorter <- mkMergeSorter(descending);

	Vector#(2,FIFO#(Bit#(inSz))) buffers <- replicateM(mkSizedBRAMFIFO(bufsize*bufcount));


	
	Vector#(2, BulkMergeSorterEnqIfc#(inSz)) enq_;
	for ( Integer i = 0; i < 2; i = i + 1 )  begin
		enq_[i] = interface BulkMergeSorterEnqIfc;
			method Action enq(Bit#(inSz) data);
				buffers[i].enq(data);
			endmethod
		endinterface: BulkMergeSorterEnqIfc;
	end
	interface enq = enq_;
	method ActionValue#(Bit#(1)) stat; // FIXME probably needs more bits
		return 0;
	endmethod
	method Bit#(inSz) first;
		return ?;
	endmethod 
	method Action deq;
	endmethod
endmodule


