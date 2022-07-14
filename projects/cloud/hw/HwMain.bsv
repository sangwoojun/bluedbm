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
	Reg#(Bool) openFirstConnect <- mkReg(False);
	Reg#(Bool) openSecndConnect <- mkReg(False);

	Reg#(Maybe#(Bit#(24))) recvPacketBuffer24 <- mkReg(tagged Invalid);
	Reg#(Maybe#(Bit#(40))) recvPacketBuffer40 <- mkReg(tagged Invalid);
	Reg#(Maybe#(Bit#(72))) recvPacketBuffer72 <- mkReg(tagged Invalid);
	rule getCmd;
		pcieWriteQ.deq;
		let w = pcieWriteQ.first;

		let d = w.data;
		let a = w.addr;

		if ( a == 0 ) begin // Open first connection (Host to FPGA1 to FPGA2)
			if ( isValid(recvPacketBuffer24) ) begin
				if ( isValid(recvPacketBuffer40) ) begin
					if ( isValid(recvPacketBuffer72) ) begin
						let prevPacket = fromMaybe(?, recvPacketBuffer72);
						AuroraIfcType extendPrev = zeroExtend(prevPacket);
						AuroraIfcType extendCurr = zeroExtend(d);
						AuroraIfcType recvPacket = (extendCurr << 72) | extendPrev;
						recvPacketQ.enq(recvPacket);

						recvPacketBuffer24 <= tagged Invalid;
						recvPacketBuffer40 <= tagged Invalid;
						recvPacketBuffer72 <= tagged Invalid;

						openFirstConnect <= True;
						// Address
					end else begin
						let prevPacket = fromMaybe(?, recvPacketBuffer40);
						Bit#(72) extendPrev = zeroExtend(prevPacket);
						Bit#(72) extendCurr = zeroExtend(d);
						Bit#(72) recvPacket = (extendCurr << 40) | extendPrev;
						recvPacketBuffer72 <= tagged Valid recvPacket;
						// RW Header + Amount of Memory
					end
				end else begin
					let prevPacket = fromMaybe(?, recvPacketBuffer24);
					Bit#(16) currPacket = truncate(d);
					Bit#(40) extendPrev = zeroExtend(prevPacket);
					Bit#(40) extendCurr = zeroExtend(currPacket);
					Bit#(40) recvPacket = (extendCurr << 24) | extendPrev;
					recvPacketBuffer40 <= tagged Valid recvPacket;
					// Packet Header
				end
			end else begin
				recvPacketBuffer24 <= tagged Valid truncate(d); 
				// # of Hops and Output Ports of FPGAs
			end
		end else begin // Open second connection (FPGA2 to FPGA1 to Host)
			openSecndConnect <= True;
		end
	endrule
	//--------------------------------------------------------------------------------------------
	// Host(0) -> (0)FPGA1(4) -> (7)FPGA2(6) -> (3)FPGA1 (First Connection)
	//--------------------------------------------------------------------------------------------
	rule fpga1_1( openFirstConnect );
		if ( recvPacketQ.notEmpty ) begin
			recvPacketQ.deq;
			AuroraIfcType encRoutingPacket = recvPacketQ.first;
			Bit#(8) numHops = encRoutingPacket[7:0] ^ 1; // Priv_Key of FPGA1

			if ( numHops != 0 ) begin
				Bit#(8) outPortFPGA1_1 = encRoutingPacket[15:8] ^ 1; // Priv_Key of FPGA1
				Bit#(8) id = truncate(outPortFPGA1_1);
				Bit#(1) qid = id[2];
				Bit#(2) pid = truncate(id);	

				Bit#(8) encNewNumHopsTmp = (numHops - 1) ^ 2; // Pub_Key of FPGA2
				AuroraIfcType encNewNumHops = zeroExtend(encNewNumHopsTmp);
				AuroraIfcType remainRoutingPacket = encRoutingPacket >> 16;
				AuroraIfcType newRemainRoutingPacket = (remainRoutingPacket << 8) | encNewNumHops;

				auroraQuads[qid].user[pid].send(newRemainRoutingPacket);
			end else begin
				// Host wants to use FPGA1's memory
				AuroraIfcType remainRoutingPacket = encRoutingPacket >> 8;
				Bit#(16) packetHeader = remainRoutingPacket[15:0] ^ 1; // Priv_Key of FPGA1
				Bit#(32) aomNheader = remainRoutingPacket[47:16] ^ 1; // Priv_Key of FPGA1
				Bit#(32) address = remainRoutingPacket[79:48] ^ 1; // Priv_Key of FPGA1

				if ( aomNheader[0] == 0 ) begin
					// Write
				end else begin
					// Read
				end
			end
		end
	endrule
	rule fpga2_1( !openFirstConnect );
		Bit#(8) idIn = 7;
		Bit#(1) qidIn = idIn[2];
		Bit#(2) pidIn = truncate(idIn);

		let p <- auroraQuads[qidIn].user[pidIn].receive;
		Bit#(8) numHops = p[7:0] ^ 2; // Priv_Key of FPGA2

		if ( numHops != 0 ) begin
			Bit#(8) outPortFPGA2_1 = p[15:8] ^ 2; // Priv_Key of FPGA2
			Bit#(8) idOut = truncate(outPortFPGA2_1);
			Bit#(1) qidOut = idOut[2];
			Bit#(2) pidOut = truncate(idOut);	
			
			Bit#(8) encNewNumHopsTmp = (numHops - 1) ^ 1; // Pub_Key of FPGA1
			AuroraIfcType encNewNumHops = zeroExtend(encNewNumHopsTmp);
			AuroraIfcType remainRoutingPacket = p >> 16;
			AuroraIfcType newRemainRoutingPacket = (remainRoutingPacket << 8) | encNewNumHops;

			auroraQuads[qidOut].user[pidOut].send(newRemainRoutingPacket);
		end else begin
			// FPGA2_1 is final destination
			AuroraIfcType remainRoutingPacket = p >> 8;
			Bit#(16) packetHeader = remainRoutingPacket[15:0] ^ 1; // Priv_Key of FPGA2
			Bit#(32) aomNheader = remainRoutingPacket[47:16] ^ 1; // Priv_Key of FPGA2
			Bit#(32) address = remainRoutingPacket[79:48] ^ 1; // Priv_Key of FPGA2

			if ( aomNheader[0] == 0 ) begin
				// Write
			end else begin
				// Read
			end
		end
	endrule
	FIFOF#(Bit#(32)) validCheckFirstConnectQ <- mkFIFOF;
	rule fpga1_2( openFirstConnect );
		Bit#(8) idIn = 3;
		Bit#(1) qidIn = idIn[2];
		Bit#(2) pidIn = truncate(idIn);

		let p <- auroraQuads[qidIn].user[pidIn].receive;
		Bit#(8) numHops = p[7:0] ^ 1; // Priv_Key of FPGA1

		if ( numHops != 0 ) begin
			Bit#(8) outPortFPGA1_2 = p[15:8] ^ 1; // Priv_Key of FPGA1
			Bit#(8) idOut = truncate(outPortFPGA1_2);
			Bit#(1) qidOut = idOut[2];
			Bit#(2) pidOut = truncate(idOut);	
			
			Bit#(8) encNewNumHopsTmp = (numHops - 1) ^ 2; // Pub_Key of FPGA2
			AuroraIfcType encNewNumHops = zeroExtend(encNewNumHopsTmp);
			AuroraIfcType remainRoutingPacket = p >> 16;
			AuroraIfcType newRemainRoutingPacket = (remainRoutingPacket << 8) | encNewNumHops;

			auroraQuads[qidOut].user[pidOut].send(newRemainRoutingPacket);
			validCheckFirstConnectQ.enq(1);
		end else if ( numHops == 0 ) begin
			// FPGA1_2 is final destination
			AuroraIfcType remainRoutingPacket = p >> 8;
			Bit#(16) packetHeader = remainRoutingPacket[15:0] ^ 1; // Priv_Key of FPGA1
			Bit#(32) aomNheader = remainRoutingPacket[47:16] ^ 1; // Priv_Key of FPGA1
			Bit#(32) address = remainRoutingPacket[79:48] ^ 1; // Priv_Key of FPGA1

			/*if ( aomNheader[0] == 0 ) begin
				// Write
				validCheckFirstConnectQ.enq(1);
			end else begin
				// Read
				validCheckFirstConnectQ.enq(0);
			end*/
		       	validCheckFirstConnectQ.enq(1);
		end
	endrule
	//--------------------------------------------------------------------------------------------
	// FPGA2 -> FPGA1 -> Host (Second Connection)
	//--------------------------------------------------------------------------------------------
	/*rule sendPacketFPGA2to1( !openSecndConnect );
		Bit#(8) id = 7;
		Bit#(1) qid = id[2];
		Bit#(2) pid = truncate(id);

		AuroraIfcType encRoutingPacket = 0;

		Bit#(8) outPortFPGA1 = 0;
		Bit#(8) packetHeader = 2;
		Bit#(1) rwHeader = 0;
		Bit#(31) aom = 4*1024;
		Bit#(32) address = 0;

		Bit#(32) encOutPortFPGA1 <- keyPairFPGA1.getEncryptedPacket (zeroExtend(outPortFPGA1));
		Bit#(32) encPacketHeader <- publicKeyHost.getEncryptedPacket (zeroExtend(packetHeader));
		Bit#(32) encAomNHeader <- publicKeyHost.getEncryptedPacket ({rwHeader, aom});
		Bit#(32) encAddress <- publicKeyHost.getEncryptedPacket (address);

		encRoutingPacket[79:72] = truncate(encOutPortFPGA1);
		encRoutingPacket[71:64] = truncate(encPacketHeader);
		encRoutingPacket[63:32] = encAomNHeader;
		encRoutingPacket[31:0] = encAddress;

		auroraQuads[qid].user[pid].send(encRoutingPacket);
	endrule	
	FIFOF#(Bit#(72)) sendPacketFPGA1toHostQ <- mkFIFOF;
	rule recvPacketFPGA1( openSecndConnect );
		Bit#(8) id = 4;
		Bit#(1) qid = id[2];
		Bit#(2) pid = truncate(id);

		let p <- auroraQuads[qid].user[pid].receive;
		Bit#(32) encOutPortFPGA1 = zeroExtend(p[79:72]);
		Bit#(32) outPortFPGA1 <- keyPairFPGA1.getDecryptedPacket (encOutPortFPGA1);

		if ( outPortFPGA1[7:0] == 0 ) begin
			sendPacketFPGA1toHostQ.enq(p[71:0]);
		end
	endrule 
	FIFOF#(Bit#(32)) relayPacketFPGA1toHostQ <- mkFIFOF;
	Reg#(Maybe#(Bit#(40))) relayPacketBuffer1 <- mkReg(tagged Invalid);
	Reg#(Maybe#(Bit#(8))) relayPacketBuffer2 <- mkReg(tagged Invalid);
	rule relayPackettoHost( openSecndConnect );
		if ( isValid(relayPacketBuffer1) ) begin
			if ( isValid(relayPacketBuffer2) ) begin
				let p = fromMaybe(?, relayPacketBuffer2);
				relayPacketFPGA1toHostQ.enq(zeroExtend(p));
				relayPacketBuffer1 <= tagged Invalid;
				relayPacketBuffer2 <= tagged Invalid;
			end else begin
				let p = fromMaybe(?, relayPacketBuffer1);
				relayPacketBuffer2 <= tagged Valid truncate(p>>32);
				relayPacketFPGA1toHostQ.enq(truncate(p));
			end
		end else begin
			let p = sendPacketFPGA1toHostQ.first;
			relayPacketBuffer1 <= tagged Valid truncate(p>>32);
			relayPacketFPGA1toHostQ.enq(truncate(p));
			sendPacketFPGA1toHostQ.deq;
		end
	endrule*/
	//--------------------------------------------------------------------------------------------
	// Send Routing Packet to Host
	//--------------------------------------------------------------------------------------------
	rule getAuroraStatus;
		pcieReadReqQ.deq;
		let r = pcieReadReqQ.first;
		Bit#(4) a = truncate(r.addr>>2);
		if ( a < 8 ) begin
			if ( openFirstConnect ) begin
				if ( validCheckFirstConnectQ.notEmpty ) begin
					pcieRespQ.enq(tuple2(r, validCheckFirstConnectQ.first));
					validCheckFirstConnectQ.deq;
				end else begin 
					pcieRespQ.enq(tuple2(r, 32'h12345678));
				end
			end /*else begin
				if ( relayPacketFPGA1toHostQ.notEmpty ) begin
					pcieRespQ.enq(tuple2(r, relayPacketFPGA1toHostQ.first));
					relayPacketFPGA1toHostQ.deq;
				end else begin 
					pcieRespQ.enq(tuple2(r, 32'h12345678));
				end
			end*/
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