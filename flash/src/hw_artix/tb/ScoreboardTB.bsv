import FIFOF             ::*;
import FIFO             ::*;
import Vector            ::*;
import GetPut ::*;
import BRAMFIFO::*;
import FShow::*;
import Randomizable::*;

import ControllerTypes::*;
import Scoreboard::*;

typedef 8 NUM_CMDS;

typedef enum {
	INIT,
	GET_NEXT_CMD,
	EXECUTE_CMD,
	RETURN_STATUS
} SBTBState deriving (Bits, Eq);

module mkSBTB();

	SBIfc sb <- mkScoreboard();

	//generate an array of commands
	Vector#(NUM_CMDS, FlashCmd) cmdTest = newVector();
	cmdTest[0] = FlashCmd { tag: 0, op: WRITE_PAGE, chip: 0, block: 77, page: 1};
	cmdTest[1] = FlashCmd { tag: 1, op: WRITE_PAGE, chip: 2, block: 77, page: 1};
	cmdTest[2] = FlashCmd { tag: 2, op: READ_PAGE, chip: 1, block: 77, page: 1};
	cmdTest[3] = FlashCmd { tag: 3, op: READ_PAGE, chip: 5, block: 77, page: 1};
	cmdTest[4] = FlashCmd { tag: 4, op: READ_PAGE, chip: 3, block: 77, page: 1};
	cmdTest[5] = FlashCmd { tag: 5, op: WRITE_PAGE, chip: 1, block: 77, page: 1};
	cmdTest[6] = FlashCmd { tag: 6, op: READ_PAGE, chip: 1, block: 77, page: 1};

	Reg#(Bit#(TLog#(NUM_CMDS))) cmdCnt <- mkReg(0);
	Reg#(Bit#(64)) cycleCnt <- mkReg(0);
	Reg#(SBTBState) state <- mkReg(INIT);
	Randomize#(Bool) randomizer <- mkGenericRandomizer();
	Reg#(BusCmd) currBusCmd <- mkRegU();

	rule countCyc;
		cycleCnt <= cycleCnt + 1;
		//$display("Cycle %d ---------------------", cycleCnt);
		if (cycleCnt == 100000) begin
			$display("Timed out");
			$finish;
		end
	endrule

	rule enqCmd; //if (cmdCnt < 7);
		sb.cmdIn.put(cmdTest[cmdCnt]);
		let c = cmdTest[cmdCnt];
		//if (cmdCnt < fromInteger(valueOf(NUM_CMDS)-1)) begin
		if (cmdCnt < 6) begin
	   	cmdCnt <= cmdCnt + 1;
		end
		else begin
	   	cmdCnt <= 0;
		end
		$display("@%t: flashCmd Enq: tag=%x, op=%d, chip=%d, block=%d, page=%d", $time, c.tag, c.op, c.chip, c.block, c.page);
	endrule

	rule init if (state==INIT);
		randomizer.cntrl.init();
		state <= GET_NEXT_CMD;
	endrule

	rule getCmd if (state==GET_NEXT_CMD);
		BusCmd busCmd <- sb.cmdOut.get();
		currBusCmd <= busCmd;
		$display("@%t: >>>> BusCmd to execute: tag=%x, chip=%x, block=%x, page=%x, busOp=", $time, busCmd.tag, busCmd.chip, busCmd.block, busCmd.page, fshow(busCmd.busOp));
		if (busCmd.busOp==GET_STATUS || busCmd.busOp==GET_STATUS_READ_DATA) begin
			state <= RETURN_STATUS;
		end
		else begin
			state <= EXECUTE_CMD;
		end
	endrule

	rule execCmd if (state==EXECUTE_CMD);
		//basically do nothing here
		state <= GET_NEXT_CMD;
	endrule

	rule returnStatus if (state==RETURN_STATUS);
		state <= GET_NEXT_CMD;
		Bool randStatus <- randomizer.next();
		sb.busyIn.put(tuple2(currBusCmd.chip, randStatus));
		$display("@%t: Returned isBusy for chip[%d]:", $time, currBusCmd.chip, fshow(randStatus));
	endrule

endmodule






	


