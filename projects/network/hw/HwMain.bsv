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

	Reg#(Maybe#(Bit#(32))) recvPacketBuffer32 <- mkReg(tagged Invalid);
	Reg#(Maybe#(Bit#(48))) recvPacketBuffer48 <- mkReg(tagged Invalid);
	Reg#(Maybe#(Bit#(80))) recvPacketBuffer80 <- mkReg(tagged Invalid);
	rule getCmd;
		pcieWriteQ.deq;
		let w = pcieWriteQ.first;

		let d = w.data;
		let a = w.addr;

		if ( a == 0 ) begin // Host -> FPGA1_1
			if ( isValid(recvPacketBuffer32) ) begin
				if ( isValid(recvPacketBuffer48) ) begin
					if ( isValid(recvPacketBuffer80) ) begin
						let prevPacket = fromMaybe(?, recvPacketBuffer80);
						AuroraIfcType extendPrev = zeroExtend(prevPacket);
						AuroraIfcType extendCurr = zeroExtend(d);
						AuroraIfcType recvPacket = (extendCurr << 80) | extendPrev;
						recvPacketQ.enq(recvPacket);

						recvPacketBuffer32 <= tagged Invalid;
						recvPacketBuffer48 <= tagged Invalid;
						recvPacketBuffer80 <= tagged Invalid;

						openConnect <= True;
						// Address 32-bit
					end else begin
						let prevPacket = fromMaybe(?, recvPacketBuffer48);
						Bit#(80) extendPrev = zeroExtend(prevPacket);
						Bit#(80) extendCurr = zeroExtend(d);
						Bit#(80) recvPacket = (extendCurr << 48) | extendPrev;
						recvPacketBuffer80 <= tagged Valid recvPacket;
						// RW Header + Amount of Memory 32-bit
					end
				end else begin
					let prevPacket = fromMaybe(?, recvPacketBuffer32);
					Bit#(16) currPacket = truncate(d);
					Bit#(48) extendPrev = zeroExtend(prevPacket);
					Bit#(48) extendCurr = zeroExtend(currPacket);
					Bit#(48) recvPacket = (extendCurr << 32) | extendPrev;
					recvPacketBuffer48 <= tagged Valid recvPacket;
					// Actual Route 16-bit
				end
			end else begin
				recvPacketBuffer32 <= tagged Valid d; 
				// # of Hops Packet Header (Header Part) 32-bit
			end
		end
	endrule
	//--------------------------------------------------------------------------------------------
	// Host(0) -> (0)FPGA1_1(4) -> (7)FPGA2_1(6) -> (3)FPGA1_2 (First Connection)
	//--------------------------------------------------------------------------------------------
	FIFOF#(Tuple4#(Bit#(1), Bit#(2), Bit#(24), AuroraIfcType)) sendPacketByAuroraFPGA1_1Q <- mkFIFOF;
	FIFOF#(Tuple4#(Bit#(1), Bit#(2), Bit#(24), AuroraIfcType)) sendPacketByAuroraFPGA2_1Q <- mkFIFOF;
	FIFOF#(Tuple4#(Bit#(1), Bit#(2), Bit#(24), AuroraIfcType)) sendPacketByAuroraFPGA1_2Q <- mkFIFOF;
	rule fpga1_1( openConnect && recvPacketQ.notEmpty );
		Integer privKeyFPGA1 = 1;

		recvPacketQ.deq;
		AuroraIfcType recvPacket = recvPacketQ.first;
		Bit#(32) headerPart = recvPacket[31:0] ^ fromInteger(privKeyFPGA1);
		Bit#(8) numHops = headerPart[7:0];
		Bit#(24) packetHeader = headerPart[31:8];
		
		if ( numHops != 0 ) begin
			Bit#(8) outPortFPGA1_1 = recvPacket[39:32] ^ fromInteger(privKeyFPGA1);
			Bit#(1) qidOut = outPortFPGA1_1[2];
			Bit#(2) pidOut = truncate(outPortFPGA1_1);	

			Bit#(8) newNumHops = numHops - 1;
			Bit#(32) newHeaderPart = (zeroExtend(packetHeader) << 8) | zeroExtend(newNumHops);
			Bit#(32) encNewHeaderPartTmp = newHeaderPart ^ fromInteger(pubKeyFPGA2);
			AuroraIfcType encNewHeaderPart = zeroExtend(encNewHeaderPartTmp);

			AuroraIfcType remainingPacket = recvPacket >> 40;
			AuroraIfcType newPacket = (remainingPacket << 32) | encNewHeaderPart;

			//auroraQuads[qidOut].user[pidOut].send(newPacket);
			sendPacketByAuroraFPGA1_1Q.enq(tuple4(qidOut, pidOut, packetHeader, newPacket));
		end else begin
			// Host wants to use FPGA1's memory
			if ( packetHeader[0] == 0 ) begin
				AuroraIfcType remainedPacket = recvPacket >> 32;
				
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
		Bit#(32) headerPart = recvPacket[31:0] ^ fromInteger(privKeyFPGA2);
		Bit#(8) numHops = headerPart[7:0];
		Bit#(24) packetHeader = headerPart[31:8];

		if ( numHops != 0 ) begin
			Bit#(8) outPortFPGA2_1 = recvPacket[39:32] ^ fromInteger(privKeyFPGA2);
			Bit#(1) qidOut = outPortFPGA2_1[2];
			Bit#(2) pidOut = truncate(outPortFPGA2_1);	

			Bit#(8) newNumHops = numHops - 1;
			Bit#(32) newHeaderPart = (zeroExtend(packetHeader) << 8) | zeroExtend(newNumHops);
			Bit#(32) encNewHeaderPartTmp = newHeaderPart ^ fromInteger(pubKeyFPGA1);
			AuroraIfcType encNewHeaderPart = zeroExtend(encNewHeaderPartTmp);

			AuroraIfcType remainingPacket = recvPacket >> 40;
			AuroraIfcType newPacket = (remainingPacket << 32) | encNewHeaderPart;

			//auroraQuads[qidOut].user[pidOut].send(newPacket);
			sendPacketByAuroraFPGA2_1Q.enq(tuple4(qidOut, pidOut, packetHeader, newPacket));
		end else begin
			// FPGA2_1 is final destination
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
	FIFOF#(Bit#(32)) validCheckConnectionQ <- mkFIFOF;
	rule fpga1_2( openConnect );
		Integer privKeyFPGA1 = 1;

		Bit#(8) inPortFPGA1_2 = 3;
		Bit#(1) qidIn = inPortFPGA1_2[2];
		Bit#(2) pidIn = truncate(inPortFPGA1_2);

		let recvPacket <- auroraQuads[qidIn].user[pidIn].receive;
		Bit#(32) headerPart = recvPacket[31:0] ^ fromInteger(privKeyFPGA1);
		Bit#(8) numHops = headerPart[7:0];
		Bit#(24) packetHeader = headerPart[31:8];

		if ( numHops != 0 ) begin
			Bit#(8) outPortFPGA1_2 = recvPacket[39:32] ^ fromInteger(privKeyFPGA1);
			Bit#(1) qidOut = outPortFPGA1_2[2];
			Bit#(2) pidOut = truncate(outPortFPGA1_2);	

			Bit#(8) newNumHops = numHops - 1;
			Bit#(32) newHeaderPart = (zeroExtend(packetHeader) << 8) | zeroExtend(newNumHops);
			Bit#(32) encNewHeaderPartTmp = newHeaderPart ^ fromInteger(pubKeyFPGA2);
			AuroraIfcType encNewHeaderPart = zeroExtend(encNewHeaderPartTmp);

			AuroraIfcType remainingPacket = recvPacket >> 40;
			AuroraIfcType newPacket = (remainingPacket << 32) | encNewHeaderPart;

			//auroraQuads[qidOut].user[pidOut].send(newPacket);
			sendPacketByAuroraFPGA1_2Q.enq(tuple4(qidOut, pidOut, packetHeader, newPacket));
		end else begin
			// FPGA1_2 is final destination
			if ( packetHeader[0] == 0 ) begin
				AuroraIfcType remainedPacket = recvPacket >> 32;
				
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
	FIFOF#(Tuple4#(Bit#(1), Bit#(2), Bit#(8), AuroraIfcType)) relayPacketByAuroraFPGA1Q <- mkFIFOF;
	rule sendPacketFPGA1( openConnect );
		if ( scheduler == 0 ) begin
			if ( sendPacketByAuroraFPGA1_1Q.notEmpty ) begin
				Bit#(8) auroraExtCntFPGA1_1 = 0;
				sendPacketByAuroraFPGA1_1Q.deq;
				let qidOut = tpl_1(sendPacketByAuroraFPGA1_1Q.first);
				let pidOut = tpl_2(sendPacketByAuroraFPGA1_1Q.first);
				let packetHeader = tpl_3(sendPacketByAuroraFPGA1_1Q.first);
				let payload = tpl_4(sendPacketByAuroraFPGA1_1Q.first);

				let routeCnt = packetHeader[7:1];
				let payloadByte = packetHeader[23:16];

				if ( (routeCnt > 0) && (routeCnt < 3) ) begin
					Bit#(8) totalByte = 4+2+payloadByte;
					Bit#(16) totalBits = zeroExtend(totalByte) * 8;
					Bit#(16) decidedCycle = cycleDecider(totalBits);
					auroraExtCntFPGA1_1 = truncate(decidedCycle);
				end else if ( (routeCnt > 2) && (routeCnt < 5) ) begin
					Bit#(8) totalByte = 4+4+payloadByte;
					Bit#(16) totalBits = zeroExtend(totalByte) * 8;
					Bit#(16) decidedCycle = cycleDecider(totalBits);
					auroraExtCntFPGA1_1 = truncate(decidedCycle);
				end else if ( (routeCnt > 4) && (routeCnt < 9) ) begin
					Bit#(8) totalByte = 4+8+payloadByte;
					Bit#(16) totalBits = zeroExtend(totalByte) * 8;
					Bit#(16) decidedCycle = cycleDecider(totalBits);
					auroraExtCntFPGA1_1 = truncate(decidedCycle);
				end

				scheduler <= scheduler + 1;
				relayPacketByAuroraFPGA1Q.enq(tuple4(qidOut, pidOut, auroraExtCntFPGA1_1, payload));
			end
		end else begin
			if ( sendPacketByAuroraFPGA1_2Q.notEmpty ) begin
				Bit#(8) auroraExtCntFPGA1_2 = 0;
				sendPacketByAuroraFPGA1_2Q.deq;
				let qidOut = tpl_1(sendPacketByAuroraFPGA1_2Q.first);
				let pidOut = tpl_2(sendPacketByAuroraFPGA1_2Q.first);
				let packetHeader = tpl_3(sendPacketByAuroraFPGA1_2Q.first);
				let payload = tpl_4(sendPacketByAuroraFPGA1_2Q.first);

				let routeCnt = packetHeader[7:1];
				let payloadByte = packetHeader[23:16];

				if ( (routeCnt > 0) && (routeCnt < 3) ) begin
					Bit#(8) totalByte = 4+2+payloadByte;
					Bit#(16) totalBits = zeroExtend(totalByte) * 8;
					Bit#(16) decidedCycle = cycleDecider(totalBits);
					auroraExtCntFPGA1_2 = truncate(decidedCycle);
				end else if ( (routeCnt > 2) && (routeCnt < 5) ) begin
					Bit#(8) totalByte = 4+4+payloadByte;
					Bit#(16) totalBits = zeroExtend(totalByte) * 8;
					Bit#(16) decidedCycle = cycleDecider(totalBits);
					auroraExtCntFPGA1_2 = truncate(decidedCycle);
				end else if ( (routeCnt > 4) && (routeCnt < 9) ) begin
					Bit#(8) totalByte = 4+8+payloadByte;
					Bit#(16) totalBits = zeroExtend(totalByte) * 8;
					Bit#(16) decidedCycle = cycleDecider(totalBits);
					auroraExtCntFPGA1_2 = truncate(decidedCycle);
				end

				scheduler <= 0;
				relayPacketByAuroraFPGA1Q.enq(tuple4(qidOut, pidOut, auroraExtCntFPGA1_2, payload));
			end
		end
	endrule
	rule relayPacketFPGA1( openConnect );
		if ( relayPacketByAuroraFPGA1Q.notEmpty ) begin
			relayPacketByAuroraFPGA1Q.deq;
			let qidOut = tpl_1(relayPacketByAuroraFPGA1Q.first);
			let pidOut = tpl_2(relayPacketByAuroraFPGA1Q.first);
			let auroraExtCnt = tpl_3(relayPacketByAuroraFPGA1Q.first);
			let payload = tpl_4(relayPacketByAuroraFPGA1Q.first);

			auroraQuads[qidOut].user[pidOut].send(AuroraSend{packet:payload,num:auroraExtCnt});
		end
	endrule
	rule sendNrelayPacketFPGA2( !openConnect );
		if ( sendPacketByAuroraFPGA2_1Q.notEmpty ) begin
			Bit#(8) auroraExtCntFPGA2_1 = 0;
			sendPacketByAuroraFPGA2_1Q.deq;
			let qidOut = tpl_1(sendPacketByAuroraFPGA2_1Q.first);
			let pidOut = tpl_2(sendPacketByAuroraFPGA2_1Q.first);
			let packetHeader = tpl_3(sendPacketByAuroraFPGA2_1Q.first);
			let payload = tpl_4(sendPacketByAuroraFPGA2_1Q.first);

			let routeCnt = packetHeader[7:1];
			let payloadByte = packetHeader[23:16];

			if ( (routeCnt > 0) && (routeCnt < 3) ) begin
				Bit#(8) totalByte = 4+2+payloadByte;
				Bit#(16) totalBits = zeroExtend(totalByte) * 8;
				Bit#(16) decidedCycle = cycleDecider(totalBits);
				auroraExtCntFPGA2_1 = truncate(decidedCycle);
			end else if ( (routeCnt > 2) && (routeCnt < 5) ) begin
				Bit#(8) totalByte = 4+4+payloadByte;
				Bit#(16) totalBits = zeroExtend(totalByte) * 8;
				Bit#(16) decidedCycle = cycleDecider(totalBits);
				auroraExtCntFPGA2_1 = truncate(decidedCycle);
			end else if ( (routeCnt > 4) && (routeCnt < 9) ) begin
				Bit#(8) totalByte = 4+8+payloadByte;
				Bit#(16) totalBits = zeroExtend(totalByte) * 8;
				Bit#(16) decidedCycle = cycleDecider(totalBits);
				auroraExtCntFPGA2_1 = truncate(decidedCycle);
			end

			auroraQuads[qidOut].user[pidOut].send(AuroraSend{packet:payload,num:auroraExtCntFPGA2_1});
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
