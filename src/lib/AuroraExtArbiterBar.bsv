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

typedef 20 NodeCount;

interface AuroraExtArbiterBarIfc;
endinterface

module mkAuroraExtArbiterBar#(Vector#(tPortCount, AuroraExtUserIfc) extports, Vector#(tEndpointCount, AuroraEndpointCmdIfc) endpoints, Reg#(Bit#(HeaderFieldSz)) myIdx) (AuroraExtArbiterBarIfc)
	provisos(
	NumAlias#(TAdd#(tPortCount,tEndpointCount),tTotalInCount));

	Integer endpointCount = valueOf(tEndpointCount);
	Integer portCount = valueOf(tPortCount);
	Integer totalInCount = valueOf(tTotalInCount);

	//function AuroraExtUserIfc uifc(AuroraEndpointCmdIfc cmd) = cmd.user;
	//Vector#(tTotalInCount, AuroraExtUserIfc) ports = append(extports, map(uifc,endpoints));



endmodule

