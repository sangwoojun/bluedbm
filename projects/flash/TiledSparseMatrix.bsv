import FIFO::*;
import FIFOF::*;
import Clocks::*;
import Vector::*;

import BRAM::*;
import BRAMFIFO::*;

import MergeN::*;
import Split4Width::*;
import AcceleratorReader::*;

//import DRAMController::*;
import DRAMArbiter::*;

interface SparseDecoderIfc;
	method Action enq(Bit#(128) data);
	method Action deq;
	method Maybe#(Tuple3#(Bit#(64), Bit#(64), Bit#(64))) first;
	method Bit#(8) bytes;

	method Action init;
endinterface

module mkSparseDecoderTiled (SparseDecoderIfc);
	Split2WidthIfc#(64) split <- mkSplit2WidthReverse;
	FIFO#(Maybe#(Tuple3#(Bit#(28), Bit#(64), Bit#(14)))) outQ <- mkFIFO;
	FIFO#(Bit#(8)) bytesQ <- mkFIFO;
	Reg#(Bit#(64)) lastRow <- mkReg(0);
	rule proc;
		Bit#(64) recv = split.first;
		split.deq;
		Bit#(28) col = truncate(recv);
		Bit#(14) dat = truncate(recv>>32);
		Bit#(14) row = truncate(recv>>(32+14));
		
		Bit#(4) colH = truncate(recv>>28);
		Bit#(4) rowH = truncate(recv>>(32+28));
		bytesQ.enq(8);
		
		if ( colH != 4 || rowH != 2 ) begin
			outQ.enq(tagged Invalid);
			$display ( "Wrong headers! %d %d %x", colH, rowH, recv );
		end else begin
			Bit#(64) crow = lastRow + zeroExtend(row);
			outQ.enq(tagged Valid tuple3(col,crow,dat));
			lastRow <= crow;
		end
	endrule

	method Action enq(Bit#(128) data);
		split.enq(data);
	endmethod
	method Action deq;
		bytesQ.deq;
		outQ.deq;
	endmethod
	method Maybe#(Tuple3#(Bit#(64), Bit#(64), Bit#(64))) first;
		let d_ = outQ.first;
		if ( isValid(d_) ) begin
			let d = fromMaybe(?, d_);
			return tagged Valid tuple3(zeroExtend(tpl_1(d)), zeroExtend(tpl_2(d)), zeroExtend(tpl_3(d)));
		end else begin
			return tagged Invalid;
		end
	endmethod
	method Bit#(8) bytes;
		return bytesQ.first;
	endmethod
	method Action init;
		lastRow <= 0;
	endmethod
endmodule

typedef enum {
	TILE_INIT,
	TILE_PROC,
	TILE_FLUSH
} TileProcState deriving (Bits,Eq);

interface TiledSparseMatrixIfc;
	method Action matrixIn(Bit#(512) data);
	method Action tileStart(Bit#(32) bytes, Bit#(32) offset);
	method Action vectorInOffset(Bit#(32) bytes);
	method Action vectorOutOffset(Bit#(32) bytes);
endinterface

module mkTiledSparseMatrix#(DRAMArbiterUserIfc dram) (TiledSparseMatrixIfc);
	Reg#(TileProcState) state <- mkReg(TILE_INIT);

	Reg#(Bit#(64)) bytesRemaining <- mkReg(0);

	BRAM2Port#(Bit#(18), Bit#(32)) colbuffer <- mkBRAM2Server(defaultValue); // 1MB

	Reg#(Bool) procDoneFlag <- mkReg(False);

	Reg#(Bit#(32)) initCounter <- mkReg(0);
	rule init (state == TILE_INIT);
		Bit#(18) maxv = ~0;
		colbuffer.portA.request.put( BRAMRequest{
			write:True, responseOnWrite: False,
			address:truncate(initCounter),
			datain:0
		});
		if ( initCounter == zeroExtend(maxv) ) begin
			if ( bytesRemaining > 0 ) begin
				state <= TILE_PROC;
				initCounter <= 0;
				procDoneFlag <= False;
				$display( "TILE init done" );
			end
		end else begin
			initCounter <= initCounter + 1;
		end
	endrule

	Reg#(Bit#(64)) vectorInOff <- mkReg(16*1024*1024);
	Reg#(Bit#(64)) vectorOutOff <- mkReg(512*1024*1024);
	Reg#(Bit#(32)) tileOff <- mkReg(0);
	Reg#(Bit#(32)) flushVectorIdx <- mkReg(0);

	
	SparseDecoderIfc decoder <- mkSparseDecoderTiled;
	Split4WidthIfc#(128) split <- mkSplit4Width;
	rule feedDecoder;
		split.deq;
		let d = split.first;
		decoder.enq(d);
	endrule
	FIFO#(Tuple2#(Bit#(64), Bit#(64))) crdQ <- mkSizedBRAMFIFO(256);
	FIFO#(Bool) doneQ <- mkSizedFIFO(256);
	FIFO#(Tuple2#(Bool,Bit#(4))) sameEdgeQ <- mkSizedFIFO(256);

	Reg#(Bit#(64)) lastEdgeSend <- mkReg(0);

	Reg#(Bit#(16)) procInPipeUp <- mkReg(0);
	Reg#(Bit#(16)) procInPipeDown <- mkReg(0);

	rule getColRowData (state == TILE_PROC);
		decoder.deq;
		let bytes = decoder.bytes;
		let crd = decoder.first;
		if ( isValid (crd) ) begin
			let d = fromMaybe(?, crd);
			Bit#(64) col = tpl_1(d);
			Bit#(64) row = tpl_2(d);
			Bit#(64) dat = tpl_3(d);
			Bit#(64) raddr = vectorInOff + row*4;

			//$display( "Decoded %d %d %d", col, row, dat );

			if ( dat >= 1 ) begin //filtering (128 is only one, 1 is 128 edges in the col)
				//$display("Sending DRAM read req!");
				if ( (lastEdgeSend>>6) == (row>>6) ) begin
					sameEdgeQ.enq(tuple2(True, row[3:0]));
				end else begin
					dram.readReq({raddr>>6,0}, 64);
					sameEdgeQ.enq(tuple2(False, row[3:0]));
					lastEdgeSend <= row;
				end
				crdQ.enq(tuple2(col,dat));
				procInPipeUp <= procInPipeUp + 1;
				if ( bytesRemaining > zeroExtend(bytes) ) begin
					doneQ.enq(False);
				end else begin
					doneQ.enq(True);
					$display("Done proc with valid data!");
				end
			end
		end

		if ( bytesRemaining > zeroExtend(bytes) ) begin
			bytesRemaining <= bytesRemaining - zeroExtend(bytes);
			//$display("bytesRemaining %d, %d", bytesRemaining, bytes);
		end else begin
			bytesRemaining <= 0;
			if ( !isValid(crd) ) begin
				if ( procInPipeUp - procInPipeDown == 0 ) begin
					state <= TILE_FLUSH;
					flushVectorIdx <= 0;
					$display("Done proc with notvalid data!");
				end else begin
					procDoneFlag <= True;
					$display("Done proc with notvalid data, data still in pipeline!");
				end
			end
		end 
	endrule
	
	FIFO#(Bit#(18)) colbufoffQ <- mkSizedFIFO(8);
	FIFO#(Bit#(32)) addcolvQ <- mkSizedFIFO(8);
	Reg#(Bit#(512)) lastEdgeRecv <- mkReg(0);
	FIFO#(Bit#(32)) edgeReadQ <- mkFIFO;

	rule recvRowVal (state==TILE_PROC);
		let d_ = lastEdgeRecv;
		sameEdgeQ.deq;
		let s = sameEdgeQ.first;
		Bool exist = tpl_1(s);
		Bit#(4) woff = tpl_2(s);
		if ( !exist ) begin
			d_ <- dram.read;
			lastEdgeRecv <= d_;
		end

		edgeReadQ.enq(truncate(d_>>(woff<<2)));
	endrule
	FIFO#(Tuple2#(Bit#(32),Bit#(32))) colvdQ <- mkFIFO;
	FIFO#(Bit#(32)) colQ <- mkFIFO;
	rule matchRowVal (state==TILE_PROC);
		Bit#(32) vrow = edgeReadQ.first;
		edgeReadQ.deq;

		crdQ.deq;
		let crd = crdQ.first;
		Bit#(64) col = tpl_1(crd);
		Bit#(64) dat = tpl_2(crd);
		colvdQ.enq(tuple2(vrow, truncate(dat)));
		colQ.enq(truncate(col));
		//$display("Processing dram data");
	endrule

	rule calcres (state==TILE_PROC);
		colvdQ.deq;
		let d = colvdQ.first;
		let vrow = tpl_1(d);
		let dat = tpl_2(d);
		Bit#(32) res = vrow * dat;
		addcolvQ.enq(res);
	endrule

	rule calcoff (state==TILE_PROC);
		colQ.deq;
		let col = colQ.first;

		Bit#(18) colbufoff = truncate(col-tileOff);
		colbuffer.portB.request.put( BRAMRequest{
			write:False, responseOnWrite: ?,
			address:colbufoff,
			datain:?
		});
		colbufoffQ.enq(colbufoff);
	endrule
		
		//$display( "matching %d %d %d", col, vrow, dat );

	FIFO#(Bit#(32)) colvQ <- mkFIFO();
	rule getColV ( state == TILE_PROC );
		let v <- colbuffer.portB.response.get();
		colvQ.enq(v);
	endrule

	rule updColV ( state == TILE_PROC );
		let off = colbufoffQ.first;
		let addv = addcolvQ.first;
		addcolvQ.deq;
		colbufoffQ.deq;
		let done = doneQ.first;
		doneQ.deq;

		let v = colvQ.first;
		colvQ.deq;

		//$display( "writing back %d %d", off, addv );


		colbuffer.portA.request.put( BRAMRequest{
			write:True, responseOnWrite: False,
			address:off,
			datain:v+addv
		});
		procInPipeDown <= procInPipeDown + 1;
		
		if ( done == True || 
			(procInPipeUp-procInPipeDown==1 &&procDoneFlag == True) ) begin
			state <= TILE_FLUSH;
			flushVectorIdx <= 0;
			$display( "Done proc %d %d %d %d", done?1:0, procDoneFlag?1:0, procInPipeUp, procInPipeDown );
		end
	endrule

	FIFO#(Bit#(18)) colbufloadoffQ <- mkSizedFIFO(8);
	rule flushVectorLoad ( state == TILE_FLUSH );
		Bit#(18) maxv = ~0;
		colbuffer.portA.request.put( BRAMRequest{
			write:False, responseOnWrite: False,
			address:truncate(flushVectorIdx),
			datain:0
		});
		colbufloadoffQ.enq(truncate(flushVectorIdx));
		if ( initCounter == zeroExtend(maxv) ) begin
		end else begin
			flushVectorIdx <= flushVectorIdx + 1;
		end
	endrule

	FIFO#(Bit#(1)) doneFlushQ <- mkFIFO;
	rule flushVectorStore (state == TILE_FLUSH);
		Bit#(18) maxv = ~0;
		let v <- colbuffer.portA.response.get();
		let r = colbufloadoffQ.first;
		colbufloadoffQ.deq;
		
		Bit#(64) waddr = vectorOutOff + zeroExtend(r)*4;

		dram.write(waddr, zeroExtend(v), 4);
		if ( r == maxv ) begin
			state <= TILE_INIT;
			flushVectorIdx <= 0;
			$display( "Done flush" );
			//doneFlushQ.enq(1);

		end
	endrule


	method Action matrixIn(Bit#(512) data);
		split.enq(data);
	endmethod
	method Action tileStart(Bit#(32) bytes, Bit#(32) offset) if ( bytesRemaining == 0 && state == TILE_INIT );
		tileOff <= offset;
		bytesRemaining <= zeroExtend(bytes);
		decoder.init;
		$display( "bytesRemaining: %d, tileOff: %d", bytes, offset );
	endmethod
	method Action vectorInOffset(Bit#(32) bytes);
	endmethod
	method Action vectorOutOffset(Bit#(32) bytes);
	endmethod
endmodule

module mkTiledSparseMatrixAccel#(DRAMArbiterUserIfc dram) (AcceleratorReaderIfc);
	TiledSparseMatrixIfc ts <- mkTiledSparseMatrix(dram);

	method Action dataIn(Bit#(512) d);
		ts.matrixIn(d);
	endmethod
	method Action cmdIn(Bit#(32) header, Bit#(128) cmd_);
		Bit#(32) cmd = truncate(cmd_>>(32*3));
		if ( cmd == 0 ) begin
			Bit#(32) bytes = truncate(cmd_>>32);
			Bit#(32) offset = truncate(cmd_);
			ts.tileStart(bytes, offset);
		end
	endmethod
	method ActionValue#(Bit#(128)) resOut if (False);
		return ?;
	endmethod
endmodule
