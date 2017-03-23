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

	DRAMArbiterPageIfc#(4) drama <- mkDRAMArbiterPage(dram);
	PcieSharedBufferIfc#(8) pciea <- mkPcieSharedBuffer(pcie);
	DualFlashManagerIfc flashman <- mkDualFlashManager(flashes);

	Reg#(Bit#(32)) vdcnt <- mkReg((256)*32);
	Vector#(8, LinearCongruentialIfc#(32)) prng32 <- replicateM(mkLinearCongruential);


	LinearCongruentialIfc#(32) prng1 <- mkLinearCongruential;
	VectorDeserializerIfc#(8, Bit#(32)) vdes <- mkVectorDeserializer;
	SortingNetworkIfc#(Bit#(32), 8) sorter8 <- mkSortingNetwork8(False);

	rule ssorter (vdcnt > 0);
		Vector#(8,Bit#(32)) sval;
		for ( Integer i = 0; i < 8; i=i+1 ) begin
			sval[i] <- prng32[i].next;
		end

		sorter8.enq(sval);
		vdcnt <= vdcnt-1;
	endrule

	MultiPageSorterIfc#(12,Bit#(32),8,8) mpsorter <- mkMultiPageSorter(False);
	rule vget;
		let v <- sorter8.get;
		mpsorter.enq(v);
	endrule
	
	Reg#(Bit#(32)) cycleCount <- mkReg(0);
	rule countcycles;
		cycleCount <= cycleCount + 1;
	endrule

	Reg#(Bit#(32)) deqcnt <- mkReg(0);
	Reg#(Bit#(32)) lastsrt <- mkReg(0);
	rule psortres;
		let d_ <- mpsorter.get;
		Bit#(32) d = (d_[0]);
		if ( lastsrt > d ) begin
			$display( "unsorted @ %x -- %d %d", deqcnt, lastsrt, d );
		end
		lastsrt <= d;
		deqcnt <= deqcnt + 1;

		if ( deqcnt[10:0] == 0 ) begin
			pciea.write(32,deqcnt);
			$display ( "Count %d in %d", deqcnt, cycleCount );
		end
	endrule



	DRAMMultiFIFOIfc#(16, 1) drammfifo0 <- mkDRAMMultiFIFO(drama.users[0]);
	DRAMMultiFIFOIfc#(16, 1) drammfifo1 <- mkDRAMMultiFIFO(drama.users[1]);
	DRAMMultiFIFOIfc#(16, 1) drammfifo2 <- mkDRAMMultiFIFO(drama.users[2]);
	DRAMMultiFIFOIfc#(16, 1) drammfifo3 <- mkDRAMMultiFIFO(drama.users[3]);
	Vector#(16,DRAMMultiFIFOEpIfc) ep0 = drammfifo0.endpoints;
	Vector#(16,DRAMMultiFIFOEpIfc) ep1 = drammfifo1.endpoints;
	Vector#(16,DRAMMultiFIFOEpIfc) ep2 = drammfifo2.endpoints;
	Vector#(16,DRAMMultiFIFOEpIfc) ep3 = drammfifo3.endpoints;
	Vector#(1,DRAMMultiFIFOSrcIfc) sc0 = drammfifo0.sources;
	Vector#(1,DRAMMultiFIFOSrcIfc) sc1 = drammfifo1.sources;
	Vector#(1,DRAMMultiFIFOSrcIfc) sc2 = drammfifo2.sources;
	Vector#(1,DRAMMultiFIFOSrcIfc) sc3 = drammfifo3.sources;
	SortMergerIfc#(16,1,Bit#(32),8) smer0 <- mkSortMerger16(ep0,sc0, False);
	SortMergerIfc#(16,1,Bit#(32),8) smer1 <- mkSortMerger16(ep1,sc1, False);
	SortMergerIfc#(16,1,Bit#(32),8) smer2 <- mkSortMerger16(ep2,sc2, False);
	SortMergerIfc#(16,1,Bit#(32),8) smer3 <- mkSortMerger16(ep3,sc3, False);

	VectorDeserializerIfc#(16, Bit#(8)) vdes_mack <- mkVectorDeserializer;
	MergeNIfc#(4, Bit#(8)) mmack <- mkMergeN;
	rule ackmer;
		let v <- drammfifo0.ack;
		mmack.enq[0].enq(zeroExtend(v));
	endrule
	rule ackmer1;
		let v <- drammfifo1.ack;
		mmack.enq[1].enq(zeroExtend(v));
	endrule
	rule ackmer2;
		let v <- drammfifo2.ack;
		mmack.enq[2].enq(zeroExtend(v));
	endrule
	rule ackmer3;
		let v <- drammfifo3.ack;
		mmack.enq[3].enq(zeroExtend(v));
	endrule
	rule getmack;
		let v = mmack.first;
		mmack.deq;
		vdes_mack.enq(zeroExtend(v));
	endrule
	VectorPackerIfc#(16,Bit#(8),128) packer_mack <- mkVectorPacker;
	rule smack;
		packer_mack.enq(vdes_mack.first);
		vdes_mack.deq;
	endrule
	rule sendmack;
		pciea.enq(packer_mack.first);
		packer_mack.deq;
	endrule

	rule procCmd;
		let d = pciea.first;
		pciea.deq;

		Bit#(32) ctype = truncate(d>>(128-32));
		if ( ctype == 8 ) begin
			Bit#(32) c = truncate(d);
			$display("setting vdcnt to %d", c);
			vdcnt <= truncate(d);
			
		end else if ( ctype == 7 ) begin
			Bit#(4) mid = truncate(d>>64);
			let src = truncate(d>>32);
			let cnt = truncate(d);
			if ( mid == 0 ) begin
				smer0.cmdsrc(src,cnt);
			end else if (mid == 1) begin
				smer1.cmdsrc(src,cnt);
			end else if (mid == 2) begin
				smer2.cmdsrc(src,cnt);
			end else begin
				smer3.cmdsrc(src,cnt);
			end
		end else if ( ctype == 6 ) begin
			Bit#(32) addr = truncate(d>>64);
			Bit#(32) size = truncate(d>>32);
			Bit#(8) ds = truncate(d);
			Bit#(8) rw = truncate(d>>8);
			Bit#(8) did = truncate(d>>16);
			if ( rw == 0 ) begin
				if ( did == 0 ) begin
					drammfifo0.rcmd(zeroExtend(addr), size, truncate(ds));
				end else
				if ( did == 1 ) begin
					drammfifo1.rcmd(zeroExtend(addr), size, truncate(ds));
				end else
				if ( did == 2 ) begin
					drammfifo2.rcmd(zeroExtend(addr), size, truncate(ds));
				end else
				begin
					drammfifo3.rcmd(zeroExtend(addr), size, truncate(ds));
				end
			end else begin
				if ( did == 0 ) begin
					drammfifo0.wcmd(zeroExtend(addr), size, truncate(ds));
				end else
				if ( did == 1 ) begin
					drammfifo1.wcmd(zeroExtend(addr), size, truncate(ds));
				end else
				if ( did == 2 ) begin
					drammfifo2.wcmd(zeroExtend(addr), size, truncate(ds));
				end else
				begin
					drammfifo3.wcmd(zeroExtend(addr), size, truncate(ds));
				end
			end
		
		end else begin
			for ( Integer i = 0; i < 8; i=i+1 ) begin
				prng32[i].seed(truncate(d>>(i*16)));
			end
		end
	endrule

endmodule

