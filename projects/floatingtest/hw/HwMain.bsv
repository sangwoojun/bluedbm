import FIFO::*;
import FIFOF::*;
import Clocks::*;
import Vector::*;

import BRAM::*;
import BRAMFIFO::*;

import MergeN::*;

import PcieCtrl::*;
import PcieSharedBuffer::*;

//import DMACircularQueue::*;

import AuroraImportFmc1::*;
import ControllerTypes::*;
import FlashCtrlVirtex1::*;
import FlashCtrlModel::*;
import DualFlashManager::*;

import DRAMController::*;
import DRAMArbiter::*;

import Float32::*;

typedef 8 BusCount; // 8 per card in hw, 2 per card in sim
typedef TMul#(2,BusCount) BBusCount; //Board*bus
//typedef 64 TagCount; // Has to be larger than the software setting
typedef 4 DMAEngineCount;

typedef 3 AccelCount;
typedef TAdd#(AccelCount,1) DestCount; // 0 is always host DRAM

typedef 32 CoreCnt;

interface DistAccumIfc;
	method Action enq(Bit#(32) fa, Bit#(32) fb);
	method ActionValue#(Bit#(32)) res;
endinterface
module mkDistAccum (DistAccumIfc);
	FpPairIfc fp_mult32 <- mkFpMult32;
	FpPairIfc fp_add32 <- mkFpAdd32;
	FpPairIfc fp_sub32 <- mkFpSub32;
	
	Reg#(Bit#(32)) fpTotSum <- mkReg(0);
	
	rule trymult;
		fp_sub32.deq;
		let d = fp_sub32.first;
		fp_mult32.enq(d,d);
	endrule
	rule tryadd;
		fp_mult32.deq;
		let first = fp_mult32.first;
		fp_add32.enq(first, fpTotSum); // FIXME this is incorrect
	endrule

	method Action enq(Bit#(32) fa, Bit#(32) fb);
		fp_sub32.enq(fa, fb );
	endmethod
	method ActionValue#(Bit#(32)) res;
		fp_add32.deq;
		fpTotSum <= fp_add32.first;
		return fp_add32.first;
	endmethod
endmodule

interface HwMainIfc;
endinterface

module mkHwMain#(PcieUserIfc pcie, Vector#(2,FlashCtrlUser) flashes, 
		//FlashManagerIfc flashMan, 
		DRAMUserIfc dram,
		Clock clk250,
		Reset rst250
	) 
	(HwMainIfc);

	Clock curClk <- exposeCurrentClock;
	Reset curRst <- exposeCurrentReset;

	Clock pcieclk = pcie.user_clk;
	Reset pcierst = pcie.user_rst;

	PcieSharedBufferIfc#(12) pciebuf <- mkPcieSharedBuffer(pcie);

	DRAMArbiterIfc#(2) drama <- mkDRAMArbiter(dram);
	FpPairIfc fp_mult32 <- mkFpMult32;
	FpPairIfc fp_add32 <- mkFpAdd32;
	FpPairIfc fp_sub32 <- mkFpSub32;

	Reg#(Bit#(64)) cycles <- mkReg(0);
	rule cycleCount;
		cycles <= cycles + 1;
	endrule

	MergeNIfc#(CoreCnt, Tuple2#(Bit#(8),Bit#(32))) mcnt <- mkMergeN;

	Vector#(CoreCnt, DistAccumIfc) cDistAccum <- replicateM(mkDistAccum);
	for ( Integer i = 0; i < valueOf(CoreCnt); i=i+1) begin
		Reg#(Bit#(32)) emitCnt <- mkReg(0);
		rule injectCalc;
			if ( i == 0 ) begin
				cDistAccum[i].enq(32'h3e4ccccd, 32'h40a9999a);
			end else begin
				cDistAccum[i].enq(fromInteger(i)<<23, 32'h40a9999a);
			end
		endrule
		rule readout;
			let res <- cDistAccum[i].res;
			if ( emitCnt[7:0] == 0 ) begin
				//mcnt.enq[i].enq(tuple2(fromInteger(i), truncate(emitCnt)));
				mcnt.enq[i].enq(tuple2(fromInteger(i), res));
			end
			emitCnt <= emitCnt + 1;
		endrule
	end
	rule setDone;
		mcnt.deq;
		let d_ = mcnt.first;
		pciebuf.write(zeroExtend(tpl_1(d_)), tpl_2(d_));
		
	endrule
endmodule

