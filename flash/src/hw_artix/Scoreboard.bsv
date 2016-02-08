import FIFOF             ::*;
import FIFO             ::*;
import Vector            ::*;
import GetPut ::*;
import BRAMFIFO::*;
import ControllerTypes::*;

typedef enum {
	NEXT_REQ,
	SERVICE_REQ
} SBState deriving (Bits, Eq);

typedef enum {
	INIT,
	RD_ISSUED,
	RD_DATA,
	WR_BUF_REQ_ISSUED,
	WR_ISSUED,
	ER_ISSUED, 
	WAIT_STATUS
} Stage deriving (Bits, Eq);

typedef struct {
	FlashCmd cmd;
} SBElem deriving (Bits, Eq);

interface SBIfc;
	interface Put#(FlashCmd) cmdIn;
	interface Get#(BusCmd) cmdOut;
	interface Put#(Tuple2#(ChipT, Bool)) busyIn;
	(* always_enabled *)
	method Action setWdataRdy(Bool rdy, TagT tag);
	//method Bool isSBIdle();
endinterface

(* synthesize *)
module mkScoreboard(SBIfc);

	//For MLC. Estimates
	Integer t_R = 3000; //75us MAX
	Integer t_PROG = 5000; //1300us Typ; use 500us here
	Integer t_BERS = 50000; //3.8ms Typ; use 500us here
	Integer t_R_PollWait = 500; //5us; Wait between status polls if busy
	Integer t_PROG_PollWait = 500; //50us; Wait between status polls if busy
	Integer t_BERS_PollWait = 10000; //100us; Wait between status polls if busy

	Integer sbChipQDepth = 8;

	Vector#(ChipsPerBus, FIFOF#(SBElem)) chipQs <- replicateM(mkSizedFIFOF(sbChipQDepth));
	Vector#(ChipsPerBus, FIFO#(Bool)) chipBusy <- replicateM(mkFIFO());
	Vector#(ChipsPerBus, Reg#(Bit#(32))) busyTimers <- replicateM(mkReg(0));
	Vector#(ChipsPerBus, Reg#(Stage)) chipStages <- replicateM(mkReg(INIT));
	FIFO#(BusCmd) cmdOutQ <- mkFIFO(); //TODO what size here?
	Reg#(ChipT) currChip <- mkReg(0);
	Reg#(BusCmd) currCmdOut <- mkRegU();
	Reg#(SBState) state <- mkReg(NEXT_REQ);
	Reg#(Bool) wdataRdy <- mkReg(False);
	Reg#(TagT) wdataRdyTag <- mkRegU();

	SBElem currReq = chipQs[currChip].first();

	rule doChooseChip if (state==NEXT_REQ);
		if (chipQs[currChip].notEmpty && busyTimers[currChip]==0) begin
			//service request
			state <= SERVICE_REQ;
			$display("@%t\t%m: Servicing chip: %d", $time, currChip);
		end
		else begin
			currChip <= currChip + 1;
		end
	endrule

	rule doServiceReq if (state==SERVICE_REQ);
		BusOp busOp;
		case (currReq.cmd.op)
			READ_PAGE: begin
				if (chipStages[currChip] == INIT) begin
					busOp = READ_CMD;
					chipStages[currChip] <= RD_ISSUED;
					busyTimers[currChip] <= fromInteger(t_R);
				end
				else if (chipStages[currChip] == RD_ISSUED) begin
					//This op should poll status; if not busy read data
					busOp = GET_STATUS_READ_DATA; 
					chipStages[currChip] <= RD_DATA;
				end
				else begin //chipStages[currChip] == RD_DATA
					if (chipBusy[currChip].first()) begin
						busOp = INVALID;
						busyTimers[currChip] <= fromInteger(t_R_PollWait);
						chipStages[currChip] <= RD_ISSUED;
					end
					else begin //done with this 
						busOp = INVALID;
						chipStages[currChip] <= INIT;
						chipQs[currChip].deq;
						$display("@%t\t%m: done with request: tag=%x, chip=%d", $time, currReq.cmd.tag, currChip);
					end
					chipBusy[currChip].deq;
				end
			end
			WRITE_PAGE: begin
				if (chipStages[currChip] == INIT) begin
					//issue req to buffer data
					busOp = WRITE_DATA_BUF_REQ;
					chipStages[currChip] <= WR_BUF_REQ_ISSUED;
					busyTimers[currChip] <= 0;
				end
				else if (chipStages[currChip] == WR_BUF_REQ_ISSUED) begin
					//check if write page data is ready & tag match
					if (wdataRdy==True && wdataRdyTag==currReq.cmd.tag) begin
						busOp = WRITE_CMD_DATA;
						chipStages[currChip] <= WR_ISSUED;
						busyTimers[currChip] <= fromInteger(t_PROG);
					end
					else begin
						busOp = INVALID;
					end
				end
				else if (chipStages[currChip] == WR_ISSUED) begin
					busOp = WRITE_GET_STATUS; 
					chipStages[currChip] <= WAIT_STATUS;
				end
				else begin //chipStages[currChip] == WAIT_STATUS
					if (chipBusy[currChip].first()) begin
						busOp = INVALID;
						busyTimers[currChip] <= fromInteger(t_PROG_PollWait);
						chipStages[currChip] <= WR_ISSUED;
					end
					else begin //done with this 
						busOp = INVALID;
						chipStages[currChip] <= INIT;
						chipQs[currChip].deq;
						$display("@%t\t%m: done with request: tag=%x, chip=%d", $time, currReq.cmd.tag, currChip);
					end
					chipBusy[currChip].deq;
				end
			end
			ERASE_BLOCK: begin
				if (chipStages[currChip] == INIT) begin
					busOp = ERASE_CMD;
					chipStages[currChip] <= ER_ISSUED;
					busyTimers[currChip] <= fromInteger(t_BERS);
				end
				else if (chipStages[currChip] == ER_ISSUED) begin
					busOp = ERASE_GET_STATUS; 
					chipStages[currChip] <= WAIT_STATUS;
				end
				else begin //chipStages[currChip] == WAIT_STATUS
					if (chipBusy[currChip].first()) begin
						busOp = INVALID;
						busyTimers[currChip] <= fromInteger(t_BERS_PollWait);
						chipStages[currChip] <= ER_ISSUED;
					end
					else begin //done with this 
						busOp = INVALID;
						chipStages[currChip] <= INIT;
						chipQs[currChip].deq;
						$display("@%t\t%m: done with request: tag=%x, chip=%d", $time, currReq.cmd.tag, currChip);
					end
					chipBusy[currChip].deq;
				end
			end
			default: busOp = INVALID;
		endcase

		if (busOp!=INVALID) begin
				cmdOutQ.enq( BusCmd {
									tag: 		currReq.cmd.tag,
									busOp:	busOp,
									chip:		currReq.cmd.chip,
									block: 	currReq.cmd.block,
									page: 	currReq.cmd.page	} );
				$display("@%t\t%m: cmdOut enqueued: tag=%x, chip=%x, busOp=", $time, currReq.cmd.tag, currReq.cmd.chip, fshow(busOp));
		end
		state <= NEXT_REQ;
		currChip <= currChip + 1;

	endrule

	for (Integer i=0; i<valueOf(ChipsPerBus); i=i+1) begin
		//specify urgency to be low
		//(* descending_urgency = "doServiceReq, decBusyTimer" *)
		//(* execution_order = "doServiceReq, decBusyTimer" *)

		//Generates warnings because two rules writes to busyTimers. Ok to ignore. 
		//Specifying urgency doesn't quite work. When doServiceReq fires, none of the
		// counters decrement anymore. Scheduling is not aggressive enough
		rule decBusyTimer; //if (busyTimers[i] > 0); 
			if (busyTimers[i] > 0) begin
				busyTimers[i] <= busyTimers[i] - 1;
			//	$display("@%t\t%m: busy timer [%d] = %d decrement", $time, i, busyTimers[i]);
			end
		endrule
	end



	interface Put cmdIn;
		method Action put(FlashCmd cmd);
			chipQs[cmd.chip].enq( SBElem{cmd: cmd} ); //distribute to each fifo		
		endmethod
	endinterface

	interface Get cmdOut;
		method ActionValue#(BusCmd) get();
			cmdOutQ.deq;
			return cmdOutQ.first();
		endmethod
	endinterface

	interface Put busyIn;
		method Action put(Tuple2#(ChipT, Bool) chipStatus);
			ChipT c = tpl_1(chipStatus);
			Bool st = tpl_2(chipStatus);
			chipBusy[c].enq(st);
		endmethod
	endinterface

	method Action setWdataRdy(Bool rdy, TagT tag);
		wdataRdy <= rdy;
		wdataRdyTag <= tag;
	endmethod
//	method isSBIdle();
//		return ( state==NEXT_REQ &&


endmodule
