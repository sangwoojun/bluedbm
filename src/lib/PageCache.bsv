//import XilinxVC707DDR3::*;
import FIFO::*;
import Vector::*;
import BRAM::*;

typedef 16 WordBytes;
typedef TMul#(8,WordBytes) WordSz;
//typedef TAdd#(8192,64) PageBytes;
typedef TAdd#(8192,128) PageBytes;
typedef TDiv#(PageBytes,WordBytes) PageWords;
typedef TLog#(PageWords) PageWordsLog;

interface PageCacheIfc#(numeric type tBufferSizeLog, numeric type tMaxTag);
	method Action readPage(Bit#(64) pageIdx, Bit#(8) tag);
	method ActionValue#(Tuple2#(Bit#(WordSz), Bit#(8))) readWord;
	method Action writePage (Bit#(64) pageIdx, Bit#(8) tag);
	method Action writeWord (Bit#(WordSz) data, Bit#(8) tag);
endinterface

module mkPageCache (PageCacheIfc#(tBufferSizeLog, tMaxTag))
provisos ( Add#(a__, TAdd#(PageWordsLog, tBufferSizeLog), 64),Add#(b__, tBufferSizeLog, 64));
	BRAM2Port#(Bit#(TAdd#(PageWordsLog,tBufferSizeLog)), Bit#(WordSz)) pageBuffer <- mkBRAM2Server(defaultValue); // 8k pages 

	Integer wordBytes = valueOf(WordBytes);
	Integer wordSz = valueOf(WordSz);
	Integer pageBytes = valueOf(PageBytes);
	Integer pageWords = valueOf(PageWords);
	Integer pageWordsLog = valueOf(PageWordsLog);

	Integer maxTag = valueOf(tMaxTag);

	Reg#(Bit#(64)) curReadIdx <- mkReg(0);
	Reg#(Bit#(8)) curReadTag <- mkReg(0);
	Reg#(Bit#(32)) readCount <- mkReg(99999999);
	
	//Reg#(Bit#(64)) curWriteIdx <- mkReg(0);
	Vector#(tMaxTag, Reg#(Tuple2#(Bit#(tBufferSizeLog), Bit#(16)))) writeIdx <- replicateM(mkReg(tuple2(0, 65530)));
	Reg#(Bit#(8)) curWriteTag <- mkReg(0);
	Reg#(Bit#(32)) writeCount <- mkReg(99999999);

	Reg#(Bit#(64)) globalCounter <- mkReg(0);
	FIFO#(Bit#(8)) readTagQ <- mkSizedFIFO(8);

	rule driveReadReq( readCount < fromInteger(pageWords) );
		Bit#(tBufferSizeLog) bufidx = truncate(curReadIdx);
		Bit#(64) addroff = extend(bufidx)<<pageWordsLog;
		Bit#(64) exreadCount = extend(readCount);
		
		pageBuffer.portB.request.put(
			BRAMRequest{
				write:False, 
				responseOnWrite:?, 
				address:truncate(addroff+exreadCount), 
				datain:?});
		readCount <= readCount + 1;
		readTagQ.enq(curReadTag);
	endrule
	FIFO#(Bit#(WordSz)) readDataQ <- mkFIFO;
	rule recvReadResp;
		let v <- pageBuffer.portB.response.get();
		readDataQ.enq(v);
	endrule

	FIFO#(Bool) fakeQ_wp <- mkFIFO();
	FIFO#(Tuple2#(Bit#(64), Bit#(8))) writePageQ <- mkFIFO();
	
	method Action readPage (Bit#(64) pageIdx, Bit#(8) tag) 
		if ( readCount >= fromInteger(pageWords));

		curReadTag <= tag;
		Bit#(tBufferSizeLog) pageIdxt = truncate(pageIdx);
		curReadIdx <= zeroExtend(pageIdxt);
		readCount <= 0;
		$display ( "PageCache starting read @ page %d with tag %d", pageIdxt, tag );
	endmethod
	method ActionValue#(Tuple2#(Bit#(WordSz), Bit#(8))) readWord;
		//let v <- pageBuffer.portB.response.get();
		let v = readDataQ.first;
		readDataQ.deq;
		//readCount <= readCount - 8;
		globalCounter <= globalCounter + 1;
		readTagQ.deq;
		return tuple2(v, readTagQ.first);
	endmethod
	
	method Action writePage (Bit#(64) pageIdx, Bit#(8) tag);
		writePageQ.enq(tuple2(pageIdx, tag));
	endmethod
	method Action writeWord (Bit#(WordSz) data, Bit#(8) tag);
		let wi = writeIdx[tag];
		let idx = tpl_1(wi);
		Bit#(64) offset = zeroExtend(tpl_2(wi));

		
		if ( offset < fromInteger(pageWords) ) begin
			Bit#(64) idxoff = zeroExtend(idx)<<pageWordsLog;
			pageBuffer.portA.request.put(BRAMRequest{write:True, responseOnWrite:False, address:truncate(offset+idxoff), datain:data});
			writeIdx[tag] <= tuple2(tpl_1(wi), tpl_2(wi) + 1);
		end else begin
			//fakeQ_wp.deq;
			writePageQ.deq;

			let tag = tpl_2(writePageQ.first);
			let idx = tpl_1(writePageQ.first);
			Bit#(64) idxoff = zeroExtend(idx)<<pageWordsLog;
			Bit#(16) offset = 0;

			writeIdx[tag] <= tuple2(truncate(idx), 1);
			pageBuffer.portA.request.put(BRAMRequest{write:True, responseOnWrite:False, address:truncate(idxoff), datain:data});
		end
	endmethod
endmodule
