import FIFO::*;
import FIFOF::*;
import Clocks::*;
import Vector::*;

import BRAM::*;
import BRAMFIFO::*;

import MergeN::*;

interface Split4WidthIfc#(numeric type dst);
	method Action enq(Bit#(TMul#(dst,4)) data);
	method Action deq;
	method Bit#(dst) first;
endinterface

module mkSplit4Width (Split4WidthIfc#(dst))
	provisos(Add#(a__, dst, TMul#(dst, 4)));

	Reg#(Bit#(TMul#(dst,4))) buffer <- mkReg(0);
	Reg#(Bit#(2)) cnt <- mkReg(0);
	FIFO#(Bit#(dst)) outQ <- mkFIFO;
	rule split( cnt > 0 );
		cnt <= cnt - 1;
		outQ.enq(truncate(buffer));
		buffer <= (buffer>>valueOf(dst));
	endrule
	method Action enq(Bit#(TMul#(dst,4)) data) if (cnt == 0);
		cnt <= 3;
		buffer <= (data>>valueOf(dst));
		outQ.enq(truncate(data));
	endmethod
	method Action deq;
		outQ.deq;
	endmethod
	method Bit#(dst) first;
		return outQ.first;
	endmethod
endmodule

interface SparseDecoderIfc;
	method Action enq(Bit#(128) data);
	method Action deq;
	method Maybe#(Tuple3#(Bit#(64), Bit#(64), Bit#(64))) first;
	method Bit#(8) bytes;
endinterface

typedef enum {
	DECODER_INIT,
	DECODER_LONGCOL,
	DECODER_LONGROW
} DecoderState deriving (Bits,Eq);

module mkSparseDecoder (SparseDecoderIfc);
	FIFO#(Bit#(8)) bytesQ <- mkFIFO;
	FIFO#(Maybe#(Tuple3#(Bit#(64), Bit#(64), Bit#(64)))) outQ <- mkFIFO;
	Split4WidthIfc#(32) splitter <- mkSplit4Width;
	Reg#(DecoderState) decoderState <- mkReg(DECODER_INIT);
	Reg#(Bit#(64)) curCol <- mkReg(0);
	Reg#(Bit#(64)) curDat <- mkReg(1);

	Reg#(Bit#(28)) colBuf <- mkReg(0);
	Reg#(Bit#(28)) rowBuf <- mkReg(0);

	Reg#(Bit#(64)) lastRow <- mkReg(0);
	
	rule procheader ( decoderState == DECODER_INIT );
		splitter.deq;
		Bit#(32) d = splitter.first;

		Bit#(4) header = truncate(d>>28);
		Bit#(28) body = truncate(d);

		if ( header == 6 ) begin //LongCol
			decoderState <= DECODER_LONGCOL;
			colBuf <= body;
		end else if ( header == 8 ) begin //ShortRow
			Bit#(64) newRow = lastRow + zeroExtend(body);
			lastRow <= newRow;

			outQ.enq(tagged Valid tuple3(curCol, newRow, curDat));
			bytesQ.enq(4);
		end else if ( header == 10 ) begin //LongRow
			decoderState <= DECODER_LONGROW;
			rowBuf <= body;
		end else begin
			outQ.enq(tagged Invalid);
			bytesQ.enq(4);
		end
	endrule

	rule procLongcol ( decoderState == DECODER_LONGCOL );
		splitter.deq;
		Bit#(32) d = splitter.first;
		decoderState <= DECODER_INIT;

		Bit#(64) b = zeroExtend(colBuf);
		curCol <= (b<<32) | zeroExtend(d);

		outQ.enq(tagged Invalid);
		bytesQ.enq(8);

		lastRow <= 0;
		
		$display( "longcol %x", d );
	endrule
	
	rule procLongrow ( decoderState == DECODER_LONGROW );
		splitter.deq;
		Bit#(32) d = splitter.first;
		decoderState <= DECODER_INIT;
			
		Bit#(64) b = zeroExtend(rowBuf);
		Bit#(64) nr = (b<<32) | zeroExtend(rowBuf);
		lastRow <= nr;

		outQ.enq(tagged Valid tuple3(curCol, nr, curDat));
		
		bytesQ.enq(8);
		
		$display( "longrow %x", d );
	endrule

	method Action enq(Bit#(128) data);
		splitter.enq(data);
	endmethod
	method Action deq;
		outQ.deq;
		bytesQ.deq;
	endmethod
	method Maybe#(Tuple3#(Bit#(64), Bit#(64), Bit#(64))) first;
		return outQ.first;
	endmethod
	method Bit#(8) bytes;
		return bytesQ.first;
	endmethod
endmodule

interface SparseVectorMatrixIfc;
	method Action vectorIn(Bit#(64) idx, Bit#(64) val);
	method Action vectorToken(Bit#(64) len);

	method Action matrixIn(Bit#(512) data);
	method Action matrixToken(Bit#(64) len);

	method ActionValue#(Tuple2#(Bit#(64), Bit#(64))) colOut;
endinterface

module mkSparseVectorMatrix ( SparseVectorMatrixIfc );
	Reg#(Bit#(64)) matrixBytesRemain <- mkReg(0);

	Split4WidthIfc#(128) split <- mkSplit4Width;
	SparseDecoderIfc dataDecoder <- mkSparseDecoder;
	rule feeddatadec;
		split.deq;
		dataDecoder.enq(split.first);
	endrule
	FIFO#(Maybe#(Tuple3#(Bit#(64), Bit#(64), Bit#(64)))) decodedMQ <- mkFIFO;
	FIFO#(Bool) matrixIsLastQ <- mkFIFO;
	rule getDecodedMatrix ( matrixBytesRemain > 0 );
		let mo = dataDecoder.first;
		let bytes = dataDecoder.bytes;
		dataDecoder.deq;
		if ( isValid(mo) ) begin
			let m = fromMaybe(?, mo);
			$display ( "%d %d %d ... %d", tpl_1(m), tpl_2(m), tpl_3(m), matrixBytesRemain );
		end else begin
			$display( "-- %d, %d", matrixBytesRemain, bytes );
		end
		decodedMQ.enq(mo);

		if ( matrixBytesRemain <= zeroExtend(bytes) ) begin
			matrixBytesRemain <= 0;
			matrixIsLastQ.enq(True);
			$display( "matrixIsLastQ enqing true!" );
		end else begin
			matrixBytesRemain <= matrixBytesRemain - zeroExtend(bytes);
			matrixIsLastQ.enq(False);
		end
	endrule

	FIFOF#(Bit#(64)) vectorIdxQ <- mkSizedBRAMFIFOF(128);
	Reg#(Bit#(64)) vectorInRemain <- mkReg(0);

	Reg#(Bool) doFFMatrix <- mkReg(False);
	Reg#(Bool) doFFVector <- mkReg(False);
	Reg#(Bool) doFlushVector <- mkReg(False);

	FIFO#(Tuple2#(Bit#(64), Bit#(64))) outQ <- mkFIFO;
	Reg#(Bit#(64)) colSum <- mkReg(0);

	Reg#(Bool) vectorInReady <- mkReg(True);
	Reg#(Bit#(64)) compareLastCidx <- mkReg(0);
	Reg#(Bit#(64)) compareLastVidx <- mkReg(0);
	rule compare (
		doFFMatrix == False && doFFVector == False
		&& doFlushVector == False
		&& vectorInReady == False 
		&& vectorInRemain == 0 );

		let mo = decodedMQ.first;
		let islast = matrixIsLastQ.first;

		if ( isValid(mo) ) begin
			let v = vectorIdxQ.first;

			let m = fromMaybe(?, mo);

			let cidx = tpl_1(m);
			let ridx = tpl_2(m);

			if ( compareLastCidx != cidx ) begin
				doFFVector <= True;
				compareLastCidx <= cidx;
				colSum <= 0;
				outQ.enq(tuple2(compareLastCidx, colSum));
				$display ( "Starting vector FF" );
			end
			else
			if ( compareLastVidx > v ) begin
				doFFMatrix <= True;
				compareLastVidx <= v;
				colSum <= 0;
				outQ.enq(tuple2(cidx, colSum));
				$display ( "Starting matrix FF" );
			end
			else begin
				compareLastCidx <= cidx;
				compareLastVidx <= v;
				if ( v == ridx ) begin
					//match!!
					colSum <= colSum + 1;
					$display( "match! %d == %d > %d", v, ridx, colSum );

					vectorIdxQ.deq;
					vectorIdxQ.enq(v);

					decodedMQ.deq;
					matrixIsLastQ.deq;
				end else if ( v > ridx ) begin
					//$display( "mismatch! %d > %d", v, ridx );
					decodedMQ.deq;
					matrixIsLastQ.deq;
					
				end else begin // (v < ridx)
					//$display( "mismatch! %d < %d", v, ridx );
					vectorIdxQ.deq;
					vectorIdxQ.enq(v);
				end
			end
		
			if (islast) begin
				//$display( "starting vector flush" );
				doFlushVector <= True;
				$display( "Starting flush vector" );
				// if last compare:
				// empty vectorQ
				// and then vectorInReady <= True;
			end
		end else begin
			if ( islast ) begin
				doFlushVector <= True;
				$display( "Starting flush vector" );
			end

			$display( "Invalid matrix value" );

			decodedMQ.deq;
			matrixIsLastQ.deq;
		end
	endrule
	rule ffMatrix ( doFFMatrix == True );
		let mo = decodedMQ.first;
		let islast = matrixIsLastQ.first;

		if ( isValid(mo) ) begin
			let m = fromMaybe(?, mo);
			let cidx = tpl_1(m);
			let ridx = tpl_2(m);
			if ( cidx == compareLastCidx ) begin
				decodedMQ.deq;
				matrixIsLastQ.deq;
			end else begin
				compareLastCidx <= cidx;
				doFFMatrix <= False;
				$display( "Done matrix FF" );
			end
		end else begin
			decodedMQ.deq;
			matrixIsLastQ.deq;
			doFFMatrix <= False;
			$display( "Done matrix FF" );
		end
	endrule
	rule ffVector ( doFFVector == True );
		let v = vectorIdxQ.first;

		if ( compareLastVidx < v ) begin
			vectorIdxQ.deq;
			vectorIdxQ.enq(v);
		end else begin
			compareLastVidx <= 0;
			doFFVector <= False;
			//$display( "Done vector FF" );
		end
	endrule
	rule flushVector ( doFlushVector == True );
		if ( vectorIdxQ.notEmpty ) begin
			vectorIdxQ.deq;
			$display( "vector flushing" );
		end else begin
			doFlushVector <= False;
			vectorInReady <= True;
			$display( "Done vector flush" );
		end
	endrule

	method Action vectorIn(Bit#(64) idx, Bit#(64) val) if (vectorInRemain > 0);
		vectorInRemain <= vectorInRemain - 1;
		vectorIdxQ.enq(idx);
		$display( "Vector data received for %d %d", idx, val );
	endmethod
	method Action vectorToken(Bit#(64) len) if (vectorInReady == True && vectorInRemain == 0);
		vectorInReady <= False;
		vectorInRemain <= len;
		$display( "Vector token received for %d", len );
	endmethod

	method Action matrixIn(Bit#(512) data);// if ( matrixBytesRemain > 0 );
		split.enq(data);
	endmethod
	method Action matrixToken(Bit#(64) len) if ( matrixBytesRemain == 0 );
		matrixBytesRemain <= len;
		$display( "Matrix token received for %d", len );
	endmethod

	method ActionValue#(Tuple2#(Bit#(64), Bit#(64))) colOut;
		outQ.deq;
		return outQ.first;
	endmethod
endmodule
