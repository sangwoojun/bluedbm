import FIFO::*;

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
		outQ.enq(truncate(buffer>>(valueOf(dst)*3)));
		buffer <= (buffer<<valueOf(dst));
	endrule
	method Action enq(Bit#(TMul#(dst,4)) data) if (cnt == 0);
		cnt <= 3;
		buffer <= (data<<valueOf(dst));
		//outQ.enq(truncate(data));
		outQ.enq(truncate(data>>(valueOf(dst)*3)));
	endmethod
	method Action deq;
		outQ.deq;
	endmethod
	method Bit#(dst) first;
		return outQ.first;
	endmethod
endmodule

module mkSplit4WidthReverse (Split4WidthIfc#(dst))
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

interface Split2WidthIfc#(numeric type dst);
	method Action enq(Bit#(TMul#(dst,2)) data);
	method Action deq;
	method Bit#(dst) first;
endinterface

module mkSplit2WidthReverse (Split2WidthIfc#(dst))
	provisos(Add#(a__, dst, TMul#(dst, 2)));

	Reg#(Bit#(TMul#(dst,2))) buffer <- mkReg(0);
	Reg#(Bit#(2)) cnt <- mkReg(0);
	FIFO#(Bit#(dst)) outQ <- mkFIFO;
	rule split( cnt > 0 );
		cnt <= cnt - 1;
		outQ.enq(truncate(buffer));
		buffer <= (buffer>>valueOf(dst));
	endrule
	method Action enq(Bit#(TMul#(dst,2)) data) if (cnt == 0);
		cnt <= 1;
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
