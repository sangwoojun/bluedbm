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
import DRAMArbiterPage::*;

import LinearCongruential::*;
import PageSorter::*;
import SortingNetwork::*;
import SortingNetwork8::*;

import DRAMMultiFIFO::*;
import SortMerger::*;

import VectorPacker::*;

typedef 8 BusCount; // 8 per card in hw, 2 per card in sim
typedef TMul#(2,BusCount) BBusCount; //Board*bus
//typedef 64 TagCount; // Has to be larger than the software setting

interface HwMainIfc;
endinterface

module mkHwMain#(PcieUserIfc pcie, Vector#(2,FlashCtrlUser) flashes
	//, FlashManagerIfc flashMan, 
		, DRAMUserIfc dram
		, Clock clk250 
		, Reset rst250
	) 
	(HwMainIfc);

	Clock curClk <- exposeCurrentClock;
	Reset curRst <- exposeCurrentReset;

	Clock pcieclk = pcie.user_clk;
	Reset pcierst = pcie.user_rst;

	DRAMArbiterPageIfc#(2) drama <- mkDRAMArbiterPage(dram);
	//DMACircularQueueIfc#(22) dma <- mkDMACircularQueue(pcie); // 4MB
	PcieSharedBufferIfc#(19) pciea <- mkPcieSharedBuffer(pcie);
	DualFlashManagerIfc flashman <- mkDualFlashManager(flashes);


	LinearCongruentialIfc#(32) prng1 <- mkLinearCongruential;
	VectorDeserializerIfc#(8, Bit#(32)) vdes <- mkVectorDeserializer;
	SortingNetworkIfc#(Bit#(32), 8) sorter8 <- mkSortingNetwork8(False);
	Reg#(Bit#(8)) vdcnt <- mkReg(128);
	rule vdcr (vdcnt >0);
		vdcnt <= vdcnt-1;
		let v <- prng1.next;
		vdes.enq(v);
		$display("gen %x",v);
	endrule
	rule vdcg;
		vdes.deq;
		let v = vdes.first;
		sorter8.enq(v);
		$display("vectorized %x ... ",v[0]);
	endrule
	rule vget;
		let v <- sorter8.get;
		$display( ">>>\n%d\n%d\n%d\n%d\n%d\n%d\n%d\n%d",
			v[0],
			v[1],
			v[2],
			v[3],
			v[4],
			v[5],
			v[6],
			v[7]
		);
	endrule

	
	Reg#(Bit#(32)) genCount <- mkReg(256*4);

	PageSorterIfc#(Bit#(68), 3, 8) pageSorter <- mkPageSorter(False);
	SortingNetworkIfc#(Bit#(68), 3) wordSorter <- mkSortingNetwork3(False);



	DRAMMultiFIFOIfc#(16, 1) drammfifo <- mkDRAMMultiFIFO(drama.users[0]);
	SortMergerIfc#(16,1,Bit#(68),3) smer <- mkSortMerger16(drammfifo.endpoints, drammfifo.sources, False);

endmodule

