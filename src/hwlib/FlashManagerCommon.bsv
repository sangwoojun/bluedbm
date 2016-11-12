/**
IMPORTANT: tags need to be encoded in a certain way now:
tag[0] board
tag[3:1] bus
tag[~7:4] tag
**/

typedef 8 BusCount; // 8 per card in hw, 2 per card in sim
typedef TMul#(2,BusCount) BBusCount; //Board*bus
typedef 128 TagCount;

typedef enum {
	STATE_NULL,
	STATE_WRITE_READY,
	STATE_WRITE_DONE,
	STATE_ERASE_DONE,
	STATE_ERASE_FAIL
} FlashStatus deriving (Bits, Eq);

typedef struct {
	FlashOp op;
	
	Bit#(8) tag;

	Bit#(4) bus;
	ChipT chip; //Bit#(3)
	Bit#(16) block;
	Bit#(8) page;
} FlashManagerCmd deriving (Bits, Eq);

typedef struct {
	Bit#(4) bus;
	ChipT chip; //Bit#(3)
	Bit#(16) block;
	Bit#(8) page;
} FlashManagerAddr deriving (Bits,Eq);

function FlashManagerAddr decodeFlashAddr(Bit#(32) code);
	Bit#(16) block = truncate(code);
	Bit#(8) page = truncate(code>>16);
	Bit#(4) bus = truncate(code>>24);
	ChipT chip = truncate(code>>28);
	return FlashManagerAddr{
		bus:bus,
		chip:chip,
		block:block,
		page:page
	};
endfunction

function FlashManagerCmd decodeFlashCommand(Bit#(64) code);
	Bit#(4) opcode = code[3:0];
	Bit#(4) bbus = code[7:4];
	Bit#(8) tag = code[15:8];
	Bit#(16) block = code[31:16];

	Bit#(8) page = code[39:32];
	ChipT chip = truncate(code>>40);
	let cur_flashop = ERASE_BLOCK;
	if ( opcode == 0 ) begin
		cur_flashop = ERASE_BLOCK;
	end else if ( opcode == 1 ) begin
		cur_flashop = READ_PAGE;
	end else if ( opcode == 2 ) begin
		cur_flashop = WRITE_PAGE;
	end

	return FlashManagerCmd{
		op:cur_flashop,
		tag:tag,
		bus:bbus,
		chip:chip,
		block:block,
		page:page
	};
endfunction
