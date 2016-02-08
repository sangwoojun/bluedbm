import FIFO::*;
import FIFOF::*;
import Vector::*;
import RWire::*;

interface FIFODeqIfc;
	method Action deq;
endinterface
interface FIFOMD #(type t, /*type tdst, */numeric type ports);
	method Action enq(t d);
	method Maybe#(t) first;
	interface Vector#(ports, FIFODeqIfc) deqs;
endinterface

module mkFIFOMD (FIFOMD#(t,ports))
	provisos(Bits#(t,wt)
		);

	FIFOF#(t) dataQ <- mkSizedFIFOF(8);
	Vector#(ports,Wire#(Bool)) deqWires <- replicateM(mkDWire(False));

	rule deqrule;
		Bool deqreq = False;
		for ( Integer i = 0; i < valueOf(ports); i = i + 1 ) begin
			deqreq = deqreq || deqWires[i];
		end
		//Bool deqreq = fold(funcOr, deqWires);
		if ( deqreq ) begin
			dataQ.deq;
		end
	endrule

	Vector#(ports, FIFODeqIfc) deqifc;

	for ( Integer idx = 0; idx < valueOf(ports); idx = idx + 1) begin
		deqifc[idx] = interface FIFODeqIfc;
			method Action deq;
			deqWires[idx] <= True;
			endmethod
		endinterface: FIFODeqIfc;
	end
	method Action enq(t d);
		dataQ.enq(d);
	endmethod
	method Maybe#(t) first;
		Maybe#(t) fd = tagged Invalid;
		if ( dataQ.notEmpty ) fd = tagged Valid dataQ.first;
		return fd;
	endmethod
	interface deqs = deqifc;
endmodule

interface XBarInPortIfc #(type tData, type tDst);
	method Action send(tData data, tDst dst);
endinterface
interface XBarOutPortIfc #(type tData);
	method ActionValue#(tData) receive;
	method Bool notEmpty;
endinterface

interface XBarIfc #(numeric type inPorts, numeric type outPorts, type tData, type tDst);
	interface Vector#(inPorts, XBarInPortIfc#(tData, tDst)) userIn;
	interface Vector#(outPorts, XBarOutPortIfc#(tData)) userOut;
endinterface

module mkXBar (XBarIfc#(inPorts, outPorts, tData, tDst))
	provisos(
		Bits#(tData, tDataSz), 
		Bits#(tDst, tDstSz), 
		Arith#(tDst),
		Ord#(tDst),
		PrimIndex#(tDst, tDstI)
		);
	Vector#(inPorts, FIFOMD#(tData, outPorts)) vBuffer <- replicateM(mkFIFOMD);
	Vector#(inPorts, FIFOMD#(tDst, outPorts)) vDst <- replicateM(mkFIFOMD);
	Vector#(outPorts, FIFOF#(tData)) vDstPortQ <- replicateM(mkFIFOF);

	for ( Integer pidx = 0; pidx < valueOf(outPorts); pidx = pidx + 1 ) begin
		Reg#(tDst) curPrioInPort <- mkReg(fromInteger(pidx));
		FIFO#(tDst) readSrcQ <- mkFIFO;
		rule relayOut;
			Maybe#(tDst) srcIdx = tagged Invalid;
			for ( Integer i = 0; i < valueof(inPorts); i = i + 1) begin
				tDst checkInPort = fromInteger(i);
				
				let dstm = vDst[checkInPort].first;
				if ( isValid(dstm) ) begin
					if ( !isValid(srcIdx) || checkInPort == curPrioInPort ) begin

						let dst = fromMaybe(?,dstm);
						if ( dst == fromInteger(pidx) ) begin
							srcIdx = tagged Valid checkInPort;
						end
					end
				end
			end
			
			if ( isValid(srcIdx) ) begin
				let inidx = fromMaybe(?,srcIdx);
				vDst[inidx].deqs[pidx].deq;
				readSrcQ.enq(inidx);
			end
			
		//endrule
		//rule rotatePrio;
			if (curPrioInPort + 1 >= fromInteger(valueOf(inPorts)) )
				curPrioInPort <= 0;
			else 
				curPrioInPort <= curPrioInPort + 1;
		endrule
		rule relayData2;
			let inidx = readSrcQ.first;
			readSrcQ.deq;

			vBuffer[inidx].deqs[pidx].deq;
			let packetdm = vBuffer[inidx].first;
			let packetd = fromMaybe(?,packetdm);
			vDstPortQ[pidx].enq(packetd);
		endrule
	end

	Vector#(inPorts, XBarInPortIfc#(tData,tDst)) usersin;
	Vector#(outPorts, XBarOutPortIfc#(tData)) usersout;

	for ( Integer idx = 0; idx < valueOf(inPorts); idx = idx + 1) begin
		usersin[idx] = interface XBarInPortIfc#(tData, tDst);
		method Action send(tData data, tDst dst);
			vBuffer[idx].enq(data);
			vDst[idx].enq(dst);
		endmethod
		endinterface:XBarInPortIfc;
	end
	for ( Integer idx = 0; idx < valueOf(outPorts); idx = idx + 1) begin
		usersout[idx] = interface XBarOutPortIfc#(tData);
		method ActionValue#(tData) receive;
			vDstPortQ[idx].deq;
			return vDstPortQ[idx].first;
		endmethod
		method Bool notEmpty;
			return vDstPortQ[idx].notEmpty;
		endmethod
		endinterface: XBarOutPortIfc;
	end
	interface Vector userIn = usersin;
	interface Vector userOut = usersout;
endmodule
