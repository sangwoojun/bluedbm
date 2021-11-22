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

	Reg#(Bit#(1)) inQuad <- mkReg(0);
	Reg#(Bit#(3)) inPort <- mkReg(0);
	Reg#(Bit#(1)) outQuad <- mkReg(0);
	Reg#(Bit#(3)) outPort <- mkReg(0);
	//--------------------------------------------------------------------------------------------
	//Write Request
	//--------------------------------------------------------------------------------------------
	SyncFIFOIfc#(IOWrite) pcieWriteQ <- mkSyncFIFOToCC(16, pcieclk, pcierst);
	FIFO#(AuroraIfcType) inputPortQ <- mkFIFO;
	Reg#(AuroraIfcType) inPayloadBuffer <- mkReg(0);
	Reg#(Bit#(1)) inPayloadBufferCnt <- mkReg(0);
	rule getWriteReq;
		let w <- pcie.dataReceive;
		pcieWriteQ.enq(w);
	endrule
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
		auroraQuads[inQuad].user[inPort].send(d);
	endrule
	//--------------------------------------------------------------------------------------
	//Read Request
	//--------------------------------------------------------------------------------------
	SyncFIFOIfc#(Tuple2#(IOReadReq, Bit#(32))) pcieRespQ <- mkSyncFIFOFromCC(16, pcieclk);
	SyncFIFOIfc#(IOReadReq) pcieReadReqQ <- mkSyncFIFOToCC(16, pcieclk, pcierst);
	FIFO#(AuroraIfcType) outputPortQ <- mkFIFO;
	Reg#(Bit#(32)) outPayloadBuffer <- mkReg(0);
	Reg#(Bit#(1)) outPayloadBufferCnt <- mkReg(0);
	rule getPacket;
		let d <- auroraQuads[inQuad].user[inPort].receive;
		outputPortQ.enq(d);
	endrule
	rule getReadReq;
		let r <- pcie.dataReq;
		pcieReadReqQ.enq(r);
	endrule
	rule getReadStat;
		pcieReadReqQ.deq;
		let r = pcieReadReqQ.first;

		let a = r.addr;
		if (outPayloadBufferCnt == 0 ) begin
			outputPortQ.deq;
			let d = outputPortQ.first;
			pcieRespQ.enq(tuple2(r, truncate(d)));
			outPayloadBuffer <= truncate(outputPortQ.first>>32);
			outPayloadBufferCnt <= outPayloadBufferCnt + 1;
		end else begin
			pcieRespQ.enq(tuple2(r, outPayloadBuffer));
			outPayloadBufferCnt <= 0;
		end
	endrule
	rule returnReadResp;
		let r_ = pcieRespQ.first;
		pcieRespQ.deq;

		pcie.dataSend(tpl_1(r_), tpl_2(r_));
	endrule
endmodule
