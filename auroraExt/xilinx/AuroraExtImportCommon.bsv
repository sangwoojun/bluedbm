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

typedef struct {
	Bit#(512) packet;
	Bit#(8) num;
} AuroraSend deriving (Bits, Eq);

typedef 4 AuroraExtPerQuad;


typedef 64 AuroraPhysWidth;
typedef TSub#(AuroraPhysWidth, 2) BodySz;
typedef TMul#(AuroraPhysWidth, 8) AuroraIfcWidth;
typedef Bit#(AuroraIfcWidth) AuroraIfcType; // 512-bit = 64-Byte


interface AuroraExtIfc;
	interface Vector#(AuroraExtPerQuad, Aurora_Pins#(1)) aurora;
	interface Vector#(AuroraExtPerQuad, AuroraExtUserIfc) user;
endinterface

interface AuroraExtUserIfc;
	method Action send(AuroraSend data);
	method ActionValue#(AuroraIfcType) receive;

	method Bit#(1) lane_up;
	method Bit#(1) channel_up;
endinterface

function Bit#(16) cycleDecider(Bit#(16) totalBits);
        Bit#(16) decidedCycle = 0;
        if ( (totalBits > 0) && (totalBits <= 64)) begin
                decidedCycle = 1;
        end else if ( (totalBits > 64) && (totalBits <= 128) ) begin
                decidedCycle = 2;
        end else if ( (totalBits > 128) && (totalBits <= 192) ) begin
                decidedCycle = 3;
        end else if ( (totalBits > 192) && (totalBits <= 256) ) begin
                decidedCycle = 4;
        end else if ( (totalBits > 256) && (totalBits <= 320) ) begin
                decidedCycle = 5;
        end else if ( (totalBits > 320) && (totalBits <= 384) ) begin
                decidedCycle = 6;
        end else if ( (totalBits > 384) && (totalBits <= 448) ) begin
                decidedCycle = 7;
        end else if ( (totalBits > 448) && (totalBits <= 512) ) begin
                decidedCycle = 8;
        end
        return decidedCycle;
endfunction

