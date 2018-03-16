import FIFO::*;
import FIFOF::*;
import Clocks::*;
import Vector::*;

import BRAM::*;
import BRAMFIFO::*;

import ScatterN::*;

import MergeSorter::*;
import SortingNetwork::*;

interface BitonicSorterIfc#(numeric type vcnt, type inType);
	method Vector#(vcnt, inType) sort(Vector#(vcnt, inType) data);
endinterface

module mkBitonicSorter#(Bool descending) ( BitonicSorterIfc#(vcnt, inType) )
	provisos(Bits#(inType,inTypeSz), Ord#(inType), Add#(1,a__,inTypeSz));

	method Vector#(vcnt, inType) sort(Vector#(vcnt, inType) data);
		return sortBitonic(data, descending);
	endmethod
endmodule


/**
**/

interface SingleMergerIfc#(type inType, numeric type cntSz);
	method Action enq1(inType data);
	method Action enq2(inType data);
	method Action runMerge(Bit#(cntSz) count);
	method ActionValue#(inType) get;
endinterface

module mkSingleMerger#(Bool descending) (SingleMergerIfc#(inType, cntSz))
	provisos(Bits#(inType,inTypeSz), Ord#(inType), Add#(1,a__,inTypeSz));
	Reg#(Bit#(cntSz)) mCountTotal <- mkReg(0);
	Reg#(Bit#(cntSz)) mCount1 <- mkReg(0);
	Reg#(Bit#(cntSz)) mCount2 <- mkReg(0);

	FIFO#(inType) inQ1 <- mkFIFO;
	FIFO#(inType) inQ2 <- mkFIFO;

	FIFO#(inType) outQ <- mkFIFO;

	rule ff1 (mCount1 > 0 && mCount2 == 0);
		mCountTotal <= mCountTotal - 1;
		inQ1.deq;
		outQ.enq(inQ1.first);
		mCount1 <= mCount1 - 1;
	endrule
	rule ff2 (mCount1 == 0 && mCount2 > 0);
		mCountTotal <= mCountTotal - 1;
		inQ2.deq;
		outQ.enq(inQ2.first);
		mCount2 <= mCount2 - 1;
	endrule
	rule doMerge (mCount1 > 0 && mCount2 > 0 );
		mCountTotal <= mCountTotal - 1;
		let d1 = inQ1.first;
		let d2 = inQ2.first;
		if ( descending ) begin
			if ( d1 > d2 ) begin
				outQ.enq(d1);
				inQ1.deq;
				mCount1 <= mCount1 -1;
			end else begin
				outQ.enq(d2);
				inQ2.deq;
				mCount2 <= mCount2 -1;
			end
		end else begin
			if ( d1 > d2 ) begin
				outQ.enq(d2);
				inQ2.deq;
				mCount2 <= mCount2 -1;
			end else begin
				outQ.enq(d1);
				inQ1.deq;
				mCount1 <= mCount1 -1;
			end
		end
	endrule

	method Action enq1(inType data);
		inQ1.enq(data);
	endmethod
	method Action enq2(inType data);
		inQ2.enq(data);
	endmethod
	method Action runMerge(Bit#(cntSz) count) if (mCountTotal == 0);
		mCountTotal <= count * 2;
		mCount1 <= count;
		mCount2 <= count;
	endmethod
	method ActionValue#(inType) get;
		outQ.deq;
		return outQ.first;
	endmethod
endmodule

interface PageSorterIfc#(type inType, numeric type tupleCount, numeric type pageSz);
	method Action enq(Vector#(tupleCount,inType) data);
	method ActionValue#(Vector#(tupleCount,inType)) get;
endinterface

/*
module mkPageSorter#(Bool descending) (PageSorterIfc#(inType, tupleCount, pageSz))
	provisos(
	Bits#(Vector::Vector#(tupleCount, inType), inVSz)
	, Add#(1,b__,inVSz)
	, Bits#(inType, inTypeSz)
	, Add#(1,c__,inTypeSz)
	, Literal#(inType)
	, Ord#(inType)
	);

	Integer iPageSz = valueOf(pageSz);
	Integer pageSize = 2**iPageSz;
	Integer iTupleCount = valueOf(tupleCount);

	SingleMergerIfc#(inType,16) merger <- mkSingleMerger(descending);
	//VectorMergerIfc#(tupleCount, inType,16) merger <- mkVectorMerger(descending);

	Vector#(2,FIFO#(Vector#(tupleCount,inType))) buffers <- replicateM(mkSizedBRAMFIFO(pageSize/2));
	//Vector#(2, Reg#(Bit#(32))) bufferCntUp <- replicateM(mkReg(0));
	//Vector#(2, Reg#(Bit#(32))) bufferCntDown <- replicateM(mkReg(0));

	Reg#(Bit#(32)) curStride <- mkReg(0);
	Reg#(Bit#(32)) strideSum <- mkReg(0);

	FIFO#(Bit#(16)) cmdQ <- mkFIFO;
	rule genCmd (curStride > 0);
		//cmdQ.enq(curStride*fromInteger(tupleCount));
		Bit#(16) mergeStride = truncate(curStride*fromInteger(iTupleCount));
		merger.runMerge(mergeStride);
		//$display( "merger inserting command for stride %d (%d)", mergeStride, strideSum );

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







	
	//Vector#(2,FIFO#(Vector#(tupleCount, inType))) insQ <- replicateM(mkFIFO);
	Vector#(2,Reg#(Bit#(32))) totalInsCount <- replicateM(mkReg(0));
	for ( Integer i = 0; i < 2; i = i + 1 ) begin
		
		Reg#(Vector#(tupleCount, inType)) insBuf <- mkReg(?);
		Reg#(Bit#(8)) vecIdx <- mkReg(0);
		rule startInsertData ( totalInsCount[i] > 0 && vecIdx == 0);
			buffers[i].deq;
			//bufferCntDown[i] <= bufferCntDown[i] + 1;

			let d = buffers[i].first;
			insBuf <= d;
			if ( i == 0 ) merger.enq1(d[0]);
			else if ( i == 1 ) merger.enq2(d[0]);

			vecIdx <= fromInteger(iTupleCount)-1;
			totalInsCount[i] <= totalInsCount[i] - 1;
			//$display( "inserting data from %d", i );
		endrule
		rule insertData ( vecIdx > 0 );
			vecIdx <= vecIdx - 1;
			let idx = fromInteger(iTupleCount)-vecIdx;
			if ( i == 0 ) merger.enq1(insBuf[idx]);
			else if ( i == 1 ) merger.enq2(insBuf[idx]);
		endrule
	end


	
	//Reg#(Bit#(32)) curStrideOut <- mkReg(0);
	FIFO#(Vector#(tupleCount, inType)) readQ <- mkSizedBRAMFIFO(pageSize/2);
	Vector#(tupleCount, Reg#(inType)) readBuf <- replicateM(mkReg(0));
	Reg#(Bit#(8)) readIdx <- mkReg(0);
	rule readSorted;
		let d <- merger.get;
		if ( readIdx + 1 >= fromInteger(iTupleCount) ) begin
			Vector#(tupleCount, inType) readv;
			for ( Integer i = 0; i < iTupleCount; i=i+1) begin
				readv[i] = readBuf[i];
			end
			readv[iTupleCount-1] = d;
			readQ.enq(readv);
			readIdx <= 0;
		end else begin
			readBuf[readIdx] <= d;
			readIdx <= readIdx + 1;
		end
	endrule





	Reg#(Bit#(32)) curInsCount <- mkReg(0);
	Reg#(Bit#(32)) curInsStride <- mkReg(0);
	Reg#(Bit#(32)) insStrideCount <- mkReg(0);
	Reg#(Bit#(32)) totalReadCount <- mkReg(0);
	FIFO#(Vector#(tupleCount, inType)) outQ <- mkFIFO;


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
	method Action enq(Vector#(tupleCount,inType) data) if (curInsStride == 0);
		//$display( "Sort enq" );
		buffers[enqIdx[0]].enq(data);
		//bufferCntUp[enqIdx[0]] <= bufferCntUp[enqIdx[0]] + 1;
		if ( enqIdx+1 < fromInteger(pageSize) ) begin
			enqIdx <= enqIdx + 1;
		end
		else begin
			curStride <= 1;
			totalInsCount[0] <= fromInteger(iPageSz) * fromInteger(pageSize)/2;
			totalInsCount[1] <= fromInteger(iPageSz) * fromInteger(pageSize)/2;
			curInsStride <= 2;
			enqIdx <= 0;
		end
	endmethod
	method ActionValue#(Vector#(tupleCount,inType)) get;
		outQ.deq;
		return outQ.first;
	endmethod
endmodule
*/


interface MultiPageSorterIfc#(numeric type ways, type inType, numeric type tupleCount, numeric type pageSz);
	method Action enq(Vector#(tupleCount,inType) data);
	method ActionValue#(Vector#(tupleCount,inType)) get;
endinterface


module mkMultiPageSorter#( Bool descending) (MultiPageSorterIfc#(ways, inType, tupleCount, pageSz))
	provisos(
	Bits#(Vector::Vector#(tupleCount, inType), inVSz)
	, Add#(1,a__,ways)
	, Add#(1,b__,inVSz)
	, Bits#(inType, inTypeSz)
	, Add#(1,c__,inTypeSz)
	, Literal#(inType)
	, Ord#(inType)
	);

	Integer iPageSz = valueOf(pageSz);
	Integer pageSize = 2**iPageSz;
	Integer iTupleCount = valueOf(tupleCount);
	Integer iWays = valueOf(ways);

	Vector#(ways, PageSorterIfc#(inType,tupleCount,pageSz)) sorters;
	for ( Integer i = 0; i < iWays; i=i+1 ) begin
		sorters[i] <- mkPageSorterV(descending);
	end
	//Vector#(ways, Reg#(Bit#(pageSz))) inCntUp <- replicateM(mkReg(0));
	//Vector#(ways, Reg#(Bit#(pageSz))) inCntDown <- replicateM(mkReg(0));

	FIFO#(Bit#(TLog#(ways))) enqAvailQ <- mkSizedFIFO(fromInteger(iWays));
	FIFO#(Bit#(TLog#(ways))) deqAvailQ <- mkSizedFIFO(fromInteger(iWays));
	Reg#(Bit#(TAdd#(1,TLog#(ways)))) initQcounter <- mkReg(fromInteger(iWays));
	rule initQs(initQcounter > 0);
		initQcounter <= initQcounter - 1;
		enqAvailQ.enq(truncate(initQcounter-1));
	endrule
	Reg#(Bit#(TAdd#(1,pageSz))) enqoff <- mkReg(0);
	Reg#(Bit#(TAdd#(1,pageSz))) deqoff <- mkReg(0);
	Reg#(Bit#(TLog#(ways))) curenq <- mkReg(0);
	Reg#(Bit#(TLog#(ways))) curdeq <- mkReg(0);

	FIFO#(Vector#(tupleCount,inType)) enqQ <- mkFIFO;
	FIFO#(Vector#(tupleCount,inType)) deqQ <- mkFIFO;

	FIFO#(Tuple2#(Bit#(TLog#(ways)),Vector#(tupleCount,inType))) enqdQ <- mkFIFO;
	ScatterNIfc#(ways,Vector#(tupleCount,inType)) sdin <- mkScatterN;

	rule enqdata;
		let target = curenq;
		if ( enqoff == 0 ) begin
			target = enqAvailQ.first;
			enqAvailQ.deq;
			curenq <= target;
			deqAvailQ.enq(target);
		end 
		
		if ( enqoff + 1 >= fromInteger(pageSize) ) begin
			enqoff <= 0;
		end else begin
			enqoff <= enqoff + 1;
		end

		//enqdQ.enq(tuple2(target,enqQ.first));
		sdin.enq(enqQ.first,target);
		enqQ.deq;
	endrule
	
	for ( Integer i = 0; i < iWays; i=i+1 ) begin
		rule sorterenqdata;
			let d <- sdin.get[i].get;
			sorters[i].enq(d);
		endrule
	end
	
	/*
	rule sorterenqdata;
		enqdQ.deq;
		let d = enqdQ.first;
		sorters[tpl_1(d)].enq(tpl_2(d));
	endrule
	*/

	rule deqdata;
		let src = curdeq;
		if ( deqoff == 0 ) begin
			src = deqAvailQ.first;
			deqAvailQ.deq;
			curdeq <= src;
			enqAvailQ.enq(src);
		end

		if ( deqoff + 1 >= fromInteger(pageSize) ) begin
			deqoff <= 0;
		end else begin
			deqoff <= deqoff + 1;
		end

		let d <- sorters[src].get;
		deqQ.enq(d);
	endrule



	method Action enq(Vector#(tupleCount,inType) data);
		enqQ.enq(data);
	endmethod
	method ActionValue#(Vector#(tupleCount,inType)) get;
		deqQ.deq;
		return deqQ.first;
	endmethod
endmodule

module mkMultiPageSorterToCC#(Clock fastclk, Reset fastrst, Bool descending) (MultiPageSorterIfc#(ways, inType, tupleCount, pageSz))
	provisos(
	Bits#(Vector::Vector#(tupleCount, inType), inVSz)
	, Add#(1,a__,ways)
	, Add#(1,b__,inVSz)
	, Bits#(inType, inTypeSz)
	, Add#(1,c__,inTypeSz)
	, Literal#(inType)
	, Ord#(inType)
	);

	Integer iPageSz = valueOf(pageSz);
	Integer pageSize = 2**iPageSz;
	Integer iTupleCount = valueOf(tupleCount);
	Integer iWays = valueOf(ways);

	Vector#(ways, PageSorterIfc#(inType,tupleCount,pageSz)) sorters;
	for ( Integer i = 0; i < iWays; i=i+1 ) begin
		sorters[i] <- mkPageSorterV(descending);
	end
	//Vector#(ways, Reg#(Bit#(pageSz))) inCntUp <- replicateM(mkReg(0));
	//Vector#(ways, Reg#(Bit#(pageSz))) inCntDown <- replicateM(mkReg(0));

	FIFO#(Bit#(TLog#(ways))) enqAvailQ <- mkSizedFIFO(fromInteger(iWays), clocked_by fastclk, reset_by fastrst);
	FIFO#(Bit#(TLog#(ways))) deqAvailQ <- mkSizedFIFO(fromInteger(iWays), clocked_by fastclk, reset_by fastrst);
	Reg#(Bit#(TAdd#(1,TLog#(ways)))) initQcounter <- mkReg(fromInteger(iWays), clocked_by fastclk, reset_by fastrst);
	rule initQs(initQcounter > 0);
		initQcounter <= initQcounter - 1;
		enqAvailQ.enq(truncate(initQcounter-1));
	endrule
	Reg#(Bit#(TAdd#(1,pageSz))) enqoff <- mkReg(0, clocked_by fastclk, reset_by fastrst);
	Reg#(Bit#(TAdd#(1,pageSz))) deqoff <- mkReg(0, clocked_by fastclk, reset_by fastrst);
	Reg#(Bit#(TLog#(ways))) curenq <- mkReg(0, clocked_by fastclk, reset_by fastrst);
	Reg#(Bit#(TLog#(ways))) curdeq <- mkReg(0, clocked_by fastclk, reset_by fastrst);

	FIFO#(Vector#(tupleCount,inType)) enqQ <- mkFIFO(clocked_by fastclk, reset_by fastrst);
	FIFO#(Vector#(tupleCount,inType)) deqQ <- mkFIFO(clocked_by fastclk, reset_by fastrst);

	FIFO#(Tuple2#(Bit#(TLog#(ways)),Vector#(tupleCount,inType))) enqdQ <- mkFIFO;
	ScatterNIfc#(ways,Vector#(tupleCount,inType)) sdin <- mkScatterN(clocked_by fastclk, reset_by fastrst);

	rule enqdata;
		let target = curenq;
		if ( enqoff == 0 ) begin
			target = enqAvailQ.first;
			enqAvailQ.deq;
			curenq <= target;
			deqAvailQ.enq(target);
		end 
		
		if ( enqoff + 1 >= fromInteger(pageSize) ) begin
			enqoff <= 0;
		end else begin
			enqoff <= enqoff + 1;
		end

		//enqdQ.enq(tuple2(target,enqQ.first));
		sdin.enq(enqQ.first,target);
		enqQ.deq;
	endrule
	
	Vector#(ways, SyncFIFOIfc#(Vector#(tupleCount,inType))) vDeqQ <- replicateM(mkSyncFIFOFromCC(8, fastclk));
	for ( Integer i = 0; i < iWays; i=i+1 ) begin
		SyncFIFOIfc#(Vector#(tupleCount,inType)) enqSQ <- mkSyncFIFOToCC(8, fastclk, fastrst);
		rule sorterenqdata;
			let d <- sdin.get[i].get;
			enqSQ.enq(d);
		endrule
		rule sorterenqdata2;
			enqSQ.deq;
			let d = enqSQ.first;
			sorters[i].enq(d);
		endrule

		rule getsorted;
			let d <- sorters[i].get;
			vDeqQ[i].enq(d);
		endrule
	end
	
	/*
	rule sorterenqdata;
		enqdQ.deq;
		let d = enqdQ.first;
		sorters[tpl_1(d)].enq(tpl_2(d));
	endrule
	*/

	rule deqdata;
		let src = curdeq;
		if ( deqoff == 0 ) begin
			src = deqAvailQ.first;
			deqAvailQ.deq;
			curdeq <= src;
			enqAvailQ.enq(src);
		end

		if ( deqoff + 1 >= fromInteger(pageSize) ) begin
			deqoff <= 0;
		end else begin
			deqoff <= deqoff + 1;
		end

		//let d <- sorters[src].get;
		vDeqQ[src].deq;
		let d = vDeqQ[src].first;
		deqQ.enq(d);
	endrule



	method Action enq(Vector#(tupleCount,inType) data);
		enqQ.enq(data);
	endmethod
	method ActionValue#(Vector#(tupleCount,inType)) get;
		deqQ.deq;
		return deqQ.first;
	endmethod
endmodule
module mkMultiPageSorterCC#(Clock fastclk, Reset fastrst, Bool descending) (MultiPageSorterIfc#(ways, inType, tupleCount, pageSz))
	provisos(
	Bits#(Vector::Vector#(tupleCount, inType), inVSz)
	, Add#(1,a__,ways)
	, Add#(1,b__,inVSz)
	, Bits#(inType, inTypeSz)
	, Add#(1,c__,inTypeSz)
	, Literal#(inType)
	, Ord#(inType)
	);

	MultiPageSorterIfc#(ways,inType,tupleCount,pageSz) mpsorter <- mkMultiPageSorter(descending, clocked_by fastclk, reset_by fastrst);

	SyncFIFOIfc#(Vector#(tupleCount,inType)) getQ <- mkSyncFIFOToCC(8, fastclk, fastrst);
	SyncFIFOIfc#(Vector#(tupleCount,inType)) enqQ <- mkSyncFIFOFromCC(8, fastclk);

	rule enqr;
		enqQ.deq;
		mpsorter.enq(enqQ.first);
	endrule

	rule getr;
		let d <- mpsorter.get;
		getQ.enq(d);
	endrule

	method Action enq(Vector#(tupleCount,inType) data);
		enqQ.enq(data);
	endmethod
	method ActionValue#(Vector#(tupleCount,inType)) get;
		getQ.deq;
		return getQ.first;
	endmethod
endmodule


module mkPageSorterV#(Bool descending) (PageSorterIfc#(inType, tupleCount, pageSz))
	provisos(
	Bits#(Vector::Vector#(tupleCount, inType), inVSz)
	, Add#(1,b__,inVSz)
	, Bits#(inType, inTypeSz)
	, Add#(1,c__,inTypeSz)
	, Literal#(inType)
	, Ord#(inType)
	);

	Integer iPageSz = valueOf(pageSz);
	Integer pageSize = 2**iPageSz;
	Integer iTupleCount = valueOf(tupleCount);

	//SingleMergerIfc#(inType,16) merger <- mkSingleMerger(descending);
	VectorMergerIfc#(tupleCount, inType,16) merger <- mkVectorMerger(descending);

	Vector#(2,FIFO#(Vector#(tupleCount,inType))) buffers <- replicateM(mkSizedBRAMFIFO(pageSize/2));
	//Vector#(2, Reg#(Bit#(32))) bufferCntUp <- replicateM(mkReg(0));
	//Vector#(2, Reg#(Bit#(32))) bufferCntDown <- replicateM(mkReg(0));

	Reg#(Bit#(32)) curStride <- mkReg(0);
	Reg#(Bit#(32)) strideSum <- mkReg(0);

	FIFO#(Bit#(16)) cmdQ <- mkFIFO;
	rule genCmd (curStride > 0);
		//cmdQ.enq(curStride*fromInteger(tupleCount));
		Bit#(16) mergeStride = truncate(curStride);
		merger.runMerge(mergeStride);
		//$display( "merger inserting command for stride %d (%d)", mergeStride, strideSum );

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







	
	//Vector#(2,FIFO#(Vector#(tupleCount, inType))) insQ <- replicateM(mkFIFO);
	Vector#(2,Reg#(Bit#(32))) totalInsCount <- replicateM(mkReg(0));
	for ( Integer i = 0; i < 2; i = i + 1 ) begin
		
		Reg#(Vector#(tupleCount, inType)) insBuf <- mkReg(?);
		Reg#(Bit#(8)) vecIdx <- mkReg(0);
		rule startInsertData ( totalInsCount[i] > 0 ); // && vecIdx == 0);
			buffers[i].deq;
			//bufferCntDown[i] <= bufferCntDown[i] + 1;
			let d = buffers[i].first;

			if ( i == 0 ) merger.enq1(d);
			else if ( i == 1 ) merger.enq2(d);
			//$display ( "Enqueueing merger data!" );

			totalInsCount[i] <= totalInsCount[i] - 1;
		endrule
	end


	
	//Reg#(Bit#(32)) curStrideOut <- mkReg(0);
	FIFO#(Vector#(tupleCount, inType)) readQ <- mkSizedBRAMFIFO(pageSize/2);
	Reg#(Bit#(8)) readIdx <- mkReg(0);
	rule readSorted;
		let d <- merger.get;
		//$display ( "Got results!" );
		/*
		sorter.enq(d);
	endrule
	rule readSorted2;
		let d <- sorter.get;
		//readQ.enq(d);
		*/
		readQ.enq(sortBitonic(d,descending));
	endrule





	Reg#(Bit#(32)) curInsCount <- mkReg(0);
	Reg#(Bit#(32)) curInsStride <- mkReg(0);
	Reg#(Bit#(32)) insStrideCount <- mkReg(0);
	Reg#(Bit#(32)) totalReadCount <- mkReg(0);
	FIFO#(Vector#(tupleCount, inType)) outQ <- mkFIFO;


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
	method Action enq(Vector#(tupleCount,inType) data) if (curInsStride == 0);
		buffers[enqIdx[0]].enq(data);
		//bufferCntUp[enqIdx[0]] <= bufferCntUp[enqIdx[0]] + 1;
		if ( enqIdx+1 < fromInteger(pageSize) ) begin
			enqIdx <= enqIdx + 1;
		end
		else begin
			curStride <= 1;
			totalInsCount[0] <= fromInteger(iPageSz) * fromInteger(pageSize)/2;
			totalInsCount[1] <= fromInteger(iPageSz) * fromInteger(pageSize)/2;
			curInsStride <= 2;
			enqIdx <= 0;
		end
	endmethod
	method ActionValue#(Vector#(tupleCount,inType)) get;
		outQ.deq;
		return outQ.first;
	endmethod
endmodule



