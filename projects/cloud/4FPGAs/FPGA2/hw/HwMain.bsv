// This HwMain is for only FPGA2
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

Integer privKeyFPGA2 = 2;

module mkHwMain#(PcieUserIfc pcie, DRAMUserIfc dram, Vector#(2, AuroraExtIfc) auroraQuads) (HwMainIfc);

	Clock curClk <- exposeCurrentClock;
	Reset curRst <- exposeCurrentReset;

	Clock pcieclk = pcie.user_clk;
	Reset pcierst = pcie.user_rst;	

	//--------------------------------------------------------------------------------------------
	// Host -> FPGA1_1(0) -> (4)FPGA2_1(5) -> (1)FPGA1_2(2) -> (6)FPGA2_2(7) -> (3)FPGA1_3
	//--------------------------------------------------------------------------------------------
	FIFOF#(AuroraIfcType) recvPacketByAuroraFPGA2Q <- mkFIFOF;
	FIFOF#(Tuple4#(Bit#(1), Bit#(2), Bit#(24), AuroraIfcType)) sendPacketByAuroraFPGA2Q <- mkFIFOF;
	rule fpga2_1;
		Bit#(8) inPortFPGA2_1 = 4;
		Bit#(1) qidIn = inPortFPGA2_1[2];
		Bit#(2) pidIn = truncate(inPortFPGA2_1);

		let recvPacket <- auroraQuads[qidIn].user[pidIn].receive;
		recvPacketByAuroraFPGA2Q.enq(recvPacket);
	endrule
	rule fpga2_2;
		Bit#(8) inPortFPGA2_2 = 6;
		Bit#(1) qidIn = inPortFPGA2_2[2];
		Bit#(2) pidIn = truncate(inPortFPGA2_2);

		let recvPacket <- auroraQuads[qidIn].user[pidIn].receive;
		recvPacketByAuroraFPGA2Q.enq(recvPacket);	
	endrule
	rule sendPacketFPGA2( recvPacketByAuroraFPGA2Q.notEmpty );
		recvPacketByAuroraFPGA2Q.deq;
		let recvPacket = recvPacketByAuroraFPGA2Q.first;
		Bit#(32) headerPart = recvPacket[31:0] ^ fromInteger(privKeyFPGA2);
		Bit#(8) numHops = headerPart[7:0];
		Bit#(24) packetHeader = headerPart[31:8];

		if ( numHops != 0 ) begin
			Bit#(8) outPortFPGA2 = recvPacket[39:32] ^ fromInteger(privKeyFPGA2);
			Bit#(1) qidOut = outPortFPGA2[2];
			Bit#(2) pidOut = truncate(outPortFPGA2);	

			Bit#(8) newNumHops = numHops - 1;
			Bit#(32) newHeaderPart = (zeroExtend(packetHeader) << 8) | zeroExtend(newNumHops);
			Bit#(32) encNewHeaderPartTmp = newHeaderPart ^ fromInteger(pubKeyFPGA1);
			AuroraIfcType encNewHeaderPart = zeroExtend(encNewHeaderPartTmp);

			AuroraIfcType remainingPacket = recvPacket >> 40;
			AuroraIfcType newPacket = (remainingPacket << 32) | encNewHeaderPart;

			sendPacketByAuroraFPGA2Q.enq(tuple4(qidOut, pidOut, packetHeader, newPacket));
		end else begin
			// FPGA2 is final destination
			if ( packetHeader[0] == 0 ) begin
				AuroraIfcType remainedPacket = recvPacket >> 32;
				
				Bit#(32) aomNheader = remainedPacket[31:0] ^ fromInteger(privKeyFPGA2);
				Bit#(32) address = remainedPacket[63:32] ^ fromInteger(privKeyFPGA2);

				if ( aomNheader[0] == 0 ) begin
					// Write
				end else begin
					// Read
				end
			end
		end
	endrule
	rule relayPacketFPGA2;
		if ( sendPacketByAuroraFPGA2Q.notEmpty ) begin
			Bit#(8) auroraExtCntFPGA2 = 0;
			sendPacketByAuroraFPGA2Q.deq;
			let qidOut = tpl_1(sendPacketByAuroraFPGA2Q.first);
			let pidOut = tpl_2(sendPacketByAuroraFPGA2Q.first);
			let packetHeader = tpl_3(sendPacketByAuroraFPGA2Q.first);
			let payload = tpl_4(sendPacketByAuroraFPGA2Q.first);

			let routeCnt = packetHeader[7:1];
			let payloadByte = packetHeader[23:16];

			if ( (routeCnt > 0) && (routeCnt < 3) ) begin
				Bit#(8) totalByte = 4+2+payloadByte;
				Bit#(16) totalBits = zeroExtend(totalByte) * 8;
				Bit#(16) decidedCycle = cycleDecider(totalBits);
				auroraExtCntFPGA2 = truncate(decidedCycle);
			end else if ( (routeCnt > 2) && (routeCnt < 5) ) begin
				Bit#(8) totalByte = 4+4+payloadByte;
				Bit#(16) totalBits = zeroExtend(totalByte) * 8;
				Bit#(16) decidedCycle = cycleDecider(totalBits);
				auroraExtCntFPGA2 = truncate(decidedCycle);
			end else if ( (routeCnt > 4) && (routeCnt < 9) ) begin
				Bit#(8) totalByte = 4+8+payloadByte;
				Bit#(16) totalBits = zeroExtend(totalByte) * 8;
				Bit#(16) decidedCycle = cycleDecider(totalBits);
				auroraExtCntFPGA2 = truncate(decidedCycle);
			end

			auroraQuads[qidOut].user[pidOut].send(AuroraSend{packet:payload,num:auroraExtCntFPGA2});
		end
	endrule
endmodule
