import FIFOF             ::*;
import FIFO             ::*;
import Vector            ::*;
import GetPut ::*;
import BRAMFIFO::*;

import ControllerTypes::*;
import NandPhyWrapper::*;
import NandPhy::*;
import NandPhyWenNclkWrapper::*;
import GFTypes::*;
import ReedSolomon::*;
import RSEncoder::*;
import Scoreboard::*;


typedef enum {
	IDLE, 				//0
	WAIT_CYCLES,		//1

	UNINIT,				//2
	INIT,					//3
	INIT_INC,			//4
	EN_SYNC,				//5
	INIT_EN_NANDCLK,	//6
	INIT_CALIB,			//7

	READ_PAGE_REQ,		//8
	READ_DATA,			//9
	READ_PAGE_WAIT,	//10
	READ_DATA_WAIT_BUF, //11
	WRITE_PAGE,			//12
	WRITE_PAGE_WAIT,	//13
	ERASE_BLOCK,		//14
	POLL_STATUS,		//15
	POLL_STATUS_POLL,	//16
	GET_STATUS,			//17
	ERASE_GET_STATUS,			//18
	WRITE_GET_STATUS,			//19
	WRITE_ERROR,		//20
	READ_ERROR			//21
} CtrlState deriving (Bits, Eq);

interface BusIfc;
	method Action sendCmd (FlashCmd cmd);
	method ActionValue#(TagT) writeDataBufReq(); 
	method ActionValue#(Bit#(1)) writeDataTransferReq(); 
	method Action writeWord (Bit#(16) data);
	method ActionValue#(Tuple2#(Bit#(16), TagT)) readWord (); 
	method ActionValue#(Tuple2#(TagT, StatusT)) ackStatus (); 
	method Bool isInitIdle();
	(* always_enabled *)
	method Action setWdataRdy(Bool rdy, TagT tag);
	method Bit#(16) getDebugRawData;
	method Bit#(16) getDebugBusState;
	method Bit#(16) getDebugAddr;
endinterface


interface BusControllerIfc;
	interface BusIfc busIfc;
	interface NANDPins nandPins;
	//interface PhyDebugCtrl phyDebugCtrl;
	//interface PhyDebug phyDebug;
	interface PhyWenNclkGet phyWenNclkGet;
endinterface

//(* no_default_clock, no_default_reset *)
//Default clock and rests are clk0 and rst0
(* synthesize *)
module mkBusController#(
	Clock clk90, 
	Reset rst90
	)(
	//(* clocked_by="no_clock", reset_by="no_reset" *) Inout#(Bit#(36)) dbgCtrlIla, 
	//(* clocked_by="no_clock", reset_by="no_reset" *) Inout#(Bit#(36)) dbgCtrlVio,
	BusControllerIfc ifc);
	
	//Timing parameters for timing parameters between different cycle types
	//using SHORT_RESET for simulation. Doens't matter because we poll
	// until status is ready
	Integer t_POR = 1000; //1ms. Power-on Reset time. reduced, but ok since we poll until ready
	Integer t_ITC = 150; //1us (tITC)
	Integer t_WHR_ASYNC = 13; //120ns. WE# HIGH to RE# LOW
	Integer t_WB_ASYNC = 20; //200ns
	Integer t_ADL_ASYNC = 25; //200ns
	Integer t_RHW_ASYNC = 25; //200ns
	Integer t_EN_CLK = 1000; //Delay after enabling NAND CLK. Not in spec. 

	Integer t_WHR_SYNC = 8; //80ns. WE# HIGH to RE# LOW
	Integer t_ADL_SYNC = 7; //70ns
	Integer t_RHW_SYNC = 10; //100ns
	Integer t_WB_SYNC = 10; //100ns
	//Integer t_BERS = 20000; //3.8 to 10ms. But start polling earlier.

	Integer nAddrBursts = 5; //5 addr bursts is standard
	Integer nAddrBurstsErase = 3; //3 addr bursts for erase
	
	//States
	Reg#(CtrlState) state <- mkReg(UNINIT);
	Reg#(CtrlState) returnState <- mkReg(IDLE);
	Reg#(CtrlState) rdyReturnState <- mkReg(IDLE);

	//Counters
	Reg#(Bit#(32)) waitCnt <- mkReg(0);
	Reg#(Bit#(8)) addrCnt <- mkReg(0);
	Reg#(Bit#(4)) cmdCnt <- mkReg(0);
	Reg#(Bit#(16)) dataCnt <- mkReg(0);
	Reg#(Bit#(16)) wrEnqWordCnt <- mkReg(0);
	Reg#(Bit#(16)) wrEnqBlkCnt <- mkReg(0);
	Reg#(Bit#(16)) currK <- mkReg(0);
	Reg#(Bit#(16)) rdEnqWordCnt <- mkReg(0);
	Reg#(Bit#(16)) rdEnqBlkCnt <- mkReg(0);
	Reg#(Bit#(16)) currN <- mkReg(0);

	//Debug
	Reg#(Bit#(16)) debugR0 <- mkReg(0);
	Reg#(BusCmd) debugCmd <- mkRegU();
	Reg#(Bit#(16)) debugAddr <- mkReg(0);
	Reg#(Bit#(8)) debugFlagLo <- mkReg(0);
	Reg#(Bit#(8)) debugFlagHi <- mkReg(0);
