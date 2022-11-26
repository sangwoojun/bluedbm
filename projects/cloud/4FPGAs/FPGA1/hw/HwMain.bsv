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

Integer idxFPGA1_1 = 0;
Integer idxFPGA1_2 = 1;
Integer idxFPGA2_1 = 2;
Integer idxFPGA2_2 = 3;

Integer pubKeyFPGA1 = 1;
Integer pubKeyFPGA2 = 2;

Integer privKeyFPGA1 = 1;

function Bit#(8) cycleDeciderExt(Bit#(8) routeCnt, Bit#(8) payloadByte);
	Bit#(8) auroraExtCnt = 0;
	if ( routeCnt == 0 ) begin
		Bit#(8) totalByte = 4+payloadByte;
		Bit#(16) totalBits = zeroExtend(totalByte) * 8;
		Bit#(16) decidedCycle = cycleDecider(totalBits);
		auroraExtCnt = truncate(decidedCycle);
	end else begin
		Bit#(8) totalByte = 4+2+payloadByte;
		Bit#(16) totalBits = zeroExtend(totalByte) * 8;
		Bit#(16) decidedCycle = cycleDecider(totalBits);
		auroraExtCnt = truncate(decidedCycle);
	end
	return auroraExtCnt;
endfunction

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
	//--------------------------------------------------------------------------------------------
	// Get Commands from Host via PCIe
	//--------------------------------------------------------------------------------------------
	FIFOF#(Tuple3#(AuroraIfcType, Bit#(8), Bit#(8))) sendPacketByAuroraFPGA1Q <- mkFIFOF;
	FIFOF#(AuroraIfcType) recvPacketByAuroraFPGA1Q <- mkFIFOF;
	FIFOF#(Bit#(32)) validCheckConnectionQ <- mkFIFOF;
	rule getCmd;
		pcieWriteQ.deq;
		let w = pcieWriteQ.first;

		let d = w.data;
		let a = w.addr;

		if ( a == 0 ) begin
			if ( d == 0 ) begin // Source Routing
				// Payload
				Bit#(32) address = 0;
				Bit#(32) aom = 4*1024;
				Bit#(1) header = 0; // 0: Write, 1: Read
				Bit#(32) aomNheader = (aom << 1) | zeroExtend(header);
				// Actual Route
				Bit#(8) outPortFPGA1_2 = 2;
				Bit#(8) outPortFPGA2_1 = 5;
				// Header Part
				Bit#(8) payloadByte = 8;
				Bit#(8) startPoint = fromInteger(idxFPGA1_1);
				Bit#(8) routeCnt = 2;
				Bit#(1) sdFlag = 0;
				Bit#(8) numHops = 2;
				Bit#(32) headerPartSR = (zeroExtend(payloadByte) << 24) | (zeroExtend(startPoint) << 16) | 
							(zeroExtend(routeCnt) << 9) | (zeroExtend(sdFlag) << 8) | 
							(zeroExtend(numHops));
				// Encryption
				// Payload
				Bit#(32) encAddress = address ^ fromInteger(pubKeyFPGA2);
				Bit#(32) encAomNheader = aomNheader ^ fromInteger(pubKeyFPGA2);
				// Actual Route
				Bit#(8) encOutPortFPGA1_2 = outPortFPGA1_2 ^ fromInteger(pubKeyFPGA1);
				Bit#(8) encOutPortFPGA2_1 = outPortFPGA2_1 ^ fromInteger(pubKeyFPGA2);
				Bit#(16) encActualRoute = (zeroExtend(encOutPortFPGA1_2) << 8) | (zeroExtend(encOutPortFPGA2_1));
				// Header Part
				Bit#(32) encHeaderPartSR = headerPartSR ^ fromInteger(pubKeyFPGA2);

				// Final
				AuroraIfcType srPacket = (zeroExtend(encAddress) << 80) | (zeroExtend(encAomNheader) << 48) | 
							 (zeroExtend(encActualRoute) << 32) | (zeroExtend(encHeaderPartSR));
				sendPacketByAuroraFPGA1Q.enq(tuple3(srPacket, routeCnt, payloadByte));
			end else if ( d == 1 )  begin // Data Sending 
				// Payload 
				Bit#(64) data = 4294967296;
				// Actual Route
				Bit#(8) outPortFPGA1_2 = 2;
				Bit#(8) outPortFPGA2_1 = 5;
				// Header Part
				Bit#(8) payloadByte = 8;
				Bit#(8) startPoint = fromInteger(idxFPGA1_1);
				Bit#(8) routeCnt = 2;
				Bit#(1) sdFlag = 1;
				Bit#(8) numHops = 2;
				Bit#(32) headerPartDS = (zeroExtend(payloadByte) << 24) | (zeroExtend(startPoint) << 16) | 
							(zeroExtend(routeCnt) << 9) | (zeroExtend(sdFlag) << 8) | 
							(zeroExtend(numHops));
				// Encryption
				// Payload
				Bit#(64) encData = data ^ fromInteger(pubKeyFPGA2);
				// Actual Route
				Bit#(8) encOutPortFPGA1_2 = outPortFPGA1_2 ^ fromInteger(pubKeyFPGA1);
				Bit#(8) encOutPortFPGA2_1 = outPortFPGA2_1 ^ fromInteger(pubKeyFPGA2);
				Bit#(16) encActualRoute = (zeroExtend(encOutPortFPGA1_2) << 8) | (zeroExtend(encOutPortFPGA2_1));
				// Header Part
				Bit#(32) encHeaderPartDS = headerPartDS ^ fromInteger(pubKeyFPGA2);

				// Final
				AuroraIfcType dsPacket = (zeroExtend(encData) << 48) | (zeroExtend(encActualRoute) << 32) | 
							 (zeroExtend(encHeaderPartDS));
				sendPacketByAuroraFPGA1Q.enq(tuple3(dsPacket, routeCnt, payloadByte));
			end
		end
	endrule
	//--------------------------------------------------------------------------------------------
	// FPGA1_1(0) -> (4)FPGA2_1(5) -> (1)FPGA1_2(2) -> (6)FPGA2_2(7) -> (3)ValidChecker
	//--------------------------------------------------------------------------------------------
	rule fpga1_1Sender( sendPacketByAuroraFPGA1Q.notEmpty );
		sendPacketByAuroraFPGA1Q.deq;
		let sendPacket = tpl_1(sendPacketByAuroraFPGA1Q.first);
		let routeCnt = tpl_2(sendPacketByAuroraFPGA1Q.first);
		let payloadByte = tpl_3(sendPacketByAuroraFPGA1Q.first);

		Bit#(8) auroraExtCntFPGA1 = cycleDeciderExt(routeCnt, payloadByte);

		auroraQuads[0].user[0].send(AuroraSend{packet:sendPacket,num:auroraExtCntFPGA1});	
	endrule
	rule fpga1_1Receiver;
		Bit#(8) inPortFPGA1_1 = 0;
		Bit#(1) qidIn = inPortFPGA1_1[2];
		Bit#(2) pidIn = truncate(inPortFPGA1_1);

		let recvPacket <- auroraQuads[qidIn].user[pidIn].receive;
		recvPacketByAuroraFPGA1Q.enq(recvPacket);
	endrule
	rule fpga1_2Receiver;
		Bit#(8) inPortFPGA1_2 = 1;
		Bit#(1) qidIn = inPortFPGA1_2[2];
		Bit#(2) pidIn = truncate(inPortFPGA1_2);

		let recvPacket <- auroraQuads[qidIn].user[pidIn].receive;
		recvPacketByAuroraFPGA1Q.enq(recvPacket);
	endrule
	rule fpga1_2and3Sender( recvPacketByAuroraFPGA1Q.notEmpty );
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

			Bit#(8) auroraExtCntFPGA1 = cycleDeciderExt(routeCnt, payloadByte);

			auroraQuads[qidOut].user[pidOut].send(AuroraSend{packet:newPacket,num:auroraExtCntFPGA1});	
		end else begin
			// Host wants to use FPGA1's memory
			Bit#(8) addTrunc = 0;
			if ( routeCnt == 1 ) begin
				addTrunc = 8;
			end else begin
				addTrunc = 0;
			end
			AuroraIfcType payload = recvPacket >> (32+addTrunc);
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
			end else if ( packetHeader[0] == 1 ) begin // Data Sending
				Bit#(64) data = payload[63:0] ^ fromInteger(privKeyFPGA1);

				if ( data == 4294967296 ) begin
					validCheckConnectionQ.enq(1);
				end else begin
					validCheckConnectionQ.enq(0);
				end
			end
		end
	endrule
	rule validChecker;
		Bit#(8) validCheckPort = 3;
		Bit#(1) qidIn = validCheckPort[2];
		Bit#(2) pidIn = truncate(validCheckPort);

		let recvPacket <- auroraQuads[qidIn].user[pidIn].receive;
		
		if ( recvPacket == 1 ) begin
			validCheckConnectionQ.enq(1);
		end else if ( recvPacket == 0 ) begin
			validCheckConnectionQ.enq(0);
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
		end
	endrule
endmodule
