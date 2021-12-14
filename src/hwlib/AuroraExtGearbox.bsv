import FIFO::*;
import FIFOF::*;
import Clocks :: *;
import Vector:: *;

import BRAM::*;
import BRAMFIFO::*;

import AuroraCommon::*;

typedef 64 AuroraPhysWidth;
typedef TSub#(AuroraPhysWidth, 2) AuroraFCWidth;
typedef Bit#(AuroraPhysWidth) AuroraIfcType;
typedef Bit#(AuroraFCWidth) AuroraFC;

interface AuroraExtFlowControlIfc;
	method Action send(AuroraIfcType data);
	method ActionValue#(AuroraIfcType) receive;

	method Bit#(1) channel_up;
	method Bit#(1) lane_up;
endinterface

module mkAuroraExtFlowControl#(AuroraControllerIfc#(AuroraPhysWidth) user, Clock uclk, Reset urst, Integer idx) (AuroraExtFlowControlIfc);
	Integer recvQDepth = 128;
	Integer windowSize = 64;

	Reg#(Bit#(16)) maxInFlightUp <- mkReg(0);
	Reg#(Bit#(16)) maxInFlightDown <- mkReg(0);
	Reg#(Bit#(16)) curInQUp <- mkReg(0);
	Reg#(Bit#(16)) curInQDown <- mkReg(0);
	Reg#(Bit#(16)) curSendBudgetUp <- mkReg(0);
	Reg#(Bit#(16)) curSendBudgetDown <- mkReg(0);
	
	//-------------------------------------------------------------------------------------
	// Rules for Sending
	//-------------------------------------------------------------------------------------
	SyncFIFOIfc#(AuroraIfcType) outPacketQ <- mkSyncFIFOToCC(8, uclk, urst);
	FIFO#(AuroraIfcType) sendQ <- mkSizedFIFO(32);
	rule sendPacket;
		let curSendBudget = curSendBudgetUp - curSendBudgetDown;
		if ((maxInFlightUp-maxInFlightDown)
			+(curInQUp-curInQDown)
			+fromInteger(windowSize) < fromInteger(recvQDepth)) begin
		
			user.send({fromInteger(windowSize), 2'b01});
			maxInFlightUp <= maxInFlightUp + fromInteger(windowSize);
		end else if ( curSendBudget > 0 ) begin
			sendQ.deq;
			user.send(sendQ.first);
			curSendBudgetDown <= curSendBudgetDown + 1;
		end
	endrule

	Reg#(Maybe#(AuroraFC)) outPacketBuffer <- mkReg(tagged Invalid);
	rule serOutPacket;
		if ( isValid(outPacketBuffer) ) begin
			let d = fromMaybe(?, outPacketBuffer);
			outPacketBuffer <= tagged Invalid;
			sendQ.enq({d, 2'b10});
		end else begin
			outPacketQ.deq;
			let d = outPacketQ.first;
			outPacketBuffer <= tagged Valid truncate(d>>valueof(AuroraFCWidth));
			sendQ.enq({truncate(d), 2'b00});
		end
	endrule

	//-------------------------------------------------------------------------------------
	// Rules for receiving
	//-------------------------------------------------------------------------------------
	SyncFIFOIfc#(AuroraIfcType) inPacketQ <- mkSyncFIFOFromCC(8, uclk);
	FIFO#(AuroraIfcType) recvQ <- mkSizedBRAMFIFO(recvQDepth);
	Reg#(AuroraFC) inPacketBuffer <- mkReg(0);
	rule recvPacket;
		let d <- user.receive;
	   	//$display( "(%t) %m, AuroraExtFlowControl idx = %d, received %x", $time, idx, d );
		Bit#(1) control = d[0];
		Bit#(1) header = d[1];

		if ( control == 1 ) begin
			AuroraFC curData = truncateLSB(d);
			curSendBudgetUp <= curSendBudgetUp + truncate(curData);
		end else begin 
			if ( header == 1 ) begin
				let pasData = inPacketBuffer;
				Bit#(2) curData = truncateLSB(d);
				recvQ.enq({curData, pasData});
				curInQUp <= curInQUp + 1;
				maxInFlightDown <= maxInFlightDown + 1;
			end else begin
				AuroraFC curData = truncateLSB(d);
				inPacketBuffer <= curData;
			end
		end
	endrule
 
	rule desInPacket;
		curInQDown <= curInQDown + 1;
		recvQ.deq;
		inPacketQ.enq(recvQ.first);
	endrule
	
	method Action send(AuroraIfcType data);
		outPacketQ.enq(data);
	endmethod
	method ActionValue#(AuroraIfcType) receive;
		inPacketQ.deq;
		return inPacketQ.first;
	endmethod
	method Bit#(1) channel_up = user.channel_up;
	method Bit#(1) lane_up = user.lane_up;
endmodule
