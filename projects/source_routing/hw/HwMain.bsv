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
	Reg#(AuroraIfcType) routingPacketFPGA1to2 <- mkReg(0);
	Reg#(Bool) openFirstConnect <- mkReg(False);
	Reg#(Bool) openSecndConnect <- mkReg(False);
	rule getCmd;
		pcieWriteQ.deq;
		let w = pcieWriteQ.first;

		let d = w.data;
		let a = w.addr;

		if ( a == 0 ) begin
			if ( d == 0 ) begin // Open first connection (FPGA1 to 2)
	 			AuroraIfcType routingPacketTmp = 0;
				
				routingPacketTmp[7:0] = 0;
				routingPacketTmp[15:8] = 0;
				routingPacketTmp[23:16] = 4;
				routingPacketTmp[31:24] = 7;
				routingPacketTmp[63:32] = 4*1024;
				routingPacketTmp[123:64] = 0;
				routingPacketFPGA1to2 <= routingPacketTmp;

				openFirstConnect <= True;
			end else begin // Open second connection (FPGA2 to 1)
				openSecndConnect <= True;
			end
		end
	endrule
	//--------------------------------------------------------------------------------------------
	// Host to FPGA1 to FPGA2 (First Connection)
	//--------------------------------------------------------------------------------------------
	rule sendPacketFPGA1to2( openFirstConnect );
		Bit#(8) idFPGA1 = routingPacketFPGA1to2[23:16];
		Bit#(1) qidOutFPGA1 = idFPGA1[2];
		Bit#(2) pidOutFPGA1 = truncate(idFPGA1);

		auroraQuads[qidOutFPGA1].user[pidOutFPGA1].send(routingPacketFPGA1to2);
	endrule
	Reg#(Bool) recvPacketFPGA2Done <- mkReg(False);
	rule recvPacketFPGA2( !openFirstConnect );
		Bit#(8) id = routingPacketFPGA1to2[31:24];
		Bit#(1) qidIn = id[2];
		Bit#(2) pidIn = truncate(id);

		let p <- auroraQuads[qidIn].user[pidIn].receive;
		auroraQuads[qidIn].user[pidIn].send(p);
		recvPacketFPGA2Done <= True;
	endrule
	FIFOF#(Bit#(32)) validCheckFirstConnecQ <- mkFIFOF;
	rule validCheckFirstConnec( openFirstConnect );
		Bit#(8) id = routingPacketFPGA1to2[23:16];
		Bit#(1) qidIn = id[2];
		Bit#(2) pidIn = truncate(id);

		let p <- auroraQuads[qidIn].user[pidIn].receive;
	
		if ( p[63:32] == 4*1024 ) begin
			validCheckFirstConnecQ.enq(1);
		end else begin
			validCheckFirstConnecQ.enq(0);
		end
	endrule
	//--------------------------------------------------------------------------------------------
	// FPGA2 to FPGA1 to Host (Second Connection)
	//--------------------------------------------------------------------------------------------
	Reg#(AuroraIfcType) routingPacketFPGA2to1 <- mkReg(0);
	rule sendPacketFPGA2to1( !openSecndConnect );
		AuroraIfcType routingPacketTmp = 0;
		routingPacketTmp[7:0] = 6;
		routingPacketTmp[15:8] = 3;
		routingPacketTmp[23:16] = 0;
		routingPacketTmp[31:24] = 0;
		routingPacketTmp[63:32] = 4*1024;
		routingPacketTmp[123:64] = 0;
		
		auroraQuads[1].user[2].send(routingPacketTmp);

		routingPacketFPGA2to1 <= routingPacketTmp;
	endrule	
	FIFOF#(Bit#(32)) sendPacketFPGA1toHostQ <- mkFIFOF;
	rule recvPacketFPGA1( openSecndConnect );
		Bit#(8) id = routingPacketFPGA2to1[15:8];
		Bit#(1) qidIn = id[2];
		Bit#(2) pidIn = truncate(id);

		let p <- auroraQuads[qidIn].user[pidIn].receive;
		if ( p[63:32] == 4*1024 ) begin
			sendPacketFPGA1toHostQ.enq(1);
		end else begin
			sendPacketFPGA1toHostQ.enq(0);
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
				if ( sendPacketFPGA1toHostQ.notEmpty ) begin
					pcieRespQ.enq(tuple2(r, sendPacketFPGA1toHostQ.first));
					sendPacketFPGA1toHostQ.deq;
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