//	Reg#(Bit#(16)) debugR2 <- mkReg(0);
//	Reg#(Bit#(16)) debugR3 <- mkReg(0);

	//Command/Data FIFOs
	FIFOF#(FlashCmd) flashCmdQ <- mkSizedFIFOF(4); //TODO adjust
	Reg#(ChipT) chipR <- mkReg(0);
	Vector#(5, Reg#(Bit#(8))) addrDecoded <- replicateM(mkReg(0));
	FIFO#(TagT) wrDataBufReqQ <- mkSizedFIFO(valueOf(ChipsPerBus));
	FIFO#(Bit#(1)) wrDataTransReqQ <- mkSizedFIFO(valueOf(ChipsPerBus));
	FIFO#(Tuple2#(TagT, StatusT)) ackQ <- mkSizedFIFO(16);

	//Tag management
	FIFO#(TagT) readTagQ <- mkSizedFIFO(8); //each time we do a 8k read burst, we enq the tag in this fifo
	Reg#(Bit#(16)) rdWdCnt <- mkReg(0);
	Reg#(TagT) cmdTagR <- mkReg(0);


	//Sync or async mode
	Reg#(Bool) inSyncMode <- mkReg(False);

	//Number of bursts is half the page size in sync mode (DDR)
	Bit#(16) nDataBursts = (inSyncMode) ? fromInteger(pageSize/2) : fromInteger(pageSize);

	//Select between sync mode timing and async mode timing
	Bit#(32) t_WHR = (inSyncMode) ? fromInteger(t_WHR_SYNC) : fromInteger(t_WHR_ASYNC);
	Bit#(32) t_RHW = (inSyncMode) ? fromInteger(t_RHW_SYNC) : fromInteger(t_RHW_ASYNC);
	Bit#(32) t_WB = (inSyncMode) ? fromInteger(t_WB_SYNC) : fromInteger(t_WB_ASYNC);
	Bit#(32) t_ADL = (inSyncMode) ? fromInteger(t_ADL_SYNC) : fromInteger(t_ADL_ASYNC);

	//Nand PHY instantiation
	NandPhyIfc phy <- mkNandPhy(clk90, rst90);
	//ECC decoder and encoder
	FIFO#(Bit#(16)) encodeInQ <- mkSizedFIFO(64); //TODO adjust
	//Note: the size of this FIFO is very important because during write
	//bursts, we must make sure this FIFO always has data. 
	//Size this to be: K-K_LAST=35 + any rs encoder delays between blocks
	//(should be none)
	//Don't size it too large. We fill the buffer to start with. More delay. 
	FIFOF#(Bit#(16)) encodeOutQ <- mkSizedFIFOF(40); 
	RSEncoderIfc rsEncoderHi <- mkRSEncoder();
	RSEncoderIfc rsEncoderLo <- mkRSEncoder();

	//On reads, must make sure all FIFOs into decoder always has space to accept
	//data When starting a read, ensure this FIFO is empty as a precaution
	FIFOF#(Bit#(16)) decodeInQ <- mkSizedBRAMFIFOF(pageSize/2 + 1);
	FIFOF#(Bit#(16)) decodeInBufQ <- mkSizedBRAMFIFOF(pageSize/4 + 1);
	//FIFO#(Bit#(8)) decodeOutHiQ <- mkSizedFIFO(4); //doesn't matter here
	//FIFO#(Bit#(8)) decodeOutLoQ <- mkSizedFIFO(4); //doesn't matter here
	FIFO#(Byte) decodeKQ <- mkSizedFIFO(pageECCBlks*3 + 1);
	FIFO#(Byte) decodeTQ <- mkSizedFIFO(pageECCBlks*3 + 1);
	IReedSolomon rsDecoderHi <- mkReedSolomon();
	IReedSolomon rsDecoderLo <- mkReedSolomon();

	//Scoreboard instantiation
	SBIfc sb <- mkScoreboard();

	//******************************************************
	// Initialization
	//******************************************************
	rule doUninitialized if (state==UNINIT);
		cmdCnt <= 0;
		addrCnt <= 0;
		dataCnt <= 0;
		flashCmdQ.deq();
		FlashCmd cmd = flashCmdQ.first();
		chipR <= cmd.chip;
		case(cmd.op)
			INIT_BUS: state <= INIT;
			EN_SYNC: state <= EN_SYNC;
			INIT_SYNC: state <= INIT_EN_NANDCLK;
			default: state <= UNINIT;
		endcase
		$display("BusController: Executing INITIALIZATION command=%x", cmd.op);
	endrule

	//******************************************************
	// Scoreboard
	//******************************************************
	//After Bus is initialized, push all commands to scoreboard
	rule doSBCmd if (state!=UNINIT);
		flashCmdQ.deq();
		FlashCmd fcmd = flashCmdQ.first();
		sb.cmdIn.put(fcmd);
	//	BusOp op;
	//	case(fcmd.op) 
	//		READ_PAGE: op = READ_CMD;
	//		WRITE_PAGE: op = WRITE_CMD_DATA;
	//		ERASE_BLOCK: op = ERASE_CMD;
	//		default: op = INVALID;
	//	endcase
	//	busCmdQPLACEHOLDER.enq( BusCmd { 	
	//										tag: fcmd.tag,
	//										busOp: op,
	//										chip: fcmd.chip,
	//										block: fcmd.block,
	//										page: fcmd.page } );
	endrule

		

	//******************************************************
	// Decode command
	//******************************************************
	rule doDecodeCmd if (state==IDLE);
		cmdCnt <= 0;
		addrCnt <= 0;
		dataCnt <= 0;
		//BusCmd cmd = busCmdQPLACEHOLDER.first();
		//busCmdQPLACEHOLDER.deq();
		BusCmd cmd <- sb.cmdOut.get();
		case(cmd.busOp)
			READ_CMD: state <= READ_PAGE_REQ;
			GET_STATUS_READ_DATA: state <= READ_PAGE_WAIT;
			WRITE_DATA_BUF_REQ: wrDataBufReqQ.enq(cmd.tag);
			WRITE_CMD_DATA: begin
			  	state <= WRITE_PAGE_WAIT;
				wrDataTransReqQ.enq(1); 
			end
			ERASE_CMD: state <= ERASE_BLOCK;
			WRITE_GET_STATUS: state <= WRITE_GET_STATUS;
			ERASE_GET_STATUS: state <= ERASE_GET_STATUS;
			default: state <= IDLE;
		endcase
		rdyReturnState <= IDLE;
		//decode addr
		chipR <= cmd.chip;
		addrDecoded[0] <= 0; //column addr
		addrDecoded[1] <= 0;
		addrDecoded[2] <= cmd.page;
		addrDecoded[3] <= truncate(cmd.block);
		addrDecoded[4] <= truncateLSB(cmd.block);
		cmdTagR <= cmd.tag;
		debugCmd <= cmd;
		debugAddr <= 0;
		$display("BusController: Executing command=%x", cmd.busOp);
	endrule	



	//******************************************************
	// Wait rule; waits a certain number of cycles
	//******************************************************
	rule doWaitCycles if (state==WAIT_CYCLES);
		if (waitCnt>2) begin
			waitCnt <= waitCnt-1;
		end
		else begin
			state <= returnState;
		end
	endrule


	//******************************************************
	// Read Page (Sync or Async)
	//******************************************************
	Integer nreadReqCmds = 5;
	PhyCmd readReqCmds[nreadReqCmds] = {
			PhyCmd { inSyncMode: inSyncMode, phyCycle: PHY_CHIP_SEL, nandCmd: tagged ChipSel chipR,
						numBurst: 0, postCmdWait: 0},
			PhyCmd { inSyncMode: inSyncMode, phyCycle: PHY_CMD, nandCmd: tagged OnfiCmd N_READ_MODE,
						numBurst: 0, postCmdWait: 0},
			PhyCmd { inSyncMode: inSyncMode, phyCycle: PHY_ADDR, nandCmd: ?, 
						numBurst: fromInteger(nAddrBursts), postCmdWait: 0},
			PhyCmd { inSyncMode: inSyncMode, phyCycle: PHY_CMD, nandCmd: tagged OnfiCmd N_READ_PAGE_END, 
						numBurst: 0, postCmdWait: t_WB},
			PhyCmd { inSyncMode: inSyncMode, phyCycle: PHY_DESELECT_ALL, nandCmd: ?, 
						numBurst: 0, postCmdWait: 0}
			};
	
	Integer nreadDataCmds = 4;
	PhyCmd readDataCmds[nreadDataCmds] = {
			PhyCmd { inSyncMode: inSyncMode, phyCycle: PHY_CHIP_SEL, nandCmd: tagged ChipSel chipR,
						numBurst: 0, postCmdWait: 0},
			PhyCmd { inSyncMode: inSyncMode, phyCycle: PHY_CMD, nandCmd: tagged OnfiCmd N_READ_MODE, 
						numBurst: 0, postCmdWait: t_WHR},
			PhyCmd { inSyncMode: inSyncMode, phyCycle: PHY_READ, nandCmd: ?, 
						numBurst: nDataBursts, postCmdWait: t_RHW},
			PhyCmd { inSyncMode: inSyncMode, phyCycle: PHY_DESELECT_ALL, nandCmd: ?, 
						numBurst: 0, postCmdWait: 0}
			};

	rule doReadPageCmd if (state==READ_PAGE_REQ && cmdCnt < fromInteger(nreadReqCmds));
		phy.phyUser.sendCmd(readReqCmds[cmdCnt]);
		Bit#(8) c = zeroExtend(debugCmd.chip);
		Bit#(8) b = truncate(debugCmd.block);
		debugAddr <= {c, b};
		cmdCnt <= cmdCnt + 1;
	endrule
		
	rule doReadPageAddr if (state==READ_PAGE_REQ && addrCnt < fromInteger(nAddrBursts));
		phy.phyUser.sendAddr(addrDecoded[addrCnt]);
		addrCnt <= addrCnt + 1;
	endrule


	rule doReadPageCmdDone if (state==READ_PAGE_REQ && 
									addrCnt==fromInteger(nAddrBursts) && 
									cmdCnt==fromInteger(nreadReqCmds));
		state <= IDLE;
	endrule

	rule doReadPageWait if (state==READ_PAGE_WAIT);
		//state <= POLL_STATUS;
		state <= GET_STATUS;
		rdyReturnState <= READ_DATA_WAIT_BUF;
		cmdCnt <= 0;
		addrCnt <= 0;
		dataCnt <= 0;
		Bit#(8) c = zeroExtend(debugCmd.chip);
		Bit#(8) b = truncate(debugCmd.block);
		debugAddr <= {c, b};
	endrule

	//wait until we have enough buffer space for read data
	//TODO: OPTIMIZE 
	rule doReadDataWaitBuf if (state==READ_DATA_WAIT_BUF && !decodeInQ.notEmpty);
		state <= READ_DATA;
		$display("@%t\t%m: Bus waiting for read buffer space", $time);
	endrule

	rule doReadDataCmd if (state==READ_DATA && cmdCnt < fromInteger(nreadDataCmds));
		phy.phyUser.sendCmd(readDataCmds[cmdCnt]);
		cmdCnt <= cmdCnt + 1;
		Bit#(8) c = zeroExtend(debugCmd.chip);
		Bit#(8) b = truncate(debugCmd.block);
		debugAddr <= {c, b};
	endrule

	//Sync DDR bursts
	rule doReadDataDDR if (state==READ_DATA && inSyncMode==True && dataCnt < nDataBursts);
		if ( /*(dataCnt==0 && decodeInQ.notEmpty) ||*/ (!decodeInQ.notFull) ) begin
			//throw error if decodeInQ is not empty at the start  //TODO this may be too conservative?
			// OR
			//at any point, the Q becomes full
			state <= READ_ERROR;
			$display("@%t\t%m: *** read error at dataCnt=%d", $time, dataCnt);
		end
		else begin
			if (dataCnt==0) begin
				//enq the tag for this 8k burst
				readTagQ.enq(cmdTagR);
			end

			Bit#(16) rd <- phy.phyUser.rdWord();
			
			//Inject some errors if simulating
			//TODO FIXME
			`ifdef NAND_SIM
				if (dataCnt>nDataBursts-6) begin //injection frequency
					rd = rd & 16'hFF00; //inject err low
					$display("@%t\t%m: injected read error LOW rd[%d]=%x", $time, dataCnt, rd);
				end
				else if (dataCnt[7:0]==32) begin
					rd = rd & 16'h00FF; //inject err hi
					$display("@%t\t%m: injected read error HIGH rd[%d]=%x", $time, dataCnt, rd);
				end
			`endif

			decodeInQ.enq(rd);
			debugR0 <= rd;
			dataCnt <= dataCnt + 1;
			$display("@%t\t%m: read raw data[%d]: %x", $time, dataCnt, rd);
			//if it's the first burst of a block, enq the decoder control info
			if (rdEnqWordCnt == 0) 
			begin
				rdEnqWordCnt <= rdEnqWordCnt + 1;
				if (rdEnqBlkCnt == fromInteger(pageECCBlks-1)) begin
					decodeKQ.enq(fromInteger(valueOf(K_LAST)));
					rdEnqBlkCnt <= 0;
					currN <= fromInteger(valueOf(K_LAST) + 2*valueOf(T)); //K+2T
				end
				else begin
					decodeKQ.enq(fromInteger(valueOf(K)));
					rdEnqBlkCnt <= rdEnqBlkCnt + 1;
					currN <= fromInteger(max_block_size); //255
				end
				decodeTQ.enq(fromInteger(valueOf(T)));
			end
			else if (rdEnqWordCnt == currN-1) begin
				rdEnqWordCnt <= 0;
			end
			else begin
				rdEnqWordCnt <= rdEnqWordCnt + 1;
			end
		end
	endrule

	//Async SDR bursts
	Reg#(Bit#(8)) rdTmp <- mkReg(0);
	rule doReadDataSDR if (state==READ_DATA && inSyncMode==False && dataCnt < nDataBursts);
		//TODO: ASYNC doesn't have ECC Implemented, so this doesn't work at all
		Bit#(16) rd <- phy.phyUser.rdWord();
		Bit#(8) rdTrunc = truncate(rd);
		dataCnt <= dataCnt + 1;

		if (dataCnt[0]==0) begin //even bursts
			rdTmp <= rdTrunc;
		end
		else begin //odd burst, enq into fifo
			Bit#(16) rdMerged = {rdTmp, rdTrunc};
			//readQ.enq(rdMerged);
			
			debugR0 <= rdMerged;
			$display("NandCtrl: read data: %x", rdMerged);
		end
	endrule

	rule doReadDataDone if (state==READ_DATA && 
								dataCnt == nDataBursts && 
								cmdCnt==fromInteger(nreadDataCmds));
		state <= IDLE;
	endrule


	//******************************************************
	// Write Page (Sync or Async)
	//******************************************************
	Integer nwriteReqCmds = 6;	
	PhyCmd writeReqCmds[nwriteReqCmds] = {
			PhyCmd { inSyncMode: inSyncMode, phyCycle: PHY_CHIP_SEL, nandCmd: tagged ChipSel chipR,
						numBurst: 0, postCmdWait: 0},
			PhyCmd { inSyncMode: inSyncMode, phyCycle: PHY_CMD, nandCmd: tagged OnfiCmd N_PROGRAM_PAGE, 
						numBurst: 0, postCmdWait: 0},
			PhyCmd { inSyncMode: inSyncMode, phyCycle: PHY_ADDR, nandCmd: ?, 
						numBurst: fromInteger(nAddrBursts), postCmdWait: t_ADL},
			PhyCmd { inSyncMode: inSyncMode, phyCycle: PHY_WRITE, nandCmd: ?, 
						numBurst: nDataBursts, postCmdWait: 0}, 
			PhyCmd { inSyncMode: inSyncMode, phyCycle: PHY_CMD, nandCmd: tagged OnfiCmd N_PROGRAM_PAGE_END, 
		 				numBurst: 0, postCmdWait: t_WB},
			PhyCmd { inSyncMode: inSyncMode, phyCycle: PHY_DESELECT_ALL, nandCmd: ?, 
						numBurst: 0, postCmdWait: 0}
			};


	rule doWriteDataWait if (state==WRITE_PAGE_WAIT);
		if (!encodeOutQ.notFull) begin
			state <= WRITE_PAGE;
		end
	endrule

	rule doWritePageCmd if (state==WRITE_PAGE && cmdCnt < fromInteger(nwriteReqCmds));
		phy.phyUser.sendCmd(writeReqCmds[cmdCnt]);
		cmdCnt <= cmdCnt + 1;
		Bit#(8) c = zeroExtend(debugCmd.chip);
		Bit#(8) b = truncate(debugCmd.block);
		debugAddr <= {c, b};
	endrule
		
	rule doWritePageAddr if (state==WRITE_PAGE && addrCnt < fromInteger(nAddrBursts));
		phy.phyUser.sendAddr(addrDecoded[addrCnt]); 
		addrCnt <= addrCnt + 1;
	endrule

	//we need to make sure the write FIFO always has data, otherwise writes won't work

	//Sync DDR write
	rule doWritePageDataDDR if (state==WRITE_PAGE && inSyncMode && dataCnt < nDataBursts);
		if (encodeOutQ.notEmpty) begin
			phy.phyUser.wrWord(encodeOutQ.first());
			debugR0 <= encodeOutQ.first();
			encodeOutQ.deq();
			dataCnt <= dataCnt + 1;
			$display("@%t\t%m: sync DDR write [%d] = %x", $time, dataCnt, encodeOutQ.first());
		end
		else begin //encodeOutQ should NEVER be empty 
			state <= WRITE_ERROR;
		end
	endrule

	//Async SDR write
	rule doWritePageDataSDR if (state==WRITE_PAGE && !inSyncMode && dataCnt < nDataBursts);
		if (encodeOutQ.notEmpty) begin
			if (dataCnt[0]==0) begin
				Bit#(8) wd = truncateLSB(encodeOutQ.first());
				phy.phyUser.wrWord(zeroExtend(wd));
			end
			else begin
				Bit#(8) wd = truncate(encodeOutQ.first());
				phy.phyUser.wrWord(zeroExtend(wd));
				encodeOutQ.deq();
			end
			dataCnt <= dataCnt + 1;
		end
		else begin //encodeOutQ should NEVER be empty 
			state <= WRITE_ERROR;
		end
	endrule

		
	rule doWriteDone if (state==WRITE_PAGE && dataCnt==nDataBursts 
								&& cmdCnt==fromInteger(nwriteReqCmds) && 
								addrCnt==fromInteger(nAddrBursts));
		//wait for write to finish
		//state <= POLL_STATUS;
		//rdyReturnState <= IDLE;
		state <= IDLE;
	endrule


		
	//******************************************************
	// Erase Block
	//******************************************************
	Integer neraseCmds = 5;
	PhyCmd eraseCmds[neraseCmds] = {
			PhyCmd { inSyncMode: inSyncMode, phyCycle: PHY_CHIP_SEL, nandCmd: tagged ChipSel chipR,
						numBurst: 0, postCmdWait: 0},
			PhyCmd { inSyncMode: inSyncMode, phyCycle: PHY_CMD, nandCmd: tagged OnfiCmd N_ERASE_BLOCK, 
						numBurst: 0, postCmdWait: 0},
			PhyCmd { inSyncMode: inSyncMode, phyCycle: PHY_ADDR, nandCmd: ?, 
						numBurst: fromInteger(nAddrBurstsErase), postCmdWait: 0},
			PhyCmd { inSyncMode: inSyncMode, phyCycle: PHY_CMD, nandCmd: tagged OnfiCmd N_ERASE_BLOCK_END, 
		 				numBurst: 0, postCmdWait: fromInteger(t_WB_SYNC)},
			PhyCmd { inSyncMode: inSyncMode, phyCycle: PHY_DESELECT_ALL, nandCmd: ?, 
						numBurst: 0, postCmdWait: 0}
			};

	rule doEraseBlockCmd if (state==ERASE_BLOCK && cmdCnt < fromInteger(neraseCmds));
		phy.phyUser.sendCmd(eraseCmds[cmdCnt]);
		cmdCnt <= cmdCnt + 1;
		Bit#(8) c = zeroExtend(debugCmd.chip);
		Bit#(8) b = truncate(debugCmd.block);
		debugAddr <= {c, b};
	endrule

	rule doEraseBlockAddr if (state==ERASE_BLOCK && 
									addrCnt < fromInteger(nAddrBurstsErase));
		//Write 3 row addresses (page, block) indices 2,3,4.
		//Note: page addr is ignored by the NAND, but still have to send it
		let ind = addrCnt+2;
		phy.phyUser.sendAddr(addrDecoded[ind]);
		addrCnt <= addrCnt + 1;
	endrule

	rule doEraseBlockPoll if (state==ERASE_BLOCK && addrCnt==fromInteger(nAddrBurstsErase) && cmdCnt==fromInteger(neraseCmds));
		//wait for write to finish
		//state <= POLL_STATUS;
		//rdyReturnState <= IDLE;
		state <= IDLE;
	endrule



	//******************************************************
	// Async/Sync Poll Status
	//******************************************************
	Integer nstatusCmds = 4;
	PhyCmd statusCmds[nstatusCmds] = { 
			PhyCmd { inSyncMode: inSyncMode, phyCycle: PHY_CHIP_SEL, nandCmd: tagged ChipSel chipR,
						numBurst: 0, postCmdWait: 0},
			PhyCmd { inSyncMode: inSyncMode, phyCycle: PHY_CMD, nandCmd: tagged OnfiCmd N_READ_STATUS, 
			  			numBurst: 0, postCmdWait: t_WHR},
			PhyCmd { inSyncMode: inSyncMode, phyCycle: PHY_READ, nandCmd: ?, 
		 				numBurst: 1, postCmdWait: t_RHW},
			PhyCmd { inSyncMode: inSyncMode, phyCycle: PHY_DESELECT_ALL, nandCmd: ?, 
						numBurst: 0, postCmdWait: 0}
		};
	rule doStatusCntReset if (state==POLL_STATUS);
		cmdCnt <= 0;
		state <= POLL_STATUS_POLL;
	endrule 

	rule doReadStatusCmd if (state==POLL_STATUS_POLL && cmdCnt < fromInteger(nstatusCmds));
		phy.phyUser.sendCmd(statusCmds[cmdCnt]);
		cmdCnt <= cmdCnt + 1;
	endrule

	rule doReadStatusGet if (state==POLL_STATUS_POLL && cmdCnt==fromInteger(nstatusCmds));
		Bit#(16) status <- phy.phyUser.rdWord();
		cmdCnt <= 0;
		$display("NandCtrl: status=%x", status);
		debugR0 <= status; //debug

		//During calibration, get status is used to initialize IDDR regs so that we don't have
		//DON'T CARES
		if (rdyReturnState==INIT_CALIB) begin
			state <= rdyReturnState;
		end
		else begin
			if (status[7:0]==8'hE0) begin 
				state <= rdyReturnState;
			end
			else begin
				//wait a while before polling
				waitCnt <= 100;
				state <= WAIT_CYCLES;
				returnState <= POLL_STATUS_POLL;
			end
		end
	endrule

	//Get status; does not poll
	rule doGetStatusOnlyCmd if ( (state==GET_STATUS || state==ERASE_GET_STATUS || state==WRITE_GET_STATUS)
	  											&& cmdCnt < fromInteger(nstatusCmds));
		phy.phyUser.sendCmd(statusCmds[cmdCnt]);
		cmdCnt <= cmdCnt + 1;
		Bit#(8) c = zeroExtend(debugCmd.chip);
		Bit#(8) b = truncate(debugCmd.block);
		debugAddr <= {c, b};
	endrule

	rule doGetStatusData if ( (state==GET_STATUS || state==ERASE_GET_STATUS || state==WRITE_GET_STATUS)
										&& cmdCnt==fromInteger(nstatusCmds));
		Bit#(16) status <- phy.phyUser.rdWord();
		$display("NandCtrl: GET status=%x", status);
		debugR0 <= status; //debug

		if (status[7:0]==8'hE0 || status[7:0]==8'hE1) begin 
			sb.busyIn.put(tuple2(chipR, False)); //not busy
			cmdCnt <= 0;
			state <= rdyReturnState;
			//If erase or write get status, send ack
			if (state==WRITE_GET_STATUS) begin
				ackQ.enq(tuple2(cmdTagR, WRITE_DONE));
			end
			else if (state==ERASE_GET_STATUS) begin
				if (status[7:0]==8'hE0) begin
					ackQ.enq(tuple2(cmdTagR, ERASE_DONE));
				end
				else begin //status 8'hE1, bad block
					ackQ.enq(tuple2(cmdTagR, ERASE_ERROR));
				end
			end
		end
		else begin
			sb.busyIn.put(tuple2(chipR, True)); //still busy
			state <= IDLE; //always return to idle if busy
		end
	endrule

	//******************************************************
	// Power On Initialization for all targets on the bus. 
	// For each target:
	// 1) Go bus idle
	// 2) Issue power on reset; wait t_POR
	//******************************************************

	Integer ninitCmds = 3;
	PhyCmd initCmds[ninitCmds] = {
				PhyCmd { inSyncMode: inSyncMode, phyCycle: PHY_CHIP_SEL, nandCmd: tagged ChipSel chipR, 
	 						numBurst: 0, postCmdWait: 0},
				PhyCmd { inSyncMode: inSyncMode, phyCycle: PHY_CMD, nandCmd: tagged OnfiCmd N_RESET, 
	 		  				numBurst: 0, postCmdWait: fromInteger(t_POR)},
				PhyCmd { inSyncMode: inSyncMode, phyCycle: PHY_DESELECT_ALL, nandCmd: ?, 
							numBurst: 0, postCmdWait: fromInteger(t_ITC)}
				};

	rule doInitCmd if (state==INIT && cmdCnt < fromInteger(ninitCmds));
		phy.phyUser.sendCmd(initCmds[cmdCnt]);
		cmdCnt <= cmdCnt + 1;
	endrule

	rule doInitWait if (state==INIT && cmdCnt==fromInteger(ninitCmds));
		state <= POLL_STATUS;
		rdyReturnState <= INIT_INC;
	endrule

	rule doInitInc if (state==INIT_INC);
		if (chipR < fromInteger(valueOf(ChipsPerBus) - 1)) begin
			chipR <= chipR + 1;
			state <= INIT;
		end
		else begin
			chipR <= 0;
			//state <= IDLE;
			state <= UNINIT;
		end
	endrule

	//******************************************************
	// Sync Mode 5 activation and calibration
	// 1) poll status until ready
	// 2) activate sync mode 5 interface
	// 3) release CE#, wait t_ITC+t_WB
	// 4) enable nand clock
	// 5) select CE#, go sync bus idle
	// 6) calibrate read timing by issuing READ ID 
	//******************************************************

	Integer nactSyncData = 4;
	Integer nactSyncCmds = 5;
	PhyCmd actSyncCmds[nactSyncCmds] = {
				PhyCmd { inSyncMode: inSyncMode, phyCycle: PHY_CHIP_SEL, nandCmd: tagged ChipSel chipR, 
	 						numBurst: 0, postCmdWait: 0},
				PhyCmd { inSyncMode: inSyncMode, phyCycle: PHY_CMD, nandCmd: tagged OnfiCmd N_SET_FEATURES, 
							numBurst: 0, postCmdWait: 0},
				PhyCmd { inSyncMode: inSyncMode, phyCycle: PHY_ADDR, nandCmd: ?, 
							numBurst: 1, postCmdWait: t_ADL},
				PhyCmd { inSyncMode: inSyncMode, phyCycle: PHY_WRITE, nandCmd: ?, 
							numBurst: fromInteger(nactSyncData), postCmdWait: t_WB},
				PhyCmd { inSyncMode: inSyncMode, phyCycle: PHY_DESELECT_ALL, nandCmd: ?, 
							numBurst: 0, postCmdWait: fromInteger(t_ITC)}
				};

	Integer nactSyncAddr = 1;
	Bit#(8) actSyncAddr = 8'h01;
	//commands for sync mode 5 (0x15)
	Bit#(8) actSyncData[nactSyncData] = { 8'h15, 8'h00, 8'h00, 8'h00 };
	
	rule doInitActSync if (state==EN_SYNC && cmdCnt < fromInteger(nactSyncCmds));
		phy.phyUser.sendCmd(actSyncCmds[cmdCnt]);
		cmdCnt <= cmdCnt + 1;
	endrule

	rule doInitActSyncAddr if (state==EN_SYNC && addrCnt < fromInteger(nactSyncAddr));
		phy.phyUser.sendAddr(actSyncAddr);
		addrCnt <= addrCnt + 1;
	endrule

	rule doInitActSyncData if (state==EN_SYNC && dataCnt < fromInteger(nactSyncData));
		phy.phyUser.wrWord(zeroExtend(actSyncData[dataCnt]));
		dataCnt <= dataCnt + 1;
	endrule

	rule doSyncInitDone if (state==EN_SYNC && cmdCnt==fromInteger(nactSyncCmds) && 
								addrCnt==fromInteger(nactSyncAddr) && 
								dataCnt==fromInteger(nactSyncData));
		if (chipR < fromInteger(valueOf(ChipsPerBus) - 1)) begin
			chipR <= chipR + 1;
			//state <= EN_SYNC; //stay in same state
			cmdCnt <= 0;
			addrCnt <= 0;
			dataCnt <= 0;
		end
		else begin
			state <= UNINIT;
		end
	endrule




	PhyCmd enNandclkCmd = PhyCmd { inSyncMode: inSyncMode, phyCycle: PHY_ENABLE_NAND_CLK, nandCmd: ?, 
							numBurst: 0, postCmdWait: fromInteger(t_EN_CLK)};

	Integer ncalibCmds = 5;
	Integer ncalibIdAddr = 1;
	PhyCmd calibCmds[ncalibCmds] = {
				PhyCmd { inSyncMode: inSyncMode, phyCycle: PHY_CHIP_SEL, nandCmd: tagged ChipSel chipR, 
	 						numBurst: 0, postCmdWait: 0},
				PhyCmd { inSyncMode: inSyncMode, phyCycle: PHY_CMD, nandCmd: tagged OnfiCmd N_READ_ID, 
							numBurst: 0, postCmdWait: 0},
				PhyCmd { inSyncMode: inSyncMode, phyCycle: PHY_ADDR, nandCmd: ?, 
							numBurst: 1, postCmdWait: t_WHR},
				PhyCmd { inSyncMode: inSyncMode, phyCycle: PHY_SYNC_CALIB, nandCmd: ?, 
							numBurst: 8, postCmdWait: t_RHW},
				PhyCmd { inSyncMode: inSyncMode, phyCycle: PHY_DESELECT_ALL, nandCmd: ?, 
							numBurst: 0, postCmdWait: 0}
				};
	Bit#(8) calibIdAddr = 8'h00;


	rule doEnNandClk if (state==INIT_EN_NANDCLK);
		phy.phyUser.sendCmd(enNandclkCmd);
		//Go issue a status poll to initialize IDDR to a defined value (instead of DON'T CARE)
		state <= POLL_STATUS;
		rdyReturnState <= INIT_CALIB;
		cmdCnt <= 0;
		addrCnt <= 0;
		//We have entered Sync Mode 5
		inSyncMode <= True;
	endrule

	//Calibration rules
	rule doInitCalib if (state==INIT_CALIB && cmdCnt < fromInteger(ncalibCmds));
		phy.phyUser.sendCmd(calibCmds[cmdCnt]);
		cmdCnt <= cmdCnt + 1;
	endrule

	rule doInitCalibIdAddr if (state==INIT_CALIB && addrCnt < fromInteger(ncalibIdAddr));
		phy.phyUser.sendAddr(calibIdAddr);
		addrCnt <= addrCnt+1;
	endrule

	rule doInitCalibDone if (state==INIT_CALIB && cmdCnt==fromInteger(ncalibCmds) &&
										addrCnt==fromInteger(ncalibIdAddr));
		state <= IDLE;
	endrule
	
	//******************************************************
	// Debug
	//******************************************************
	//rule debugStatus;
		//phy.phyDebug.setDebug0(debugR0);
		//phy.phyDebug.setDebug1(zeroExtend(pack(state)));
		//phy.phyDebug.setDebug1({debugFlagHi, debugFlagLo});
	//endrule

	rule writeError if (state==WRITE_ERROR);
		$display("@%t, %m: *** write error!", $time);
	endrule

	rule readError if (state==READ_ERROR);
		$display("@%t, %m: *** read error!", $time);
	endrule

	//******************************************************
	// ECC Rules
	//******************************************************

	rule doEncoderIn;
		rsEncoderHi.rs_enc_in.put( truncateLSB(encodeInQ.first()) );
		rsEncoderLo.rs_enc_in.put( truncate(encodeInQ.first()) );
		encodeInQ.deq();
	endrule

	rule doEncoderOut;
		Byte encDataHi <- rsEncoderHi.rs_enc_out.get();
		Byte encDataLo <- rsEncoderLo.rs_enc_out.get();
		encodeOutQ.enq({encDataHi, encDataLo});
	endrule

	rule doDecoderDataBuf;
		decodeInQ.deq();
		decodeInBufQ.enq(decodeInQ.first);
	endrule

	rule doDecoderDataIn;
		rsDecoderHi.rs_input.put( truncateLSB(decodeInBufQ.first()) );
		rsDecoderLo.rs_input.put( truncate(decodeInBufQ.first()) );
		decodeInBufQ.deq();
	endrule

	rule doDecoderKIn;
		rsDecoderHi.rs_k_in.put( decodeKQ.first() );
		rsDecoderLo.rs_k_in.put( decodeKQ.first() );
		decodeKQ.deq();
	endrule

	rule doDecoderTIn;
		rsDecoderHi.rs_t_in.put( decodeTQ.first() );
		rsDecoderLo.rs_t_in.put( decodeTQ.first() );
		decodeTQ.deq();
	endrule

	//rule doDecoderOutHi;
	//	Bit#(8) dataHi <- rsDecoderHi.rs_output.get();
	//	decodeOutHiQ.enq(dataHi);
	//endrule

	//rule doDecoderOutLo;
	//	Bit#(8) dataLo <- rsDecoderLo.rs_output.get();
	//	decodeOutLoQ.enq(dataLo);
	//endrule

	//TODO: for now, if encountered an uncorrectable err, just print it
	rule doDecoderHiCantCorrect;
		Bool errHi <- rsDecoderHi.rs_flag.get();
		debugFlagHi <= zeroExtend(pack(errHi));
		if (errHi) begin
			$display("@%t\t%m: *** read error! decoderHi ECC can't correct flag raised", $time);
		end
	endrule

	rule doDecoderLoCantCorrect;
		Bool errLo <- rsDecoderLo.rs_flag.get();
		debugFlagLo <= zeroExtend(pack(errLo));
		if (errLo) begin
			$display("@%t\t%m: *** read error! decoderLo ECC can't correct flag raised", $time);
		end
	endrule



	//******************************************************
	// Interfaces
	//******************************************************
	interface nandPins = phy.nandPins;

	interface BusIfc busIfc;
		method Action sendCmd (FlashCmd cmd);
			flashCmdQ.enq( cmd );
		endmethod

		//Requests for the write data to be buffered for a request
		method ActionValue#(TagT) writeDataBufReq(); 
			wrDataBufReqQ.deq();
			return wrDataBufReqQ.first();
		endmethod

		//Requests for the write data to be transferred
		method ActionValue#(Bit#(1)) writeDataTransferReq(); 
			wrDataTransReqQ.deq();
			return wrDataTransReqQ.first();
		endmethod

		method Action writeWord (Bit#(16) data);
			encodeInQ.enq(data);
			//enq k into Encoder every k words of data. 16 blocks of k=243; k_last=208
			if (wrEnqWordCnt == 0)
			begin
				wrEnqWordCnt <= wrEnqWordCnt + 1;
				//We make sure k_in has FIFO of a reasonable size so method fires
				if (wrEnqBlkCnt == fromInteger(pageECCBlks-1)) begin
					rsEncoderHi.rs_k_in.put(fromInteger(valueOf(K_LAST)));
					rsEncoderLo.rs_k_in.put(fromInteger(valueOf(K_LAST)));
					currK <= fromInteger(valueOf(K_LAST));
					wrEnqBlkCnt <= 0;
	//				$display("@%t %m: Enq K=%d, data=%x", $time, valueOf(K_LAST), data);
				end
				else begin
					rsEncoderHi.rs_k_in.put(fromInteger(valueOf(K)));
					rsEncoderLo.rs_k_in.put(fromInteger(valueOf(K)));
					currK <= fromInteger(valueOf(K));
					wrEnqBlkCnt <= wrEnqBlkCnt + 1;
	//				$display("@%t %m: Enq K=%d, data=%x", $time, valueOf(K), data);
				end
			end
			else if (wrEnqWordCnt == currK-1) 
			begin
				wrEnqWordCnt <= 0; 
	//			$display("@%t %m: Enq last word, data=%x", $time, data);
			end
			else begin
				wrEnqWordCnt <= wrEnqWordCnt + 1;
			end
		endmethod 



		method ActionValue#(Tuple2#(Bit#(16), TagT)) readWord (); 
			if (rdWdCnt < fromInteger(pageSizeUser/2 - 1)) begin
				rdWdCnt <= rdWdCnt + 1;
			end
			else begin
				rdWdCnt <= 0;
				readTagQ.deq();
			end
			TagT rtag = readTagQ.first();
			//Bit#(16) dataAll = {decodeOutHiQ.first, decodeOutLoQ.first};
			//decodeOutHiQ.deq;
			//decodeOutLoQ.deq;
			Bit#(8) dataHi <- rsDecoderHi.rs_output.get();
			Bit#(8) dataLo <- rsDecoderLo.rs_output.get();
			Bit#(16) dataAll = {dataHi, dataLo};
			return tuple2(dataAll, rtag);
		endmethod
	
		method ActionValue#(Tuple2#(TagT, StatusT)) ackStatus (); 
			ackQ.deq();
			return ackQ.first();
		endmethod

		method Bool isInitIdle();
			//This method only works to tell the flash controller that it can issue the next
			// initialization command
			//idle if in idle state and no pending requests
			return ((state==UNINIT || state==IDLE) && (!flashCmdQ.notEmpty) && (phy.phyUser.isIdle));
		endmethod
	
		method Action setWdataRdy(Bool rdy, TagT tag);
			sb.setWdataRdy(rdy, tag);
		endmethod

		method Bit#(16) getDebugRawData;
			return debugR0;
		endmethod

		method Bit#(16) getDebugBusState;
			return (zeroExtend(pack(state)));
		endmethod

		method Bit#(16) getDebugAddr;
			return debugAddr;
		endmethod
	endinterface

	interface phyWenNclkGet = phy.phyWenNclkGet;
	
	//interface phyDebugCtrl = phy.phyDebugCtrl;

	//interface phyDebug = phy.phyDebug;

endmodule

