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

module mkHwMain#(PcieUserIfc pcie, DRAMUserIfc dram, auroraQuad117, auroraQuad119) (HwMainIfc);

	Clock curClk <- exposeCurrentClock;
	Reset curRst <- exposeCurrentReset;

	Clock pcieclk = pcie.user_clk;
	Reset pcierst = pcie.user_rst;

	SyncFIFOIfc#(AuroraIfcType) inputPortQ <- mkSyncFIFOToCC(32, clocked_by pcieclk, reset_by pcierst);
	SyncFIFOIfc#(AuroraIfcType) outputPortQ <- mkSyncFIFOToCC(32, clocked_by pcieclk, reset_by pcierest);

	Reg#(AuroraIfcType) inPayloadBuffer <- mkReg(0);
	Reg#(Bit#(1)) inQuad <- mkReg(0);
	Reg#(Bit#(3)) inPort <- mkReg(0);
	Reg#(Bit#(1)) outQuad <- mkReg(0);
	Reg#(Bit#(3)) outPort <- mkReg(0);
	Reg#(Bit#(1)) inPayloadBufferCnt <- mkReg(0);
	rule recvWrite;
		let w <- pcie.dataReceive;
		let d = w.data;
		let a = w.addr;

		if ( a == 0 ) begin
			case ( d ) matches
				{ 0 } : begin 
					inQuad <= 0;;
					inPort <= 0;
					outQuad <= 0;
					outPort <= 1;
					end
				{ 1 } : begin
					inQuad <= 0;
					inPort <= 1;
					outQuad <= 0;
					outPort <= 0;
					end
				{ 2 } : begin
					inQuad <= 0;
					inPort <= 2;
					outQuad <= 1;
					outPort <= 0;
					end
				{ 3 } : begin
					inQuad <= 0;
					inPort <= 3;
					outQuad <= 1;
					outPort <= 1;
					end
				{ 4 } : begin
					inQuad <= 1;
					inPort <= 0;
					outQuad <= 0;
					outPort <= 2;
					end
				{ 5 } : begin
					inQuad <= 1;
					inPort <= 1;
					outQuad <= 0;
					outPort <= 3;
					end
			endcase
		end else begin
			if (inPacketBufferCnt == 0 ) begin
				inPayloadBuffer <= zeroExtend(d);
				inPayloadBufferCnt <= inPayloadBufferCnt + 1;
			end else begin
				AuroraIfcType inPayload = (inPayloadBuffer<<32)|zeroExtend(d);		
				inputPortQ.enq(inPayload);
				inPayloadBufferCnt <= 0;
			end
		end
	endrule
	
	rule relayInput;
		inputPortQ.deq;
		let d = inputPortQ.first;
		auroraQuad[inQuad].user[inPort].send(d);
	endrule
	
	rule recvPacket;
		let d <- auroraQuad[outQuad].user[outPort].receive;
		outputPortQ.enq(d);
	endrule

	rule echoRead;
		let r <- pcie.dataReq;
		outputPortQ.deq;
		pcie.dataSend(tpl_1(r), outputPortQ.first);
	endrule
	
endmodule
