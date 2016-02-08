import FIFOF::*;
import FIFO::*;

interface StreamingDeserializerIfc#(type tFrom, type tTo);
	method ActionValue#(tTo) deq;
	method Action enq(tFrom in, Bool cont);
endinterface

module mkStreamingDeserializer (StreamingDeserializerIfc#(tFrom, tTo))
	provisos(
		Bits#(tFrom, tFromSz)
		, Bits#(tTo, tToSz)
		, Add#(tFromSz, __a, tToSz)
		//, Log#(tFromSz, tFromSzLog)
	);
	Integer fromSz = valueOf(tFromSz);
	Integer toSz = valueOf(tToSz);

	Reg#(Bit#(32)) outCounter <- mkReg(0);
	Reg#(Bit#(tToSz)) outBuffer <- mkReg(0);

	FIFO#(tTo) outQ <- mkFIFO;

	method ActionValue#(tTo) deq;
		outQ.deq;
		return outQ.first;
	endmethod
	method Action enq(tFrom in, Bool cont);
		let inData = pack(in);
		Bit#(tToSz) nextBuffer = outBuffer | (zeroExtend(inData)<<outCounter);

		if ( outCounter + fromInteger(fromSz) > fromInteger(toSz) ) begin
			let over = outCounter + fromInteger(fromSz) - fromInteger(toSz);
			outQ.enq(unpack(nextBuffer));
			if ( cont ) begin
				outCounter <= over;
				let minus = fromInteger(toSz) - outCounter;
				outBuffer <= (zeroExtend(inData) >> minus);
				//$display( "%x >%d %d %x", inData, over,outCounter, inData >> minus );
			end else begin
				outCounter <= 0;
				outBuffer <= 0;
			end
		end
		else if ( outCounter + fromInteger(fromSz) == fromInteger(toSz) ) begin
			outBuffer <= 0;
			outCounter <= 0;
			outQ.enq(unpack(nextBuffer));
		end else if ( cont ) begin
			outBuffer <= nextBuffer;
			outCounter <= outCounter + fromInteger(fromSz);
			//$display( "outcounter -> %d", outCounter + fromInteger(fromSz) );
		end else begin
			outBuffer <= 0;
			outCounter <= 0;
		end
	endmethod
endmodule

interface StreamingSerializerIfc#(type tFrom, type tTo);
	method ActionValue#(Tuple2#(tTo,Bool)) deq;
	method Action enq(tFrom in);
endinterface

module mkStreamingSerializer (StreamingSerializerIfc#(tFrom, tTo))
	provisos(
		Bits#(tFrom, tFromSz)
		, Bits#(tTo, tToSz)
		, Add#(tToSz, __a, tFromSz)
		//, Log#(tFromSz, tFromSzLog)
	);

	Integer fromSz = valueOf(tFromSz);
	Integer toSz = valueOf(tToSz);

	FIFOF#(Bit#(tFromSz)) inQ <- mkFIFOF;
	Reg#(Bit#(32)) inCounter <- mkReg(0); // FIXME 32
	Reg#(Maybe#(Bit#(tFromSz))) inBuffer <- mkReg(tagged Invalid);

	FIFO#(Tuple2#(tTo, Bool)) outQ <- mkFIFO;

	rule serialize;
		Bit#(tFromSz) inBufferData = fromMaybe(?, inBuffer);
		Bit#(tToSz) outData = truncate(inBufferData>>inCounter);

	
		if ( !isValid(inBuffer) ) begin
			inQ.deq;
			inBuffer <= tagged Valid inQ.first;
			inCounter <= 0;
		end else if ( inCounter + fromInteger(toSz) == fromInteger(fromSz) ) begin
			outQ.enq(tuple2(unpack(outData), True));
			inCounter <= 0;
			if ( inQ.notEmpty ) begin
				Bit#(tFromSz) fromData = inQ.first;
				inQ.deq;
				inBuffer <= tagged Valid fromData;
			end else begin
				inBuffer <= tagged Invalid;
			end
		end else if ( inCounter + fromInteger(toSz) > fromInteger(fromSz) ) begin
			if ( inQ.notEmpty ) begin
				Bit#(tFromSz) fromData = inQ.first;
				inQ.deq;
				inBuffer <= tagged Valid fromData;

				let over = inCounter + fromInteger(toSz) - fromInteger(fromSz);
				Bit#(tToSz) combData = truncate( fromData << (fromInteger(toSz) -over)) | outData;
				
				outQ.enq(tuple2(unpack(combData), True));
				inCounter <= over;
			end else begin
				outQ.enq(tuple2(unpack(outData), False));
				inCounter <= 0;
				inBuffer <= tagged Invalid;
			end
		end else begin
			outQ.enq(tuple2(unpack(outData), True));
			inCounter <= inCounter + fromInteger(toSz);
		end
	endrule


	method ActionValue#(Tuple2#(tTo,Bool)) deq; // value, continue?
		outQ.deq;
		let d = outQ.first;
		let data = tpl_1(d);
		let cont = tpl_2(d);
		return tuple2(data,cont);
	endmethod
	method Action enq(tFrom in);
		inQ.enq(pack(in));
	endmethod
endmodule
