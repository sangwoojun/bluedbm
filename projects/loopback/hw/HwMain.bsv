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
import AuroraExtImport::*;
import AuroraExtImport117::*;

interface HwMainIfc;
endinterface

module mkHwMain#(PcieUserIfc pcie, DRAMUserIfc dram, Vector#(2,AuroraExtUserIfc) auroraExts) 
	(HwMainIfc);

	Clock curClk <- exposeCurrentClock;
	Reset curRst <- exposeCurrentReset;

	Clock pcieclk = pcie.user_clk;
	Reset pcierst = pcie.user_rst;

	Reg#(AuroraPacket) inputBuffer <- mkReg(0, clocked_by pcieclk, reset_by pcierst);
	SyncFIFOIfc#(AuroraPacket) inputPortQ <- mkSyncFIFOToCC(32, clocked_by pcieclk, reset_by pcierst);
	SyncFIFOIfc#(AuroraPacket) outputPortQ <- mkSyncFIFOToCC(32, clocked_by pcieclk, reset_by pcierest);

	rule recvWrite;
		let w <- pcie.dataReceive;
		let d = w.data;
		let a = w.addr;

		if ( a == 0 ) begin
			case ( d ) matches
				{ 0 } : begin 
					inputBuffer.src <= 0;
					inputBuffer.dst <= 1;
					end
				{ 1 } : begin
					inputBuffer.src <= 1;
					inputBuffer.dst <= 0;
					end
				{ 2 } : begin
					inputBuffer.src <= 2;
					inputBuffer.dst <= 4;
					end
				{ 3 } : begin
					inputBuffer.src <= 3;
					inputBuffer.dst <= 5;
					end
				{ 4 } : begin
					inputBuffer.src <= 4;
					inputBuffer.dst <= 2;
					end
				{ 5 } : begin
					inputBuffer.src <= 5;
					inputBuffer.dst <= 3;
					end
			endcase
		end else begin
			if (writeBufferCnt == 0 ) begin
				writeBuffer <= d;
				writeBufferCnt <= writeBufferCnt + 1;
			end else begin
				AuroraPacket inputBufferTemp = inputBuffer;
				Bit#(64) v = (writeBuffer<<32)|d;
				inputBufferTemp.payload = v;
				inputPortQ.enq(v);
				writeBufferCnt <= 0;
			end
		end
	endrule
	rule echoRead;
		let r <- pcie.dataReq;
		outputPortQ.deq;
		pcie.dataSend(tpl_1(r), outputPortQ.first);
	endrule
	rule relayInput;
		inputPortQ.deq;
		auroraExts[0].send(data);	
	endrule
	rule recvPacket;
		let d = auroraExts[1].receive;
		outputPortQ.enq(d);
	endrule
endmodule
