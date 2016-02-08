import FIFOF		::*;
import FIFO		::*;
import Vector		::*;
import Connectable ::*;
import RegFile::*;
import BRAMFIFO::*;

import ControllerTypes::*;
import NandPhyWrapper::*;
import NandInfraWrapper::*;
import NandPhy::*;
import BusController::*;
import NandPhyWenNclkWrapper::*;
import ChipscopeWrapper::*;

typedef enum {
	INIT = 0,
	INIT_WAIT = 1,
	ACCEPT_CMD = 2
} CtrlState deriving (Bits, Eq);


interface FlashCtrlPins;
	(* prefix = "B_SHARED" *)
	interface Vector#(NUM_CHIPBUSES, NANDWenNclk) nandBusShared;
	(* prefix = "B" *)
	interface Vector#(NUM_CHIPBUSES, Vector#(BUSES_PER_CHIPBUS, NANDPins)) nandBus;
endinterface

//Defined in ControllerTypes.bsv
/*
interface FlashCtrlUser;
	method Action sendCmd (FlashCmd cmd);
	method Action writeWord (Bit#(128) data, TagT tag);
	method ActionValue#(Tuple2#(Bit#(128), TagT)) readWord (); 
	method ActionValue#(TagT) writeDataReq(); 
	method ActionValue#(Tuple2#(TagT, StatusT)) ackStatus (); 
endinterface
*/

interface FlashCtrlInfra;
	interface Clock sysclk0;
	interface Reset sysrst0;
endinterface

