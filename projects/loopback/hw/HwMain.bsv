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
	Vector#(8, Reg#(Bit#(1))) debuggingBitsC <- replicateM(mkReg(0));
	Vector#(8, Reg#(Bit#(1))) debuggingBitsL <- replicateM(mkReg(0));
	Reg#(Bit#(1)) debuggingCnt_1 <- mkReg(0);
	Reg#(Bit#(4)) debuggingCnt_2 <- mkReg(0);
	Reg#(Bool) debugDone <- mkReg(True);
	
	rule debugChannelLane;
		debuggingBitsC[0] <= auroraQuads[0].user[0].channel_up;
		debuggingBitsC[1] <= auroraQuads[0].user[1].channel_up;
		debuggingBitsC[2] <= auroraQuads[0].user[2].channel_up;
		debuggingBitsC[3] <= auroraQuads[0].user[3].channel_up;
		
		debuggingBitsC[4] <= auroraQuads[1].user[0].channel_up;
		debuggingBitsC[5] <= auroraQuads[1].user[1].channel_up;
		debuggingBitsC[6] <= auroraQuads[1].user[2].channel_up;
		debuggingBitsC[7] <= auroraQuads[1].user[3].channel_up;

		debuggingBitsL[0] <= auroraQuads[0].user[0].lane_up;
		debuggingBitsL[1] <= auroraQuads[0].user[1].lane_up;
		debuggingBitsL[2] <= auroraQuads[0].user[2].lane_up;
		debuggingBitsL[3] <= auroraQuads[0].user[3].lane_up;
		
		debuggingBitsL[4] <= auroraQuads[1].user[0].lane_up;
		debuggingBitsL[5] <= auroraQuads[1].user[1].lane_up;
		debuggingBitsL[6] <= auroraQuads[1].user[2].lane_up;
		debuggingBitsL[7] <= auroraQuads[1].user[3].lane_up;
	endrule
	rule getReadStatDebug(debugDone);
		pcieReadReqQ.deq;
		let r = pcieReadReqQ.first;

		let a = r.addr;
		if ( debuggingCnt_1 < 1 ) begin
			if ( debuggingCnt_2 < 7 ) begin
				debuggingCnt_2 <= debuggingCnt_2 + 1;
			end else begin
				debuggingCnt_1 <= debuggingCnt_1 + 1;
				debuggingCnt_2 <= 0;
			end
			pcieRespQ.enq(tuple2(r, zeroExtend(debuggingBitsC[debuggingCnt_2])));
		end else begin
			if ( debuggingCnt_2 < 7 ) begin
				debuggingCnt_2 <= debuggingCnt_2 + 1;
			end else begin
				debuggingCnt_1 <= 0;
				debuggingCnt_2 <= 0;
				debugDone <= False;
			end
			pcieRespQ.enq(tuple2(r, zeroExtend(debuggingBitsL[debuggingCnt_2])));
		end
	endrule
	//--------------------------------------------------------------------------------------------
	// Send Payload
	//--------------------------------------------------------------------------------------------
	Reg#(Bit#(1)) inQuad <- mkReg(0);
	Reg#(Bit#(3)) inPort <- mkReg(0);
	Reg#(Bit#(1)) outQuad <- mkReg(0);
	Reg#(Bit#(3)) outPort <- mkReg(0);

	FIFO#(AuroraIfcType) inputPortQ <- mkFIFO;
	Reg#(AuroraIfcType) inPayloadBuffer <- mkReg(0);
	Reg#(Bit#(1)) inPayloadBufferCnt <- mkReg(0);
	Reg#(Bool) inPayloadSendDone <- mkReg(False);

	rule getCmd;
		pcieWriteQ.deq;
		let w = pcieWriteQ.first;

		let d = w.data;
		let a = w.addr;

		if ( a == 0 ) begin // command
			case ( d ) matches
				{ 0 } : begin 
					inQuad <= 0;
					inPort <= 0;
					outQuad <= 0;
					outPort <= 1;
					$display( "Designating input port done as X1Y16!" );
					$display( "Output port should be X1Y17" );
					end
				{ 1 } : begin
					inQuad <= 0;
					inPort <= 1;
					outQuad <= 0;
					outPort <= 0;
					$display( "Designating input port done as X1Y17" );
					$display( "Output port should be X1Y16" );
					end
				{ 2 } : begin
					inQuad <= 0;
					inPort <= 2;
					outQuad <= 1;
					outPort <= 0;
					$display( "Designating input port done as X1Y18" );
					$display( "Output port should be X1Y24" );
					end
				{ 3 } : begin
					inQuad <= 0;
					inPort <= 3;
					outQuad <= 1;
					outPort <= 1;
					$display( "Designating input port done as X1Y19" );
					$display( "Output port should be X1Y25" );
					end
				{ 4 } : begin
					inQuad <= 1;
					inPort <= 0;
					outQuad <= 0;
					outPort <= 2;
					$display( "Designating input port done as X1Y24" );
					$display( "Output port should be X1Y18" );
					end
				{ 5 } : begin
					inQuad <= 1;
					inPort <= 1;
					outQuad <= 0;
					outPort <= 3;
					$display( "Designating input port done as X1Y25" );
					$display( "Output port should be X1Y19" );
					end
			endcase
		end else begin
			if (inPayloadBufferCnt == 0 ) begin
				inPayloadBuffer <= zeroExtend(d);
				inPayloadBufferCnt <= inPayloadBufferCnt + 1;
			end else begin
				AuroraIfcType inPayload = (inPayloadBuffer<<32)|zeroExtend(d);		
				inputPortQ.enq(inPayload);
				inPayloadBufferCnt <= 0;
			end
		end
	endrule
	rule relayPayload;
		inputPortQ.deq;
		let d = inputPortQ.first;
		auroraQuads[0].user[0].send(d);
		inPayloadSendDone <= True;
	endrule
	//--------------------------------------------------------------------------------------
	// Receive Payload
	//--------------------------------------------------------------------------------------
	//FIFO#(AuroraIfcType) outputPortQ <- mkFIFO;
	Reg#(Bit#(32)) outPayloadBuffer <- mkReg(0);
	Reg#(Bit#(1)) outPayloadBufferCnt <- mkReg(0);
	Reg#(Bit#(4)) quadCnt <- mkReg(0);
	Reg#(Bool) outPayloadWriteStart <- mkReg(False);
	Vector#(8, Reg#(AuroraIfcType)) outputPort <- replicateM(mkReg(0));

	rule getPacket(inPayloadSendDone);
		let d_0 <- auroraQuads[0].user[0].receive;
		outputPort[0] <= d_0;
		let d_1 <- auroraQuads[0].user[1].receive;
		outputPort[1] <= d_1;
		let d_2 <- auroraQuads[0].user[2].receive;
		outputPort[2] <= d_2;
		let d_3 <- auroraQuads[0].user[3].receive;
		outputPort[3] <= d_3;
		let d_4 <- auroraQuads[1].user[0].receive;
		outputPort[4] <= d_4;
		let d_5 <- auroraQuads[1].user[1].receive;
		outputPort[5] <= d_5;
		let d_6 <- auroraQuads[1].user[2].receive;
		outputPort[6] <= d_6;
		let d_7 <- auroraQuads[1].user[3].receive;
		outputPort[7] <= d_7;
		outPayloadWriteStart <= True;
		//outputPortQ.enq(d);
	endrule
	rule getReadStatRecPayload(inPayloadSendDone && outPayloadWriteStart);
		pcieReadReqQ.deq;
		let r = pcieReadReqQ.first;

		let a = r.addr;
		if (outPayloadBufferCnt == 0 ) begin
			//outputPortQ.deq;
			//let d = outputPortQ.first;
			pcieRespQ.enq(tuple2(r, truncate(outputPort[quadCnt])));
			outPayloadBuffer <= truncate(outputPort[quadCnt]>>32);
			outPayloadBufferCnt <= outPayloadBufferCnt + 1;
		end else begin
			pcieRespQ.enq(tuple2(r, outPayloadBuffer));
			outPayloadBufferCnt <= 0;
			if ( quadCnt == 7 ) quadCnt <= 0;
			else quadCnt <= quadCnt + 1;
		end
	endrule
endmodule
