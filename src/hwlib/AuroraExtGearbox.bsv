import FIFO::*;
import FIFOF::*;
import Clocks :: *;
import Vector:: *;

import BRAM::*;
import BRAMFIFO::*;

import AuroraCommon::*;

typedef 64 AuroraPhysWidth;
typedef TSub#(AuroraPhysWidth, 2) BodySz;
typedef TMul#(BodySz,2) AuroraIfcWidth;
typedef Bit#(AuroraIfcWidth) AuroraIfcType;

typedef TDiv#(AuroraIfcWidth, 2) AuroraIfcWidthH;

interface AuroraExtFlowControlIfc;
	method Action send(AuroraIfcType data);
	method ActionValue#(AuroraIfcType) receive;

	method Bit#(1) channel_up;
	method Bit#(1) lane_up;
endinterface
module mkAuroraExtFlowControl#(AuroraControllerIfc#(AuroraPhysWidth) auroraExt, Clock aclk, Reset arst) (AuroraExtFlowControlIfc);
	//Clock aclk = auroraExt.aurora_clk;
	//Reset arst = auroraExt.aurora_rst;

	Integer recvQDepth = 128;
	Integer windowSize = 64;
	SyncFIFOIfc#(AuroraIfcType) recvQ <- mkSyncFIFOToCC(2, aclk, arst);
	
	//SyncFIFOIfc#(Bit#(AuroraIfcWidthH)) recvQt <- mkSyncFIFOToCC(2, aclk, arst);
	//SyncFIFOIfc#(Bit#(AuroraIfcWidthH)) recvQb <- mkSyncFIFOToCC(2, aclk, arst);
	FIFO#(AuroraIfcType) recvBufferQ <- mkSizedFIFO(recvQDepth, clocked_by aclk, reset_by arst);
	FIFO#(AuroraIfcType) recvQ2 <- mkFIFO;

	Reg#(Bit#(16)) maxInFlightUp <- mkReg(0, clocked_by aclk, reset_by arst);
	Reg#(Bit#(16)) maxInFlightDown <- mkReg(0, clocked_by aclk, reset_by arst);
	Reg#(Bit#(16)) curInQUp <- mkReg(0, clocked_by aclk, reset_by arst);
	Reg#(Bit#(16)) curInQDown <- mkReg(0, clocked_by aclk, reset_by arst);
	FIFOF#(Bit#(8)) flowControlQ <- mkFIFOF(clocked_by aclk, reset_by arst);
	rule emitFlowControlPacket
		((maxInFlightUp-maxInFlightDown)
		+(curInQUp-curInQDown)
		+fromInteger(windowSize) < fromInteger(recvQDepth));

		flowControlQ.enq(fromInteger(windowSize));
		maxInFlightUp <= maxInFlightUp + fromInteger(windowSize);
	endrule

	Reg#(Bit#(16)) curSendBudgetUp <- mkReg(0, clocked_by aclk, reset_by arst);
	Reg#(Bit#(16)) curSendBudgetDown <- mkReg(0, clocked_by aclk, reset_by arst);


	SyncFIFOIfc#(AuroraIfcType) sendQ <- mkSyncFIFOFromCC(4, aclk);
	//SyncFIFOIfc#(Bit#(AuroraIfcWidthH)) sendQt <- mkSyncFIFOFromCC(4, aclk);
	//SyncFIFOIfc#(Bit#(AuroraIfcWidthH)) sendQb <- mkSyncFIFOFromCC(4, aclk);

	FIFO#(Bit#(AuroraPhysWidth)) auroraOutQ <- mkFIFO(clocked_by aclk, reset_by arst);
	rule flushAuroraOutQ;
		auroraOutQ.deq;
		auroraExt.send(auroraOutQ.first);
	endrule
	Reg#(Maybe#(Bit#(BodySz))) packetSendBuffer <- mkReg(tagged Invalid, clocked_by aclk, reset_by arst);
	rule sendPacketPart;
		let curSendBudget = curSendBudgetUp - curSendBudgetDown;
		if ( flowControlQ.notEmpty ) begin
			flowControlQ.deq;
			auroraOutQ.enq({2'b01, zeroExtend(flowControlQ.first)});
		end else
		if ( curSendBudget > 0 ) begin
			if ( isValid(packetSendBuffer) ) begin
				let btpl = fromMaybe(?, packetSendBuffer);
				//auroraIntraImport.user.send({2'b10,
				auroraOutQ.enq({2'b10,
					btpl});
				packetSendBuffer <= tagged Invalid;
				curSendBudgetDown <= curSendBudgetDown + 1;
			end else begin
				sendQ.deq;
				//sendQt.deq;
				//sendQb.deq;
				//let data = {sendQb.first, sendQt.first};
				let data = sendQ.first;
				packetSendBuffer <= tagged Valid 
					truncate(data>>valueOf(BodySz));
				auroraOutQ.enq({2'b00,truncate(data)});
			end
		end
	endrule

	FIFO#(Bit#(AuroraPhysWidth)) auroraInQ <- mkFIFO(clocked_by aclk, reset_by arst);
	rule fillAuroraInQ;
		let d <- auroraExt.receive;
		auroraInQ.enq(d);
	endrule
	Reg#(Maybe#(Bit#(BodySz))) packetRecvBuffer <- mkReg(tagged Invalid, clocked_by aclk, reset_by arst);
	rule recvPacketPart;
		let crdata = auroraInQ.first;
		auroraInQ.deq;
		Bit#(BodySz) cdata = truncate(crdata);
		Bit#(8) header = truncate(crdata>>valueOf(BodySz));
		Bit#(1) idx = header[1];
		Bit#(1) control = header[0];

		if ( control == 1 ) begin
			curSendBudgetUp <= curSendBudgetUp + truncate(cdata);
		end else
		if ( isValid(packetRecvBuffer) ) begin
			let pdata = fromMaybe(0, packetRecvBuffer);
			if ( idx == 1 ) begin
				packetRecvBuffer <= tagged Invalid;
				recvBufferQ.enq( {cdata, pdata} );

				maxInFlightDown <= maxInFlightDown + 1;
				curInQUp <= curInQUp + 1;
			end
			else begin
				packetRecvBuffer <= tagged Valid cdata;
			end
		end
		else begin
			if ( idx == 0 ) 
				packetRecvBuffer <= tagged Valid cdata;
		end
	endrule
	rule flushReadBuffer;
		curInQDown <= curInQDown + 1;

		recvBufferQ.deq;
		recvQ.enq(recvBufferQ.first);
		//recvQt.enq(truncate(recvBufferQ.first));
		//recvQb.enq(truncate(recvBufferQ.first>>valueOf(AuroraIfcWidthH)));
	endrule
	rule flushReadBuffer2;
		recvQ.deq;
		//recvQt.deq;
		//recvQb.deq;

		//recvQ2.enq({recvQb.first,recvQt.first});
		recvQ2.enq(recvQ.first);
	endrule

	
	method Action send(AuroraIfcType data);
		sendQ.enq(data);

		//sendQt.enq(truncate(data));
		//sendQb.enq(truncate(data>>valueOf(AuroraIfcWidthH)));
	endmethod
	method ActionValue#(AuroraIfcType) receive;
		recvQ2.deq;
		return recvQ2.first;
	endmethod
	method Bit#(1) channel_up = auroraExt.channel_up;
	method Bit#(1) lane_up = auroraExt.lane_up;
endmodule

