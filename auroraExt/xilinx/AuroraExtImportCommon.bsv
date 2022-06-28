package AuroraExtImportCommon;

import FIFO::*;
import BRAM::*;
import BRAMFIFO::*;
import Vector::*;

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
typedef TSub#(AuroraPhysWidth, 2) BodySz;
typedef TMul#(AuroraPhysWidth, 9) AuroraIfcWidth;
typedef Bit#(AuroraIfcWidth) AuroraIfcType; // 576-bit = 72-Byte


interface AuroraExtIfc;
	interface Vector#(AuroraExtPerQuad, Aurora_Pins#(1)) aurora;
	interface Vector#(AuroraExtPerQuad, AuroraExtUserIfc) user;
endinterface

interface AuroraExtUserIfc;
	method Action send(AuroraIfcType data);
	method ActionValue#(AuroraIfcType) receive;

	method Bit#(1) lane_up;
	method Bit#(1) channel_up;
endinterface


module mkAuroraExtFlowControl#(AuroraControllerIfc#(AuroraPhysWidth) user, Clock uclk, Reset urst, Integer idx) (AuroraExtUserIfc);
	Integer recvQDepth = 1152;
	Integer windowSize = 576;

	Reg#(Bit#(16)) maxInFlightUp <- mkReg(0, clocked_by uclk, reset_by urst);
	Reg#(Bit#(16)) maxInFlightDown <- mkReg(0, clocked_by uclk, reset_by urst);
	Reg#(Bit#(16)) curInQUp <- mkReg(0, clocked_by uclk, reset_by urst);
	Reg#(Bit#(16)) curInQDown <- mkReg(0, clocked_by uclk, reset_by urst);
	Reg#(Bit#(16)) curSendBudgetUp <- mkReg(0, clocked_by uclk, reset_by urst);
	Reg#(Bit#(16)) curSendBudgetDown <- mkReg(0, clocked_by uclk, reset_by urst);
	
	FIFO#(Bit#(AuroraPhysWidth)) sendQ <- mkSizedFIFO(32, clocked_by uclk, reset_by urst);
	rule sendPacket( user.lane_up != 0 && user.channel_up != 0 );
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
		end else if ( curSendBudget == 0 ) begin
			user.send({fromInteger(windowSize), 2'b01});
		end
	endrule
	
	SyncFIFOIfc#(AuroraIfcType) outPacketQ <- mkSyncFIFOFromCC(32, uclk);
	Reg#(Maybe#(Bit#(514))) outPacketBuffer1 <- mkReg(tagged Invalid, clocked_by uclk, reset_by urst);
	Reg#(Bit#(452)) outPacketBuffer2 <- mkReg(0, clocked_by uclk, reset_by urst);
	Reg#(Bit#(8)) outPacketBufferCnt <- mkReg(0, clocked_by uclk, reset_by urst);
	rule serOutPacket;
		if ( isValid(outPacketBuffer1) ) begin
			if ( outPacketBufferCnt > 0 ) begin
				if ( outPacketBufferCnt == 8 ) begin
					let d = outPacketBuffer2;
					sendQ.enq({truncate(d), 2'b10});
					
					outPacketBuffer1 <= tagged Invalid;
					outPacketBufferCnt <= 0;
				end else begin
					let d = outPacketBuffer2;
					outPacketBuffer2 <= truncate(d>>valueof(BodySz));
					outPacketBufferCnt <= outPacketBufferCnt + 1;
					sendQ.enq({truncate(d), 2'b00});
				end
			end else begin
				let d = fromMaybe(?, outPacketBuffer1);
				outPacketBuffer2 <= truncate(d>>valueof(BodySz));
				outPacketBufferCnt <= outPacketBufferCnt + 1;
				sendQ.enq({truncate(d), 2'b00});
			end
		end else begin
			outPacketQ.deq;
			let d = outPacketQ.first;
			outPacketBuffer1 <= tagged Valid truncate(d>>valueof(BodySz));
			sendQ.enq({truncate(d), 2'b00});
		end
	endrule

	FIFO#(AuroraIfcType) recvQ <- mkSizedBRAMFIFO(recvQDepth, clocked_by uclk, reset_by urst);
	Reg#(Maybe#(Bit#(558))) inPacketBuffer1 <- mkReg(tagged Invalid, clocked_by uclk, reset_by urst);
	Reg#(Bit#(558)) inPacketBuffer2 <- mkReg(0, clocked_by uclk, reset_by urst);
	Reg#(Bit#(8)) inPacketBufferCnt <- mkReg(0, clocked_by uclk, reset_by urst);
	rule recvPacket( user.lane_up != 0 && user.channel_up != 0 );
		let d <- user.receive;
		Bit#(1) control = d[0];
		Bit#(1) header = d[1];
		Bit#(BodySz) curData = truncate(d>>2);

		if ( control == 1 ) begin
			curSendBudgetUp <= curSendBudgetUp + truncate(curData);
		end else begin 
			if ( header == 1 ) begin
				let pasData = inPacketBuffer2;
				recvQ.enq({truncate(curData), pasData});
				curInQUp <= curInQUp + 1;
				maxInFlightDown <= maxInFlightDown + 1;
			end else begin
				if ( isValid(inPacketBuffer1) ) begin
					if ( inPacketBufferCnt > 0 ) begin
						if ( inPacketBufferCnt == 8 ) begin
							inPacketBuffer1 <= tagged Invalid;
							inPacketBufferCnt <= 0;
						end else begin
							inPacketBufferCnt <= inPacketBufferCnt + 1;
						end
						let p = inPacketBuffer2;
						Bit#(558) c = zeroExtend(curData);
						inPacketBuffer2 <= (c<<62)|(p);
					end else begin
						let p = fromMaybe(?, inPacketBuffer1);
						Bit#(558) c = zeroExtend(curData);
						inPacketBuffer2 <= (c<<62)|(p);
						inPacketBufferCnt <= inPacketBufferCnt + 1;
					end
				end else begin
					inPacketBuffer1 <= tagged Valid zeroExtend(curData);
				end
			end
		end
	endrule

 	SyncFIFOIfc#(AuroraIfcType) inPacketQ <- mkSyncFIFOToCC(32, uclk, urst);
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
	   		$display( "(%t) AuroraExtImport \t\tread %x %d", $time, d, i );
		endrule
		rule w0 if ( bdpiSendAvailable(nodeIdx, fromInteger(i)));
			let d = writeQ[i].first;
			if ( bdpiWrite(nodeIdx, fromInteger(i), d) ) begin
		  		$display( "(%t) AuroraExtImport \t\twrite %x %d", $time, d, i );
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
		    			$display("aurora.send port %d data %d", i, data);
		    			writeQ[i].enq(data);
		 		endmethod
		 		method ActionValue#(Bit#(64)) receive;
		    			let data = mirrorQ[i].first;
		    			mirrorQ[i].deq;
		    			$display("aurora.receive port %d data %h", i, data);
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
endmodule
endpackage: AuroraExtImportCommon
