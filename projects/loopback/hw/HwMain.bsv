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

	SyncFIFOIfc#(AuroraIfcType) inputPortQ <- mkSyncFIFOToCC(32, pcieclk, pcierst);
	SyncFIFOIfc#(AuroraIfcType) outputPortQ <- mkSyncFIFOToCC(32, pcieclk, pcierst);

	Reg#(AuroraIfcType) inPayloadBuffer <- mkReg(0);
	Reg#(Bit#(32)) outPayloadBuffer <- mkReg(0);
	Reg#(Bit#(1)) inQuad <- mkReg(0);
	Reg#(Bit#(3)) inPort <- mkReg(0);
	Reg#(Bit#(1)) outQuad <- mkReg(0);
	Reg#(Bit#(3)) outPort <- mkReg(0);
	Reg#(Bit#(1)) inPayloadBufferCnt <- mkReg(0);
	Reg#(Bit#(1)) outPayloadBufferCnt <- mkReg(0);
	
	rule recvWrite;
		let w <- pcie.dataReceive;
		let d = w.data;
		let a = w.addr;
		$display( "Data received: %x", d );
		if ( a == 0 ) begin
			case ( d ) matches
				{ 0 } : begin 
					inQuad <= 0;
					inPort <= 0;
					outQuad <= 0;
					outPort <= 1;
					$display( "Designating port done!" );
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
			if (inPayloadBufferCnt == 0 ) begin
				inPayloadBuffer <= zeroExtend(d);
				inPayloadBufferCnt <= inPayloadBufferCnt + 1;
			end else begin
				AuroraIfcType inPayload = (inPayloadBuffer<<32)|zeroExtend(d);		
				inputPortQ.enq(inPayload);
				inPayloadBufferCnt <= 0;
				$display( "Enqing data: %x", inPayload );
			end
		end
	endrule
	
	rule relayInput;
		inputPortQ.deq;
		let d = inputPortQ.first;
		auroraQuads[inQuad].user[inPort].send(d);
	endrule
	
	rule recvPacket;
		let d <- auroraQuads[inQuad].user[inPort].receive;
		outputPortQ.enq(d);
		$display( "Received data: %x", d );
	endrule

	rule echoRead;
		let r <- pcie.dataReq;
		let a = r.addr;
		if (outPayloadBufferCnt == 0 ) begin
			outputPortQ.deq;
			let d = outputPortQ.first;
			pcie.dataSend(r, truncate(d));
			outPayloadBuffer <= truncate(outputPortQ.first>>32);
			outPayloadBufferCnt <= outPayloadBufferCnt + 1;
		end else begin
			pcie.dataSend(r, outPayloadBuffer);
		end
	endrule
	
endmodule