interface DebugIlaPartial;
	method Action debugPort4(Bit#(16) d);
	method Action debugPort5_64(Bit#(64) d);
	method Action debugPort6_64(Bit#(64) d);
endinterface

(* always_enabled *)
interface FlashCtrlDebug;
	interface Vector#(NUM_BUSES, DebugIlaPartial) debugBus;
	interface DebugVIO debugVio;
endinterface

interface FlashControllerIfc;
	interface FlashCtrlPins pins;
	interface FlashCtrlUser user;
	interface FlashCtrlInfra infra;
	interface FlashCtrlDebug debug;
endinterface


(* no_default_clock, no_default_reset *)
(*synthesize*)
module mkFlashController#(
	Clock sysClkP,
	Clock sysClkN,
	Reset sysRstn
	)(FlashControllerIfc);

	//Controller Infrastructure (clock, reset)
	VNandInfra nandInfra <- vMkNandInfra(sysClkP, sysClkN, sysRstn);

	Clock clk0 = nandInfra.clk0;
	Reset rst0 = nandInfra.rst0;

	//chipscope debug
	CSDebugIfc csDebug <- mkChipscopeDebug(clocked_by clk0, reset_by rst0);
	//Vectorize
	Vector#(NUM_DEBUG_ILAS, DebugILA) csDebugIla = newVector(); //8
	csDebugIla[0] = csDebug.ila0;
	csDebugIla[1] = csDebug.ila1;
	csDebugIla[2] = csDebug.ila2;
	csDebugIla[3] = csDebug.ila3;
	csDebugIla[4] = csDebug.ila4;
	csDebugIla[5] = csDebug.ila5;
	csDebugIla[6] = csDebug.ila6;
	csDebugIla[7] = csDebug.ila7;

	for (Integer i=valueOf(NUM_BUSES); i < valueOf(NUM_DEBUG_ILAS); i=i+1) begin
		rule setILAZero;
			csDebugIla[i].setDebug0(0);
			csDebugIla[i].setDebug1(0);
			csDebugIla[i].setDebug2(0);
			csDebugIla[i].setDebug3(0);
			csDebugIla[i].setDebug4(0);
			csDebugIla[i].setDebug5_64(0);
			csDebugIla[i].setDebug6_64(0);
		endrule
	end

	//Nand WEN/NandClk (because of weird organization, this module is
	// shared among half buses)
	Vector#(NUM_CHIPBUSES, VNANDPhyWenNclk) busWenNclk <- replicateM(vMkNandPhyWenNclk(clk0, rst0));

	//Bus controllers.
	Vector#(NUM_BUSES, BusControllerIfc) busCtrl = newVector();
	for (Integer i=0; i<valueOf(NUM_BUSES); i=i+1) begin
		busCtrl[i] <- mkBusController(nandInfra.clk90, nandInfra.rst90, clocked_by clk0, reset_by rst0);
	end


	//Tag to command mapping table
	//Since the BSV library Regfile only has 5 read ports, we'll just replicate it for each bus
	//Vector#(NUM_BUSES, RegFile#(TagT, FlashCmd)) tagTable <- replicateM(mkRegFileFull(clocked_by clk0, reset_by rst0));
	RegFile#(TagT, FlashCmd) tagTable <- mkRegFileFull(clocked_by clk0, reset_by rst0);

	Reg#(CtrlState) state <- mkReg(INIT, clocked_by clk0, reset_by rst0);
	Reg#(BusT) busInd <- mkReg(0, clocked_by clk0, reset_by rst0);
	Vector#(NUM_BUSES, Reg#(Bit#(2))) wrState <- replicateM(mkReg(0, clocked_by clk0, reset_by rst0));
	//Reg#(Bit#(16)) berrCnt <- mkReg(0, clocked_by clk0, reset_by rst0);
	Vector#(NUM_BUSES, Reg#(Bit#(16))) rDataDebug <- replicateM(mkReg(0, clocked_by clk0, reset_by rst0));

	Vector#(NUM_BUSES, Reg#(ChipT)) wdataChip <- replicateM(mkReg(0, clocked_by clk0, reset_by rst0));
	Vector#(NUM_BUSES, Reg#(Bit#(16))) wdataCnt <- replicateM(mkReg(0, clocked_by clk0, reset_by rst0));
	Vector#(NUM_BUSES, Reg#(Bit#(16))) wdataCntSub <- replicateM(mkReg(0, clocked_by clk0, reset_by rst0));
	Vector#(NUM_BUSES, Reg#(Bit#(16))) rdataCntSub <- replicateM(mkReg(0, clocked_by clk0, reset_by rst0));
	Vector#(NUM_BUSES, Reg#(Bit#(128))) rdataAggrReg <- replicateM(mkReg(0, clocked_by clk0, reset_by rst0));
	FIFO#(Tuple2#(TagT, StatusT)) ackStatusQ <- mkSizedFIFO(16, clocked_by clk0, reset_by rst0);

	//make cmdQ as deep as number of tags
	FIFO#(FlashCmd) flashCmdQ <- mkSizedFIFO(valueOf(NumTags), clocked_by clk0, reset_by rst0); 
	FIFO#(Tuple2#(Bit#(128), TagT)) taggedWDataInQ <- mkFIFO(clocked_by clk0, reset_by rst0);
	FIFO#(Tuple2#(Bit#(128), TagT)) taggedRDataOutQ <- mkSizedFIFO(8, clocked_by clk0, reset_by rst0);
	Vector#(NUM_BUSES, FIFO#(Tuple2#(Bit#(128), TagT))) taggedRDataBusQ <- replicateM(mkSizedFIFO(valueOf(NUM_BUSES)*2, clocked_by clk0, reset_by rst0));
	FIFO#(TagT) wrDataReqQ <- mkFIFO(clocked_by clk0, reset_by rst0);

	//Write Page buffers, 2 per bus
	Integer writePageBufDepth = pageSizeUser/(128/8); //8KB page using 128-bit wide fifo
	Vector#(NUM_BUSES, FIFOF#(Tuple2#(Bit#(128), TagT))) writePageBufFront <- replicateM(mkSizedBRAMFIFOF(writePageBufDepth, clocked_by clk0, reset_by rst0));
	Vector#(NUM_BUSES, FIFOF#(Tuple2#(Bit#(128), TagT))) writePageBufBack <- replicateM(mkSizedBRAMFIFOF(writePageBufDepth, clocked_by clk0, reset_by rst0));
	Vector#(NUM_BUSES, Reg#(Bit#(16))) writeWordCnt <- replicateM(mkReg(0, clocked_by clk0, reset_by rst0));
	Vector#(NUM_BUSES, Reg#(Bit#(1))) writeFetchSt <- replicateM(mkReg(0, clocked_by clk0, reset_by rst0));
	Vector#(NUM_BUSES, Reg#(Bool)) wdataRdyR <- replicateM(mkReg(False, clocked_by clk0, reset_by rst0));
	Vector#(NUM_BUSES, Reg#(TagT)) wdataRdyTag <- replicateM(mkRegU(clocked_by clk0, reset_by rst0));




	//rule for WEN/NCLK; Shared per chipbus
	for (Integer cbi=0; cbi < valueOf(NUM_CHIPBUSES); cbi=cbi+1) begin
		Integer bi = cbi * valueOf(BUSES_PER_CHIPBUS);
		Integer bj = cbi * valueOf(BUSES_PER_CHIPBUS) + 1;
		rule wenNclkConn;
			busWenNclk[cbi].wenNclk0.setWEN(busCtrl[bi].phyWenNclkGet.getWEN);
			busWenNclk[cbi].wenNclk0.setWENSel(busCtrl[bi].phyWenNclkGet.getWENSel);
			busWenNclk[cbi].wenNclk1.setWEN(busCtrl[bj].phyWenNclkGet.getWEN);
			busWenNclk[cbi].wenNclk1.setWENSel(busCtrl[bj].phyWenNclkGet.getWENSel);
		endrule
	end

	//Initialization: must perform each init op one bus at a time 
	// due to shared WEN/NCLK
	//(1) INIT_BUS (2)EN_SYNC (3)INIT_SYNC
	Reg#(FlashOp) initCmd <- mkReg(INIT_BUS, clocked_by clk0, reset_by rst0);

	rule doInit if (state==INIT);
		busCtrl[busInd].busIfc.sendCmd( FlashCmd {tag: 0, op: initCmd, bus: busInd, chip: 0, block: 0, page: 0} );
		state <= INIT_WAIT;
	endrule

	rule doInitWait if (state==INIT_WAIT);
		if (busCtrl[busInd].busIfc.isInitIdle) begin
			if (busInd < fromInteger(valueOf(NUM_BUSES)-1)) begin
				busInd <= busInd + 1;
				state <= INIT;
			end
			else begin
				busInd <= 0;	
				if (initCmd==INIT_BUS) begin
					initCmd <= EN_SYNC;
					state <= INIT;
				end 
				else if (initCmd==EN_SYNC) begin
					initCmd <= INIT_SYNC;
					state <= INIT;
				end
				else begin
					state <= ACCEPT_CMD;
				end
			end
		end
	endrule

	//Accept command and forward to each bus
	rule doIdleAcceptCmd if (state==ACCEPT_CMD);
		FlashCmd cmd = flashCmdQ.first();
		flashCmdQ.deq();
		tagTable.upd(cmd.tag, cmd);
		busCtrl[cmd.bus].busIfc.sendCmd(cmd);
		//keep track of the write requests for each chip so we can prefetch
		//if (cmd.op == WRITE_PAGE) begin
		//	writeCmdTagQ[cmd.bus][cmd.chip].enq(cmd.tag);
		//end
		$display("@%t\t%m: flash ctrl accepted cmd: tag=%x, bus=%d, op=%d, chip=%d, blk=%d", $time,
	  						cmd.tag, cmd.bus, cmd.op, cmd.chip, cmd.block);
	endrule

	for (Integer bus=0; bus < valueOf(NUM_BUSES); bus=bus+1) begin
		//handles write data BUFFERING requests from each bus controller
		rule doHandleWriteDataReqFromBus if (!writePageBufBack[bus].notEmpty && writeWordCnt[bus]==0 && writeFetchSt[bus]==0);
			TagT tag <- busCtrl[bus].busIfc.writeDataBufReq();
			wrDataReqQ.enq(tag);
			writeFetchSt[bus] <= 1;
		endrule

		rule doWriteFetchWait if (writeWordCnt[bus]==fromInteger(writePageBufDepth-1) && writeFetchSt[bus]==1);
			writeFetchSt[bus] <= 0;
		endrule

		//trnasfer from back buffer to front buffer
		rule doWriteBufTransfer;
			writePageBufFront[bus].enq(writePageBufBack[bus].first);
			writePageBufBack[bus].deq();
		endrule
		
		//Let bus controllers know if the write data has been fetched, and the tag
		rule setWriteDataRdy;
			if (!writePageBufFront[bus].notFull) begin
				TagT t = tpl_2(writePageBufFront[bus].first);
				wdataRdyTag[bus] <= t;
				wdataRdyR[bus] <= True;
			end
			else begin
				wdataRdyTag[bus] <= ?;
				wdataRdyR[bus] <= False;
			end
		endrule

		rule setWriteDataReg;
			busCtrl[bus].busIfc.setWdataRdy(wdataRdyR[bus],wdataRdyTag[bus]);
		endrule

		rule doWriteDataTransferReq if (!writePageBufFront[bus].notFull && wrState[bus]==0);
			Bit#(1) token <- busCtrl[bus].busIfc.writeDataTransferReq();
			wdataCnt[bus] <= 0;
			wdataCntSub[bus] <= 0;
			wrState[bus] <= 1;
		endrule

		rule doWriteDataTransferToBus if (wrState[bus] == 1);
			//break down each 128-bits into 16-bit bursts
			if (wdataCnt[bus] < fromInteger(writePageBufDepth)) begin
				Bit#(128) wDataBuf = tpl_1(writePageBufFront[bus].first());
				Bit#(16) wData = truncateLSB(wDataBuf << (16*wdataCntSub[bus])); //take MSB 16 bits
				busCtrl[bus].busIfc.writeWord(wData);
				$display("@%t\t%m: flash ctrl sent write data bus=%x, [%d_%d]: %x", $time, 
								bus, wdataCnt[bus], wdataCntSub[bus], wData);
				
				if(wdataCntSub[bus] == (128/16 - 1)) begin //TODO type these constants
					wdataCntSub[bus] <= 0;
					writePageBufFront[bus].deq();
					wdataCnt[bus] <= wdataCnt[bus] + 1;
				end
				else begin
					wdataCntSub[bus] <= wdataCntSub[bus] + 1;
				end
			end
			else begin
				wrState[bus] <= 0;
			end
		endrule



		//handle read data from bus controllers
		rule doReadDataCollect;
			//aggregate 16 bit bursts into 128-bit burst
			let taggedRData <- busCtrl[bus].busIfc.readWord();
			Bit#(16) rdata = tpl_1(taggedRData);
			TagT rTag = tpl_2(taggedRData);
			rDataDebug[bus] <= rdata;
			Bit#(128) rdataAggr = (rdataAggrReg[bus]<<16) | zeroExtend(rdata); 
			rdataAggrReg[bus] <= rdataAggr;
			if (rdataCntSub[bus] == (128/16-1)) begin
				rdataCntSub[bus] <= 0;
				taggedRDataBusQ[bus].enq(tuple2(rdataAggr, rTag));
			end
			else begin
				rdataCntSub[bus] <= rdataCntSub[bus] + 1;
			end
		endrule

		rule doReadDataForward;
			taggedRDataBusQ[bus].deq();
			taggedRDataOutQ.enq(taggedRDataBusQ[bus].first);
		endrule

		//handle erase and write done acks from bus controller
		rule doAckStatus;
			let resp <- busCtrl[bus].busIfc.ackStatus();
			ackStatusQ.enq(resp);
		endrule

	end //foreach(bus)

	



			

	for (Integer i=0; i < valueOf(NUM_BUSES); i=i+1) begin
		rule debugSet;
			csDebugIla[i].setDebug0(busCtrl[i].busIfc.getDebugRawData); 
			csDebugIla[i].setDebug1(busCtrl[i].busIfc.getDebugBusState); 
			csDebugIla[i].setDebug2(busCtrl[i].busIfc.getDebugAddr); 
			csDebugIla[i].setDebug3(rDataDebug[i]); //Error corrected data
			//csDebugIla[i].setDebug4(zeroExtend(pack(state)));
			//csDebugIla[i].setDebug5_64(latencyCnt);
			//csDebugIla[i].setDebug6_64(errCnt[i]);
		endrule
	end

	//rule debugSetVio;
	//	csDebug.vio.setDebugVin(csDebug.vio.getDebugVout());
	//endrule

	Vector#(NUM_CHIPBUSES, Vector#(BUSES_PER_CHIPBUS, NANDPins)) nandBusVec = newVector();
	Vector#(NUM_CHIPBUSES, NANDWenNclk) nandBusSharedVec = newVector();

	for (Integer i=0; i < valueOf(NUM_BUSES); i=i+1) begin
		Integer bi = i / valueOf(BUSES_PER_CHIPBUS);
		Integer bj = i % valueOf(BUSES_PER_CHIPBUS);
		nandBusVec[bi][bj] = busCtrl[i].nandPins;
	end

	for (Integer i=0; i < valueOf(NUM_CHIPBUSES); i=i+1) begin
		nandBusSharedVec[i] = busWenNclk[i].nandWenNclk;
	end

	Vector#(NUM_BUSES, DebugIlaPartial) debugVec = newVector();

	for (Integer b=0; b < valueOf(NUM_BUSES); b=b+1) begin
		debugVec[b] = 	interface DebugIlaPartial;
								method Action debugPort4(Bit#(16) d);
									csDebugIla[b].setDebug4(d);
								endmethod

								method Action debugPort5_64(Bit#(64) d);
									csDebugIla[b].setDebug5_64(d);
								endmethod

								method Action debugPort6_64(Bit#(64) d);
									csDebugIla[b].setDebug6_64(d);
								endmethod
							endinterface;
	end

	interface FlashCtrlDebug debug;
		interface debugBus = debugVec;
		interface debugVio = csDebug.vio;
	endinterface


	interface FlashCtrlPins pins;
		interface nandBus = nandBusVec;
		interface nandBusShared = nandBusSharedVec;
	endinterface

	interface FlashCtrlUser user;
		method Action sendCmd (FlashCmd cmd);
			flashCmdQ.enq(cmd);
		endmethod
		method Action writeWord (Tuple2#(Bit#(128), TagT) taggedData); //host sending write data to flash
			Bit#(128) data = tpl_1(taggedData);
			TagT tag = tpl_2(taggedData);
			//look up cmd in tag table
			FlashCmd wCmd = tagTable.sub(tag);
			//send data to the correct write page buffer for the chip
			writePageBufBack[wCmd.bus].enq(tuple2(data, tag));
			if (writeWordCnt[wCmd.bus]==fromInteger(writePageBufDepth-1)) begin
				writeWordCnt[wCmd.bus] <= 0;
			end
			else begin
				writeWordCnt[wCmd.bus] <= writeWordCnt[wCmd.bus] + 1;
			end
		endmethod
		method ActionValue#(Tuple2#(Bit#(128), TagT)) readWord (); 
			taggedRDataOutQ.deq();
			return taggedRDataOutQ.first();
		endmethod
		method ActionValue#(TagT) writeDataReq(); 
			wrDataReqQ.deq();
			return wrDataReqQ.first;
		endmethod
		method ActionValue#(Tuple2#(TagT, StatusT)) ackStatus (); 
			ackStatusQ.deq();
			return ackStatusQ.first();
		endmethod
	endinterface

	interface FlashCtrlInfra infra;
		interface sysclk0 = clk0;
		interface sysrst0 = rst0;
	endinterface



endmodule
