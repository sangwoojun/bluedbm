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
	Reg#(Bool) openConnect <- mkReg(False);

	Reg#(Maybe#(Bit#(32))) recvPacketBuffer32 <- mkReg(tagged Invalid);
	Reg#(Maybe#(Bit#(48))) recvPacketBuffer48 <- mkReg(tagged Invalid);
	Reg#(Maybe#(Bit#(80))) recvPacketBuffer80 <- mkReg(tagged Invalid);
	rule getCmd;
		pcieWriteQ.deq;
		let w = pcieWriteQ.first;

		let d = w.data;
		let a = w.addr;

		if ( a == 0 ) begin // Open first connection (Host to FPGA1 to FPGA2)
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
						// Address
					end else begin
						let prevPacket = fromMaybe(?, recvPacketBuffer48);
						Bit#(80) extendPrev = zeroExtend(prevPacket);
						Bit#(80) extendCurr = zeroExtend(d);
						Bit#(80) recvPacket = (extendCurr << 48) | extendPrev;
						recvPacketBuffer80 <= tagged Valid recvPacket;
						// RW Header + Amount of Memory
					end
				end else begin
					let prevPacket = fromMaybe(?, recvPacketBuffer32);
					Bit#(16) currPacket = truncate(d);
					Bit#(48) extendPrev = zeroExtend(prevPacket);
					Bit#(48) extendCurr = zeroExtend(currPacket);
					Bit#(48) recvPacket = (extendCurr << 32) | extendPrev;
					recvPacketBuffer48 <= tagged Valid recvPacket;
					// Packet Header
				end
			end else begin
				recvPacketBuffer32 <= tagged Valid d; 
				// # of Hops and Output Ports of FPGAs
			end
		end
	endrule
	//--------------------------------------------------------------------------------------------
	// Host(0) -> (0)FPGA1_1(4) -> (7)FPGA2_1(7) -> (4)FPGA1_2(3) -> (6)FPGA2_2 (First Connection)
	//--------------------------------------------------------------------------------------------
	FIFOF#(Tuple3#(Bit#(1), Bit#(2), AuroraIfcType)) sendPacketByAuroraFPGA1_1Q <- mkFIFOF;
	FIFOF#(Tuple3#(Bit#(1), Bit#(2), AuroraIfcType)) sendPacketByAuroraFPGA1_2Q <- mkFIFOF;
	FIFOF#(Tuple3#(Bit#(1), Bit#(2), AuroraIfcType)) sendPacketByAuroraFPGA2_1Q <- mkFIFOF;
	FIFOF#(Tuple3#(Bit#(1), Bit#(2), AuroraIfcType)) sendPacketByAuroraFPGA2_2Q <- mkFIFOF;
	rule fpga1_1( openConnect );
		if ( recvPacketQ.notEmpty ) begin
			recvPacketQ.deq;
			AuroraIfcType encRoutingPacket = recvPacketQ.first;
			Bit#(8) numHops = encRoutingPacket[7:0] ^ 1; // Priv_Key of FPGA1
			
			if ( numHops != 0 ) begin
				Bit#(8) outPortFPGA1_1 = encRoutingPacket[15:8] ^ 1; // Priv_Key of FPGA1
				Bit#(8) id = truncate(outPortFPGA1_1);
				Bit#(1) qid = id[2];
				Bit#(2) pid = truncate(id);	

				Bit#(8) encNewNumHopsTmp = (numHops - 1) ^ 2; // 2, Pub_Key of FPGA2
				AuroraIfcType encNewNumHops = zeroExtend(encNewNumHopsTmp);
				AuroraIfcType remainRoutingPacket = encRoutingPacket >> 16;
				AuroraIfcType newRemainRoutingPacket = (remainRoutingPacket << 8) | encNewNumHops;

				//auroraQuads[qid].user[pid].send(newRemainRoutingPacket);
				sendPacketByAuroraFPGA1_1Q.enq(tuple3(qid, pid, newRemainRoutingPacket));
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
	rule fpga2_1( !openConnect );
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
			
			Bit#(8) encNewNumHopsTmp = (numHops - 1) ^ 1; // 1, Pub_Key of FPGA1
			AuroraIfcType encNewNumHops = zeroExtend(encNewNumHopsTmp);
			AuroraIfcType remainRoutingPacket = p >> 16;
			AuroraIfcType newRemainRoutingPacket = (remainRoutingPacket << 8) | encNewNumHops;

			//auroraQuads[qidOut].user[pidOut].send(newRemainRoutingPacket);
			sendPacketByAuroraFPGA2_1Q.enq(tuple3(qidOut, pidOut, newRemainRoutingPacket));
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
	rule fpga1_2( openConnect );
		Bit#(8) idIn = 4;
		Bit#(1) qidIn = idIn[2];
		Bit#(2) pidIn = truncate(idIn);

		let p <- auroraQuads[qidIn].user[pidIn].receive;
		Bit#(8) numHops = p[7:0] ^ 1; // Priv_Key of FPGA1

		if ( numHops != 0 ) begin
			Bit#(8) outPortFPGA1_2 = p[15:8] ^ 1; // Priv_Key of FPGA1
			Bit#(8) idOut = truncate(outPortFPGA1_2);
			Bit#(1) qidOut = idOut[2];
			Bit#(2) pidOut = truncate(idOut);	
			
			Bit#(8) encNewNumHopsTmp = (numHops - 1) ^ 2; // 0, Pub_Key of FPGA2
			AuroraIfcType encNewNumHops = zeroExtend(encNewNumHopsTmp);
			AuroraIfcType remainRoutingPacket = p >> 16;
			AuroraIfcType newRemainRoutingPacket = (remainRoutingPacket << 8) | encNewNumHops;

			//auroraQuads[qidOut].user[pidOut].send(newRemainRoutingPacket);
			sendPacketByAuroraFPGA1_2Q.enq(tuple3(qidOut, pidOut, newRemainRoutingPacket));
		end else begin
			// FPGA1_1 is final destination
			AuroraIfcType remainRoutingPacket = p >> 8;
			Bit#(16) packetHeader = remainRoutingPacket[15:0] ^ 1; // Priv_Key of FPGA1
			Bit#(32) aomNheader = remainRoutingPacket[47:16] ^ 1; // Priv_Key of FPGA1
			Bit#(32) address = remainRoutingPacket[79:48] ^ 1; // Priv_Key of FPGA1

			if ( aomNheader[0] == 0 ) begin
				// Write
			end else begin
				// Read
			end
		end
	endrule
	rule fpga2_2( !openConnect );
		Bit#(8) idIn = 6;
		Bit#(1) qidIn = idIn[2];
		Bit#(2) pidIn = truncate(idIn);

		let p <- auroraQuads[qidIn].user[pidIn].receive;
		Bit#(8) numHops = p[7:0] ^ 2; // Priv_Key of FPGA2
		
		if ( numHops != 0 ) begin
			Bit#(8) outPortFPGA2_2 = p[15:8] ^ 2; // Priv_Key of FPGA2
			Bit#(8) idOut = truncate(outPortFPGA2_2);
			Bit#(1) qidOut = idOut[2];
			Bit#(2) pidOut = truncate(idOut);	
			
			Bit#(8) encNewNumHopsTmp = (numHops - 1) ^ 1; // ?, Pub_Key of FPGA1
			AuroraIfcType encNewNumHops = zeroExtend(encNewNumHopsTmp);
			AuroraIfcType remainRoutingPacket = p >> 16;
			AuroraIfcType newRemainRoutingPacket = (remainRoutingPacket << 8) | encNewNumHops;

			//auroraQuads[qidOut].user[pidOut].send(newRemainRoutingPacket);
			//sendPacketByAuroraFPGA2_2Q.enq(tuple3(qidOut, pidOut, newRemainRoutingPacket));
		end else begin
			// FPGA2_2 is final destination
			AuroraIfcType remainRoutingPacket = p >> 8;
			Bit#(16) packetHeader = remainRoutingPacket[15:0] ^ 2; // Priv_Key of FPGA2
			Bit#(32) aomNheader = remainRoutingPacket[47:16] ^ 2; // Priv_Key of FPGA2
			Bit#(32) address = remainRoutingPacket[79:48] ^ 2; // Priv_Key of FPGA2

			if ( aomNheader[0] == 0 ) begin
				// Write
				//auroraQuads[qidIn].user[pidIn].send(0);
				sendPacketByAuroraFPGA2_2Q.enq(tuple3(qidIn, pidIn, 0));
			end
		end
	endrule
	FIFOF#(Bit#(32)) validCheckConnectQ <- mkFIFOF;
	rule validCheckFirstConnection( openConnect );
		Bit#(8) idIn = 3;
		Bit#(1) qidIn = idIn[2];
		Bit#(2) pidIn = truncate(idIn);

		let p <- auroraQuads[qidIn].user[pidIn].receive;
	
		if ( p == 0 ) begin
			validCheckConnectQ.enq(1);
		end else begin
			validCheckConnectQ.enq(0);
		end
	endrule
	//--------------------------------------------------------------------------------------------
	// Scheduler FPGA1 & FPGA2
	//--------------------------------------------------------------------------------------------
	Reg#(Bit#(1)) schedulerFPGA1 <- mkReg(0);
	Reg#(Bit#(1)) schedulerFPGA2 <- mkReg(0);
	rule schedulerForFPGA1( openConnect );
		Bit#(1) qidOut = 0;
		Bit#(2) pidOut = 0;
		AuroraIfcType payload = 0;
		if ( schedulerFPGA1 == 0 ) begin
			if ( sendPacketByAuroraFPGA1_1Q.notEmpty ) begin
				sendPacketByAuroraFPGA1_1Q.deq;
				qidOut = tpl_1(sendPacketByAuroraFPGA1_1Q.first);
				pidOut = tpl_2(sendPacketByAuroraFPGA1_1Q.first);
				payload = tpl_3(sendPacketByAuroraFPGA1_1Q.first);

				schedulerFPGA1 <= schedulerFPGA1 + 1;
			end
		end else begin
			if ( sendPacketByAuroraFPGA1_2Q.notEmpty ) begin
				sendPacketByAuroraFPGA1_2Q.deq;
				qidOut = tpl_1(sendPacketByAuroraFPGA1_2Q.first);
				pidOut = tpl_2(sendPacketByAuroraFPGA1_2Q.first);
				payload = tpl_3(sendPacketByAuroraFPGA1_2Q.first);

				schedulerFPGA1 <= 0;
			end
		end
		auroraQuads[qidOut].user[pidOut].send(payload);
	endrule
	rule schedulerForFPGA2( !openConnect );
		Bit#(1) qidOut = 0;
		Bit#(2) pidOut = 0;
		AuroraIfcType payload = 0;
		if ( schedulerFPGA2 == 0 ) begin
			if ( sendPacketByAuroraFPGA2_1Q.notEmpty ) begin
				sendPacketByAuroraFPGA2_1Q.deq;
				qidOut = tpl_1(sendPacketByAuroraFPGA2_1Q.first);
				pidOut = tpl_2(sendPacketByAuroraFPGA2_1Q.first);
				payload = tpl_3(sendPacketByAuroraFPGA2_1Q.first);

				schedulerFPGA2 <= schedulerFPGA2 + 1;
			end
		end else begin
			if ( sendPacketByAuroraFPGA2_2Q.notEmpty ) begin
				sendPacketByAuroraFPGA2_2Q.deq;
				qidOut = tpl_1(sendPacketByAuroraFPGA2_2Q.first);
				pidOut = tpl_2(sendPacketByAuroraFPGA2_2Q.first);
				payload = tpl_3(sendPacketByAuroraFPGA2_2Q.first);

				schedulerFPGA2 <= 0;
			end
		end
		auroraQuads[qidOut].user[pidOut].send(payload);
	endrule
	//--------------------------------------------------------------------------------------------
	// Send Routing Packet to Host
	//--------------------------------------------------------------------------------------------
	rule getAuroraStatus;
		pcieReadReqQ.deq;
		let r = pcieReadReqQ.first;
		Bit#(4) a = truncate(r.addr>>2);
		if ( a < 8 ) begin
			if ( validCheckConnectQ.notEmpty ) begin
				pcieRespQ.enq(tuple2(r, validCheckConnectQ.first));
				validCheckConnectQ.deq;
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
