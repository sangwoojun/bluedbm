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
	Reg#(Bool) openConnect <- mkReg(False);

	Reg#(Maybe#(Bit#(24))) recvPacketBuffer24 <- mkReg(tagged Invalid);
	Reg#(Maybe#(Bit#(40))) recvPacketBuffer40 <- mkReg(tagged Invalid);
	Reg#(Maybe#(Bit#(72))) recvPacketBuffer72 <- mkReg(tagged Invalid);
	rule getCmd;
		pcieWriteQ.deq;
		let w = pcieWriteQ.first;

		let d = w.data;
		let a = w.addr;

		if ( a == 0 ) begin // Host -> FPGA1_1
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

						openConnect <= True;
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
					// Actual Route
				end
			end else begin
				recvPacketBuffer24 <= tagged Valid truncate(d); 
				// # of Hops Packet Header (Header Part)
			end
		end
	endrule
	//--------------------------------------------------------------------------------------------
	// Host(0) -> (0)FPGA1_1(4) -> (7)FPGA2_1(6) -> (3)FPGA1_2 (First Connection)
	//--------------------------------------------------------------------------------------------
	FIFOF#(Tuple3#(Bit#(1), Bit#(2), AuroraIfcType)) sendPacketByAuroraFPGA1_1Q <- mkFIFOF;
	FIFOF#(Tuple3#(Bit#(1), Bit#(2), AuroraIfcType)) sendPacketByAuroraFPGA2_1Q <- mkFIFOF;
	FIFOF#(Tuple3#(Bit#(1), Bit#(2), AuroraIfcType)) sendPacketByAuroraFPGA1_2Q <- mkFIFOF;
	rule fpga1_1( openConnect && recvPacketQ.notEmpty );
		Integer privKeyFPGA1 = 1;

		recvPacketQ.deq;
		AuroraIfcType recvPacket = recvPacketQ.first;
		Bit#(8) numHops = recvPacket[7:0] ^ fromInteger(privKeyFPGA1);
		Bit#(16) encPacketHeader = recvPacket[23:8];
		
		if ( numHops != 0 ) begin
			Bit#(8) outPortFPGA1_1 = recvPacket[31:24] ^ fromInteger(privKeyFPGA1);
			Bit#(1) qidOut = outPortFPGA1_1[2];
			Bit#(2) pidOut = truncate(outPortFPGA1_1);	

			Bit#(8) encNewNumHops = (numHops - 1) ^ fromInteger(pubKeyFPGA2);
			AuroraIfcType encNewHeaderPart = (zeroExtend(encPacketHeader) << 8) | zeroExtend(encNewNumHops);

			AuroraIfcType remainingPacket = recvPacket >> 32;
			AuroraIfcType newPacket = (remainingPacket << 24) | encNewHeaderPart;

			//auroraQuads[qidOut].user[pidOut].send(newPacket);
			sendPacketByAuroraFPGA1_1Q.enq(tuple3(qidOut, pidOut, newPacket));
		end else begin
			// Host wants to use FPGA1's memory
			Bit#(16) packetHeader = encPacketHeader ^ fromInteger(privKeyFPGA1);
			if ( packetHeader == 0 ) begin
				AuroraIfcType remainedPacket = recvPacket >> 24;
				
				Bit#(32) aomNheader = remainedPacket[31:0] ^ fromInteger(privKeyFPGA1);
				Bit#(32) address = remainedPacket[63:32] ^ fromInteger(privKeyFPGA1); 

				if ( aomNheader[0] == 0 ) begin
					// Write
				end else begin
					// Read
				end
			end
		end
	endrule
	rule fpga2_1( !openConnect );
		Integer privKeyFPGA2 = 2;

		Bit#(8) inPortFPGA2_1 = 7;
		Bit#(1) qidIn = inPortFPGA2_1[2];
		Bit#(2) pidIn = truncate(inPortFPGA2_1);

		let recvPacket <- auroraQuads[qidIn].user[pidIn].receive;
		Bit#(8) numHops = recvPacket[7:0] ^ fromInteger(privKeyFPGA2);
		Bit#(16) encPacketHeader = recvPacket[23:8];

		if ( numHops != 0 ) begin
			Bit#(8) outPortFPGA2_1 = recvPacket[31:24] ^ fromInteger(privKeyFPGA2);
			Bit#(1) qidOut = outPortFPGA2_1[2];
			Bit#(2) pidOut = truncate(outPortFPGA2_1);	
			
			Bit#(8) encNewNumHops = (numHops - 1) ^ fromInteger(pubKeyFPGA1);
			AuroraIfcType encNewHeaderPart = (zeroExtend(encPacketHeader) << 8) | zeroExtend(encNewNumHops);

			AuroraIfcType remainingPacket = recvPacket >> 32;
			AuroraIfcType newPacket = (remainingPacket << 24) | encNewHeaderPart;

			//auroraQuads[qidOut].user[pidOut].send(newPacket);
			sendPacketByAuroraFPGA2_1Q.enq(tuple3(qidOut, pidOut, newPacket));
		end else begin
			// FPGA2_1 is final destination
			Bit#(16) packetHeader = encPacketHeader ^ fromInteger(privKeyFPGA2);
			if ( packetHeader == 0 ) begin
				AuroraIfcType remainedPacket = recvPacket >> 24;
				
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
	FIFOF#(Bit#(32)) validCheckConnectionQ <- mkFIFOF;
	rule fpga1_2( openConnect );
		Integer privKeyFPGA1 = 1;

		Bit#(8) inPortFPGA1_2 = 3;
		Bit#(1) qidIn = inPortFPGA1_2[2];
		Bit#(2) pidIn = truncate(inPortFPGA1_2);

		let recvPacket <- auroraQuads[qidIn].user[pidIn].receive;
		Bit#(8) numHops = recvPacket[7:0] ^ fromInteger(privKeyFPGA1);
		Bit#(16) encPacketHeader = recvPacket[23:8];

		if ( numHops != 0 ) begin
			Bit#(8) outPortFPGA1_2 = recvPacket[31:24] ^ fromInteger(privKeyFPGA1);
			Bit#(1) qidOut = outPortFPGA1_2[2];
			Bit#(2) pidOut = truncate(outPortFPGA1_2);	
			
			Bit#(8) encNewNumHops = (numHops - 1) ^ fromInteger(pubKeyFPGA2);
			AuroraIfcType encNewHeaderPart = (zeroExtend(encPacketHeader) << 8) | zeroExtend(encNewNumHops);

			AuroraIfcType remainingPacket = recvPacket >> 32;
			AuroraIfcType newPacket = (remainingPacket << 24) | encNewHeaderPart;

			//auroraQuads[qidOut].user[pidOut].send(newPacket);
			sendPacketByAuroraFPGA1_2Q.enq(tuple3(qidOut, pidOut, newPacket));
		end else begin
			// FPGA1_2 is final destination
			Bit#(16) packetHeader = encPacketHeader ^ fromInteger(privKeyFPGA1);
			if ( packetHeader == 0 ) begin
				AuroraIfcType remainedPacket = recvPacket >> 24;
				
				Bit#(32) aomNheader = remainedPacket[31:0] ^ fromInteger(privKeyFPGA1);
				Bit#(32) address = remainedPacket[63:32] ^ fromInteger(privKeyFPGA1);

				if ( aomNheader[31:1] == 4*1024 ) begin
					validCheckConnectionQ.enq(1);
				end else begin
					validCheckConnectionQ.enq(0);
				end
			end
		end
	endrule
	Reg#(Bit#(1)) scheduler <- mkReg(0);
	FIFOF#(Tuple3#(Bit#(1), Bit#(2), AuroraIfcType)) relayPacketByAuroraFPGA1Q <- mkFIFOF;
	rule schedulerforFPGA1( openConnect );
		if ( scheduler == 0 ) begin
			if ( sendPacketByAuroraFPGA1_1Q.notEmpty ) begin
				sendPacketByAuroraFPGA1_1Q.deq;
				let qidOut = tpl_1(sendPacketByAuroraFPGA1_1Q.first);
				let pidOut = tpl_2(sendPacketByAuroraFPGA1_1Q.first);
				let payload = tpl_3(sendPacketByAuroraFPGA1_1Q.first);

				scheduler <= scheduler + 1;
				relayPacketByAuroraFPGA1Q.enq(tuple3(qidOut, pidOut, payload));
			end
		end else begin
			if ( sendPacketByAuroraFPGA1_2Q.notEmpty ) begin
				sendPacketByAuroraFPGA1_2Q.deq;
				let qidOut = tpl_1(sendPacketByAuroraFPGA1_2Q.first);
				let pidOut = tpl_2(sendPacketByAuroraFPGA1_2Q.first);
				let payload = tpl_3(sendPacketByAuroraFPGA1_2Q.first);

				scheduler <= 0;
				relayPacketByAuroraFPGA1Q.enq(tuple3(qidOut, pidOut, payload));
			end
		end
	endrule
	rule relayPacketByAuroraFPGA1( openConnect );
		if ( relayPacketByAuroraFPGA1Q.notEmpty ) begin
			relayPacketByAuroraFPGA1Q.deq;
			let qidOut = tpl_1(relayPacketByAuroraFPGA1Q.first);
			let pidOut = tpl_2(relayPacketByAuroraFPGA1Q.first);
			let payload = tpl_3(relayPacketByAuroraFPGA1Q.first);

			auroraQuads[qidOut].user[pidOut].send(payload);
		end
	endrule
	rule relayPacketByAuroraFPGA2( !openConnect );
		if ( sendPacketByAuroraFPGA2_1Q.notEmpty ) begin
			sendPacketByAuroraFPGA2_1Q.deq;
			let qidOut = tpl_1(sendPacketByAuroraFPGA2_1Q.first);
			let pidOut = tpl_2(sendPacketByAuroraFPGA2_1Q.first);
			let payload = tpl_3(sendPacketByAuroraFPGA2_1Q.first);

			auroraQuads[qidOut].user[pidOut].send(payload);
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
