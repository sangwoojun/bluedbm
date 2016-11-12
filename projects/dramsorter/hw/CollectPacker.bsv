import FIFO::*;
import FIFOF::*;
import Clocks::*;
import Vector::*;

interface CollectPackerIfc#(numeric type srcSz, numeric type dstSz);
	method Action enq(Bit#(srcSz) data);
	method Bit#(dstSz) first;
	method Action deq;
endinterface

module mkCollectPacker (CollectPackerIfc#(srcSz, dstSz))
	provisos(Add#(__a,srcSz,dstSz));

	Integer iSrcSz = valueOf(srcSz);
	Integer iDstSz = valueOf(dstSz);
	
	Reg#(Bit#(TAdd#(TLog#(dstSz),1))) counter <- mkReg(0);
	Reg#(Bit#(dstSz)) buffer <- mkReg(0);

	FIFO#(Bit#(srcSz)) inQ <- mkFIFO;
	FIFO#(Bit#(dstSz)) outQ <- mkFIFO;
	rule doPack;
		inQ.deq;
		let d = inQ.first;
		$display ( "CollectPacker packing %x", d );
		let nb = (buffer<<valueOf(srcSz))|zeroExtend(d);
		if ( counter + fromInteger(iSrcSz*2) >= fromInteger(iDstSz) ) begin
			counter <= 0;
			buffer <= 0;
			outQ.enq(nb);
			$display ( "CollectPacker emitting %x", nb );
		end else begin
			counter <= counter + fromInteger(iSrcSz);
			buffer <= nb;
		end
	endrule

	method Action enq(Bit#(srcSz) data);
		inQ.enq(data);
	endmethod
	method Bit#(dstSz) first;
		return outQ.first;
	endmethod
	method Action deq;
		outQ.deq;
	endmethod
endmodule

interface CollectUnpackerIfc#(numeric type dstSz, numeric type srcSz);
	method Action enq(Bit#(srcSz) data);
	method Bit#(dstSz) first;
	method Action deq;
endinterface

module mkCollectUnPacker (CollectUnPackerIfc#(dstSz, srcSz))
	provisos(Add#(__a,dstSz,srcSz));

	Integer iSrcSz = valueOf(srcSz);
	Integer iDstSz = valueOf(dstSz);
	
	FIFO#(Bit#(srcSz)) inQ <- mkFIFO;
	FIFO#(Bit#(dstSz)) outQ <- mkFIFO;

	Reg#(Bit#(TAdd#(TLog#(srcSz),1))) counter <- mkReg(~0);
	Reg#(Bit#(srcSz)) buffer <- mkReg(0);

	rule doUnpack;
		if ( counter + fromInteger(iDstSz) >= fromInteger(iSrcSz) ) begin
			outQ.enq(truncate(inQ.first));
			buffer <= (inQ.first>>iDstSz);
			counter <= fromInteger(iDstSz);
		end else begin
			counter <= counter + fromInteger(iDstSz);
			buffer <= (buffer>>iDstSz);
			outQ.enq(truncate(buffer));
		end
	endrule

	method Action enq(Bit#(srcSz) data);
		inQ.enq(data);
	endmethod
	method Bit#(dstSz) first;
		return outQ.first;
	endmethod
	method Action deq;
		outQ.deq;
	endmethod
endmodule
