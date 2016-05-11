static uint64_t block_mbs = 4;

enum TypeHeader {
	NullWord = 0,
	ShortHalf = 2,
	ShortCol = 4,
	LongCol= 6,
	ShortRow = 8,
	ShortDouble = 9,
	LongRow = 10,
	ShortData = 12,
	LongData = 14
};
static int headeroffset = 28;
static uint32_t bodymask = (1<<headeroffset)-1;


