import FIFO::*;
import FIFOF::*;
import Clocks::*;
import Vector::*;

import BRAM::*;
import BRAMFIFO::*;

import MergeN::*;

import PcieCtrl::*;

import DMACircularQueue::*;

import AuroraImportFmc1::*;
import ControllerTypes::*;
import FlashCtrlVirtex1::*;
import FlashCtrlModel::*;
import DualFlashManager::*;

import DRAMController::*;
import DRAMArbiter::*;

import LinearCongruential::*;
import PageSorter::*;
import SortingNetwork::*;
import MergeSorter::*;

typedef 8 BusCount; // 8 per card in hw, 2 per card in sim
typedef TMul#(2,BusCount) BBusCount; //Board*bus
//typedef 64 TagCount; // Has to be larger than the software setting
typedef 4 DMAEngineCount;

typedef 3 AccelCount;
typedef TAdd#(AccelCount,1) DestCount; // 0 is always host DRAM

interface HwMainIfc;
endinterface

module mkHwMain#(PcieUserIfc pcie, Vector#(2,FlashCtrlUser) flashes, FlashManagerIfc flashMan, 
		DRAMUserIfc dram,
		Clock clk250,
		Reset rst250
	) 
	(HwMainIfc);

	Clock curClk <- exposeCurrentClock;
	Reset curRst <- exposeCurrentReset;

	Clock pcieclk = pcie.user_clk;
	Reset pcierst = pcie.user_rst;

	DRAMArbiterIfc#(2) drama <- mkDRAMArbiter(dram);
	DMACircularQueueIfc#(22) dma <- mkDMACircularQueue(pcie); // 4MB
	DualFlashManagerIfc flashman <- mkDualFlashManager(flashes);



	LinearCongruentialIfc#(34) prng1 <- mkLinearCongruential;
	LinearCongruentialIfc#(34) prng2 <- mkLinearCongruential;
	LinearCongruentialIfc#(34) prng3 <- mkLinearCongruential;
	LinearCongruentialIfc#(34) prng4 <- mkLinearCongruential;
	LinearCongruentialIfc#(34) prng5 <- mkLinearCongruential;
	LinearCongruentialIfc#(34) prng6 <- mkLinearCongruential;

	
	Reg#(Bit#(32)) genCount <- mkReg(256*4);

	PageSorterIfc#(Bit#(68), 3, 8) pageSorter <- mkPageSorter(False);
	SortingNetworkIfc#(Bit#(68), 3) wordSorter <- mkSortingNetwork3(False);

	rule genPage (genCount>0);
		genCount <= genCount - 1;
		Bit#(34) v1_ <- prng1.next;
		Bit#(34) v1__ <- prng2.next;

		Bit#(34) v2_ <- prng3.next;
		Bit#(34) v2__ <- prng4.next;
		Bit#(34) v3_ <- prng5.next;
		Bit#(34) v3__ <- prng6.next;

		Bit#(68) v1 = {v1_,v1__};
		Bit#(68) v2 = {0,v2_};
		Bit#(68) v3 = {v3_,0};

		Vector#(3,Bit#(68)) iv;
		iv[0] = v1;
		iv[1] = v2;
		iv[2] = v3;
		wordSorter.enq(iv);
		//pageSorter.enq(iv);
		//$display("--- %x %x %x", iv[0], iv[1], iv[2]);
	endrule
	rule sortPage;
		let iv <- wordSorter.get;
		pageSorter.enq(iv);
		//$display("+++ %x %x %x", iv[0], iv[1], iv[2]);
	endrule

	rule readSorted;
		let v <- pageSorter.get;
		//dma.enq({0,v[0],v[1],v[2]});
		$display( ">>> %x %x %x", v[0], v[1], v[2] );
	endrule


endmodule

