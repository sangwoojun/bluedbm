package DualFlashManagerBurst;

import FIFO::*;
import FIFOF::*;
import Clocks::*;
import Vector::*;

import BRAM::*;
import BRAMFIFO::*;

import ControllerTypes::*;
import FlashCtrlVirtex1::*;

import MergeN::*;
import Serializer::*;

import Assert::*;

typedef Bit#(32) FlashAddress;
typedef Bit#(256) FlashWord;
typedef Tuple2#(FlashWord,Bit#(8)) FlashTaggedWord;
typedef struct {
	FlashOp op;

	TagT tag; // may have duplicates across cards
	
	Bit#(1) card;
	BusT bus; // NUM_BUSES = 8 for MLC, 2 for BSIM
	ChipT chip; // ChipsPerBus = 8 for MLC and BSIM
	Bit#(16) block;
	Bit#(8) page;
} FlashManagerCmd deriving (Bits, Eq);


function FlashManagerCmd decodeCommand(FlashAddress addr, FlashOp op);
	return FlashManagerCmd {
		op: op,

		tag: 0, // must be configured separately

		// Complete reverse order for parallelism
		// total 23 + 8 = 31 bits for MLC
		page: truncate(addr>>(1+16 + valueOf(TLog#(NUM_BUSES))+valueOf(TLog#(ChipsPerBus)))), // 7 + 16 = 23 for MLC
		block: truncate(addr>>(1+valueOf(TLog#(NUM_BUSES))+valueOf(TLog#(ChipsPerBus)))), // 1+3+3 = 7 for MLC
		chip: truncate(addr>>(1+valueOf(TLog#(NUM_BUSES)))), // 1+3 = 4 for MLC
		bus: truncate(addr>>1),
		card: truncate(addr)
	};
endfunction

typedef enum {
	STATE_NULL,
	STATE_WRITE_READY,
	STATE_WRITE_DONE,
	STATE_ERASE_DONE,
	STATE_ERASE_FAIL
} FlashStatusCode deriving (Bits, Eq);

typedef struct {
	FlashStatusCode code;
	Bit#(8) tag;
} FlashStatus deriving (Bits, Eq);



interface DualFlashManagerBurstIfc;
	method Action readPage(Bit#(8) tag, FlashAddress page);
	method Action writePage(Bit#(8) tag, FlashAddress page);
	method Action eraseBlock(Bit#(8) tag, FlashAddress block);
	method ActionValue#(FlashStatus) fevent;
	method ActionValue#(FlashTaggedWord) readWord;
	method Action writeWord(Bit#(8) tag, FlashWord data);


	//TODO decode block mapping req
endinterface

// burstBytes MUST be multiples of 256 bits (32 bytes)
module mkDualFlashManagerBurst#(Vector#(2,FlashCtrlUser) flashes, Integer burstBytes) (DualFlashManagerBurstIfc);
	staticAssert(burstBytes%32==0, "burstBytes in mkDualFlashManagerBurst must be multiples of 32 bytes (256 bits)");
	Integer burstWords = burstBytes/32;

	FIFO#(Tuple2#(Bit#(8), FlashManagerCmd)) flashCmdQ <- mkFIFO;
	FIFO#(FlashManagerCmd) flashCmdUpdatedTagQ <- mkFIFO;
	Vector#(2, FIFO#(TagT)) freeCardTagsQ <- replicateM(mkSizedFIFO(128));
	Reg#(Bit#(8)) freeTagPopCounter <- mkReg(0);
	rule populateFreeTags( freeTagPopCounter < 128 );
		freeTagPopCounter <= freeTagPopCounter + 1;
		freeCardTagsQ[0].enq(truncate(freeTagPopCounter));
		freeCardTagsQ[1].enq(truncate(freeTagPopCounter));
	endrule

	Vector#(2, BRAM2Port#(TagT, Tuple2#(Bit#(8),BusT))) tagMap <- replicateM(mkBRAM2Server(defaultValue)); // 128B


	//////////////////////////////////////////////////////////////////////
	/////*********** Start Flash Command Issue //////////*/

	rule getFreeCardTag;
		flashCmdQ.deq;
		let cmd_ = flashCmdQ.first;
		let tag = tpl_1(cmd_);
		let cmd = tpl_2(cmd_);
		let c = cmd.card;

		TagT newtag = freeCardTagsQ[c].first;
		freeCardTagsQ[c].deq;

		tagMap[c].portA.request.put(
			BRAMRequest{
			write:True,
			responseOnWrite:False,
			address:newtag,
			datain:tuple2(tag,cmd.bus)
			}
		);
		cmd.tag = newtag;

		flashCmdUpdatedTagQ.enq(cmd);
	endrule

	rule forwardFlashCmd;
		let cmd = flashCmdUpdatedTagQ.first;
		flashCmdUpdatedTagQ.deq;

		flashes[cmd.card].sendCmd( FlashCmd{
			tag: cmd.tag,
			op: cmd.op,
			bus: cmd.bus,
			chip: cmd.chip,
			block: cmd.block,
			page: cmd.page
		});
	endrule

	//////*/////////////////// End Flash Command Issue //////////////////*/
	//////////////////////////////////////////////////////////////////////
	
	//////////////////////////////////////////////////////////////////////
	/*********** Start Flash Read / Burst reorder //////////*/

	//Burst merger
	BurstMergeNIfc#(TMul#(NUM_BUSES, 2), FlashTaggedWord, 12) burstorder <- mkBurstMergeN;
	FIFO#(FlashTaggedWord) wordOutQ <- mkFIFO;
	rule relayBurstReadData;
		burstorder.deq;
		wordOutQ.enq(burstorder.first);
	endrule
	rule ignoreBurst;
		let b <- burstorder.getBurst;
	endrule

	for (Integer cidx = 0; cidx < 2; cidx = cidx + 1) begin
		Vector#(NUM_BUSES, FIFO#(Tuple2#(Bit#(128),Bit#(8)))) busOrderQ <- replicateM(mkFIFO);

		FIFO#(Bit#(128)) readDataQ <- mkSizedFIFO(4);
		rule getRead;
			let taggedRdata <- flashes[cidx].readWord();
			Bit#(128) data = tpl_1(taggedRdata);
			TagT tag = tpl_2(taggedRdata);

			tagMap[cidx].portB.request.put( BRAMRequest{
				write:False, responseOnWrite:False,
				address: tag,
				datain:?
				});

			readDataQ.enq(data);
		endrule
		rule scatterBus;
			let d <- tagMap[cidx].portB.response.get;
			let otag = tpl_1(d);
			let bus = tpl_2(d);

			let data = readDataQ.first;
			readDataQ.deq;

			busOrderQ[bus].enq(tuple2(data, otag));
		endrule

		for (Integer bidx = 0; bidx < valueOf(NUM_BUSES); bidx = bidx + 1) begin
			//TODO if burst is large (KBs), should use BRAMFIFO
			FIFO#(FlashTaggedWord) busBurstQ <- mkSizedFIFO((burstBytes/32)+1);
			DeSerializerIfc#(128, 2) desword <- mkDeSerializer;
			FIFO#(Bit#(8)) skiptag <- mkStreamSkip(2,1); // of every two elements, take only idx 1
			rule deserialize;
				busOrderQ[bidx].deq;
				let d = busOrderQ[bidx].first;

				desword.put(tpl_1(d));
				skiptag.enq(tpl_2(d));
			endrule

			//TODO assert less than 12
			Reg#(Bit#(12)) burstReadyUp <- mkReg(0);
			Reg#(Bit#(12)) burstReadyDown <- mkReg(0);
			Reg#(Bit#(16)) readWordCnt <- mkReg(0); // Used to ignore 32 bytes at the end of each page
			rule enqBurst1;
				let w <- desword.get;
				let t = skiptag.first;
				skiptag.deq;

				if ( readWordCnt < (8192/32) ) begin
					busBurstQ.enq(tuple2(w,t));
					burstReadyUp <= burstReadyUp + 1;
					// If enough data pushed in buffer, start burst
					if ( burstReadyUp-burstReadyDown+1 >= fromInteger(burstWords) ) begin
						burstReadyDown <= burstReadyDown + fromInteger(burstWords);
						burstorder.enq[cidx*valueOf(NUM_BUSES)+bidx].burst(fromInteger(burstWords));
					end
					readWordCnt <= readWordCnt + 1;
				end else if ( readWordCnt +1 < (8224/32) ) begin
					readWordCnt <= readWordCnt + 1;
					$display( "Ignoring end bytes per page" );
				end else begin
					$display( "Ignoring end bytes per page" );
					readWordCnt <= 0;
				end
				
			endrule
			rule relayBurstData;
				busBurstQ.deq;
				burstorder.enq[cidx*valueOf(NUM_BUSES)+bidx].enq(busBurstQ.first);
			endrule
		end
	end
	////////*///////////////// End Flash Read / Burst reorder //////////*/
	//////////////////////////////////////////////////////////////////////


	
	/*
	for (Integer cidx = 0; cidx < 2; cidx = cidx + 1) begin
		//for (Integer bidx = 0; bidx < valueOf(NUM_BUSES); bidx = bidx + 1) begin
		//end

		rule getWriteReq;
			TagT tag <- flashes[cidx].writeDataReq;
			//flashes[cwt].writeWord(tuple2(wd,0));
		endrule
		rule getAck;
			let status <- flashes[cidx].ackStatus;
		endrule
	end
	*/



	method Action readPage(Bit#(8) tag, FlashAddress page);
		flashCmdQ.enq(tuple2(tag, decodeCommand(page, READ_PAGE)));
	endmethod
	method Action writePage(Bit#(8) tag, FlashAddress page);
		flashCmdQ.enq(tuple2(tag, decodeCommand(page, WRITE_PAGE)));
	endmethod
	method Action eraseBlock(Bit#(8) tag, FlashAddress block);
		flashCmdQ.enq(tuple2(tag, decodeCommand(block, ERASE_BLOCK)));
	endmethod
	method ActionValue#(FlashStatus) fevent;
		return ?;
	endmethod
	method ActionValue#(FlashTaggedWord) readWord;
		wordOutQ.deq;
		return wordOutQ.first;
	endmethod
	method Action writeWord(Bit#(8) tag, FlashWord data);
	endmethod
endmodule

endpackage: DualFlashManagerBurst
