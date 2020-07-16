package FlashManagerCommon;
import ControllerTypes::*;
import FlashCtrlVirtex1::*;

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
	STATE_NULL = 0,
	STATE_WRITE_READY = 1,
	STATE_WRITE_DONE = 2,
	STATE_ERASE_DONE = 3,
	STATE_ERASE_FAIL = 4
} FlashStatusCode deriving (Bits, Eq);

typedef struct {
	FlashStatusCode code;
	Bit#(8) tag;
} FlashStatus deriving (Bits, Eq);




endpackage: FlashManagerCommon
