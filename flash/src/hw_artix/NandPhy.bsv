//Potential timing problems:
// DQS and clk90 are not aligned on a read. It appears that ISERDESE2 align its output to 
// OCLK (which is clk90), but I cannot be sure. 
//At power up, default mode is * asynchronous mode 0 *


import Connectable       ::*;
import Clocks            ::*;
import FIFO              ::*;
import FIFOF             ::*;
import SpecialFIFOs      ::*;
import TriState          ::*;
import Vector            ::*;
import Counter           ::*;
import DefaultValue      ::*;

import ControllerTypes::*;
import NandPhyWrapper::*;
import NandPhyWenNclkWrapper::*;

interface PhyUser;
	method Action sendCmd (PhyCmd cmd);
	method Action sendAddr (Bit#(8) addr);
	method ActionValue#(Bit#(16)) rdWord();
	method Action wrWord (Bit#(16) data);
	method Bool isIdle();
endinterface

/*
interface PhyDebugCtrl;
	interface Inout#(Bit#(36)) dbgCtrlIla;
	interface Inout#(Bit#(36)) dbgCtrlVio;
endinterface


interface PhyDebug;
	method Action setDebug0 (Bit#(16) d);
	method Action setDebug1 (Bit#(16) d);
	method Action setDebug2 (Bit#(16) d);
	method Action setDebug3 (Bit#(16) d);
	method Action setDebug4 (Bit#(16) d);
	method Action setDebug5 (Bit#(16) d);
	method Action setDebug6 (Bit#(16) d);
	method Action setDebug7 (Bit#(16) d);
	method Action setDebugVin (Bit#(64) d);
	method Bit#(64) getDebugVout ();
endinterface
*/
interface PhyWenNclkGet;
	method Bit#(1) getWEN;
	method Bit#(1) getWENSel;
endinterface

interface NandPhyIfc;
	interface NANDPins nandPins;
	interface PhyUser phyUser;
	//interface PhyDebugCtrl phyDebugCtrl;
	//interface PhyDebug phyDebug;
	interface PhyWenNclkGet phyWenNclkGet;
endinterface


typedef enum {
	INIT_WAIT				= 0,
	ADJ_IDELAY_DQ			= 1,
	ADJ_IDELAY_DQS			= 2,
	INIT_NAND_PWR_WAIT	= 3,
	INIT_WP					= 4,
	WAIT_CYCLES				= 5,
	IDLE						= 6,
	ASYNC_CHIP_SEL			= 7,
	ASYNC_CMD_SET_CMD		= 8,
	ASYNC_CMD_LATCH_WE	= 9,
	ASYNC_READ_RE_LOW		= 10,
	ASYNC_READ_CAPTURE	= 11,
	ASYNC_READ_RE_HIGH	= 12,
	ASYNC_ADDR_WE_LOW		= 13,
	ASYNC_ADDR_WE_HIGH	= 14,
	ASYNC_WRITE_WE_LOW	= 15,
	ASYNC_WRITE_WE_HIGH	= 16,
	ASYNC_DONE				= 17,


	SYNC_CMD_SET			= 20,
	SYNC_CMD_LATCH			= 21,
	SYNC_READ_WR_LOW 		= 22,
	SYNC_READ_LATCH		= 23,
	SYNC_READ_CAPTURE		= 24,
	SYNC_ADDR_SET			= 25,
	SYNC_ADDR_LATCH		= 26,
	SYNC_ADDR_BURST		= 27,
	SYNC_WRITE_PREAMBLE	= 28,
	SYNC_WRITE_BURST		= 29,
	SYNC_CALIB_WR_LOW		= 30,
	SYNC_CALIB_LATCH		= 31,
	SYNC_CALIB_DEQ			= 32,
	SYNC_CALIB_CALIBRATE	= 33,
	SYNC_CALIB_FAIL		= 34,

	SYNC_CHIP_SEL			= 40,
	SYNC_DONE				= 41,
	
	DESELECT_ALL			= 50,
	ENABLE_NAND_CLK		= 51


} PhyState deriving (Bits, Eq);

//Reverse DQ for chips on the back of the board
function Bit#(8) orderDQ (Bit#(8) dq_in, Bit#(8) cen);
	//if selecting LSB 4 bits of cen, don't reverse DQ
	if ( reduceAnd(cen[3:0]) == 0 )
		return dq_in;
	else //else reverse DQ
		return reverseBits(dq_in);
endfunction

function Bit#(3) ceTranslateSLC (ChipT cen);
	Bit#(3) transCen;
	case (cen) 
		0: transCen = 0;
		1: transCen = 1;
		2: transCen = 4;
		3: transCen = 5;
		default: transCen = 0;
	endcase
	return transCen;
endfunction


//Default clock and resets are: clk0 and rst0
(* synthesize *)
module mkNandPhy#(
	Clock clk90, 
	Reset rst90
	)(	
	//(* clocked_by="no_clock", reset_by="no_reset" *) Inout#(Bit#(36)) dbgCtrlIlaPhy, 
	//(* clocked_by="no_clock", reset_by="no_reset" *) Inout#(Bit#(36)) dbgCtrlVioPhy,
	NandPhyIfc ifc);

	//Conservative timing parameters. In clock cycles. a
	Integer t_SYS_RESET = 1000; //System reset wait
	//Power up wait time; In simulation, use SHORT_RESET param in nand model to reduce wait
	`ifdef NAND_SIM
		Integer t_POWER_UP = 100; //100us. Reduced to 1us for sim.
	`else
		Integer t_POWER_UP = 1000000000; //100us.
	`endif

	Integer t_WW = 20; //100ns. Write protect wait time.
	Integer t_ASYNC_CMD_SETUP = 8; //Max async cmd/data setup time before WE# latch
	Integer t_ASYNC_CMD_HOLD = 5; //Max async cmd/data hold time after WE# latch
	Integer t_ASYNC_ADDR_SETUP = 8; //Max async addr setup time before WE# latch
	Integer t_ASYNC_ADDR_HOLD = 5; //Max async addr hold time after WE# latch
	Integer t_ASYNC_WRITE_SETUP = 8; //Max async wr data setup time before WE# latch
	Integer t_ASYNC_WRITE_HOLD = 5; //Max async wr data hold time after WE# latch
	Integer t_RP = 7; //50ns. Async RE# pulse width. Mode 0.
	Integer t_REH = 5; //30ns. Async RE# High hold time. Note: tRC=tRP+tREH >100n
	//Sync timing params
	Integer t_CAD = 3; //25ns 
	Integer t_CMD_DQ_SYNCREG_DELAY = 2; //2 sync regs used for DQ cmd path
	Integer t_WRCK_DQSD = 4; //20ns. Chose a safe value to wait until NAND drives DQS
	Integer t_CKWR = 3; 
	Integer t_CKWR_DQSCK_IDDR = 2; //( tCKWR - (t_DQSCK+t_ISERDES) ) Num of cycs to wait after read bursting
	Integer t_WPRE = 2; //15ns
	Integer t_WPST = 2; //15ns
	Integer t_DQSS = 2; //7.5 to 12.5ns


	//number of calibration bursts to sample
	Integer calibFifoDepth = 16;

	Clock defaultClk0 <- exposeCurrentClock();
	Reset defaultRst0 <- exposeCurrentReset();

	VNANDPhy vnandPhy <- vMkNandPhy(defaultClk0, clk90, defaultRst0, rst90);

	//State registers
	Reg#(PhyState) currState <- mkReg(INIT_WAIT);
	Reg#(PhyState) returnState <- mkReg(INIT_WAIT);

	//Timing wait counters
	Reg#(Bit#(32)) waitCnt <- mkReg(0);
	
	//DQS IDelay Tap register (0 to 31)
	Reg#(Bit#(5)) dlyValDQS <- mkReg(16);
	Reg#(Bit#(1)) dlyLdDQS <- mkReg(0);

	//Registers for command inputs
	Reg#(Bit#(8)) cen <- mkReg(8'hFF);
	Reg#(Bit#(1)) cle <- mkReg(0);
	Reg#(Bit#(1)) ale <- mkReg(0);
	Reg#(Bit#(1)) wrn <- mkReg(1);
	Reg#(Bit#(1)) wen <- mkReg(1); //WE# = NAND_CLK when wenSel=0
	Reg#(Bit#(1)) wenSel <- mkReg(1); //WE# by default. until sync mode active
	Reg#(Bit#(1)) wpn <- mkReg(0);

	//Registers for write data DQ
	Reg#(Bit#(8)) wrDataRise <- mkReg(0); 
	Reg#(Bit#(8)) wrDataFall <- mkReg(0); 
	Reg#(Bit#(1)) oenDataDQ <- mkReg(1); 
	Reg#(Bit#(1)) iddrRstDQ <- mkReg(1); //assert reset until we need IDDR

	//Registers for DQS
	Reg#(Bit#(1)) oenDQS <- mkReg(1); 
	Reg#(Bit#(1)) rstnDQS <- mkReg(0);//set to 1 to enable DQS toggle

	//Delay adjustment registers
	//Reg#(Bit#(5)) incIdelayDQS_90 <- mkReg(0, clocked_by clk90, reset_by rst90);
	//Reg#(Bit#(1)) dlyIncDQSr <- mkReg(0, clocked_by clk90, reset_by rst90);
	//Reg#(Bit#(1)) dlyCeDQSr <- mkReg(0, clocked_by clk90, reset_by rst90);
	//Reg#(Bool) initDoneSync <- mkSyncRegToCC(False, clk90, rst90);

	//Calibration registers, FIFOs and Counters
	Reg#(Bit#(8)) rLat <- mkReg(fromInteger(calibFifoDepth)); //initialize to max rLat
	Reg#(Bit#(1)) calibClk0Sel <- mkReg(0);
	Reg#(Bit#(8)) refDqR <- mkReg(8'h2C); //TODO how to set this
	FIFO#(Bit#(8)) fifoDqR0 <- mkSizedFIFO(calibFifoDepth);
	FIFO#(Bit#(8)) fifoDqR90 <- mkSizedFIFO(calibFifoDepth);
	FIFO#(Bit#(8)) fifoDqR180 <- mkSizedFIFO(calibFifoDepth);
	FIFO#(Bit#(8)) fifoDqR270 <- mkSizedFIFO(calibFifoDepth);
	Reg#(Bit#(16)) numCalibBrCnt <- mkReg(0);

	//Debug registers
	//Reg#(Bit#(8)) debugR90 <- mkReg(0, clocked_by clk90, reset_by rst90);
	//Vector#(8, Reg#(Bit#(16))) debugR <- replicateM(mkReg(0));
	//Reg#(Bit#(64)) debugVin <- mkReg(0);

	//Command and address FIFO
	FIFOF#(PhyCmd) ctrlCmdQ <- mkFIFOF(); //TODO adjust size
	FIFO#(Bit#(8)) addrQ <- mkSizedFIFO(8);

	//Counters
	Reg#(Bit#(16)) numBurstCnt <- mkReg(0);
	Reg#(Bit#(32)) postCmdWaitCnt <- mkReg(0);
	Reg#(Bit#(8)) cntRdDelay <- mkReg(0);
	Reg#(Bit#(16)) numBurstCntBr <- mkReg(0);

	//Read/write data FIFO
	FIFO#(Bit#(16)) rdQ <- mkFIFO(); //TODO adjust size
	FIFO#(Bit#(16)) wrQ <- mkFIFO(); //TODO adjust size

	//**********************************************
	// Buffer phy signals using registers in front
	//**********************************************
	/*
	rule regBufs90;
		vnandPhy.vphyUser.dlyCeDQS(dlyCeDQSr);
		vnandPhy.vphyUser.dlyIncDQS(dlyIncDQSr);
	endrule
	*/

	rule regBufs;
		vnandPhy.vphyUser.setCLE(cle);
		vnandPhy.vphyUser.setALE(ale);
		vnandPhy.vphyUser.setWRN(wrn);
		vnandPhy.vphyUser.setWPN(wpn);
		vnandPhy.vphyUser.setCEN(cen);
		//vnandPhy.vphyUser.setWEN(wen);
		//vnandPhy.vphyUser.setWENSel(wenSel);
		vnandPhy.vphyUser.oenDQS(oenDQS);
		vnandPhy.vphyUser.rstnDQS(rstnDQS);
		vnandPhy.vphyUser.oenDataDQ(oenDataDQ);
		vnandPhy.vphyUser.iddrRstDQ(iddrRstDQ);
		vnandPhy.vphyUser.wrDataRiseDQ(wrDataRise);
		vnandPhy.vphyUser.wrDataFallDQ(wrDataFall);
		vnandPhy.vphyUser.setCalibClk0Sel(calibClk0Sel);
		vnandPhy.vphyUser.dlyValDQS(dlyValDQS);
		vnandPhy.vphyUser.dlyLdDQS(dlyLdDQS);
//	vnandPhy.vphyDebug.setDebug0(debugR[0]);
//	vnandPhy.vphyDebug.setDebug1(debugR[1]);
//	vnandPhy.vphyDebug.setDebug2(debugR[2]);
//	vnandPhy.vphyDebug.setDebug3(debugR[3]);
//	vnandPhy.vphyDebug.setDebug4(debugR[4]);
//	vnandPhy.vphyDebug.setDebug5(debugR[5]);
//	vnandPhy.vphyDebug.setDebug6(debugR[6]);
//	vnandPhy.vphyDebug.setDebug7(debugR[7]);
//	vnandPhy.vphyDebug.setDebugVin(debugVin);
	endrule

	//wait rule. 
	rule doWaitCycles if (currState==WAIT_CYCLES);
		//By entering and exiting this state, we're already waiting 2 cycles. 
		if (waitCnt>2) begin
			waitCnt <= waitCnt-1;
		end
		else begin
			currState <= returnState;
		end
	endrule
		
	//**********************************************
	// Initialize IDELAY and NAND chip
	//**********************************************

	rule doInitWait if (currState==INIT_WAIT);
		wpn <= 0;
		waitCnt <= fromInteger(t_SYS_RESET);
		currState <= WAIT_CYCLES;
		returnState <= INIT_NAND_PWR_WAIT;
		$display("@%t\t %m NandPhy: INIT_WAIT", $time);
	endrule

	/*
	rule doWaitIdelayDQS if (currState==ADJ_IDELAY_DQS);
		if (initDoneSync==True) begin
			currState <= INIT_NAND_PWR_WAIT;
		end
	endrule
	*/

	//power up initialization by the NAND
	rule doInitNandPwrWait if (currState==INIT_NAND_PWR_WAIT);
		waitCnt <= fromInteger(t_POWER_UP);
		currState <= WAIT_CYCLES;
		returnState <= INIT_WP; 
		$display("@%t\t %m NandPhy: INIT_NAND_PWR_WAIT", $time);
	endrule

	//Turn off Write Protect. Wait tWW (>100ns). WP is always active, thus don't need CE. 
	rule doWP if (currState==INIT_WP);
		wpn <= 1;
		waitCnt <= fromInteger(t_WW);
		currState <= WAIT_CYCLES;
		returnState <= IDLE; 
		$display("@%t\t %m NandPhy: INIT_WP", $time);
	endrule

	//****************************************
	// Idle and accepting new commands
	//****************************************

	rule doIdle if (currState==IDLE);
		let cmd = ctrlCmdQ.first();
		if (cmd.inSyncMode) begin
			case(cmd.phyCycle)
				PHY_CHIP_SEL: currState <= SYNC_CHIP_SEL;
				PHY_DESELECT_ALL: currState <= DESELECT_ALL;
				PHY_CMD: currState <= SYNC_CMD_SET;
				PHY_READ: currState <= SYNC_READ_WR_LOW;
				PHY_WRITE: currState <= SYNC_WRITE_PREAMBLE;
				PHY_ADDR: currState <= SYNC_ADDR_SET;
				PHY_SYNC_CALIB: currState <= SYNC_CALIB_WR_LOW;
				default: currState <= IDLE;
			endcase
		end
		else begin
			case(cmd.phyCycle)
				PHY_CHIP_SEL: currState <= ASYNC_CHIP_SEL;
				PHY_DESELECT_ALL: currState <= DESELECT_ALL;
				PHY_CMD: currState <= ASYNC_CMD_SET_CMD;
				PHY_READ: currState <= ASYNC_READ_RE_LOW;
				PHY_WRITE: currState <= ASYNC_WRITE_WE_LOW;
				PHY_ADDR: currState <= ASYNC_ADDR_WE_LOW;
				PHY_ENABLE_NAND_CLK: currState <= ENABLE_NAND_CLK;
				default: currState <= IDLE;
			endcase
		end
		numBurstCnt <= cmd.numBurst;
		numBurstCntBr <= cmd.numBurst;
		postCmdWaitCnt <= cmd.postCmdWait;
		$display("@%t\t %m NandPhy: New command received: %x", $time, cmd.phyCycle);
	endrule

	//****************************************
	// Async bus idle/chip select
	//****************************************
	rule doAsyncCmdBusIdle if (currState==ASYNC_CHIP_SEL);
		//one hot encode CE#
		`ifdef SLC_NAND
			Bit#(3) ce_encoded = ceTranslateSLC(ctrlCmdQ.first().nandCmd.ChipSel);
		`else
			Bit#(3) ce_encoded = ctrlCmdQ.first().nandCmd.ChipSel;
		`endif
		Bit#(8) cen_one_hot = ~(1 << ce_encoded);
		cen <= cen_one_hot; //CE# low
		cle <= 0; //DC
		ale <= 0; //DC
		wrn <= 1; //RE# high
		wen <= 1;//select and set WE# high (NAND_CLK)
		wenSel <= 1; 
		oenDataDQ <= 1; //disable output
		currState <= IDLE;
		ctrlCmdQ.deq();
		$display("@%t\t %m NandPhy: ASYNC_CHIP_SEL %x", $time, cen_one_hot);
	endrule

	//****************************************
	// Async command
	//****************************************
	rule doAsyncCmdSetup if (currState==ASYNC_CMD_SET_CMD);
		cle <= 1;
		wen <= 0; 
		oenDataDQ <= 0; //enable cmd output on DQ
		wrDataRise <= orderDQ(pack(ctrlCmdQ.first().nandCmd.OnfiCmd), cen); //set command
		wrDataFall <= orderDQ(pack(ctrlCmdQ.first().nandCmd.OnfiCmd), cen); //set command
		//Wait for setup
		waitCnt <= fromInteger(t_ASYNC_CMD_SETUP);
		currState <= WAIT_CYCLES;
		returnState <= ASYNC_CMD_LATCH_WE;
		$display("@%t\t %m NandPhy: ASYNC_CMD_SET_CMD: %x", $time, ctrlCmdQ.first().nandCmd.OnfiCmd);
	endrule

	rule doAsyncCmdLatch if (currState==ASYNC_CMD_LATCH_WE);
		wen <= 1;
		waitCnt <= fromInteger(t_ASYNC_CMD_HOLD);
		currState <= WAIT_CYCLES;
		returnState <= ASYNC_DONE;
		$display("@%t\t %m NandPhy: ASYNC_CMD_LATCH_WE", $time);
	endrule

	//****************************************
	// Async address cycle; assume bus idle
	//****************************************
	rule doAsyncAddrWeLow if (currState==ASYNC_ADDR_WE_LOW);
		ale <= 1; //High
		wen <= 0;//select and set WE# low
		oenDataDQ <= 0; //enable output. Note this signal needs 2 cycles to propogate
		wrDataRise <= orderDQ(addrQ.first(), cen); //set address output
		wrDataFall <= orderDQ(addrQ.first(), cen); //set address output
		addrQ.deq();
		//wait for setup
		waitCnt <= fromInteger(t_ASYNC_ADDR_SETUP);
		currState <= WAIT_CYCLES;
		returnState <= ASYNC_ADDR_WE_HIGH;
		$display("@%t\t %m NandPhy: ASYNC_ADDR_WE_LOW set addr: %x", $time, addrQ.first);
	endrule

	rule doAsyncAddrWeHigh if (currState==ASYNC_ADDR_WE_HIGH);
		wen <= 1; //set WE# high to latch addr
		//wait for hold
		waitCnt <= fromInteger(t_ASYNC_ADDR_HOLD);
		currState <= WAIT_CYCLES;
		if (numBurstCnt==1) begin
			returnState <= ASYNC_DONE;
		end
		else begin
			returnState <= ASYNC_ADDR_WE_LOW;
			numBurstCnt <= numBurstCnt - 1;
		end
		$display("@%t\t %m NandPhy: ASYNC_ADDR_WE_HIGH", $time);
	endrule



	//*************************************************************
	// Async data input cycle (write to NAND); assume bus idle
	//*************************************************************
	rule doAsyncWriteWeLow if (currState==ASYNC_WRITE_WE_LOW);
		wen <= 0;//select and set WE# low
		oenDataDQ <= 0; //enable output. Note this signal needs 2 cycles to propogate
		wrDataRise <= orderDQ(truncate(wrQ.first()), cen); //set data output
		wrDataFall <= orderDQ(truncate(wrQ.first()), cen); //set data output
		wrQ.deq();
		//wait for setup
		waitCnt <= fromInteger(t_ASYNC_WRITE_SETUP);
		currState <= WAIT_CYCLES;
		returnState <= ASYNC_WRITE_WE_HIGH;
		$display("@%t\t %m NandPhy: ASYNC_WRITE_WE_LOW set data: %x", $time, wrQ.first);
	endrule

	rule doAsyncWriteWeHigh if (currState==ASYNC_WRITE_WE_HIGH);
		wen <= 1; //set WE# high to latch write data
		//wait for hold
		waitCnt <= fromInteger(t_ASYNC_WRITE_HOLD);
		currState <= WAIT_CYCLES;
		if (numBurstCnt==1) begin
			returnState <= ASYNC_DONE;
		end
		else if (numBurstCnt>0) begin
			returnState <= ASYNC_WRITE_WE_LOW;
			numBurstCnt <= numBurstCnt - 1;
		end
		else begin
			$display("%m *** NandPhy: ERROR: num bursts is incorrect. Must be >1");
		end
		$display("@%t\t %m NandPhy: ASYNC_WRITE_WE_HIGH", $time);
	endrule


	//*************************************************************
	// Async data output cycle (read from NAND); Assume bus idle
	//*************************************************************
	rule doAsyncReadReLow if (currState==ASYNC_READ_RE_LOW);
		oenDataDQ <= 1; //disable output. 
		//toggle RE# to capture data
		wrn <= 0;
		//wait tRP
		waitCnt <= fromInteger(t_RP);
		currState <= WAIT_CYCLES;
		returnState <= ASYNC_READ_CAPTURE;
		$display("@%t\t %m NandPhy: ASYNC_READ_RE_LOW", $time);
	endrule

	rule doAsyncReadCapture if (currState==ASYNC_READ_CAPTURE);
		//get data
		let rddata = orderDQ(vnandPhy.vphyUser.rdDataCombDQ(), cen);
		rdQ.enq(zeroExtend(rddata));
		$display("@%t\t %m NandPhy: ASYNC_READ_CAPTURE async read data %x", $time, rddata);
		currState <= ASYNC_READ_RE_HIGH;
	endrule
	

	rule doAsyncReadReHigh if (currState==ASYNC_READ_RE_HIGH);
		wrn <= 1;
		//wait tREH
		waitCnt <= fromInteger(t_REH);
		currState <= WAIT_CYCLES;
		//if done bursting, go idle. otherwise keep toggling RE#
		if (numBurstCnt==1) begin
			returnState <= ASYNC_DONE;
		end
		else if (numBurstCnt > 1) begin
			returnState <= ASYNC_READ_RE_LOW;
			numBurstCnt <= numBurstCnt - 1;
		end
		else begin
			$display("%m *** NandPhy: ERROR: num bursts is incorrect. Must be >1");
		end
		$display("@%t\t %m NandPhy: ASYNC_READ_RE_HIGH", $time);
	endrule


	//**************************
	// Go bus idle if done (ASYNC)
	//**************************
	rule doAsyncDone if (currState==ASYNC_DONE);
		cle <= 0; //DC
		ale <= 0; //DC
		wrn <= 1; //RE# high
		wen <= 1;//select and set WE# high (NAND_CLK)
		wenSel <= 1; 
		oenDataDQ <= 1; //disable output

		//post command wait
		if (postCmdWaitCnt > 0) begin
			currState <= WAIT_CYCLES;
			waitCnt <= postCmdWaitCnt;
			returnState <= IDLE;
		end
		else begin
			currState <= IDLE;
		end
		ctrlCmdQ.deq();
		$display("@%t\t %m NandPhy: ASYNC_DONE", $time);
	endrule

	//******************************************************
	// Deselect all targets. Should be in bus idle already
	//******************************************************
	rule doDeselect if (currState==DESELECT_ALL);
		cen <= 8'hFF;
		//post command wait
		if (postCmdWaitCnt > 0) begin
			currState <= WAIT_CYCLES;
			waitCnt <= postCmdWaitCnt;
			returnState <= IDLE;
		end
		else begin
			currState <= IDLE;
		end
		ctrlCmdQ.deq();
		$display("@%t\t %m NandPhy: DESELECT_ALL", $time);
	endrule


	//******************************************************
	// Enable clock for sync mode
	//******************************************************
	rule doEnNandClock if (currState==ENABLE_NAND_CLK);
		wenSel <= 0;
		//post command wait
		if (postCmdWaitCnt > 0) begin
			currState <= WAIT_CYCLES;
			waitCnt <= postCmdWaitCnt;
			returnState <= IDLE;
		end
		else begin
			currState <= IDLE;
		end
		ctrlCmdQ.deq();
		$display("@%t\t %m NandPhy: ENABLE_NAND_CLK", $time);
	endrule


	//******************************************************
	// Sync mode bus idle
	//******************************************************
	rule doSyncBusIdle if (currState==SYNC_CHIP_SEL);
		//one hot encode CE#
		`ifdef SLC_NAND
			Bit#(3) ce_encoded = ceTranslateSLC(ctrlCmdQ.first().nandCmd.ChipSel);
		`else
			Bit#(3) ce_encoded = ctrlCmdQ.first().nandCmd.ChipSel;
		`endif
		Bit#(8) cen_one_hot = ~(1 << ce_encoded);
		cen <= cen_one_hot; //CE# low
		ale <= 0;
		cle <= 0;
		wrn <= 1;
		oenDataDQ <= 1;
		iddrRstDQ <= 1; //still keep IDDR in reset
		oenDQS <= 1;
		rstnDQS <= 0; 
		ctrlCmdQ.deq();
		$display("@%t\t %m NandPhy: SYNC_CHIP_SEL %x", $time, cen_one_hot);
		//wait t_CAD.
		currState <= WAIT_CYCLES;
		waitCnt <= fromInteger(t_CAD);
		returnState <= IDLE;
	endrule

	//******************************************************
	// Sync mode command cycle
	//******************************************************
	rule doSyncCommandSet if (currState==SYNC_CMD_SET);
		cle <= 0;
		oenDataDQ <= 0;
		wrDataRise <= orderDQ(pack(ctrlCmdQ.first().nandCmd.OnfiCmd), cen);
		wrDataFall <= orderDQ(pack(ctrlCmdQ.first().nandCmd.OnfiCmd), cen);
		//it takes 2 cycles to appear on DQ
		currState <= WAIT_CYCLES;
		waitCnt <= fromInteger(t_CMD_DQ_SYNCREG_DELAY);
		returnState <= SYNC_CMD_LATCH;
		$display("@%t\t %m NandPhy: SYNC_CMD_SET cmd=%x", $time, ctrlCmdQ.first().nandCmd.OnfiCmd);
	endrule

	rule doSyncCommandLatch if (currState == SYNC_CMD_LATCH);
		cle <= 1;
		currState <= SYNC_DONE;
		$display("@%t\t %m NandPhy: SYNC_CMD_LATCH", $time);
	endrule

	
	//******************************************************
	// Sync mode address cycle; very similar to cmd cycle
	//******************************************************
	rule doSyncAddrSet if (currState==SYNC_ADDR_SET);
		cle <= 0;
		oenDataDQ <= 0;
		wrDataRise <= orderDQ(addrQ.first(), cen);
		wrDataFall <= orderDQ(addrQ.first(), cen);
		addrQ.deq();
		//it takes 2 cycles to appear on DQ
		currState <= WAIT_CYCLES;
		waitCnt <= fromInteger(t_CMD_DQ_SYNCREG_DELAY);
		returnState <= SYNC_ADDR_LATCH;
		$display("@%t\t %m NandPhy: SYNC_ADDR_SET addr=%x", $time, addrQ.first());
	endrule

	rule doSyncAddrLatch if (currState == SYNC_ADDR_LATCH);
		ale <= 1; //latch the addr of the PREVIOUS cycle
		//For multiple bursts of addr, setup the next addr on DQ
		if (numBurstCnt == 1) begin
			currState <= SYNC_DONE;
		end
		else begin
			wrDataRise <= orderDQ(addrQ.first(), cen);
			wrDataFall <= orderDQ(addrQ.first(), cen);
			addrQ.deq();
			currState <= SYNC_ADDR_BURST;
			numBurstCnt <= numBurstCnt - 1;
			$display("@%t\t %m NandPhy: SYNC_ADDR_LATCH addr=%x", $time, addrQ.first());
		end
	endrule

	rule doSyncAddrBurst if (currState == SYNC_ADDR_BURST);
		ale <= 0;
		//Wait tCAD between bursts
		currState <= WAIT_CYCLES;
		waitCnt <= fromInteger(t_CAD);
		returnState <= SYNC_ADDR_LATCH;
		$display("@%t\t %m NandPhy: SYNC_ADDR_BURST", $time);
	endrule


	//******************************************************************
	// Sync mode read capture timing calibration
	//******************************************************************
	rule doSyncCalibWRLow if (currState==SYNC_CALIB_WR_LOW);
		wrn <= 0;
		numCalibBrCnt <= fromInteger(calibFifoDepth);
		currState <= WAIT_CYCLES;
		waitCnt <= fromInteger(t_WRCK_DQSD);
		returnState <= SYNC_CALIB_LATCH;
	endrule
	
	//Enable CLE/ALE for num of cycles of bursts
	//Each burst corresponds to one DDR output (16-bit)
	rule doSyncCalibLatch if (currState==SYNC_CALIB_LATCH);
		if (numBurstCnt>=1) begin
			cle <= 1;
			ale <= 1;
			iddrRstDQ <= 0; //release reset on IDDR so we capture data
			numBurstCnt <= numBurstCnt - 1;
			$display("@%t\t %m NandPhy: SYNC_CALIB_LATCH asserted cle/ale", $time);
		end
		else begin
			cle <= 0;
			ale <= 0;
		end
	endrule

	//Access window can be 3-20ns after NAND_CLK edge (1 to 2 cycles)
	//Domain transfer regs (2 cycles)
	
	//Buffer a bunch of data bursts in FIFOs
	rule doSyncCalibCap if (currState==SYNC_CALIB_LATCH);
		if (numCalibBrCnt > 0) begin
			let d0 = orderDQ(vnandPhy.vphyUser.calibDqRise0(), cen); 
			let d90 = orderDQ(vnandPhy.vphyUser.calibDqRise90(), cen); 
			let d180 = orderDQ(vnandPhy.vphyUser.calibDqRise180(), cen); 
			let d270 = orderDQ(vnandPhy.vphyUser.calibDqRise270(), cen); 
			fifoDqR0.enq(d0);
			fifoDqR90.enq(d90);
			fifoDqR180.enq(d180);
			fifoDqR270.enq(d270);
			numCalibBrCnt <= numCalibBrCnt-1;
			$display("@%t\t %m NandPhy: SYNC_CALIB enq'd dqR %x %x %x %x", $time, d0, d90, d180, d270);
		end

		if (numBurstCntBr > 0) begin
			//wait until ddr bursting is done
			numBurstCntBr <= numBurstCntBr-1;
		end

		if (numBurstCntBr==0 && numCalibBrCnt==0) begin
			numCalibBrCnt <= 0;
			currState <= SYNC_CALIB_CALIBRATE;
			rLat <= 0;
		end
	endrule

	//Calibration procedure
	//1) Sample DQS domain DQ rise data at 0, 90, 180 and 270 degrees 
	//   in cycles 3, 4 and 5
	//2) Find the first valid data
	//3) Use the clock edge 90 to 180 degrees after the first valid 
	//   byte (clk0 or clk180) to capture data. At least 2.5ns of setup time

	rule doSyncCalib if (currState==SYNC_CALIB_CALIBRATE);
			$display("@%t\t %m NandPhy: SYNC_CALIB_CALIBRATE", $time);
			//Find the first valid byte
			if (fifoDqR0.first()==refDqR || fifoDqR90.first()==refDqR) begin
				//CLK is 0-180 degrees shifted from DQS
				//Use clk180 to capture data
				calibClk0Sel <= 0; //use clk180 for data capture
				rLat <= rLat+1; //data is available at clk0 on the next edge
				fifoDqR0.clear();
				fifoDqR90.clear();
				fifoDqR180.clear();
				fifoDqR270.clear();
				currState <= SYNC_DONE;
				$display("@%t\t %m NandPhy: SYNC_CALIB_CALIBRATE done, clk0sel=0, rLat=%d", $time, rLat+1);
			end
			else if (fifoDqR180.first()==refDqR || fifoDqR270.first()==refDqR) begin
				//CLK is 180-360 degrees shifted from DQS
				//Use clk0 at the next cycle edge to capture data
				rLat <= rLat+1;
				calibClk0Sel <= 1;
				fifoDqR0.clear();
				fifoDqR90.clear();
				fifoDqR180.clear();
				fifoDqR270.clear();
				currState <= SYNC_DONE;
				$display("@%t\t %m NandPhy: SYNC_CALIB_CALIBRATE done, clk0sel=1, rLat=%d", $time, rLat+1);
			end
			else if (rLat < fromInteger(calibFifoDepth)) begin
				//Check the next cycle
				rLat <= rLat + 1;
				fifoDqR0.deq();
				fifoDqR90.deq();
				fifoDqR180.deq();
				fifoDqR270.deq();
			end
			else begin
				//Something bad happened. Not capturing data correctly
				$display("@%t\t %m *** NandPhy: SYNC_CALIB_CALIBRATE failed. Possible DQ-DQS skew error", $time);
				currState <= SYNC_CALIB_FAIL;
				//TODO: adjust DQ/DQS skew
			end
	endrule

	//******************************************************************
	// Sync mode data output cycle (read from NAND); assume bus idle
	//******************************************************************
	//TODO: not very efficient here. tCAD and tWRCK can overlap
	rule doSyncReadWRLow if (currState==SYNC_READ_WR_LOW);
		wrn <= 0;
		currState <= WAIT_CYCLES;
		waitCnt <= fromInteger(t_WRCK_DQSD);
		returnState <= SYNC_READ_LATCH;
	endrule
	
	//Enable CLE/ALE for num of cycles of bursts
	//Each burst corresponds to one DDR output (16-bit)
	rule doSyncReadLatch if (currState==SYNC_READ_LATCH);
		if (numBurstCnt>=1) begin
			cle <= 1;
			ale <= 1;
			iddrRstDQ <= 0; //release reset on IDDR so we capture data
			numBurstCnt <= numBurstCnt - 1;
			$display("@%t\t %m NandPhy: SYNC_READ_LATCH asserted cle/ale", $time);
		end
		else begin
			cle <= 0;
			ale <= 0;
			//$display("@%t\t %m NandPhy: SYNC_READ_LATCH DEasserted cle/ale", $time);
		end
	endrule

	//Start capturing data rLat after cle/ale is asserted.
	//Use a separate temp counter here
	rule doSyncReadCap if (currState==SYNC_READ_LATCH);
		if (cntRdDelay >= rLat && numBurstCntBr>=1 ) begin
			let rdRise = orderDQ(vnandPhy.vphyUser.rdDataRiseDQ(), cen);
			let rdFall = orderDQ(vnandPhy.vphyUser.rdDataFallDQ(), cen);
			rdQ.enq({rdRise, rdFall});
			numBurstCntBr <= numBurstCntBr - 1;
			$display("@%t\t %m NandPhy: SYNC_READ_LATCH sync read data %x %x", $time, rdRise, rdFall);
		end
		else if (numBurstCntBr < 1) begin //we finished reading data bursts
			//wait for ( tCKWR - (t_DQSCK+t_ISERDES) )
			currState <= WAIT_CYCLES;
			waitCnt <= fromInteger(t_CKWR_DQSCK_IDDR); //TODO too conservative
			returnState <= SYNC_DONE;
			cntRdDelay <= 0;
		end
		else begin //waiting rLat
			cntRdDelay <= cntRdDelay+1;
		end
	endrule

	
	//*************************************************************
	// Sync data input cycle (write to NAND); assume bus idle
	//*************************************************************
	rule doSyncWritePreamble if (currState==SYNC_WRITE_PREAMBLE);
		oenDQS <= 0; //enable DQS
		rstnDQS <= 0; //hold DQS low
		oenDataDQ <= 0; //enable DQ
		wrDataRise <= 0; //no real data
		wrDataFall <= 0;
		//hold for t_WPRE
		currState <= WAIT_CYCLES;
		waitCnt <= fromInteger(t_WPRE);
		returnState <= SYNC_WRITE_BURST;
	endrule

	rule doSyncWriteEnable if (currState==SYNC_WRITE_BURST);
		if (numBurstCnt>=1) begin
			cle <= 1;
			ale <= 1;
			numBurstCnt <= numBurstCnt - 1;
			$display("@%t\t %m NandPhy: SYNC_WRITE_ENABLE asserted cle/ale", $time);
		end
		else begin
			cle <= 0;
			ale <= 0;
			//$display("@%t\t %m NandPhy: SYNC_WRITE_ENABLE DEasserted cle/ale", $time);
		end
	endrule

	rule doSyncWriteBurst if (currState==SYNC_WRITE_BURST);
		if (numBurstCntBr >= 1) begin
			rstnDQS <= 1;
			Bit#(8) dRise = truncateLSB(wrQ.first());
			Bit#(8) dFall = truncate(wrQ.first());
			wrDataRise <= orderDQ(dRise, cen);
			wrDataFall <= orderDQ(dFall, cen);
			wrQ.deq();
			numBurstCntBr <= numBurstCntBr - 1;
			$display("@%t\t %m NandPhy: SYNC_WRITE_BURST #%d: %x %x", $time, numBurstCntBr, dRise, dFall);
		end
		else begin
			rstnDQS <= 0;
			wrDataRise <= 0;
			wrDataFall <= 0;
			//hold t_WPST + tDQSS
			currState <= WAIT_CYCLES;
			waitCnt <= fromInteger(t_WPST + t_DQSS);
			returnState <= SYNC_DONE;
		end
	endrule

	//**************************
	// Go bus idle if done (SYNC)
	//**************************
	rule doSyncDone if (currState==SYNC_DONE);
		cle <= 0;
		ale <= 0;
		wrn <= 1;
		oenDataDQ <= 1;
		iddrRstDQ <= 1; //IDDR reset again 
		oenDQS <= 1;
		rstnDQS <= 0;
		ctrlCmdQ.deq();
		//Always wait at least tCAD
		//post command wait
		currState <= WAIT_CYCLES;
		returnState <= IDLE;
		if (postCmdWaitCnt > 0) begin
			waitCnt <= postCmdWaitCnt + fromInteger(t_CAD);
		end
		else begin
			waitCnt <= fromInteger(t_CAD);
		end
		$display("@%t\t %m NandPhy: SYNC_DONE", $time);
	endrule

	//**************************
	// clk90 domain rules
	//**************************
	//synchronize state to clk90 domain
	/*
	rule syncState;
		currState90<=currState;
	endrule

	//Init in clk90 domain
	rule doInitWait90 if (currState90==INIT_WAIT);
		initDoneSync <= False;
		dlyIncDQSr <= 0;
		dlyCeDQSr <= 0;
		incIdelayDQS_90 <= 0;
	endrule

	rule doAdjIdelayDQS90 if (currState90==ADJ_IDELAY_DQS);
		if (incIdelayDQS_90 != fromInteger(idelayDQS)) begin
			$display("@%t\t %m NandPhy: incremented dqs idelay", $time);
			dlyIncDQSr <= 1;
			dlyCeDQSr <= 1;
			incIdelayDQS_90 <= incIdelayDQS_90 + 1;
		end
		else begin
			dlyIncDQSr <= 0;
			dlyCeDQSr <= 0;
			initDoneSync <= True;
		end
	endrule
	*/


	//*****************************************************
	// Interface
	//*****************************************************
	
	interface PhyUser phyUser;
		method Action sendCmd (PhyCmd cmd);
			ctrlCmdQ.enq(cmd);
		endmethod

		method Action sendAddr (Bit#(8) addr);
			addrQ.enq(addr);
		endmethod

		method ActionValue#(Bit#(16)) rdWord();
			rdQ.deq();
			return rdQ.first();
		endmethod

		method Action wrWord (Bit#(16) data);
			wrQ.enq(data);
		endmethod

		method Bool isIdle();
			return ((currState==IDLE) && (!ctrlCmdQ.notEmpty));
		endmethod
	endinterface

	/*
	interface PhyDebugCtrl phyDebugCtrl;
		interface dbgCtrlIla = vnandPhy.vphyDebug.dbgCtrlIla;
		interface dbgCtrlVio = vnandPhy.vphyDebug.dbgCtrlVio;
	endinterface

	interface PhyDebug phyDebug;
		method Action setDebug0 (Bit#(16) d);
			debugR[0] <= d;
		endmethod

		method Action setDebug1 (Bit#(16) d);
			debugR[1] <= d;
		endmethod

		method Action setDebug2 (Bit#(16) d);
			debugR[2] <= d;
		endmethod

		method Action setDebug3 (Bit#(16) d);
			debugR[3] <= d;
		endmethod
		
		method Action setDebug4 (Bit#(16) d);
			debugR[4] <= d;
		endmethod

		method Action setDebug5 (Bit#(16) d);
			debugR[5] <= d;
		endmethod

		method Action setDebug6 (Bit#(16) d);
			debugR[6] <= d;
		endmethod

		method Action setDebug7 (Bit#(16) d);
			debugR[7] <= d;
		endmethod
		method Action setDebugVin (Bit#(64) d);
			debugVin <= d;
		endmethod

		method Bit#(64) getDebugVout();
			return vnandPhy.vphyDebug.getDebugVout();
		endmethod
	endinterface
	*/

	interface PhyWenNclkGet phyWenNclkGet;
		method Bit#(1) getWEN ();
			return wen;
		endmethod
		
		method Bit#(1) getWENSel();
			return wenSel;
		endmethod
	endinterface

	interface nandPins = vnandPhy.nandPins;


endmodule

