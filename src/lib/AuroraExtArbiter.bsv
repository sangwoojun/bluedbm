import FIFO::*;
import FIFOF::*;
import Vector::*;
import RWire::*;

import XBar::*;

import AuroraExtImport::*;
import AuroraCommon::*;
import AuroraExtGearbox::*;

typedef 6 HeaderFieldSz;
typedef TSub#(AuroraIfcWidth, TMul#(HeaderFieldSz, 3)) PayloadSz;
typedef struct {
	Bit#(PayloadSz) payload;
	//Bit#(HeaderFieldSz) len; // not used now
	Bit#(HeaderFieldSz) ptype;
	Bit#(HeaderFieldSz) src;
	Bit#(HeaderFieldSz) dst;
} AuroraPacket deriving (Bits,Eq);
function Bit#(AuroraIfcWidth) packPacket(AuroraPacket packet);
	Bit#(AuroraIfcWidth) p = {
		packet.payload,
		//packet.len,
		packet.ptype,
		packet.src,
		packet.dst
	};
	return p;
endfunction
function AuroraPacket unpackPacket(Bit#(AuroraIfcWidth) d);
	AuroraPacket packet;
	packet.dst = truncate(d);
	packet.src = truncate(d>>valueOf(HeaderFieldSz));
	packet.ptype = truncate(d>>(2*valueOf(HeaderFieldSz)));
	//packet.len = truncate(d>>(3*valueOf(HeaderFieldSz)));
	packet.payload = truncate(d>>(3*valueOf(HeaderFieldSz)));
	return packet;
endfunction

interface AuroraEndpointUserIfc#(type t);
	method Action send(t data, Bit#(HeaderFieldSz) dst);
	method ActionValue#(Tuple2#(t, Bit#(HeaderFieldSz))) receive;
endinterface
interface AuroraEndpointCmdIfc;
	interface AuroraExtUserIfc user;
	//method Action send(AuroraIfcType data);
	//method ActionValue#(AuroraIfcType) receive;
	method Bit#(6) portIdx;
endinterface

interface AuroraEndpointIfc#(type t);
interface AuroraEndpointUserIfc#(t) user;
interface AuroraEndpointCmdIfc cmd;
endinterface

module mkAuroraEndpoint#(Integer pidx, Reg#(Bit#(HeaderFieldSz)) myNetIdx) ( AuroraEndpointIfc#(t) )
	provisos(Bits#(t,wt)
		, Add#(wt,__a,PayloadSz)
		, Log#(wt, wtlog)
		);
	
	FIFO#(AuroraIfcType) sendQ <- mkFIFO;
	FIFO#(AuroraIfcType) recvQ <- mkFIFO;
	Reg#(Bit#(HeaderFieldSz)) myIdx <- mkReg(fromInteger(pidx));

interface AuroraEndpointUserIfc user;
	method Action send(t data, Bit#(HeaderFieldSz) dst);
		AuroraPacket p;
		p.dst = dst;
		p.src = myNetIdx;
		p.payload = zeroExtend(pack(data));
		p.ptype = fromInteger(pidx);
		sendQ.enq(packPacket(p));
	endmethod
	method ActionValue#(Tuple2#(t, Bit#(HeaderFieldSz))) receive;
		recvQ.deq;
		AuroraIfcType idata = recvQ.first;
		AuroraPacket p = unpackPacket(idata);
		t data = unpack(truncate(p.payload));
		Bit#(HeaderFieldSz) src = p.src;
		return tuple2(data,src);
	endmethod
endinterface
interface AuroraEndpointCmdIfc cmd;
	interface AuroraExtUserIfc user;
		method Action send(AuroraIfcType data);
			recvQ.enq(data);
		endmethod
		method ActionValue#(AuroraIfcType) receive;
			sendQ.deq;
			return sendQ.first;
		endmethod
		method Bit#(1) lane_up;
			return 1;
		endmethod
		method Bit#(1) channel_up;
			return 1;
		endmethod
	endinterface
	method Bit#(6) portIdx;
		return myIdx;
	endmethod
endinterface
endmodule

//FIXME This one has so many bugs!
module mkAuroraEndpointTyped#(Integer pidx, Reg#(Bit#(HeaderFieldSz)) myNetIdx) ( AuroraEndpointIfc#(t) )
	provisos(
		Bits#(t,wt)
		//, Add#(PayloadSz, __qq, wt)
		, Add#(PayloadSz, wt, totalW)
		, Add#(__a, wtlog, totalW)
		//, Add#(__adf, wt,PayloadSz)
		, Log#(wt, wtlog)
		);
	
	Integer dataBits = valueOf(wt);
	Integer beatWidth = valueOf(PayloadSz);

	FIFO#(AuroraIfcType) sendQ <- mkFIFO;
	FIFO#(AuroraIfcType) recvQ <- mkFIFO;
	Reg#(Bit#(HeaderFieldSz)) myIdx <- mkReg(fromInteger(pidx));

	FIFO#(Tuple2#(Bit#(wt), Bit#(HeaderFieldSz))) outDataQ <- mkFIFO;
	Reg#(Bit#(wt)) outDataBuffer <- mkReg(0);
	Reg#(Bit#(HeaderFieldSz)) outDataDst <- mkReg(0);
	Reg#(Bit#(wtlog)) outDataIdx <- mkReg(0);

	rule initDataSend( outDataIdx == 0 );
		let od = outDataQ.first;
		outDataQ.deq;
		let data = tpl_1(od);
		let dst = tpl_2(od);

		Bit#(totalW) tempW = zeroExtend(data);
		Bit#(PayloadSz) payload = truncate(tempW);


		AuroraPacket p;
		p.dst = dst;
		p.src = myNetIdx;
		p.payload = payload;
		//p.payload = truncate(data);
		p.ptype = fromInteger(pidx);
		sendQ.enq(packPacket(p));
		//$display ( "Sending data %x(%x) to %d from %d", payload, data, dst, pidx );

		if ( dataBits > beatWidth ) begin
			outDataBuffer <= data>>beatWidth;
			outDataIdx <= fromInteger(dataBits-beatWidth);
			outDataDst <= dst;
		end
	endrule

	rule sendDataOut ( outDataIdx > 0 );
		Bit#(totalW) outDataIdxT = zeroExtend(outDataIdx);
		if ( outDataIdxT > fromInteger(beatWidth) ) begin
			outDataIdx <= truncate(outDataIdxT - fromInteger(beatWidth));
		end else begin
			outDataIdx <= 0;
		end
		outDataBuffer <= outDataBuffer>>beatWidth;
		
		Bit#(totalW) tempW = zeroExtend(outDataBuffer);
		Bit#(PayloadSz) payload = truncate(tempW);

		AuroraPacket p;
		p.dst = outDataDst;
		p.src = myNetIdx;
		p.payload = payload;
		p.ptype = fromInteger(pidx);

		sendQ.enq(packPacket(p));
		//$display ( "Sending data %x to %d from %d -> %d", payload, outDataDst, pidx, outDataIdxT );

	endrule

	FIFO#(Tuple2#(t, Bit#(HeaderFieldSz))) inDataQ <- mkFIFO;
	Reg#(Bit#(wt)) inDataBuffer <- mkReg(0);
	//Reg#(Bit#(HeaderFieldSz)) inDataSrc <- mkReg(0);
	//Reg#(Bit#(wtlog)) inDataIdx <- mkReg(0);
	Reg#(Bit#(wtlog)) inDataOff <- mkReg(0);

	rule recvInData;
		let id = recvQ.first;
		recvQ.deq;
		AuroraPacket p = unpackPacket(id);
		Bit#(totalW) tempW = zeroExtend(p.payload);
		Bit#(totalW) offsetW = zeroExtend(inDataOff);
		//Bit#(totalW) nextBuffer = zeroExtend(inDataBuffer<<beatWidth) | zeroExtend(p.payload);

		Bit#(totalW) newDataOr = tempW << (offsetW*fromInteger(beatWidth));
		Bit#(totalW) nextBuffer = zeroExtend(inDataBuffer) | newDataOr;
		
		//$display( "recv - %x %x %x %d, %d/%d", p.payload, nextBuffer, newDataOr, offsetW, (offsetW+1)*fromInteger(beatWidth), fromInteger(dataBits) );
		if ( (offsetW+1)*fromInteger(beatWidth) < fromInteger(dataBits) ) begin
			inDataOff <= inDataOff + 1;
			inDataBuffer <= truncate(nextBuffer);
		end else begin
			Bit#(totalW) dataBitsT = fromInteger(dataBits);
			Bit#(totalW) beatWidthT = fromInteger(beatWidth);

			Bit#(wt) recvData = truncate(nextBuffer);
			inDataQ.enq(tuple2(unpack(recvData), p.src));
			//$display ( "Receiving data %x from %d from %d", recvData, p.src, pidx );
			inDataOff <= 0;
			inDataBuffer <= 0;
		end
	endrule
	

interface AuroraEndpointUserIfc user;
	method Action send(t data, Bit#(HeaderFieldSz) dst);
		outDataQ.enq(tuple2(pack(data), dst));
	endmethod
	method ActionValue#(Tuple2#(t, Bit#(HeaderFieldSz))) receive;
		inDataQ.deq;
		return inDataQ.first;
	endmethod
endinterface
interface AuroraEndpointCmdIfc cmd;
	interface AuroraExtUserIfc user;
		method Action send(AuroraIfcType data);
			recvQ.enq(data);
		endmethod
		method ActionValue#(AuroraIfcType) receive;
			sendQ.deq;
			return sendQ.first;
		endmethod
		method Bit#(1) lane_up;
			return 1;
		endmethod
		method Bit#(1) channel_up;
			return 1;
		endmethod

	endinterface
	method Bit#(6) portIdx;
		return myIdx;
	endmethod
endinterface
endmodule


typedef 20 NodeCount;

interface AuroraExtArbiterIfc;
	method Action setRoutingTable(Bit#(6) node, Bit#(8) portidx, Bit#(3) portsel);
endinterface

module mkAuroraExtArbiter#(Vector#(tPortCount, AuroraExtUserIfc) extports, Vector#(tEndpointCount, AuroraEndpointCmdIfc) endpoints, Reg#(Bit#(HeaderFieldSz)) myIdx) (AuroraExtArbiterIfc)
	provisos(
	NumAlias#(TAdd#(tPortCount,tEndpointCount),tTotalInCount));

	Integer endpointCount = valueOf(tEndpointCount);
	Integer portCount = valueOf(tPortCount);
	Integer totalInCount = valueOf(tTotalInCount);

	//function AuroraExtUserIfc uifc(AuroraEndpointCmdIfc cmd) = cmd.user;
	//Vector#(tTotalInCount, AuroraExtUserIfc) ports = append(extports, map(uifc,endpoints));

	//NOTE: routingTable includes 8 possible ports to get to each node. 
	//one of 8 is selected based on the packet type, so all 8 needs to be always filled!
	Vector#(NodeCount, Vector#(8, Reg#(Bit#(8)))) routingTable <- replicateM(replicateM(mkReg(0)));

	XBarIfc#(tPortCount, tPortCount,AuroraPacket, Bit#(HeaderFieldSz)) xbarPP <- mkXBar;
	XBarIfc#(tEndpointCount, tEndpointCount,AuroraPacket, Bit#(HeaderFieldSz)) xbarEE <- mkXBar;
	
	XBarIfc#(tEndpointCount, tPortCount,AuroraPacket, Bit#(HeaderFieldSz)) xbarEP <- mkXBar;
	XBarIfc#(tPortCount, tEndpointCount,AuroraPacket, Bit#(HeaderFieldSz)) xbarPE <- mkXBar;

	function Bit#(HeaderFieldSz) mapDstToPort(Bit#(HeaderFieldSz) dst, Bit#(HeaderFieldSz) ptype);
		//FIXME
		let portsel = ptype[2:0]; // <- 8 possible lanes to same link. change?
		Bit#(HeaderFieldSz) ret = truncate(routingTable[dst][portsel]);
		return ret;
	endfunction
	function Bit#(HeaderFieldSz) mapPIdxToIdx(Bit#(HeaderFieldSz) pidx);
		Bit#(HeaderFieldSz) ret = 0;
		for ( Integer i = 0; i < endpointCount; i = i + 1 ) begin
			if ( endpoints[i].portIdx == pidx ) ret = fromInteger(i);
		end

		return ret;
	endfunction
	
	for ( Integer idx = 0; idx < endpointCount; idx = idx + 1) begin
		rule recvInDataEP;
			let d <- endpoints[idx].user.receive;
			AuroraPacket packet = unpackPacket(d);
			if ( packet.dst == myIdx ) begin
				let dstpidx = mapPIdxToIdx(packet.ptype);
				xbarEE.userIn[idx].send(packet, dstpidx);
			end else begin
				let dstport = mapDstToPort(packet.dst, packet.ptype);
				xbarEP.userIn[idx].send(packet, dstport);
			end
		endrule

		Reg#(Bool) prioEP <- mkReg(False);
		rule forwardOutDataEP;
			let epidx = endpoints[idx].portIdx;
			//TODO have a table eipidx -> idx
			// to know which userOut to poll
			// deq will use first Integer idx
			if ( prioEP ) begin
				if ( xbarEE.userOut[idx].notEmpty ) begin
					let d <- xbarEE.userOut[idx].receive;
					let rp = packPacket(d);
					endpoints[idx].user.send(rp);
				end else if (xbarPE.userOut[idx].notEmpty) begin
					let d <- xbarPE.userOut[idx].receive;
					let rp = packPacket(d);
					endpoints[idx].user.send(rp);
				end
			end else begin
				if ( xbarPE.userOut[idx].notEmpty ) begin
					let d <- xbarPE.userOut[idx].receive;
					let rp = packPacket(d);
					endpoints[idx].user.send(rp);
				end else if (xbarEE.userOut[idx].notEmpty) begin
					let d <- xbarEE.userOut[idx].receive;
					let rp = packPacket(d);
					endpoints[idx].user.send(rp);
				end
			end
		endrule
	end
	
	for ( Integer idx = 0; idx < portCount; idx = idx + 1) begin
		rule recvInDataP;
			let d <- extports[idx].receive;
			AuroraPacket packet = unpackPacket(d);
			if ( packet.dst == myIdx ) begin
				let dstpidx = mapPIdxToIdx(packet.ptype);
				xbarPE.userIn[idx].send(packet, dstpidx);
			end else begin
				let dstport = mapDstToPort(packet.dst, packet.ptype);
				xbarPP.userIn[idx].send(packet, dstport);
			end
		endrule

		Reg#(Bool) prioEP <- mkReg(False);
		rule forwardOutDataP;
			if ( prioEP ) begin
				if ( xbarEP.userOut[idx].notEmpty ) begin
					let d <- xbarEP.userOut[idx].receive;
					let rp = packPacket(d);
					extports[idx].send(rp);
				end else if (xbarPP.userOut[idx].notEmpty) begin
					let d <- xbarPP.userOut[idx].receive;
					let rp = packPacket(d);
					extports[idx].send(rp);
				end
			end else begin
				if ( xbarPP.userOut[idx].notEmpty ) begin
					let d <- xbarPP.userOut[idx].receive;
					let rp = packPacket(d);
					extports[idx].send(rp);
				end else if (xbarEP.userOut[idx].notEmpty) begin
					let d <- xbarEP.userOut[idx].receive;
					let rp = packPacket(d);
					extports[idx].send(rp);
				end
			end
		endrule
	end


	method Action setRoutingTable(Bit#(6) node, Bit#(8) portidx, Bit#(3) portsel);
		routingTable[node][portsel] <= portidx;
	endmethod
endmodule

