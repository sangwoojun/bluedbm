package PageSorterSingle;
import FIFO::*;
import FIFOF::*;
import Clocks::*;
import Vector::*;

import BRAM::*;
import BRAMFIFO::*;

import ScatterN::*;

import MergeSorter::*;
import SortingNetwork::*;
import PageSorter::*;

interface PageSorterSingleIfc#(type inType, numeric type pageSz);
	method Action enq(inType data);
	method ActionValue#(inType) get;
endinterface

// preSorted == 3 would mean data is already sorted in 3-element chunks
module mkPageSorterSingle#(Integer preSorted, Bool descending) (PageSorterSingleIfc#(inType, pageSz))
	provisos(
	Bits#(inType, inTypeSz)
	, Add#(1,a__,inTypeSz)
	, Literal#(inType)
	, Ord#(inType)
	);

	Integer iPageSz = valueOf(pageSz);
	Integer pageSize = 2**iPageSz;

	SingleMergerIfc#(inType,16) merger <- mkSingleMerger(descending);

	Vector#(2,FIFO#(inType)) buffers <- replicateM(mkSizedBRAMFIFO(pageSize/2));
	Reg#(Bit#(32)) curStride <- mkReg(0);
	Reg#(Bit#(32)) strideSum <- mkReg(0);

	FIFO#(Bit#(16)) cmdQ <- mkFIFO;
	rule genCmd (curStride > 0);
		//cmdQ.enq(curStride*fromInteger(tupleCount));
		merger.runMerge(truncate(curStride));

		if ( strideSum + curStride >= fromInteger(pageSize)/2 ) begin
			if ( curStride >= fromInteger(pageSize)/2 ) begin
				curStride <= 0;
			end else begin
				curStride <= (curStride<<1);
				strideSum <= 0;
			end
		end
		else begin
			strideSum <= strideSum + curStride;
		end
	endrule







	
	Vector#(2,Reg#(Bit#(32))) totalInsCount <- replicateM(mkReg(0));
	for ( Integer i = 0; i < 2; i = i + 1 ) begin
		
		rule insertData ( totalInsCount[i] > 0);
			buffers[i].deq;

			let d = buffers[i].first;
			if ( i == 0 ) merger.enq1(d);
			else if ( i == 1 ) merger.enq2(d);

			totalInsCount[i] <= totalInsCount[i] - 1;
		endrule
	end


	
	//Reg#(Bit#(32)) curStrideOut <- mkReg(0);
	FIFO#(inType) readQ <- mkSizedBRAMFIFO(pageSize/2);
	rule readSorted;
		let d <- merger.get;
		readQ.enq(d);
	endrule





	Reg#(Bit#(32)) curInsCount <- mkReg(0);
	Reg#(Bit#(32)) curInsStride <- mkReg(0);
	Reg#(Bit#(32)) insStrideCount <- mkReg(0);
	Reg#(Bit#(32)) totalReadCount <- mkReg(0);
	FIFO#(inType) outQ <- mkFIFO;


	rule insData ( curInsStride > 0 );
		readQ.deq;
		let d = readQ.first;
		if ( curInsStride >= fromInteger(pageSize) ) begin
			outQ.enq(d);
		end else begin
			buffers[insStrideCount[0]].enq(d);
		end


		if ( curInsCount + 1 >= curInsStride ) begin
			curInsCount <= 0;
			insStrideCount <= insStrideCount + 1;
			//$display( "stride done" );
		end else begin
			curInsCount <= curInsCount + 1;
		end
		if ( totalReadCount + 1 >= fromInteger(pageSize) ) begin
			totalReadCount <= 0;
			if ( curInsStride >= fromInteger(pageSize) ) begin
				curInsStride <= 0;
				//$display("Finished sorting page");
			end else begin
				curInsStride <= (curInsStride<<1);
			end
		end else begin
			totalReadCount <= totalReadCount + 1;
		end

	endrule




	Reg#(Bit#(32)) enqIdx <- mkReg(0);
	//NOTE: data is assumed already sorted internally!
	method Action enq(inType data) if (curInsStride == 0);
		//$display( "Sort enq" );
		buffers[enqIdx[0]].enq(data);
		//bufferCntUp[enqIdx[0]] <= bufferCntUp[enqIdx[0]] + 1;
		if ( enqIdx+1 < fromInteger(pageSize) ) begin
			enqIdx <= enqIdx + 1;
		end
		else begin
			curStride <= fromInteger(2**preSorted);
			totalInsCount[0] <= fromInteger(iPageSz) * fromInteger(pageSize)/2;
			totalInsCount[1] <= fromInteger(iPageSz) * fromInteger(pageSize)/2;
			curInsStride <= 2;
			enqIdx <= 0;
		end
	endmethod
	method ActionValue#(inType) get;
		outQ.deq;
		return outQ.first;
	endmethod
endmodule

endpackage: PageSorterSingle
