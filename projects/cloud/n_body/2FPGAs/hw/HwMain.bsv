import FIFO::*;
import FIFOF::*;
import Clocks::*;
import Vector::*;
import Real::*;

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

Integer idxFPGA1 = 0;
Integer idxFPGA2 = 1;

Integer pubKeyFPGA1 = 1;
Integer pubKeyFPGA2 = 2;

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
	FIFOF#(AuroraIfcType) sendPacketByAuroraFPGA1Q <- mkFIFOF;
	Reg#(Bool) openConnect <- mkReg(False);
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
				// Header Part
				Bit#(8) payloadByte = 8;
				Bit#(8) startPoint = fromInteger(idxFPGA1);
				Bit#(8) routeCnt = 0;
				Bit#(1) sdFlag = 0;
				Bit#(8) numHops = 0;
				Bit#(32) headerPartSR = (zeroExtend(payloadByte) << 24) | (zeroExtend(startPoint) << 16) | 
							(zeroExtend(routeCnt) << 9) | (zeroExtend(sdFlag) << 8) | 
							(zeroExtend(numHops));

				// Encryption
				// Payload
				Bit#(32) encAddress = address ^ fromInteger(pubKeyFPGA2);
				Bit#(32) encAomNheader = aomNheader ^ fromInteger(pubKeyFPGA2);
				// Header Part
				Bit#(32) encHeaderPartSR = headerPartSR ^ fromInteger(pubKeyFPGA2);

				// Final
				AuroraIfcType srPacket = (zeroExtend(encAddress) << 64) | (zeroExtend(encAomNheader) << 32) | (zeroExtend(encHeaderPartSR));
				sendPacketByAuroraFPGA1Q.enq(srPacket);
				openConnect <= True;
			end else if ( d == 1 )  begin // Data Sending 
				// Payload 
				Bit#(64) data = 4294967296;
				// Header Part
				Bit#(8) payloadByte = 8;
				Bit#(8) startPoint = fromInteger(idxFPGA1);
				Bit#(8) routeCnt = 0;
				Bit#(1) sdFlag = 1;
				Bit#(8) numHops = 0;
				Bit#(32) headerPartDS = (zeroExtend(payloadByte) << 24) | (zeroExtend(startPoint) << 16) | 
							(zeroExtend(routeCnt) << 9) | (zeroExtend(sdFlag) << 8) | 
							(zeroExtend(numHops));
				// Encryption
				// Payload
				Bit#(64) encData = data ^ fromInteger(pubKeyFPGA2);
				// Header Part
				Bit#(32) encHeaderPartDS = headerPartDS ^ fromInteger(pubKeyFPGA2);

				// Final
				AuroraIfcType dsPacket = (zeroExtend(encData) << 32) | (zeroExtend(encHeaderPartDS));
				sendPacketByAuroraFPGA1Q.enq(dsPacket);
			end
		end
	endrule
	//--------------------------------------------------------------------------------------------
	// FPGA1(0) <-> (4)FPGA2
	// FPGA1(1) <-> (5)FPGA2
	// FPGA1(2) <-> (6)FPGA2
	// FPGA1(3) <-> (7)FPGA2
	//--------------------------------------------------------------------------------------------
	// FPGA1
	//--------------------------------------------------------------------------------------------
	FIFOF#(AuroraIfcType) recvPacketByAuroraFPGA1Q <- mkFIFOF;
	FIFOF#(AuroraIfcType) validCheckConnectionFPGA1Q <- mkFIFOF;
	rule fpga1Sender_Port0( openConnect && sendPacketByAuroraFPGA1Q.notEmpty );
		sendPacketByAuroraFPGA1Q.deq;
		let sendPacket = sendPacketByAuroraFPGA1Q.first;

		for ( Integer i = 0; i < 4; i = i + 1 )
			auroraQuads[0].user[i].send(AuroraSend{packet:sendPacket,num:2});
	endrule
	rule fpga1Receiver_Port0( openConnect );
		Bit#(8) inPortFPGA1_1 = 0;
		Bit#(1) qidIn = inPortFPGA1_1[2];
		Bit#(2) pidIn = truncate(inPortFPGA1_1);

		let recvPacket <- auroraQuads[qidIn].user[pidIn].receive;
		recvPacketByAuroraFPGA1Q.enq(recvPacket);
	endrule
	rule fpga1Decrypter( openConnect );
		Integer privKeyFPGA1 = 1;

		recvPacketByAuroraFPGA1Q.deq;
		let recvPacket = recvPacketByAuroraFPGA1Q.first;

		Bit#(32) headerPart = recvPacket[31:0] ^ fromInteger(privKeyFPGA1);
		Bit#(8) numHops = headerPart[7:0];
		Bit#(24) packetHeader = headerPart[31:8];
		Bit#(8) routeCnt = zeroExtend(packetHeader[7:1]);
		Bit#(8) payloadByte = packetHeader[23:16];

		AuroraIfcType payload = recvPacket >> 32;
		if ( packetHeader[0] == 0 ) begin // Source Routing
			Bit#(32) aomNheader = payload[31:0] ^ fromInteger(privKeyFPGA1);
			Bit#(32) address = payload[63:32] ^ fromInteger(privKeyFPGA1); 

			if ( aomNheader[0] == 0 ) begin // Write
				if ( aomNheader[31:1] == 4*1024 ) begin
					validCheckConnectionFPGA1Q.enq(1);
				end else begin
					validCheckConnectionFPGA1Q.enq(0);
				end		
			end	
		end else if ( packetHeader[0] == 1 ) begin // Data Sending
			Bit#(64) data = payload[63:0] ^ fromInteger(privKeyFPGA1);

			if ( data == 4294967296 ) begin
				validCheckConnectionFPGA1Q.enq(1);
			end else begin
				validCheckConnectionFPGA1Q.enq(0);
			end
		end
	endrule
	//--------------------------------------------------------------------------------------------
	// FPGA2
	//--------------------------------------------------------------------------------------------
	Vector#(4, FIFOF#(AuroraIfcType)) recvPacketByAuroraFPGA2Q <- replicateM( mkFIFOF );
	FIFOF#(AuroraIfcType) validCheckConnectionFPGA2Q <- mkFIFOF;
	rule fpga2Receiver_Port4( !openConnect );
		Bit#(8) inPortFPGA2_1 = 4;
		Bit#(1) qidIn = inPortFPGA2_1[2];
		Bit#(2) pidIn = truncate(inPortFPGA2_1);

		for ( Integer i = 0; i < 4; i = i + 1 ) begin
			let recvPacket <- auroraQuads[1].user[i].receive;
			recvPacketByAuroraFPGA2Q[i].enq(recvPacket);
		end
	endrule
	rule fpga2Decrypter( !openConnect );
		Integer privKeyFPGA2 = 2;

		recvPacketByAuroraFPGA2Q[0].deq;
		let recvPacket = recvPacketByAuroraFPGA2Q[0].first;

		Bit#(32) headerPart = recvPacket[31:0] ^ fromInteger(privKeyFPGA2);
		Bit#(8) numHops = headerPart[7:0];
		Bit#(24) packetHeader = headerPart[31:8];
		Bit#(8) routeCnt = zeroExtend(packetHeader[7:1]);
		Bit#(8) payloadByte = packetHeader[23:16];

		AuroraIfcType payload = recvPacket >> 32;
		if ( packetHeader[0] == 0 ) begin // Source Routing
			Bit#(32) aomNheader = payload[31:0] ^ fromInteger(privKeyFPGA2);
			Bit#(32) address = payload[63:32] ^ fromInteger(privKeyFPGA2); 

			if ( aomNheader[0] == 0 ) begin // Write
				if ( aomNheader[31:1] == 4*1024 ) begin
					validCheckConnectionFPGA2Q.enq(1);
				end else begin
					validCheckConnectionFPGA2Q.enq(0);
				end			
			end
		end else if ( packetHeader[0] == 1 ) begin // Data Sending
			Bit#(64) data = payload[63:0] ^ fromInteger(privKeyFPGA2);

			if ( data == 4294967296 ) begin
				validCheckConnectionFPGA2Q.enq(1);
			end else begin
				validCheckConnectionFPGA2Q.enq(0);
			end
		end
	endrule
	//--------------------------------------------------------------------------------------------
	// Send the packets to the host
	//--------------------------------------------------------------------------------------------
	FIFOF#(Bit#(32)) validCheckConnectionQ <- mkFIFOF;
	rule validCheckerFPGA1( openConnect );
		Bit#(8) validCheckPort = 1;
		Bit#(1) qidIn = validCheckPort[2];
		Bit#(2) pidIn = truncate(validCheckPort);

		let recvPacket <- auroraQuads[qidIn].user[pidIn].receive;

		if ( recvPacket == 1 ) begin
			validCheckConnectionQ.enq(1);
		end else if ( recvPacket == 0 ) begin
			validCheckConnectionQ.enq(0);
		end
	endrule
	rule validCheckerFPGA2( !openConnect );
		Bit#(8) validCheckPort = 5;
		Bit#(1) qidOut = validCheckPort[2];
		Bit#(2) pidOut = truncate(validCheckPort);

		validCheckConnectionFPGA2Q.deq;
		let sendPacket = validCheckConnectionFPGA2Q.first;

		auroraQuads[qidOut].user[pidOut].send(AuroraSend{packet:sendPacket,num:2});
	endrule
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
