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
	//PageSorterIfc#(Bit#(32),8,16) psort <- mkPageSorterV(False);
	
	/*
	SortingNetworkIfc#(Bit#(32), 8) sorter8_1 <- mkSortingNetwork8(False);
	SortingNetworkIfc#(Bit#(32), 8) sorter8_2 <- mkSortingNetwork8(False);
	LinearCongruentialIfc#(32) prng2 <- mkLinearCongruential;
	VectorDeserializerIfc#(8, Bit#(32)) vdes_1 <- mkVectorDeserializer;
	VectorDeserializerIfc#(8, Bit#(32)) vdes_2 <- mkVectorDeserializer;
	*/

	LinearCongruentialIfc#(64) prng64_0 <- mkLinearCongruential;
	LinearCongruentialIfc#(64) prng64_1 <- mkLinearCongruential;
	LinearCongruentialIfc#(64) prng64_2 <- mkLinearCongruential;
	LinearCongruentialIfc#(64) prng64_3 <- mkLinearCongruential;

	LinearCongruentialIfc#(32) prng1 <- mkLinearCongruential;
	VectorDeserializerIfc#(8, Bit#(32)) vdes <- mkVectorDeserializer;
	SortingNetworkIfc#(Bit#(32), 8) sorter8 <- mkSortingNetwork8(False);
	Reg#(Bit#(32)) vdcnt <- mkReg((256)*32);
	rule setCnt;
		let d = pciea.first;
		pciea.deq;

		Bit#(32) ctype = truncate(d>>(128-32));
		if ( ctype == 8 ) begin
			Bit#(32) c = truncate(d);
			$display("setting vdcnt to %d", c);
			vdcnt <= truncate(d);
		end else begin
			Bit#(32) d0 = truncate(d);
			Bit#(32) d1 = truncate(d>>32);
			Bit#(32) d2 = truncate(d>>(32*2));
			Bit#(32) d3 = truncate(d>>(32*3));
			prng64_0.seed(truncate(d));
			prng64_1.seed(truncate(d>>32));
			prng64_2.seed(truncate(d>>(32*2)));
			prng64_3.seed(truncate(d>>(32*3)));
			$display("seeded %d %d %d %d", d0, d1, d2, d3);
		end
	endrule

/*
	//Reg#(Bit#(32)) vdcnt <- mkReg(2048*8);
	rule vdcr (vdcnt >0);
		vdcnt <= vdcnt-1;
		let v <- prng1.next;
		vdes.enq(v);
		//$display("gen %x",v);
	endrule
	rule vdcg;
		vdes.deq;
		let v = vdes.first;
		sorter8.enq(v);
		//$display("vectorized %x ... ",v[0]);
	endrule
*/
	rule ssorter (vdcnt > 0);
		let v0 <- prng64_0.next;
		let v1 <- prng64_1.next;
		let v2 <- prng64_2.next;
		let v3 <- prng64_3.next;
		Vector#(8,Bit#(32)) sval;
		sval[0] = truncate(v0);
		sval[1] = truncate(v0>>32);
		sval[2] = truncate(v1);
		sval[3] = truncate(v1>>32);
		sval[4] = truncate(v2);
		sval[5] = truncate(v2>>32);
		sval[6] = truncate(v3);
		sval[7] = truncate(v3>>32);
		sorter8.enq(sval);
		vdcnt <= vdcnt-1;
	endrule

	Vector#(4, SortingNetworkIfc#(Bit#(32), 8)) sorters <- replicateM(mkSortingNetwork8(False));
	MultiPageSorterIfc#(4,Bit#(32),8,8) mpsorter <- mkMultiPageSorterCC(sorters, clk250, rst250,False);
	rule vget;
		let v <- sorter8.get;
		mpsorter.enq(v);
	endrule
	SortingNetworkIfc#(Bit#(32), 8) sorter8_ <- mkSortingNetwork8(False);
	rule psortres;
		let d <- mpsorter.get;
		sorter8_.enq(d);
		//vser.enq(d);
	endrule
	VectorSerializerIfc#(8,Bit#(32)) vser <- mkVectorSerializer;
	rule psortres2;
		let d <- sorter8_.get;
		vser.enq(d);
	endrule
	Reg#(Bit#(32)) deqcnt <- mkReg(0);
	Reg#(Bit#(32)) lastsrt <- mkReg(0);
	rule cmpres;
		let d = vser.first;
		vser.deq;
		if ( lastsrt > d ) begin
			$display( "unsorted @ %x -- %d %d", deqcnt, lastsrt, d );
		end
		lastsrt <= d;
		deqcnt <= deqcnt + 1;

		if ( deqcnt[7:0] == 0 ) begin
			pciea.write(32,deqcnt);
			//$display ( "sending deqcnt %d", deqcnt );
		end
	endrule

	
	Reg#(Bit#(32)) genCount <- mkReg(256*4);

	//PageSorterIfc#(Bit#(68), 3, 8) pageSorter <- mkPageSorter(False);
	//SortingNetworkIfc#(Bit#(68), 3) wordSorter <- mkSortingNetwork3(False);



	DRAMMultiFIFOIfc#(16, 1) drammfifo <- mkDRAMMultiFIFO(drama.users[0]);
	SortMergerIfc#(16,1,Bit#(68),3) smer <- mkSortMerger16(drammfifo.endpoints, drammfifo.sources, False);

endmodule

