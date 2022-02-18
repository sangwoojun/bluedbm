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
	Reg#(Bit#(1)) debuggingCnt_1 <- mkReg(0);
	Reg#(Bit#(4)) debuggingCnt_2 <- mkReg(0);

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
	// Send Payload
	//--------------------------------------------------------------------------------------------
	Reg#(Bit#(4)) qpIdx <- mkReg(0);

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
			qpIdx <= truncate(d);
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
		let qid = qpIdx[2];
		Bit#(2) pid = truncate(qpIdx);

		auroraQuads[qid].user[pid].send(d);
		inPayloadSendDone <= True;
	endrule
	//--------------------------------------------------------------------------------------
	// Receive Payload
	//--------------------------------------------------------------------------------------
	Vector#(8, FIFOF#(Bit#(32))) outputQv <- replicateM(mkFIFOF);

	for ( Integer qidx = 0; qidx < 2; qidx = qidx + 1 ) begin
		for ( Integer pidx = 0; pidx < 4; pidx = pidx + 1) begin
			Reg#(Maybe#(Bit#(32))) outputBufferUpper <- mkReg(tagged Invalid);
			rule recvPacket(inPayloadSendDone); 
				let qoff = qidx*4+pidx;
				if ( isValid(outputBufferUpper) ) begin
					outputBufferUpper <= tagged Invalid;
					outputQv[qoff].enq(fromMaybe(?,outputBufferUpper));
				end else begin
					let d <- auroraQuads[qidx].user[pidx].receive;
					outputBufferUpper <= tagged Valid truncate(d>>32);
					outputQv[qoff].enq(truncate(d));
				end
			endrule
		end
	end

	rule getAuroraStatus;
		pcieReadReqQ.deq;
		let r = pcieReadReqQ.first;
		Bit#(4) a = truncate(r.addr>>2);
		if ( a < 8 ) begin
			Bit#(1) qidx = truncate(a>>2);
			Bit#(2) pidx = truncate(a);
			if ( outputQv[a].notEmpty ) begin
				pcieRespQ.enq(tuple2(r, outputQv[a].first));
				outputQv[a].deq;
			end else begin
				pcieRespQ.enq(tuple2(r, 32'hffffffff));
			end
		end else begin
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
				end
				pcieRespQ.enq(tuple2(r, zeroExtend(debuggingBitsL[debuggingCnt_2])));
			end
		end
	endrule
endmodule
