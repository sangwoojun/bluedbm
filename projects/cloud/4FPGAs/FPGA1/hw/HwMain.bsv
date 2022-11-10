// This HwMain is for only FPGA1
import FIFO::*;
import FIFOF::*;
import Clocks::*;
import Vector::*;

import Serializer::*;

import BRAM::*;
import BRAMFIFO::*;

import PcieCtrl::*;
import DRAMController::*;

import AuroraCommon::*;
import AuroraExtImportCommon::*;
import AuroraExtImport117::*;
import AuroraExtImport119::*;

interface HwMainIfc;
endinterface

Integer pubKeyFPGA1 = 1;
Integer pubKeyFPGA2 = 2;
Integer pubKeyHost = 3;

Integer privKeyFPGA1 = 1;

module mkHwMain#(PcieUserIfc pcie, DRAMUserIfc dram, Vector#(2, AuroraExtIfc) auroraQuads) (HwMainIfc);

	Clock curClk <- exposeCurrentClock;
	Reset curRst <- exposeCurrentReset;

	Clock pcieclk = pcie.user_clk;
	Reset pcierst = pcie.user_rst;	

	//--------------------------------------------------------------------------------------
	// Pcie Read and Write
	//--------------------------------------------------------------------------------------
	SyncFIFOIfc#(Tuple2#(IOReadReq, Bit#(32))) pcieRespQ <- mkSyncFIFOFromCC(16, pcieclk);
	SyncFIFOIfc#(IOReadReq) pcieReadReqQ <- mkSyncFIFOToCC(16, pcieclk, pcierst);
	SyncFIFOIfc#(IOWrite) pcieWriteQ <- mkSyncFIFOToCC(16, pcieclk, pcierst);
	
	rule getReadReq;
		let r <- pcie.dataReq;
		pcieReadReqQ.enq(r);
	endrule
	rule returnReadResp;
		let r_ = pcieRespQ.first;
		pcieRespQ.deq;

		pcie.dataSend(tpl_1(r_), tpl_2(r_));
	endrule
	rule getWriteReq;
		let w <- pcie.dataReceive;
		pcieWriteQ.enq(w);
	endrule
	//--------------------------------------------------------------------------------------
	// Debug lane and channel
	//--------------------------------------------------------------------------------------
	Reg#(Bit#(8)) debuggingBitsC <- mkReg(0);
	Reg#(Bit#(8)) debuggingBitsL <- mkReg(0);
	Reg#(Bit#(8)) debuggingCnt <- mkReg(0);

	rule debugChannelLane;
		debuggingBitsC <= {
			auroraQuads[1].user[3].channel_up,
			auroraQuads[1].user[2].channel_up,
			auroraQuads[1].user[1].channel_up,
			auroraQuads[1].user[0].channel_up,
			auroraQuads[0].user[3].channel_up,
			auroraQuads[0].user[2].channel_up,
			auroraQuads[0].user[1].channel_up,
			auroraQuads[0].user[0].channel_up
		};

		debuggingBitsL <= {
			auroraQuads[1].user[3].lane_up,
			auroraQuads[1].user[2].lane_up,
			auroraQuads[1].user[1].lane_up,
			auroraQuads[1].user[0].lane_up,
			auroraQuads[0].user[3].lane_up,
			auroraQuads[0].user[2].lane_up,
			auroraQuads[0].user[1].lane_up,
			auroraQuads[0].user[0].lane_up
		};
	endrule
	//--------------------------------------------------------------------------------------------
	// Get Commands from Host via PCIe
	//--------------------------------------------------------------------------------------------
	FIFOF#(AuroraIfcType) recvPacketQ <- mkFIFOF;
	Reg#(Maybe#(AuroraIfcType)) recvPacketBuffer1 <- mkReg(tagged Invalid);
	Reg#(Maybe#(AuroraIfcType)) recvPacketBuffer2 <- mkReg(tagged Invalid);
	Reg#(Maybe#(AuroraIfcType)) recvPacketBuffer3 <- mkReg(tagged Invalid);
	rule getCmd;
		pcieWriteQ.deq;
		let w = pcieWriteQ.first;

		let d = w.data;
		let a = w.addr;

		if ( a == 0 ) begin
			if ( isValid(recvPacketBuffer1) ) begin
				if ( isValid(recvPacketBuffer2) ) begin
					if ( isValid(recvPacketBuffer3) ) begin
						let prevPacket = fromMaybe(?, recvPacketBuffer3);
						AuroraIfcType extendCurr = zeroExtend(d);
						AuroraIfcType recvPacket = (extendCurr << 96) | prevPacket;
						recvPacketQ.enq(recvPacket);

						recvPacketBuffer1 <= tagged Invalid;
						recvPacketBuffer2 <= tagged Invalid;
						recvPacketBuffer3 <= tagged Invalid;
						// Address 32-bit
					end else begin
						let prevPacket = fromMaybe(?, recvPacketBuffer2);
						AuroraIfcType extendCurr = zeroExtend(d);
						AuroraIfcType recvPacket = (extendCurr << 64) | prevPacket;
						recvPacketBuffer3 <= tagged Valid recvPacket;
						// RW Header + Amount of Memory 32-bit
					end
				end else begin
					let prevPacket = fromMaybe(?, recvPacketBuffer1);
					AuroraIfcType extendCurr = zeroExtend(d);
					AuroraIfcType recvPacket = (extendCurr << 32) | prevPacket;
					recvPacketBuffer2 <= tagged Valid recvPacket;
					// Actual Route 32-bit
				end
			end else begin
				recvPacketBuffer1 <= tagged Valid zeroExtend(d); 
				// # of Hops Packet Header (Header Part) 32-bit
			end
		end
	endrule
	//--------------------------------------------------------------------------------------------
	// Host -> FPGA1_1(0) -> (4)FPGA2_1(5) -> (1)FPGA1_2(2) -> (6)FPGA2_2(7) -> (3)FPGA1_3
	//--------------------------------------------------------------------------------------------
	FIFOF#(AuroraIfcType) recvPacketByAuroraFPGA1Q <- mkFIFOF;
	FIFOF#(Bit#(32)) validCheckConnectionQ <- mkFIFOF;
	rule fpga1_1( recvPacketQ.notEmpty );
		recvPacketQ.deq;
		let recvPacket = recvPacketQ.first;
		recvPacketByAuroraFPGA1Q.enq(recvPacket);
	endrule
	rule fpga1_2;
		Bit#(8) inPortFPGA1_2 = 1;
		Bit#(1) qidIn = inPortFPGA1_2[2];
		Bit#(2) pidIn = truncate(inPortFPGA1_2);

		let recvPacket <- auroraQuads[qidIn].user[pidIn].receive;
		recvPacketByAuroraFPGA1Q.enq(recvPacket);
	endrule
	rule fpga1_3;
		Bit#(8) inPortFPGA1_3 = 3;
		Bit#(1) qidIn = inPortFPGA1_3[2];
		Bit#(2) pidIn = truncate(inPortFPGA1_3);

		let recvPacket <- auroraQuads[qidIn].user[pidIn].receive;
		recvPacketByAuroraFPGA1Q.enq(recvPacket);
	endrule
	rule sendPacketFPGA1( recvPacketByAuroraFPGA1Q.notEmpty );
		recvPacketByAuroraFPGA1Q.deq;
		let recvPacket = recvPacketByAuroraFPGA1Q.first;

		Bit#(32) headerPart = recvPacket[31:0] ^ fromInteger(privKeyFPGA1);
		Bit#(8) numHops = headerPart[7:0];
		Bit#(24) packetHeader = headerPart[31:8];
		Bit#(8) routeCnt = zeroExtend(packetHeader[7:1]);
		Bit#(8) payloadByte = packetHeader[23:16];
	
		if ( numHops != 0 ) begin
			Bit#(8) outPortFPGA1 = recvPacket[39:32] ^ fromInteger(privKeyFPGA1);
			Bit#(1) qidOut = outPortFPGA1[2];
			Bit#(2) pidOut = truncate(outPortFPGA1);	

			Bit#(8) newNumHops = numHops - 1;
			Bit#(32) newHeaderPart = (zeroExtend(packetHeader) << 8) | zeroExtend(newNumHops);
			Bit#(32) encNewHeaderPartTmp = newHeaderPart ^ fromInteger(pubKeyFPGA2);
			AuroraIfcType encNewHeaderPart = zeroExtend(encNewHeaderPartTmp);

			AuroraIfcType remainingPacket = recvPacket >> 40;
			AuroraIfcType newPacket = (remainingPacket << 32) | encNewHeaderPart;

			Bit#(8) auroraExtCntFPGA1 = 0;
			if ( (routeCnt > 0) && (routeCnt < 3) ) begin
				Bit#(8) totalByte = 4+2+payloadByte;
				Bit#(16) totalBits = zeroExtend(totalByte) * 8;
				Bit#(16) decidedCycle = cycleDecider(totalBits);
				auroraExtCntFPGA1 = truncate(decidedCycle);
			end else if ( (routeCnt > 2) && (routeCnt < 5) ) begin
				Bit#(8) totalByte = 4+4+payloadByte;
				Bit#(16) totalBits = zeroExtend(totalByte) * 8;
				Bit#(16) decidedCycle = cycleDecider(totalBits);
				auroraExtCntFPGA1 = truncate(decidedCycle);
			end else if ( (routeCnt > 4) && (routeCnt < 9) ) begin
				Bit#(8) totalByte = 4+8+payloadByte;
				Bit#(16) totalBits = zeroExtend(totalByte) * 8;
				Bit#(16) decidedCycle = cycleDecider(totalBits);
				auroraExtCntFPGA1 = truncate(decidedCycle);
			end

			auroraQuads[qidOut].user[pidOut].send(AuroraSend{packet:newPacket,num:auroraExtCntFPGA1});	
		end else begin
			// Host wants to use FPGA1's memory
			AuroraIfcType bodyPart = recvPacket >> 32;
			AuroraIfcType payload = bodyPart;
			if ( packetHeader[0] == 0 ) begin // Source Routing
				Bit#(32) aomNheader = payload[31:0] ^ fromInteger(privKeyFPGA1);
				Bit#(32) address = payload[63:32] ^ fromInteger(privKeyFPGA1); 
				
				if ( aomNheader[0] == 0 ) begin // Write
					if ( aomNheader[31:1] == 4*1024 ) begin
						validCheckConnectionQ.enq(1);
					end else begin
						validCheckConnectionQ.enq(0);
					end			
				end
			end else begin
				Bit#(32) data_1 = payload[31:0] ^ fromInteger(privKeyFPGA1);
				Bit#(32) data_2 = payload[63:32] ^ fromInteger(privKeyFPGA1);
				Bit#(64) data = (zeroExtend(data_2) << 32) | zeroExtend(data_1);

				if ( data == 4294967296 ) begin
					validCheckConnectionQ.enq(1);
				end else begin
					validCheckConnectionQ.enq(0);
				end
			end
		end
	endrule
	//--------------------------------------------------------------------------------------------
	// Send Routing Packet to Host
	//--------------------------------------------------------------------------------------------
	rule getAuroraStatus;
		pcieReadReqQ.deq;
		let r = pcieReadReqQ.first;
		Bit#(4) a = truncate(r.addr>>2);
		if ( a < 8 ) begin
			if ( validCheckConnectionQ.notEmpty ) begin
				pcieRespQ.enq(tuple2(r, validCheckConnectionQ.first));
				validCheckConnectionQ.deq;
			end else begin 
				pcieRespQ.enq(tuple2(r, 32'hffffffff));
			end
		end else begin
			if ( a == 8 ) begin
				if ( debuggingCnt < 7 ) begin
					debuggingCnt <= debuggingCnt + 1;
				end else begin
					debuggingCnt <= 0;
				end
				pcieRespQ.enq(tuple2(r, zeroExtend(debuggingBitsC[debuggingCnt])));
			end else if ( a == 9 ) begin
				if ( debuggingCnt < 7 ) begin
					debuggingCnt <= debuggingCnt + 1;
				end else begin
					debuggingCnt <= 0;
				end
				pcieRespQ.enq(tuple2(r, zeroExtend(debuggingBitsL[debuggingCnt])));
			end
		end
	endrule
endmodule
