import FIFOF		::*;
import FIFO		::*;
import Vector		::*;
import Connectable ::*;
import RegFile::*;

import ChipscopeWrapper::*;
import ControllerTypes::*;
import FlashController::*;
import NullResetN::*;

typedef enum {
	INIT = 0,
	INIT_WAIT = 1,
	IDLE = 2,
	READ = 3,
	READ_DATA = 4,
	WRITE = 5,
	WRITE_DATA = 6,
	ERASE = 7,
	ACT_SYNC = 8,
	DONE = 9,
	SETUP_TAG_FREE = 10,
	TEST_SUITE = 11,
	TEST_SUITE_WAIT_DONE = 12,
	TEST_SUITE_DONE = 13
} TbState deriving (Bits, Eq);


//Create data by hashing the address
function Bit#(128) getDataHash (Bit#(16) dataCnt, Bit#(8) page, Bit#(16) block, ChipT chip, BusT bus);
		Bit#(8) dataCntTrim = truncate(dataCnt << 3);
		Bit#(8) blockTrim = truncate(block);
		Bit#(8) chipTrim = zeroExtend(chip);
		Bit#(8) busTrim = zeroExtend(bus);

		Vector#(8, Bit#(16)) dataAggr = newVector();
		for (Integer i=7; i >= 0; i=i-1) begin
			Bit#(8) dataHi = truncate(dataCntTrim + fromInteger(i) + 8'hA0 + (blockTrim<<4)+ (chipTrim<<2) + (busTrim<<6));
			Bit#(8) dataLow = truncate( (~dataHi) + blockTrim );
			dataAggr[i] = {dataHi, dataLow};
		end
		return pack(dataAggr);
endfunction

/*
//Create data by hashing the address
function Bit#(16) getDataHash (Bit#(16) dataCnt, Bit#(8) page, Bit#(16) block, ChipT chip, BusT bus);
		Bit#(8) dataCntTrim = truncate(dataCnt);
		Bit#(8) blockTrim = truncate(block);
		Bit#(8) chipTrim = zeroExtend(chip);
		Bit#(8) busTrim = zeroExtend(bus);

		Bit#(8) dataHi = truncate(dataCntTrim + 8'hA0 + (blockTrim<<4)+ (chipTrim<<2) + (busTrim<<6));
		Bit#(8) dataLow = truncate( (~dataHi) + blockTrim );
		Bit#(16) d = {dataHi, dataLow};
		return d;
endfunction
*/

