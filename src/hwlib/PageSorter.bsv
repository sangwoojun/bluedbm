import FIFO::*;
import FIFOF::*;
import Clocks::*;
import Vector::*;

import BRAM::*;
import BRAMFIFO::*;

import SortingNetwork::*;


/**
**/

interface VectorMergerIfc#(numeric type vcnt, type inType, numeric type cntSz);
	method Action enq1(Vector#(vcnt,inType) data);
	method Action enq2(Vector#(vcnt,inType) data);
	method Action runMerge(Bit#(cntSz) count);
	method ActionValue#(Vector#(vcnt,inType)) get;
endinterface

module mkVectorMerger#(Bool descending) (VectorMergerIfc#(vcnt, inType, cntSz))
	provisos(Bits#(inType,inTypeSz), Ord#(inType), Add#(1,a__,inTypeSz));
	
	Reg#(Bit#(cntSz)) mCountTotal <- mkReg(0);
	Reg#(Bit#(cntSz)) mCount1 <- mkReg(0);
	Reg#(Bit#(cntSz)) mCount2 <- mkReg(0);

	FIFO#(Vector#(vcnt,inType)) inQ1 <- mkFIFO;
	FIFO#(Vector#(vcnt,inType)) inQ2 <- mkFIFO;
	FIFO#(Vector#(vcnt,inType)) outQ <- mkFIFO;

	Reg#(Vector#(vcnt,inType)) abuf <- mkReg(?);
	Reg#(Maybe#(Bool)) append1 <- mkReg(tagged Invalid);
	Reg#(inType) atail <- mkReg(?);
	
	rule ff1 (mCount1 > 0 && mCount2 == 0);
		
		if ( isValid(append1) ) begin
			append1 <= tagged Invalid;
			outQ.enq(abuf);
		end else begin
			inQ1.deq;
			outQ.enq(inQ1.first);
		end
		mCountTotal <= mCountTotal - 1;
		mCount1 <= mCount1 - 1;
	endrule
	rule ff2 (mCount1 == 0 && mCount2 > 0);
		
		if ( isValid(append1) ) begin
			append1 <= tagged Invalid;
			outQ.enq(abuf);
		end else begin
			inQ2.deq;
			outQ.enq(inQ2.first);
		end
		mCountTotal <= mCountTotal - 1;
		mCount2 <= mCount2 - 1;
	endrule

	rule doMerge (mCount1 > 0 && mCount2 > 0 );
		Integer count = valueOf(vcnt);

		let d1 = inQ1.first;
		let d2 = inQ2.first;
		
		let tail1 = d1[count-1];
		let tail2 = d2[count-1];
		if ( isValid(append1) ) begin
			let is1 = fromMaybe(?, append1);
			if ( is1 ) begin
				d1 = abuf;
				tail1 = atail;
				inQ2.deq;
			end else begin
				d2 = abuf;
				tail2 = atail;
				inQ1.deq;
			end
		end else begin
			inQ1.deq;
			inQ2.deq;
		end


		let cleaned = halfClean(d1,d2,descending);

		let top = tpl_1(cleaned);
		let bot = sortBitonic(tpl_2(cleaned), descending);

		/*
		$display( "<<<< %d %d %d %d %d %d %d %d", d1[0], d1[1], d1[2], d1[3], d1[4], d1[5], d1[6], d1[7] );
		$display( ">>>> %d %d %d %d %d %d %d %d", d2[0], d2[1], d2[2], d2[3], d2[4], d2[5], d2[6], d2[7] );
		$display( "t1 %d t2 %d", tail1, tail2 );
		$display( "---- %d %d %d %d %d %d %d %d", top[0], top[1], top[2], top[3], top[4], top[5], top[6], top[7] );
		$display( "++++ %d %d %d %d %d %d %d %d", bot[0], bot[1], bot[2], bot[3], bot[4], bot[5], bot[6], bot[7] );
		*/

		abuf <= bot;
		if ( descending ) begin
			if ( tail1 >= tail2 ) begin
				append1 <= tagged Valid False;
				atail <= tail2;
				mCount1 <= mCount1 - 1;
			end else begin
				append1 <= tagged Valid True;
				atail <= tail1;
				mCount2 <= mCount2 - 1;
			end
		end else begin
			if ( tail2 >= tail1 ) begin
				append1 <= tagged Valid False;
				atail <= tail2;
				mCount1 <= mCount1 - 1;
			end else begin
				append1 <= tagged Valid True;
				atail <= tail1;
				mCount2 <= mCount2 - 1;
			end
		end
		mCountTotal <= mCountTotal - 1;

		//TODO outQ must be pushed through a sorting network
		outQ.enq(top);
	endrule


	method Action enq1(Vector#(vcnt,inType) data);
		inQ1.enq(data);
	endmethod
	method Action enq2(Vector#(vcnt,inType) data);
		inQ2.enq(data);
	endmethod
	method Action runMerge(Bit#(cntSz) count) if ( mCountTotal == 0);
		mCountTotal <= count * 2;
		mCount1 <= count;
		mCount2 <= count;
	endmethod
	method ActionValue#(Vector#(vcnt,inType)) get;
		outQ.deq;
		return outQ.first;
	endmethod
endmodule

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
				$display("Finished sorting page");
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


interface MultiPageSorterIfc#(numeric type ways, type inType, numeric type tupleCount, numeric type pageSz);
	method Action enq(Vector#(tupleCount,inType) data);
	method ActionValue#(Vector#(tupleCount,inType)) get;
endinterface


module mkMultiPageSorter#(Vector#(ways, SortingNetworkIfc#(inType, tupleCount)) snets, Bool descending) (MultiPageSorterIfc#(ways, inType, tupleCount, pageSz))
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
		sorters[i] <- mkPageSorterV(snets[i], descending);
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

		sorters[target].enq(enqQ.first);
		enqQ.deq;
	endrule

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

module mkMultiPageSorterCC#(Vector#(ways, SortingNetworkIfc#(inType, tupleCount)) snets, Clock fastclk, Reset fastrst, Bool descending) (MultiPageSorterIfc#(ways, inType, tupleCount, pageSz))
	provisos(
	Bits#(Vector::Vector#(tupleCount, inType), inVSz)
	, Add#(1,a__,ways)
	, Add#(1,b__,inVSz)
	, Bits#(inType, inTypeSz)
	, Add#(1,c__,inTypeSz)
	, Literal#(inType)
	, Ord#(inType)
	);

	MultiPageSorterIfc#(ways,inType,tupleCount,pageSz) mpsorter <- mkMultiPageSorter(snets, descending, clocked_by fastclk, reset_by fastrst);

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


module mkPageSorterV#(SortingNetworkIfc#(inType, tupleCount) sorter, Bool descending) (PageSorterIfc#(inType, tupleCount, pageSz))
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

			totalInsCount[i] <= totalInsCount[i] - 1;
		endrule
	end


	
	//Reg#(Bit#(32)) curStrideOut <- mkReg(0);
	FIFO#(Vector#(tupleCount, inType)) readQ <- mkSizedBRAMFIFO(pageSize/2);
	Vector#(tupleCount, Reg#(inType)) readBuf <- replicateM(mkReg(0));
	Reg#(Bit#(8)) readIdx <- mkReg(0);
	rule readSorted;
		let d <- merger.get;
		sorter.enq(d);
	endrule
	rule readSorted2;
		let d <- sorter.get;
		readQ.enq(d);
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
				$display("Finished sorting page");
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



