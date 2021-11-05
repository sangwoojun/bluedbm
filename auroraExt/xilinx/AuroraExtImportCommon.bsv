package AuroraExtImportCommon;

import FIFO::*;
import Vector::*;
import BRAMFIFO::*;

import Clocks :: *;
import ClockImport :: *;
import DefaultValue :: *;

import AuroraCommon::*;
import GetPut::*;


import "BDPI" function Bool bdpiSendAvailable(Bit#(8) nidx, Bit#(8) pidx);
import "BDPI" function Bool bdpiRecvAvailable(Bit#(8) nidx, Bit#(8) pidx);
import "BDPI" function Bit#(64) bdpiRead(Bit#(8) nidx, Bit#(8) pidx);
import "BDPI" function Bool bdpiWrite(Bit#(8) nidx, Bit#(8) pidx, Bit#(64) data);


typedef 4 AuroraExtPerQuad;

typedef 64 AuroraPhysWidth;
typedef TSub#(AuroraPhysWidth, 2) AuroraFCWidth;
typedef Bit#(AuroraPhysWidth) AuroraIfcType;
typedef Bit#(AuroraFCWidth) AuroraFC;

typedef struct {
	Bit#(1) inQuad;
	Bit#(3) inPort;
	Bit#(1) outQuad;
	Bit#(3) outPort;
	AuroraIfcType payload;
} AuroraPacket deriving (Bits, Eq);

interface AuroraExtIfc;
	interface Vector#(AuroraExtPerQuad, Aurora_Pins#(1)) aurora;
	interface Vector#(AuroraExtPerQuad, AuroraExtUserIfc) user;
	method Action setNodeIdx(HeaderField idx); 
endinterface

interface AuroraExtUserIfc;
	method Action send(AuroraIfcType data);
	method ActionValue#(AuroraIfcType) receive;
   	
	method Bit#(1) lane_up;
	method Bit#(1) channel_up;
endinterface


module mkAuroraExtFlowControl#(AuroraControllerIfc#(AuroraPhysWidth) user, Clock uclk, Reset urst, Integer idx) (AuroraExtUserIfc);
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
		AuroraFC curData = truncateLSB(d);

		if ( control == 1 ) begin
			curSendBudgetUp <= curSendBudgetUp + truncate(curData);
		end else begin 
			if ( header == 1 ) begin
				let pasData = inPacketBuffer;
				recvQ.enq({curData, pasData});
				curInQUp <= curInQUp + 1;
				maxInFlightDown <= maxInFlightDown + 1;
			end else begin
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

 
module mkAuroraExtImport_bsim#(Clock gtx_clk_in, Clock init_clk, Reset init_rst_n, Reset gt_rst_n) (AuroraExtImportIfc#(AuroraExtPerQuad));
   Clock clk <- exposeCurrentClock;
   Reset rst <- exposeCurrentReset;

	Reg#(Bit#(8)) nodeIdx <- mkReg(255);
	
   Vector#(4, FIFO#(Bit#(AuroraPhysWidth))) writeQ <- replicateM(mkFIFO);
   Vector#(4, FIFO#(Bit#(AuroraPhysWidth))) mirrorQ <- replicateM(mkFIFO);

   for (Integer i = 0; i < 4; i = i + 1) begin
	rule m0 if ( bdpiRecvAvailable(nodeIdx, fromInteger(i) ));
		let d = bdpiRead(nodeIdx, fromInteger(i));
		mirrorQ[i].enq(d);
	   	//$display( "(%t) AuroraExtImport \t\tread %x %d", $time, d, i );
	endrule
	rule w0 if ( bdpiSendAvailable(nodeIdx, fromInteger(i)));
		let d = writeQ[i].first;
		if ( bdpiWrite(nodeIdx, fromInteger(i), d) ) begin
		  	//$display( "(%t) AuroraExtImport \t\twrite %x %d", $time, d, i );
			writeQ[i].deq;
		end
	endrule
   end
	
   function AuroraControllerIfc#(AuroraPhysWidth) auroraController(Integer i);
      return (interface AuroraControllerIfc;
		 interface Reset aurora_rst_n = rst;

		 method Bit#(1) channel_up;
		    return 1;
		 endmethod
		 method Bit#(1) lane_up;
		    return 1;
		 endmethod
		 method Bit#(1) hard_err;
		    return 0;
		 endmethod
		 method Bit#(1) soft_err;
		    return 0;
		 endmethod
		 method Bit#(8) data_err_count;
		    return 0;
		 endmethod

		 method Action send(Bit#(64) data);// if ( bdpiSendAvailable(nodeIdx, 0) );
		    //$display("aurora.send port %d data %h", i, data);
		    writeQ[i].enq(data);
		 endmethod
		 method ActionValue#(Bit#(64)) receive;
		    let data = mirrorQ[i].first;
		    mirrorQ[i].deq;
		    //$display("aurora.receive port %d data %h", i, data);
		    return data;
		 endmethod
	 endinterface);
   endfunction

	interface Clock aurora_clk0 = clk;
	interface Clock aurora_clk1 = clk;
	interface Clock aurora_clk2 = clk;
	interface Clock aurora_clk3 = clk;

	interface Reset aurora_rst0 = rst;
	interface Reset aurora_rst1 = rst;
	interface Reset aurora_rst2 = rst;
	interface Reset aurora_rst3 = rst;
	
	
	interface AuroraControllerIfc user0 = auroraController(0);
	interface AuroraControllerIfc user1 = auroraController(1);
	interface AuroraControllerIfc user2 = auroraController(2);
	interface AuroraControllerIfc user3 = auroraController(3);
	method Action setNodeIdx(Bit#(8) idx);
	   $display( "aurora node idx set to %d", idx);
		nodeIdx <= idx;
	endmethod

endmodule
endpackage: AuroraExtImportCommon
