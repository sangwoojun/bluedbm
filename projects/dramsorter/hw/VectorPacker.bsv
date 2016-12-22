import FIFO::*;
import FIFOF::*;
import Clocks::*;
import Vector::*;

interface VectorPackerIfc#(numeric type scnt, type stype, type dtype);
	method Action enq(Vector#(scnt, stype) dat);
	method dtype first;
	method Action deq;
endinterface

module mkVectorPacker (VectorPackerIfc#(scnt, stype, dtype));

	

	method Action enq(Vector#(scnt, stype) dat);
	endmethod
	method dtype first;
		return ?;
	endmethod
	method Action deq;
	endmethod
endmodule

interface VectorUnpackerIfc#(numeric type stypeSz, numeric type dcnt, type dtype);
	method Action enq(Bit#(stypeSz) dat);
	method Vector#(dcnt, dtype) first;
	method Action deq;
endinterface

module mkVectorUnpacker (VectorUnpackerIfc#(stypeSz, dcnt, dtype))
	provisos(
	//Bits#(stype, stypeSz)
	Add#(a__, dtypeSz, stypeSz)
	, Bits#(dtype, dtypeSz));

	FIFO#(Bit#(stypeSz)) inQ <- mkFIFO;
	FIFO#(Vector#(dcnt, dtype)) outQ <- mkFIFO;
	rule unpackr;
		let d = inQ.first;
		inQ.deq;

		Vector#(dcnt, dtype) rvec;
		for ( Integer i = 0; i < valueOf(dcnt); i=i+1 )
		begin
			rvec[i] = unpack(truncate(d>>(i*valueOf(dtypeSz))));
		end
		outQ.enq(rvec);
	endrule

	method Action enq(Bit#(stypeSz) dat);
		inQ.enq(dat);
	endmethod
	method Vector#(dcnt, dtype) first;
		return outQ.first;
	endmethod
	method Action deq;
		outQ.deq;
	endmethod
endmodule

interface VectorSerializerIfc#(numeric type cnt, type dtype);
	method Action enq(Vector#(cnt,dtype) in);
	method Action deq;
	method dtype first;
endinterface

module mkVectorSerializer (VectorSerializerIfc#(cnt,dtype))
	provisos(
		Bits#(dtype, stypeSz)
		, Bits#(Vector#(cnt, dtype), b__)
	);
	Integer count = valueOf(cnt);
	Reg#(Vector#(cnt, dtype)) upbuf <- mkReg(?);
	Reg#(Bit#(TAdd#(1,TLog#(cnt)))) curoff <- mkReg(0);
	FIFO#(dtype) outQ <- mkFIFO;

	rule ser( curoff > 0 );
		outQ.enq(upbuf[fromInteger(count)-curoff]);
		curoff <= curoff - 1;
	endrule
	
	method Action enq(Vector#(cnt,dtype) in) if ( curoff == 0 );
		upbuf <= in;
		curoff <= fromInteger(count);
	endmethod
	method Action deq;
		outQ.deq;
	endmethod
	method dtype first;
		return outQ.first;
	endmethod
endmodule
