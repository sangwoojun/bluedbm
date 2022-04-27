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

	Reg#(Maybe#(AuroraIfcType)) inPayloadFirstHalf1 <- mkReg(tagged Invalid);
	Reg#(Maybe#(AuroraIfcType)) inPayloadSecondHalf1 <- mkReg(tagged Invalid);
	Reg#(Maybe#(AuroraIfcType)) inPayloadFirst <- mkReg(tagged Invalid);
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
			if ( isValid(inPayloadFirst) ) begin
				if ( isValid(inPayloadSecondHalf1) ) begin
					let p = fromMaybe(?, inPayloadSecondHalf1);
					let v = fromMaybe(?, inPayloadFirst);
					AuroraIfcType inPayloadSecondHalf2 = zeroExtend(d);
					AuroraIfcType inPayloadSecond = (inPayloadSecondHalf2<<32)|(p);
					AuroraIfcType inPayload = (inPayloadSecond<<64)|(v);
					inputPortQ.enq(inPayload);

					inPayloadFirst <= tagged Invalid;
					inPayloadSecondHalf1 <= tagged Invalid;
				end else begin
					inPayloadSecondHalf1 <= tagged Valid zeroExtend(d);
				end
			end else begin
				if ( isValid(inPayloadFirstHalf1) ) begin
					let p = fromMaybe(?, inPayloadFirstHalf1);
					AuroraIfcType inPayloadFirstHalf2 = zeroExtend(d);
					AuroraIfcType v = (inPayloadFirstHalf2<<32)|(p);
					inPayloadFirst <= tagged Valid v;
					
					inPayloadFirstHalf1 <= tagged Invalid;
				end else begin
					inPayloadFirstHalf1 <= tagged Valid zeroExtend(d);
				end
			end
		end
	endrule
	//--------------------------------------------------------------------------------------------
	// Traffic Generator
	//--------------------------------------------------------------------------------------------
	Integer trafficPacketTotal = 3*1024;
	Reg#(Bit#(32)) sendTrafficPacketTotal <- mkReg(0);
	Reg#(AuroraIfcType) trafficPacket <- mkReg(128'hcccccccc000000000000000000000000);
		
	rule sendTrafficPacket( setPortDone && (sendTrafficPacketTotal < fromInteger(trafficPacketTotal)) );
		let qidIn = qpIdxIn[2];
		Bit#(2) pidIn = truncate(qpIdxIn);

		auroraQuads[qidIn].user[pidIn].send(trafficPacket);
		
		trafficPacket <= trafficPacket + 1;
		sendTrafficPacketTotal <= sendTrafficPacketTotal + 1;
	endrule	
	//--------------------------------------------------------------------------------------------
	// Validation Checker
	//--------------------------------------------------------------------------------------------
	FIFOF#(Bit#(32)) validCheckerQ <- mkFIFOF;
	
	Reg#(Bit#(32)) recvTrafficPacketTotal <- mkReg(0);
	Reg#(Bit#(32)) validChecker <- mkReg(0);
	Reg#(Bit#(32)) validCheckBuffer <- mkReg(0);

	Reg#(Bool) stopTrafficGenerator <- mkReg(False);

	rule recvTrafficPacket( !stopTrafficGenerator );
		let qidOut = qpIdxOut[2];
		Bit#(2) pidOut = truncate(qpIdxOut);
		let tp <- auroraQuads[qidOut].user[pidOut].receive;
		Bit#(32) d = truncate(tp);
		
		if ( recvTrafficPacketTotal + 1 == fromInteger(trafficPacketTotal) ) begin
			if ( validChecker == d ) begin
				if ( validCheckBuffer + 1 == fromInteger(trafficPacketTotal) ) begin
					validCheckerQ.enq(1);
				end else begin
					validCheckerQ.enq(0);
				end
			end else begin
				validCheckerQ.enq(0);
			end
			stopTrafficGenerator <= True;
		end else begin
			if ( validChecker == d ) begin
				validCheckBuffer <= validCheckBuffer + 1;
			end else begin
				validCheckBuffer <= validCheckBuffer + 0;
			end
			recvTrafficPacketTotal <= recvTrafficPacketTotal + 1;
			validChecker <= validChecker + 1;
		end
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
	FIFOF#(Bit#(32)) outputQ <- mkFIFOF;

	Reg#(Maybe#(Bit#(96))) outputBufferUpper1 <- mkReg(tagged Invalid);
	Reg#(Maybe#(Bit#(64))) outputBufferUpper2 <- mkReg(tagged Invalid);
	Reg#(Maybe#(Bit#(32))) outputBufferUpper3 <- mkReg(tagged Invalid);
	rule recvPacket( inPayloadSendDone && stopTrafficGenerator ); 
		let qidOut = qpIdxOut[2];
		Bit#(2) pidOut = truncate(qpIdxOut);

		if ( isValid(outputBufferUpper1) ) begin
			if ( isValid(outputBufferUpper2) ) begin
				if ( isValid(outputBufferUpper3) ) begin
					let d = fromMaybe(?, outputBufferUpper3);
					outputQ.enq(d);
					outputBufferUpper1 <= tagged Invalid;
					outputBufferUpper2 <= tagged Invalid;
					outputBufferUpper3 <= tagged Invalid;
				end else begin
					let d = fromMaybe(?, outputBufferUpper2);
					outputBufferUpper3 <= tagged Valid truncate(d>>32);
					outputQ.enq(truncate(d));
				end
			end else begin
				let d = fromMaybe(?, outputBufferUpper1);
				outputBufferUpper2 <= tagged Valid truncate(d>>32);
				outputQ.enq(truncate(d));
			end
		end else begin
			let d <- auroraQuads[qidOut].user[pidOut].receive;
			outputBufferUpper1 <= tagged Valid truncate(d>>32);
			outputQ.enq(truncate(d));
		end
	endrule

	rule getAuroraStatus;
		pcieReadReqQ.deq;
		let r = pcieReadReqQ.first;
		Bit#(4) a = truncate(r.addr>>2);
		if ( a < 8 ) begin
			if ( inPayloadSendDone ) begin
				if ( outputQ.notEmpty ) begin
					pcieRespQ.enq(tuple2(r, outputQ.first));
					outputQ.deq;
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