module mkAuroraExtFlowControl#(AuroraControllerIfc#(AuroraPhysWidth) user, Clock uclk, Reset urst, Integer idx) (AuroraExtUserIfc);
	Integer recvQDepth = 1024;
	Integer windowSize = 512;

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
	
	SyncFIFOIfc#(AuroraSend) outPacketQ <- mkSyncFIFOFromCC(32, uclk);
	Reg#(Maybe#(Bit#(450))) outPacketBuffer1st <- mkReg(tagged Invalid, clocked_by uclk, reset_by urst); // 512-62=450
	Reg#(Bit#(388)) outPacketBuffer2nd <- mkReg(0, clocked_by uclk, reset_by urst); //450-62=388
	Reg#(Bit#(1)) outPacketBufferCnt <- mkReg(0, clocked_by uclk, reset_by urst);
	Reg#(Bit#(8)) sendPacketCnt <- mkReg(0, clocked_by uclk, reset_by urst);
	Reg#(Bit#(8)) numPacket <- mkReg(0, clocked_by uclk, reset_by urst);
	rule serOutPacket;
		if ( isValid(outPacketBuffer1st) ) begin
			if ( outPacketBufferCnt == 0 ) begin
				let p = fromMaybe(?, outPacketBuffer1st);
				outPacketBuffer2nd <= truncate(p >> valueof(BodySz));
				outPacketBufferCnt <= outPacketBufferCnt + 1;
				sendPacketCnt <= sendPacketCnt + 1;
				sendQ.enq({p[61:0], 2'b00});
			end else begin
				if ( sendPacketCnt == numPacket ) begin
					let p = outPacketBuffer2nd;
					sendQ.enq({p[61:0], 2'b10});
				
					outPacketBuffer1st <= tagged Invalid;
					outPacketBufferCnt <= 0;
					sendPacketCnt <= 0;
					numPacket <= 0;
				end else begin
					let p = outPacketBuffer2nd;
					outPacketBuffer2nd <= (p >> valueof(BodySz));
					sendPacketCnt <= sendPacketCnt + 1;
					sendQ.enq({p[61:0], 2'b00});
				end
			end
		end else begin
			outPacketQ.deq;
			let d = outPacketQ.first;
			let p = d.packet;
			let n = d.num;

			outPacketBuffer1st <= tagged Valid truncate(p>>valueof(BodySz));
			sendPacketCnt <= sendPacketCnt + 1;
			numPacket <= n;
			sendQ.enq({truncate(p), 2'b00});
		end
	endrule

	FIFO#(AuroraIfcType) recvQ <- mkSizedBRAMFIFO(recvQDepth, clocked_by uclk, reset_by urst);
	Reg#(Maybe#(Bit#(496))) inPacketBuffer1st <- mkReg(tagged Invalid, clocked_by uclk, reset_by urst);
	Reg#(Bit#(496)) inPacketBuffer2nd <- mkReg(0, clocked_by uclk, reset_by urst);
	Reg#(Bit#(1)) inPacketBufferCnt <- mkReg(0, clocked_by uclk, reset_by urst);
	Reg#(Bit#(8)) recvPacketCnt <- mkReg(0, clocked_by uclk, reset_by urst);
	rule recvPacket( user.lane_up != 0 && user.channel_up != 0 );
		let d <- user.receive;
		Bit#(1) control = d[0];
		Bit#(1) header = d[1];
		Bit#(BodySz) curData = truncate(d>>2);

		if ( control == 1 ) begin
			curSendBudgetUp <= curSendBudgetUp + truncate(curData);
		end else begin 
			if ( header == 1 ) begin
				let pasData = inPacketBuffer2nd;
				AuroraIfcType p = zeroExtend(pasData);
				AuroraIfcType c = zeroExtend(curData);	

				if ( recvPacketCnt == 2 ) begin
					AuroraIfcType finalData = (c << 124) | p;
					recvQ.enq(zeroExtend(finalData));
				end else if ( recvPacketCnt == 3 ) begin
					AuroraIfcType finalData = (c << 186) | p;
					recvQ.enq(zeroExtend(finalData));
				end else if ( recvPacketCnt == 4 ) begin
					AuroraIfcType finalData = (c << 248) | p;
					recvQ.enq(zeroExtend(finalData));
				end else if ( recvPacketCnt == 5 ) begin
					AuroraIfcType finalData = (c << 310) | p;
					recvQ.enq(zeroExtend(finalData));
				end else if ( recvPacketCnt == 6 ) begin
					AuroraIfcType finalData = (c << 372) | p;
					recvQ.enq(zeroExtend(finalData));
				end else if ( recvPacketCnt == 7 ) begin
					AuroraIfcType finalData = (c << 434) | p;
					recvQ.enq(zeroExtend(finalData));
				end else if ( recvPacketCnt == 8 ) begin
					AuroraIfcType finalData = (c << 496) | p;
					recvQ.enq(zeroExtend(finalData));
				end
				
				curInQUp <= curInQUp + 1;
				maxInFlightDown <= maxInFlightDown + 1;

				inPacketBufferCnt <= 0;
				inPacketBuffer1st <= tagged Invalid;
				inPacketBuffer2nd <= 0;

				recvPacketCnt <= 0;
			end else begin
				if ( isValid(inPacketBuffer1st) ) begin
					if ( inPacketBufferCnt == 0 ) begin
						let p = fromMaybe(?, inPacketBuffer1st);
						Bit#(496) c = zeroExtend(curData);
						inPacketBuffer2nd <= (c << 62) | p; // Second
						inPacketBufferCnt <= inPacketBufferCnt + 1;
					end else begin
						let p = inPacketBuffer2nd;
						Bit#(496) c = zeroExtend(curData);
						inPacketBuffer2nd <= (c << 62) | p; // Third
					end
				end else begin
					inPacketBuffer1st <= tagged Valid zeroExtend(curData); // First
				end
				recvPacketCnt <= recvPacketCnt + 1;
			end
		end
	endrule

 	SyncFIFOIfc#(AuroraIfcType) inPacketQ <- mkSyncFIFOToCC(32, uclk, urst);
	rule desInPacket;
		curInQDown <= curInQDown + 1;
		recvQ.deq;
		inPacketQ.enq(recvQ.first);
	endrule

	method Action send(AuroraSend data);
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
