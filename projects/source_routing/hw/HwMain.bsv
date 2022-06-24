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

interface PublicKeyHostIfc;
	method ActionValue#(Bit#(32)) getEncryptedPacket (Bit#(32) srPacket);
endinterface
module mkPublicKeyHost(PublicKeyHostIfc);
	method ActionValue#(Bit#(32)) getEncryptedPacket (Bit#(32) srPacket);
		Bit#(32) encryptedPacket = srPacket ^ 3;
		return encryptedPacket;
	endmethod
endmodule

interface KeyPairFPGA1Ifc;
	method ActionValue#(Bit#(32)) getEncryptedPacket (Bit#(32) srPacket);
	method ActionValue#(Bit#(32)) getDecryptedPacket (Bit#(32) encPacket);
endinterface
module mkKeyPairFPGA1(KeyPairFPGA1Ifc);
	method ActionValue#(Bit#(32)) getEncryptedPacket (Bit#(32) srPacket);
		Bit#(32) encryptedPacket = srPacket ^ 1;
		return encryptedPacket;
	endmethod
	method ActionValue#(Bit#(32)) getDecryptedPacket (Bit#(32) encPacket);
		Bit#(32) decryptedPacket = encPacket ^ 1;
		return decryptedPacket;
	endmethod
endmodule

interface KeyPairFPGA2Ifc;
	method ActionValue#(Bit#(32)) getEncryptedPacket (Bit#(32) srPacket);
	method ActionValue#(Bit#(32)) getDecryptedPacket (Bit#(32) encPacket);	
endinterface
module mkKeyPairFPGA2(KeyPairFPGA2Ifc);
	method ActionValue#(Bit#(32)) getEncryptedPacket (Bit#(32) srPacket);
		Bit#(32) encryptedPacket = srPacket ^ 2;
		return encryptedPacket;
	endmethod
	method ActionValue#(Bit#(32)) getDecryptedPacket (Bit#(32) encPacket);
		Bit#(32) decryptedPacket = encPacket ^ 2;
		return decryptedPacket;
	endmethod
endmodule

interface HwMainIfc;
endinterface

