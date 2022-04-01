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
	FIFO#(AuroraIfcType) inputPortQ <- mkFIFO;

	Reg#(AuroraIfcType) inPayloadHalfFirst <- mkReg(0);
	Reg#(Bit#(4)) qpIdxIn <- mkReg(0);
	Reg#(Bit#(4)) qpIdxOut <- mkReg(0);
	Reg#(Bit#(2)) inPayloadBufferCnt <- mkReg(0);
	Reg#(Bool) setPortDone <- mkReg(False);

	rule getCmd;
		pcieWriteQ.deq;
		let w = pcieWriteQ.first;

		let d = w.data;
		let a = w.addr;

		if ( a == 0 ) begin // command
			case ( d )
				0: qpIdxOut <= 4'b0001;
				1: qpIdxOut <= 4'b0000;
				2: qpIdxOut <= 4'b0100;
				4: qpIdxOut <= 4'b0010;
			endcase
			qpIdxIn <= truncate(d);
			setPortDone <= True;
		end else begin
			if (inPayloadBufferCnt == 0 ) begin
				inPayloadHalfFirst <= zeroExtend(d);
				inPayloadBufferCnt <= inPayloadBufferCnt + 1;
			end else begin
				AuroraIfcType inPayloadHalfSecond = zeroExtend(d);
				AuroraIfcType inPayload = (inPayloadHalfSecond<<32)|(inPayloadHalfFirst);		
				inputPortQ.enq(inPayload);
				inPayloadBufferCnt <= 0;
			end
		end
	endrule
	//--------------------------------------------------------------------------------------------
	// Traffic Generator
	//--------------------------------------------------------------------------------------------
	Reg#(Bit#(16)) sendTrafficPacketTotal <- mkReg(0);
	Reg#(Bit#(32)) trafficPacket <-mkReg(32'hcccc0000);
		
	rule sendTrafficPacket( setPortDone && (sendTrafficPacketTotal < 1024) );
		let qidIn = qpIdxIn[2];
		Bit#(2) pidIn = truncate(qpIdxIn);
		AuroraIfcType packet = zeroExtend(trafficPacket);

		auroraQuads[qidIn].user[pidIn].send(packet);
		
		sendTrafficPacketTotal <= sendTrafficPacketTotal + 1;
		trafficPacket <= trafficPacket + 1;
		
	endrule	
	//--------------------------------------------------------------------------------------------
	// Validation Checker
	//--------------------------------------------------------------------------------------------
	FIFOF#(Bit#(32)) validCheckerQ <- mkSizedFIFOF(256);
	
	Reg#(Bit#(16)) recvTrafficPacketTotal <- mkReg(0);
	Reg#(Bit#(16)) recvTrafficPacketCnt <- mkReg(0);
	Reg#(Bit#(16)) validChecker <- mkReg(0);
	Reg#(Bit#(16)) validCheckBuffer <- mkReg(0);

	Reg#(Bool) stopTrafficGenerator <- mkReg(False);

	rule recvTrafficPacket( (recvTrafficPacketTotal < 1024) );
		let qidOut = qpIdxOut[2];
		Bit#(2) pidOut = truncate(qpIdxOut);
		let tp <- auroraQuads[qidOut].user[pidOut].receive;
		Bit#(16) d = truncate(tp);
		
		if ( recvTrafficPacketCnt + 1 == 512 ) begin
			recvTrafficPacketCnt <= 0;
			if ( validChecker == d ) begin
				Bit#(16) v = validCheckBuffer + 1;
				validCheckerQ.enq(zeroExtend(v));
				validCheckBuffer <= validCheckBuffer + 1;
			end else begin
				validCheckerQ.enq(zeroExtend(validCheckBuffer));
			end
			
			//stopTrafficGenerator <= True;
			if ( recvTrafficPacketTotal + 1 == 1024 ) begin
				stopTrafficGenerator <= True;
			end
		end else begin
			if ( validChecker == d ) begin
				validCheckBuffer <= validCheckBuffer + 1;
			end else begin
				validCheckBuffer <= validCheckBuffer + 0;
			end
			recvTrafficPacketCnt <= recvTrafficPacketCnt + 1;
		end

		recvTrafficPacketTotal <= recvTrafficPacketTotal + 1;
		validChecker <= validChecker + 1;
	endrule
	//--------------------------------------------------------------------------------------------
	// Send Payload
	//--------------------------------------------------------------------------------------------
	Reg#(Bool) inPayloadSendDone <- mkReg(False);

	rule relayPayload( setPortDone && stopTrafficGenerator );
		inputPortQ.deq;
		let d = inputPortQ.first;
		let qid = qpIdxIn[2];
		Bit#(2) pid = truncate(qpIdxIn);

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
			rule recvPacket( inPayloadSendDone ); 
				let qoffx = qidx*4+pidx;
				if ( isValid(outputBufferUpper) ) begin
					outputBufferUpper <= tagged Invalid;
					outputQv[qoffx].enq(fromMaybe(?,outputBufferUpper));
				end else begin
					let d <- auroraQuads[qidx].user[pidx].receive;
					outputBufferUpper <= tagged Valid truncate(d>>32);
					outputQv[qoffx].enq(truncate(d));
				end
			endrule
		end
	end

	rule getAuroraStatus;
		pcieReadReqQ.deq;
		let r = pcieReadReqQ.first;
		Bit#(4) a = truncate(r.addr>>2);
		if ( a < 8 ) begin
			if ( inPayloadSendDone ) begin
				if ( outputQv[a].notEmpty ) begin
					pcieRespQ.enq(tuple2(r, outputQv[a].first));
					outputQv[a].deq;
				end else begin
					pcieRespQ.enq(tuple2(r, 32'hffffffff));
				end
			end else begin
				if ( validCheckerQ.notEmpty ) begin
					pcieRespQ.enq(tuple2(r, validCheckerQ.first));
					validCheckerQ.deq;
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