function FlashCmd decodeVin (Bit#(64) vinCmd, TagT tag);
	BusT bus = truncate(vinCmd[47:40]);
	FlashOp flashOp;
	let cmdInOp = vinCmd[55:48];
	case (cmdInOp)
		1: flashOp = READ_PAGE;
		2: flashOp = WRITE_PAGE;
		3: flashOp = ERASE_BLOCK;
		default: flashOp = READ_PAGE;
	endcase
	FlashCmd cmd = FlashCmd { 	tag: tag,
								bus: bus,
								op: flashOp,
								chip: truncate(vinCmd[39:32]),
								block: truncate(vinCmd[31:16]),
								page: truncate(vinCmd[15:0]) };
	return cmd;
endfunction

function Bit#(64) getCurrVin(Bit#(64) vio_in);
	Bit#(64) vin;
	`ifdef NAND_SIM
		//use fixed test suite for simulation
		vin = 64'hFF00000000000000; 
	`else
		vin = vio_in;
	`endif
	return vin;
endfunction

function FlashCmd getNextCmd (TagT tag, Bit#(8) testSetSel, Bit#(16) cmdCnt);
	FlashOp op = INVALID;
	ChipT c = 0;
	BusT bus = 0;
	Bit#(16) blk = 0;
	Integer numSeqBlks = 16384;

	//sequential read, same bus
	if (testSetSel == 8'h01) begin
		if (cmdCnt < fromInteger(numSeqBlks)) begin //issue 10k commands (~80MB)
			bus = 0;
			`ifdef SLC_NAND
				c = cmdCnt[1:0]; 
				blk = zeroExtend(cmdCnt[15:2]);
			`else
				c = cmdCnt[2:0]; 
				blk = zeroExtend(cmdCnt[15:3]);
			`endif
			op = READ_PAGE;
		end
	end
	//sequential write, same bus
	else if (testSetSel == 8'h02) begin
		if (cmdCnt < fromInteger(numSeqBlks)) begin //issue 10k commands (~80MB)
			bus = 0;
			`ifdef SLC_NAND
				c = cmdCnt[1:0]; 
				blk = zeroExtend(cmdCnt[15:2]);
			`else
				c = cmdCnt[2:0]; 
				blk = zeroExtend(cmdCnt[15:3]);
			`endif
			op = WRITE_PAGE;
		end
	end

	//sequential erase, same bus
	else if (testSetSel == 8'h03) begin
		if (cmdCnt < fromInteger(numSeqBlks)) begin //issue 10k commands (~80MB)
			bus = 0;
			`ifdef SLC_NAND
				c = cmdCnt[1:0]; 
				blk = zeroExtend(cmdCnt[15:2]);
			`else
				c = cmdCnt[2:0]; 
				blk = zeroExtend(cmdCnt[15:3]);
			`endif
			op = ERASE_BLOCK;
		end
	end

	//sequential read, 2 buses
	else if (testSetSel == 8'h04) begin
		if (cmdCnt < fromInteger(numSeqBlks)) begin //issue 10k commands (~80MB)
			bus = zeroExtend(cmdCnt[0]); 
			`ifdef SLC_NAND
				c = cmdCnt[2:1]; 
				blk = zeroExtend(cmdCnt[15:3]);
			`else
				c = cmdCnt[3:1]; 
				blk = zeroExtend(cmdCnt[15:4]);
			`endif
			op = READ_PAGE;
		end
	end
	//sequential write, 2 buses
	else if (testSetSel == 8'h05) begin
		if (cmdCnt < fromInteger(numSeqBlks)) begin //issue 10k commands (~80MB)
			bus = zeroExtend(cmdCnt[0]); 
			`ifdef SLC_NAND
				c = cmdCnt[2:1]; 
				blk = zeroExtend(cmdCnt[15:3]);
			`else
				c = cmdCnt[3:1]; 
				blk = zeroExtend(cmdCnt[15:4]);
			`endif
			op = WRITE_PAGE;
		end
	end
	//sequential erase, 2 buses
	else if (testSetSel == 8'h06) begin
		if (cmdCnt < fromInteger(numSeqBlks)) begin //issue 10k commands (~80MB)
			bus = zeroExtend(cmdCnt[0]); 
			`ifdef SLC_NAND
				c = cmdCnt[2:1]; 
				blk = zeroExtend(cmdCnt[15:3]);
			`else
				c = cmdCnt[3:1]; 
				blk = zeroExtend(cmdCnt[15:4]);
			`endif
			op = ERASE_BLOCK;
		end
	end

`ifndef NAND_SIM //if not simulating, then include tb for all buses
	//sequential read, 4 buses
	else if (testSetSel == 8'h07) begin
		if (cmdCnt < fromInteger(numSeqBlks)) begin //issue 10k commands (~80MB)
			bus = zeroExtend(cmdCnt[1:0]); 
			c = cmdCnt[4:2]; 
			blk = zeroExtend(cmdCnt[15:5]);
			op = READ_PAGE;
		end
	end
	//sequential write, 4 buses
	else if (testSetSel == 8'h08) begin
		if (cmdCnt < fromInteger(numSeqBlks)) begin //issue 10k commands (~80MB)
			bus = zeroExtend(cmdCnt[1:0]); 
			c = cmdCnt[4:2]; 
			blk = zeroExtend(cmdCnt[15:5]);
			op = WRITE_PAGE;
		end
	end
	//sequential erase, 4 buses
	else if (testSetSel == 8'h09) begin
		if (cmdCnt < fromInteger(numSeqBlks)) begin //issue 10k commands (~80MB)
			bus = zeroExtend(cmdCnt[1:0]); 
			c = cmdCnt[4:2]; 
			blk = zeroExtend(cmdCnt[15:5]);
			op = ERASE_BLOCK;
		end
	end

	//sequential read, 8 buses
	else if (testSetSel == 8'h0A) begin
		if (cmdCnt < fromInteger(numSeqBlks)) begin //issue 10k commands (~80MB)
			bus = zeroExtend(cmdCnt[2:0]); 
			c = cmdCnt[5:3]; 
			blk = zeroExtend(cmdCnt[15:6]);
			op = READ_PAGE;
		end
	end
	//sequential write, 8 buses
	else if (testSetSel == 8'h0B) begin
		if (cmdCnt < fromInteger(numSeqBlks)) begin //issue 10k commands (~80MB)
			bus = zeroExtend(cmdCnt[2:0]); 
			c = cmdCnt[5:3]; 
			blk = zeroExtend(cmdCnt[15:6]);
			op = WRITE_PAGE;
		end
	end
	//sequential erase, 8 buses
	else if (testSetSel == 8'h0C) begin
		if (cmdCnt < fromInteger(numSeqBlks)) begin //issue 10k commands (~80MB)
			bus = zeroExtend(cmdCnt[2:0]); 
			c = cmdCnt[5:3]; 
			blk = zeroExtend(cmdCnt[15:6]);
			op = ERASE_BLOCK;
		end
	end
	//----------------------------------------------------------
	//sequential read, same bus, one chip
	else if (testSetSel == 8'h0D) begin
		if (cmdCnt < fromInteger(numSeqBlks/8)) begin //issue 10k commands (~80MB)
			bus = 0;
			c = 0; 
			blk = zeroExtend(cmdCnt[15:0]);
			op = READ_PAGE;
		end
	end
	//sequential write, same bus, one chip
	else if (testSetSel == 8'h0E) begin
		if (cmdCnt < fromInteger(numSeqBlks/8)) begin //issue 10k commands (~80MB)
			bus = 0;
			c = 0; 
			blk = zeroExtend(cmdCnt[15:0]);
			op = WRITE_PAGE;
		end
	end

	//sequential erase, same bus, one chip
	else if (testSetSel == 8'h0F) begin
		if (cmdCnt < fromInteger(numSeqBlks/8)) begin //issue 10k commands (~80MB)
			bus = 0;
			c = 0; 
			blk = zeroExtend(cmdCnt[15:0]);
			op = ERASE_BLOCK;
		end
	end

	//sequential read, same bus, 2 chips
	else if (testSetSel == 8'h10) begin
		if (cmdCnt < fromInteger(numSeqBlks/8)) begin //issue 10k commands (~80MB)
			bus = 0;
			c = zeroExtend(cmdCnt[0]); 
			blk = zeroExtend(cmdCnt[15:1]);
			op = READ_PAGE;
		end
	end
	//sequential write, same bus, 2 chip
	else if (testSetSel == 8'h11) begin
		if (cmdCnt < fromInteger(numSeqBlks/8)) begin //issue 10k commands (~80MB)
			bus = 0;
			c = zeroExtend(cmdCnt[0]); 
			blk = zeroExtend(cmdCnt[15:1]);
			op = WRITE_PAGE;
		end
	end

	//sequential erase, same bus, 2 chips
	else if (testSetSel == 8'h12) begin
		if (cmdCnt < fromInteger(numSeqBlks/8)) begin //issue 10k commands (~80MB)
			bus = 0;
			c = zeroExtend(cmdCnt[0]); 
			blk = zeroExtend(cmdCnt[15:1]);
			op = ERASE_BLOCK;
		end
	end

	//sequential read, same bus, 4 chip
	else if (testSetSel == 8'h13) begin
		if (cmdCnt < fromInteger(numSeqBlks/8)) begin //issue 10k commands (~80MB)
			bus = 0;
			c = zeroExtend(cmdCnt[1:0]); 
			blk = zeroExtend(cmdCnt[15:2]);
			op = READ_PAGE;
		end
	end
	//sequential write, same bus, 4 chip
	else if (testSetSel == 8'h14) begin
		if (cmdCnt < fromInteger(numSeqBlks/8)) begin //issue 10k commands (~80MB)
			bus = 0;
			c = zeroExtend(cmdCnt[1:0]); 
			blk = zeroExtend(cmdCnt[15:2]);
			op = WRITE_PAGE;
		end
	end

	//sequential erase, same bus, 4 chips
	else if (testSetSel == 8'h15) begin
		if (cmdCnt < fromInteger(numSeqBlks/8)) begin //issue 10k commands (~80MB)
			bus = 0;
			c = zeroExtend(cmdCnt[1:0]); 
			blk = zeroExtend(cmdCnt[15:2]);
			op = ERASE_BLOCK;
		end
	end

	//sequential read, same bus, 8 chip
	else if (testSetSel == 8'h16) begin
		if (cmdCnt < fromInteger(numSeqBlks/8)) begin //issue 10k commands (~80MB)
			bus = 0;
			c = cmdCnt[2:0]; 
			blk = zeroExtend(cmdCnt[15:3]);
			op = READ_PAGE;
		end
	end
	//sequential write, same bus, 8 chip
	else if (testSetSel == 8'h17) begin
		if (cmdCnt < fromInteger(numSeqBlks/8)) begin //issue 10k commands (~80MB)
			bus = 0;
			c = cmdCnt[2:0]; 
			blk = zeroExtend(cmdCnt[15:3]);
			op = WRITE_PAGE;
		end
	end

	//sequential erase, same bus, 8 chips
	else if (testSetSel == 8'h18) begin
		if (cmdCnt < fromInteger(numSeqBlks/8)) begin //issue 10k commands (~80MB)
			bus = 0;
			c = cmdCnt[2:0]; 
			blk = zeroExtend(cmdCnt[15:3]);
			op = ERASE_BLOCK;
		end
	end

	//sequential read, 8 buses, 8 chips CONTINUOUS
	else if (testSetSel == 8'h19) begin
		bus = zeroExtend(cmdCnt[2:0]); 
		c = cmdCnt[5:3]; 
		blk = zeroExtend(cmdCnt[13:6]); //16k blocks is 14-bit cmdCnt
		op = READ_PAGE;
	end

`endif //ifndef NAND_SIM


   //Sim: 2 writes, 2 reads same chip/bus
	else if (testSetSel == 8'hFF) begin
		bus = 0;
		c = 0; 
		//blk = zeroExtend(cmdCnt[0]); 
		blk = 0;
		if (cmdCnt==0) begin
			op = WRITE_PAGE;
		end
		else if (cmdCnt==1) begin
			op = READ_PAGE;
		end
	end

	//Sim: 8 writes, 8 reads, 2 buses, 4 chips
	else if (testSetSel == 8'hFE) begin
		if (cmdCnt < 16) begin
			bus = zeroExtend(cmdCnt[0]);
			c = zeroExtend(cmdCnt[2:1]); 
			blk = 0; //doesnt matter
			op = (cmdCnt < 8) ? WRITE_PAGE : READ_PAGE; 
		end
	end

	FlashCmd cmd =	FlashCmd {	tag: tag,
										bus: bus,
										op: op,
										chip: c,
										block: blk,
										page: 0 };
	return cmd;
endfunction

interface TbIfc;
	(* prefix = "" *)
	interface FlashCtrlPins pins;
endinterface

(* no_default_clock, no_default_reset *)
(*synthesize*)
module mkTopTB#(
		Clock sysClkP, 
		Clock sysClkN
		//Reset sysRstn
	) (TbIfc);

	NullResetNIfc nullResetN <- mkNullResetN();

	//instantiate flash controller
	FlashControllerIfc flashCtrl <- mkFlashController(sysClkP, sysClkN, nullResetN.rst_n/*sysRstn*/);
	Clock clk0 = flashCtrl.infra.sysclk0;
	Reset rst0 = flashCtrl.infra.sysrst0;

	RegFile#(TagT, FlashCmd) tagTable <- mkRegFileFull(clocked_by clk0, reset_by rst0);

	Reg#(TbState) state <- mkReg(SETUP_TAG_FREE, clocked_by clk0, reset_by rst0);
	Reg#(Bit#(64)) vinPrev <- mkReg(0, clocked_by clk0, reset_by rst0);
	Vector#(NumTags, Reg#(Bit#(16))) rdataCnt <- replicateM(mkReg(0, clocked_by clk0, reset_by rst0));
	Reg#(FlashCmd) tagCmd <- mkRegU(clocked_by clk0, reset_by rst0);
	FIFOF#(TagT) tagFreeList <- mkSizedFIFOF(valueOf(NumTags), clocked_by clk0, reset_by rst0);
	Reg#(Bit#(16)) tagFreeCnt <- mkReg(0, clocked_by clk0, reset_by rst0);
	
	Reg#(Bit#(16)) wdataCnt <- mkReg(0, clocked_by clk0, reset_by rst0);
	Reg#(Bit#(2)) wrState <- mkReg(0, clocked_by clk0, reset_by rst0);
	
	Reg#(Bit#(64)) latencyCnt <- mkReg(0, clocked_by clk0, reset_by rst0);
	Vector#(NUM_BUSES, Reg#(Bit#(64))) errCnt <- replicateM(mkReg(0, clocked_by clk0, reset_by rst0));
	Reg#(Bit#(16)) cmdCnt <- mkReg(0, clocked_by clk0, reset_by rst0);


	//setup tag free list
	rule doSetupTagFreeList if (state==SETUP_TAG_FREE);
		if (tagFreeCnt < fromInteger(valueOf(NumTags))) begin
			tagFreeList.enq(truncate(tagFreeCnt));
			tagFreeCnt <= tagFreeCnt + 1;
		end
		else begin
			state <= IDLE;
			tagFreeCnt <= 0;
		end
	endrule

	//Continuously send commands as fast as possible
	rule doIdleAcceptCmd if (state==IDLE);
		//VIO input command from Bus 0's PHY
		Bit#(64) vin = getCurrVin(flashCtrl.debug.debugVio.getDebugVout());

		//select a test set
		Bit#(8) testSetSel = vin[63:56];
		if (testSetSel == 0) begin //use VIO as cmd
			if (vin != 0 && vin != vinPrev) begin
				vinPrev <= vin;
				TagT newTag = tagFreeList.first();
				tagFreeList.deq();
				FlashCmd cmd = decodeVin(vin, newTag);
				flashCtrl.user.sendCmd(cmd); //send cmd
				tagTable.upd(newTag, cmd);
				$display("@%t\t%m: tb sent cmd: %x", $time, vin);
				latencyCnt <= 0; //latency counter
			end
			cmdCnt <= 0;
		end
		else begin //use predefined test set
			state <= TEST_SUITE;
			cmdCnt <= 0;
			latencyCnt <= 0;
			for (Integer i=0; i < valueOf(NUM_BUSES); i=i+1) begin
				errCnt[i] <= 0;
			end
		end
	endrule


	rule doTestSuite if (state==TEST_SUITE);
		//get a free tag
		TagT newTag = tagFreeList.first();

		//get new command
		Bit#(64) vin = getCurrVin(flashCtrl.debug.debugVio.getDebugVout());
		Bit#(8) testSetSel = vin[63:56];
		let cmd = getNextCmd(newTag, testSetSel, cmdCnt);

		//check if done
		if (cmd.op == INVALID) begin
			state <= TEST_SUITE_WAIT_DONE;
		end
		else begin
			tagFreeList.deq(); //deq only when command is valid!!
			//upate tag table
			tagTable.upd(newTag, cmd);
			//issue command
			flashCtrl.user.sendCmd(cmd);
			//increment count, check if done. 
			cmdCnt <= cmdCnt + 1;
			$display("@%t\t%m: tb sent cmd: tag=%x, bus=%d, op=%d, chip=%d, blk=%d", $time,
	  						newTag, cmd.bus, cmd.op, cmd.chip, cmd.block);
		end
	endrule

	rule doTestSuiteWaitDone if (state==TEST_SUITE_WAIT_DONE);
		if (!tagFreeList.notFull) begin //wait until all tags are returned
			state <= TEST_SUITE_DONE;
		end
	endrule

	rule doTestSuiteDone if (state==TEST_SUITE_DONE);
		Bit#(64) vin = getCurrVin(flashCtrl.debug.debugVio.getDebugVout());
		$display("@%t\t%m: tb test suite complete", $time);
		if (vin[63:56] == 0) begin
			state <= IDLE;
		end
	endrule

	rule incLatencyCnt;
		latencyCnt <= latencyCnt + 1;
	endrule

	//Handle data requests and acks from the Flash controller
	rule doAck;
		let ack <- flashCtrl.user.ackStatus();
		TagT t = tpl_1(ack);
		tagFreeList.enq(t);
		$display("@%t\t%m: FlashController ack returned tag=%x", $time, t);
	endrule

	rule doWriteDataReq if (wrState == 0);
		TagT tag <- flashCtrl.user.writeDataReq();
		tagCmd <= tagTable.sub(tag);
		wdataCnt <= 0;
		wrState <= 1;
	endrule

	/*
	Reg#(Bit#(32)) wrDelayCnt <- mkReg(50, clocked_by clk0, reset_by rst0);

	rule doWriteDataReqDelay if (wrState == 1);
		if (wrDelayCnt==0) begin
			wrState <= 2;
			wrDelayCnt <= 5;
		end
		else begin
			wrDelayCnt<=wrDelayCnt - 1;
		end
	endrule
	*/

	//Send write data slowly
	rule doWriteDataSend if (wrState ==1);
		if (wdataCnt < fromInteger(pageSizeUser/16)) begin
			Bit#(128) wData = getDataHash(wdataCnt, tagCmd.page, 
											tagCmd.block, tagCmd.chip, tagCmd.bus);
			flashCtrl.user.writeWord(tuple2(wData, tagCmd.tag));
			wdataCnt <= wdataCnt + 1;
			$display("@%t\t%m: tb sent write data [%d]: %x", $time, wdataCnt, wData);
		end
		else begin
			wrState <= 0;
			//Return free tag.
			//tagFreeList.enq(tagCmd.tag); 
			//$display("@%t\t%m: FlashController write returned tag=%x", $time, tagCmd[i].tag);
		end
	endrule
	
	//Pipelined to reduce critical path
	/*
	//FIXME: testing read slowly
	Reg#(Tuple2#(Bit#(128), TagT)) taggedRDataR <- mkRegU(clocked_by clk0, reset_by rst0);
	Reg#(Bit#(4)) readState <- mkReg(0, clocked_by clk0, reset_by rst0);
	Reg#(Bit#(32)) readWait <- mkReg(10000, clocked_by clk0, reset_by rst0);
	rule doReadDataAccept if (readState==0);
		let taggedRData <- flashCtrl.user.readWord();
		taggedRDataR <= taggedRData;
		readState <= 1;
	endrule

	rule doReadWait if (readState==1);
		if (readWait ==  0) begin
			readState <= 2;
			readWait <= 16;
		end
		else begin
			readWait <= readWait - 1;
		end
	endrule


	rule doReadDecode if (readState == 2);
		let taggedRData = taggedRDataR;
		Bit#(128) rdata = tpl_1(taggedRData);
		//rDataDebug[i] <= rdata;
		TagT rTag = tpl_2(taggedRData);
		FlashCmd cmd = tagTable.sub(rTag);
		//FlashCmd cmd = tagTable[rTag];
		rdata2check.enq(rdata);
		rcmd2check.enq(cmd);
		readState <= 0;
	endrule
	*/

	FIFO#(Bit#(128)) rdata2gold <- mkFIFO(clocked_by clk0, reset_by rst0);
	FIFO#(Bit#(128)) rdata2check <- mkFIFO(clocked_by clk0, reset_by rst0);
	FIFO#(Bit#(128)) wdata2check <- mkFIFO(clocked_by clk0, reset_by rst0);
	FIFO#(FlashCmd) rcmd2gold <- mkFIFO(clocked_by clk0, reset_by rst0);
	FIFO#(FlashCmd) rcmd2check <- mkFIFO(clocked_by clk0, reset_by rst0);
	
	rule doReadData;
		let taggedRData <- flashCtrl.user.readWord();
		Bit#(128) rdata = tpl_1(taggedRData);
		//rDataDebug[i] <= rdata;
		TagT rTag = tpl_2(taggedRData);
		FlashCmd cmd = tagTable.sub(rTag);
		//FlashCmd cmd = tagTable[rTag];
		rdata2gold.enq(rdata);
		rcmd2gold.enq(cmd);
	endrule
	
	rule doReadDataGold;
		FlashCmd cmd = rcmd2gold.first;
		Bit#(128) rdata = rdata2gold.first;
		rcmd2gold.deq();
		rdata2gold.deq();
		Bit#(128) wData = getDataHash(rdataCnt[cmd.tag], cmd.page, cmd.block, cmd.chip, cmd.bus);
		rdata2check.enq(rdata);
		wdata2check.enq(wData);
		rcmd2check.enq(cmd);
	endrule


	rule doReadDataCheck;
		FlashCmd cmd = rcmd2check.first;
		Bit#(128) rdata = rdata2check.first;
		Bit#(128) wData = wdata2check.first;
		wdata2check.deq;
		rdata2check.deq;
		rcmd2check.deq;

		//check
		if (rdata != wData) begin
			$display("@%t\t%m: *** tb readback error at [%d] tag=%x, bus=%d, chip=%d, block=%d; Expected %x, got %x",
						$time, rdataCnt[cmd.tag], cmd.tag, cmd.bus, cmd.chip, cmd.block, wData, rdata);
			errCnt[cmd.bus] <= errCnt[cmd.bus] + 1;
		end
		else begin
			$display("@%t\t%m: tb readback OK! tag=%x, data[%d]=%x", $time, cmd.tag, rdataCnt[cmd.tag], rdata);
		end
		if (rdataCnt[cmd.tag] < fromInteger(pageSizeUser/16 - 1)) begin
			rdataCnt[cmd.tag] <= rdataCnt[cmd.tag] + 1;
		end
		else begin
			tagFreeList.enq(cmd.tag);
			$display("@%t\t%m: tb read returned tag=%x", $time, cmd.tag);
			rdataCnt[cmd.tag] <= 0;
		end
	endrule

	//debug
	for (Integer i=0; i < valueOf(NUM_BUSES); i=i+1) begin
		rule doDebug;
			flashCtrl.debug.debugBus[i].debugPort4(zeroExtend(pack(state)));
			flashCtrl.debug.debugBus[i].debugPort5_64(latencyCnt);
			flashCtrl.debug.debugBus[i].debugPort6_64(errCnt[i]);
		endrule
	end

	rule debugSetVio;
		flashCtrl.debug.debugVio.setDebugVin(flashCtrl.debug.debugVio.getDebugVout());
	endrule

		
	interface pins = flashCtrl.pins;

endmodule