module mkHwMain#(PcieUserIfc pcie, DRAMUserIfc dram, Vector#(2, AuroraExtIfc) auroraQuads) (HwMainIfc);

	Clock curClk <- exposeCurrentClock;
	Reset curRst <- exposeCurrentReset;

	Clock pcieclk = pcie.user_clk;
	Reset pcierst = pcie.user_rst;
	
	KeyPairFPGA1Ifc keyPairFPGA1 <- mkKeyPairFPGA1;
	KeyPairFPGA2Ifc keyPairFPGA2 <- mkKeyPairFPGA2;
	PublicKeyHostIfc publicKeyHost <- mkPublicKeyHost;

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
	FIFO#(AuroraIfcType) recvPacketQ <- mkFIFO;
	Reg#(Bool) openFirstConnect <- mkReg(False);
	Reg#(Bool) openSecndConnect <- mkReg(False);
	Reg#(Maybe#(AuroraIfcType)) recvPacketBuffer1 <- mkReg(tagged Invalid);
	Reg#(Maybe#(AuroraIfcType)) recvPacketBuffer2 <- mkReg(tagged Invalid);
	Reg#(Maybe#(AuroraIfcType)) recvPacketBuffer3 <- mkReg(tagged Invalid);

	rule getCmd;
		pcieWriteQ.deq;
		let w = pcieWriteQ.first;

		let d = w.data;
		let a = w.addr;

		if ( a == 0 ) begin // Open first connection (FPGA1 to FPGA2)
			if ( isValid(recvPacketBuffer1) ) begin
				if ( isValid(recvPacketBuffer2) ) begin
					if ( isValid(recvPacketBuffer3) ) begin
						let prevPacket = fromMaybe(?, recvPacketBuffer3);
						AuroraIfcType extendDatato128 = zeroExtend(d);
						AuroraIfcType recvPacketFinal = (extendDatato128 << 72) | prevPacket;
						recvPacketQ.enq(recvPacketFinal);

						recvPacketBuffer1 <= tagged Invalid;
						recvPacketBuffer2 <= tagged Invalid;
						recvPacketBuffer3 <= tagged Invalid;

						openFirstConnect <= True;
					end else begin
						let prevPacket = fromMaybe(?, recvPacketBuffer2);
						AuroraIfcType extendDatato128 = zeroExtend(d);
						AuroraIfcType recvPacket = (extendDatato128 << 64) | prevPacket;
						recvPacketBuffer3 <= tagged Valid recvPacket;
					end
				end else begin
					let prevPacket = fromMaybe(?, recvPacketBuffer1);
					AuroraIfcType extendDatato128 = zeroExtend(d);
					AuroraIfcType recvPacket = (extendDatato128 << 32) | prevPacket;
					recvPacketBuffer2 <= tagged Valid recvPacket;
				end
			end else begin
				recvPacketBuffer1 <= tagged Valid zeroExtend(d);
			end
		end else begin // Open second connection (FPGA2 to FPGA1)
			openSecndConnect <= True;
		end
	endrule
	//--------------------------------------------------------------------------------------------
	// Host to FPGA1 to FPGA2 (First Connection)
	//--------------------------------------------------------------------------------------------
	rule sendPacketFPGA1to2( openFirstConnect );
		recvPacketQ.deq;
		AuroraIfcType encRoutingPacket = recvPacketQ.first;
		Bit#(32) encOutPortFPGA1 = zeroExtend(encRoutingPacket[79:72]);
		Bit#(32) outPortFPGA1 <- keyPairFPGA1.getDecryptedPacket (encOutPortFPGA1);
		
		Bit#(8) id = truncate(outPortFPGA1);
		Bit#(1) qid = id[2];
		Bit#(2) pid = truncate(id);	
		
		AuroraIfcType remainRoutingPacket = zeroExtend(encRoutingPacket[71:0]);
		auroraQuads[qid].user[pid].send(remainRoutingPacket);
	endrule
	rule recvPacketFPGA2( !openFirstConnect );
		Bit#(8) id = 6;
		Bit#(1) qid = id[2];
		Bit#(2) pid = truncate(id);

		let p <- auroraQuads[qid].user[pid].receive;
		Bit#(32) encPacketHeader = zeroExtend(p[71:64]);
		Bit#(32) encAomNHeader = p[63:32];
		Bit#(32) encAddress = p[31:0];

		Bit#(32) packetHeader <- keyPairFPGA2.getDecryptedPacket (encPacketHeader);
		Bit#(32) aomNHeader <- keyPairFPGA2.getDecryptedPacket (encAomNHeader);
		Bit#(32) address <- keyPairFPGA2.getDecryptedPacket (encAddress);

		auroraQuads[qid].user[pid].send(zeroExtend(aomNHeader));
	endrule
	FIFOF#(Bit#(32)) validCheckFirstConnecQ <- mkFIFOF;
	rule validCheckFirstConnec( openFirstConnect );
		Bit#(8) id = 3;
		Bit#(1) qid = id[2];
		Bit#(2) pid = truncate(id);

		let p <- auroraQuads[qid].user[pid].receive;
	
		if ( p == 4*1024 ) begin
			validCheckFirstConnecQ.enq(1);
		end else begin
			validCheckFirstConnecQ.enq(0);
		end
	endrule
	//--------------------------------------------------------------------------------------------
	// FPGA2 to FPGA1 to Host (Second Connection)
	//--------------------------------------------------------------------------------------------
	rule sendPacketFPGA2to1( !openSecndConnect );
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
	endrule
	//--------------------------------------------------------------------------------------------
	// Send Routing Packet to Host
	//--------------------------------------------------------------------------------------------
	rule getAuroraStatus;
		pcieReadReqQ.deq;
		let r = pcieReadReqQ.first;
		Bit#(4) a = truncate(r.addr>>2);
		if ( a < 8 ) begin
			if ( openFirstConnect ) begin
				if ( validCheckFirstConnecQ.notEmpty ) begin
					pcieRespQ.enq(tuple2(r, validCheckFirstConnecQ.first));
					validCheckFirstConnecQ.deq;
				end else begin 
					pcieRespQ.enq(tuple2(r, 32'h12345678));
				end
			end else begin
				if ( relayPacketFPGA1toHostQ.notEmpty ) begin
					pcieRespQ.enq(tuple2(r, relayPacketFPGA1toHostQ.first));
					relayPacketFPGA1toHostQ.deq;
				end else begin 
					pcieRespQ.enq(tuple2(r, 32'h12345678));
				end
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
