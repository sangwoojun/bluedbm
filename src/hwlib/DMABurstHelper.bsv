import ClientServer::*;
import FIFO::*;
import FIFOF::*;
import GetPut::*;
import Vector::*;
import ConnectalMemory::*;
import MemTypes::*;
import MemreadEngine::*;
import MemwriteEngine::*;
import Pipe::*;

import BRAMFIFOVector::*;
import ControllerTypes::*;

typedef 4 NumDmaChannels;

//typedef TAdd#(8192,64) PageBytes;
typedef 8192 PageBytes;
typedef 16 WordBytes;
//typedef TMul#(8,WordBytes) WordSz;
typedef 32 WriteBufferCount;
typedef TMul#(WriteBufferCount, NumDmaChannels) WriteBufferTotal;
//typedef 32 WriteTagCount;
typedef 64 ReadBufferCount;
typedef TMul#(ReadBufferCount, NumDmaChannels) ReadBufferTotal;

typedef TLog#(ReadBufferCount) ReadBufferCountLog;
typedef TLog#(WriteBufferCount) WriteBufferCountLog;
//typedef TLog#(WriteTagCount) WriteTagCountLog;

interface DMAReadEngineIfc#(numeric type wordSz);
	method ActionValue#(Tuple2#(Bit#(wordSz), TagT)) read;
	method Action startRead(TagT tag, Bit#(32) wordCount);
	method ActionValue#(TagT) done;
	method Action addBuffer(TagT tag, Bit#(32) offset, Bit#(32) bref);
endinterface
module mkDmaReadEngine#(
	Server#(MemengineCmd,Bool) rServer,
	PipeOut#(Bit#(wordSz)) rPipe)(DMAReadEngineIfc#(wordSz))
	;
	
	Integer pageBytes = valueOf(PageBytes);
	
	Integer wordBytes = valueOf(WordBytes); 
	Integer burstBytes = 16*8;
	Integer burstWords = burstBytes/wordBytes;
	
	Vector#(NumTags, Reg#(Tuple2#(Bit#(32),Bit#(32)))) dmaReadRefs <- replicateM(mkReg(?));
	
	Reg#(Bit#(32)) dmaReadCount <- mkReg(0);

	FIFO#(Tuple2#(TagT,Bit#(32))) readBurstIdxQ <- mkSizedFIFO(8);
	FIFO#(TagT) readIdxQ <- mkFIFO;
	
	FIFO#(TagT) readDoneIdxQ <- mkFIFO;

	FIFO#(Maybe#(TagT)) readDoneQ <- mkSizedFIFO(1);

	Integer readQSize = 64;
	Reg#(Bit#(32)) readQInTotal <- mkReg(0);
	Reg#(Bit#(32)) readQOutTotal <- mkReg(0);


	FIFO#(Tuple2#(TagT, Bit#(32))) startReadReqQ <- mkSizedFIFO(valueOf(NumTags)); //ML
	//ML: Use a startReadReqQ FIFO so that req don't block the rule when distributing
	//to the dma readers
	//TODO maybe optimize this using a value and action methods
	rule handleStartReadReq if (dmaReadCount==0);
		let startReq = startReadReqQ.first;
		startReadReqQ.deq;
		let tag = tpl_1(startReq);
		let wordCount = tpl_2(startReq);
		dmaReadCount <= wordCount*fromInteger(wordBytes);
		readIdxQ.enq(tag);
	endrule


	rule driveHostDmaReq (dmaReadCount > 0 && 
		(readQInTotal - readQOutTotal + fromInteger(burstWords) < fromInteger(readQSize)) );
		let tag = readIdxQ.first;
		let rd = dmaReadRefs[tag];
		let rdRef = tpl_1(rd);
		let rdOff = tpl_2(rd);
		let dmaReadOffset = rdOff+fromInteger(pageBytes)-dmaReadCount;

		rServer.request.put(MemengineCmd{sglId:rdRef, base:extend(dmaReadOffset), len:fromInteger(burstBytes), burstLen:fromInteger(burstBytes)});

		readQInTotal <= readQInTotal + fromInteger(burstWords);

		if ( dmaReadCount > fromInteger(burstBytes) ) begin
			dmaReadCount <= dmaReadCount - fromInteger(burstBytes);
			readBurstIdxQ.enq(tuple2(readIdxQ.first, 
				fromInteger(burstWords)));
			readDoneQ.enq(tagged Invalid);
		end else begin //last burst
			dmaReadCount <= 0;
			readIdxQ.deq;
			readBurstIdxQ.enq(tuple2(readIdxQ.first, 
				truncate(dmaReadCount/fromInteger(wordBytes))));
			
			readDoneQ.enq(tagged Valid tag);
		end

	endrule

	FIFO#(Tuple2#(Bit#(wordSz), TagT)) readQ <- mkSizedFIFO(readQSize);
	
	Reg#(Bit#(32)) dmaReadBurstCount <- mkReg(0);
	//Reg#(Bit#(32)) pageWriteCount <- mkReg(0);
	rule flushHostRead;
		let ri = readBurstIdxQ.first;
		let tag = tpl_1(ri);
		let burstr = tpl_2(ri);
		if ( dmaReadBurstCount >= fromInteger(burstWords)-1 ) begin
			dmaReadBurstCount <= 0;
			readBurstIdxQ.deq;

		end else begin
			dmaReadBurstCount <= dmaReadBurstCount + 1;
		end

      let v <- toGet(rPipe).get;

	  if ( dmaReadBurstCount < burstr ) readQ.enq(tuple2(v, tag));
	endrule
	
	rule read_finish;
		let rv0 <- rServer.response.get;
		let isdone = readDoneQ.first;
		readDoneQ.deq;

		if ( isValid(isdone) ) begin
			let tag = fromMaybe(0,isdone);
			readDoneIdxQ.enq(tag);
		end
	endrule
	
	method ActionValue#(Tuple2#(Bit#(wordSz), TagT)) read;
		readQ.deq;
		readQOutTotal <= readQOutTotal + 1;
		return readQ.first;
	endmethod



	method Action startRead(TagT tag, Bit#(32) wordCount); // if ( dmaReadCount == 0 );
			startReadReqQ.enq(tuple2(tag, wordCount));
	endmethod
	method ActionValue#(TagT) done;
		readDoneIdxQ.deq;
		return readDoneIdxQ.first;
	endmethod
	method Action addBuffer(TagT tag, Bit#(32) offset, Bit#(32) bref);
		dmaReadRefs[tag] <= tuple2(bref, offset);
	endmethod
endmodule
	










interface FreeBufferClientIfc;
		method ActionValue#(Bit#(8)) done;
		method ActionValue#(Bit#(8)) getDmaRefReq;
		method Action dmaRefResp(Bit#(32) bref, Bit#(32) off);
		method ActionValue#(Bit#(8)) getTagTranslateReq;
		method Action tagTranslateResp(Bit#(8) tag);
		method ActionValue#(Tuple2#(Bit#(8), Bit#(8))) getTagTranslationStart;
		interface FIFOF#(Tuple2#(Bit#(8), Bit#(8))) tagTranslationStartIfc;
endinterface

interface DMAWriteEngineIfc#(numeric type wordSz);
	method Action write(Bit#(wordSz) word, Bit#(8) tag); 
	method Action startWrite(Bit#(8) freeidx, Bit#(32) wordCount);
	interface FreeBufferClientIfc bufClient;
endinterface
module mkDmaWriteEngine# (
	Server#(MemengineCmd,Bool) wServer,
	PipeIn#(Bit#(wordSz)) wPipe )(DMAWriteEngineIfc#(wordSz))
	;
	
	Integer bufferCount = valueOf(WriteBufferCount);
	Integer wordBytes = valueOf(WordBytes); 
	Integer burstBytes = 32*4;
	Integer burstWords = burstBytes/wordBytes;
	
	Integer pageBytes = valueOf(PageBytes);

	BRAMFIFOVectorIfc#(WriteBufferCountLog, 12, Bit#(wordSz)) writeBuffer <- mkBRAMFIFOVector(burstWords);
	Vector#(WriteBufferCount, Reg#(Tuple2#(Bit#(32), Bit#(4)))) dmaWriteOffset <- replicateM(mkReg(tuple2(0,0))); // tag -> curoffset, writeEpochIdx
	Vector#(WriteBufferCount, Reg#(Bit#(4))) dmaWriteOffsetNew <- replicateM(mkReg(0)); // tag -> writeEpochIdx
	Vector#(WriteBufferCount, Reg#(Tuple2#(Bit#(8),Bit#(32)))) dmaWriteBuf <- replicateM(mkReg(tuple2(0,0))); // tag -> bufferidx, writeCount
   
	//Reg#(Bit#(32)) writeCount <- mkReg(0);

	FIFO#(Bit#(32)) dmaBurstOffsetQ <- mkSizedFIFO(8);
	FIFO#(Tuple2#(Bit#(8), Bit#(8))) dmaWriteLocQ <- mkSizedFIFO(16);

	FIFO#(Bit#(8)) dmaRefReqQ <- mkFIFO; // idx
	FIFO#(Tuple2#(Bit#(32),Bit#(32))) dmaRefRespQ <- mkFIFO; // dmaref, offset

	FIFO#(Bit#(8)) tagTranslateReqQ <- mkFIFO; // external bufidx
	FIFO#(Bit#(8)) tagTranslateRespQ <- mkFIFO; // internal tag
	FIFOF#(Tuple2#(Bit#(8), Bit#(8))) tagTranslateStartQ <- mkFIFOF; // internal, external


	FIFO#(Bit#(8)) startWriteTagQ <- mkSizedFIFO(8);
	FIFO#(Bit#(8)) startDmaFlushQ <- mkSizedFIFO(8);
	rule startFlushDma;
		let tag <- writeBuffer.getReadyIdx;
		//let rcount = writeBuffer.getDataCount(tag);

		startDmaFlushQ.enq(zeroExtend(tag));
		let rbuf = tpl_1(dmaWriteBuf[tag]);
		dmaRefReqQ.enq(rbuf);

		writeBuffer.startBurst(fromInteger(burstWords), tag);
		//$display ( "starting write burst at tag %d >> rbuf %d", tag, rbuf );
	endrule


	FIFO#(Tuple3#(Bit#(32), Bit#(8), Bit#(8))) dmaTwo2ThreePipeQ <- mkFIFO;
	rule startFlushDma2;
		let tag = startDmaFlushQ.first;
		startDmaFlushQ.deq;

		let doff = dmaWriteOffset[tag];
		let offset = tpl_1(doff);
		//let offset = dummyOffset;
		let phase = tpl_2(doff);
		let nphase = dmaWriteOffsetNew[tag];
		if ( phase != nphase ) begin
			offset = 0;
			phase = nphase;
		end

		let rbuf = tpl_1(dmaWriteBuf[tag]);
		dmaWriteOffset[tag] <= tuple2(offset+fromInteger(burstBytes), phase);

		dmaTwo2ThreePipeQ.enq(tuple3(offset, rbuf, tag));

	endrule




	FIFO#(MemengineCmd) engineCmdQ <- mkSizedFIFO(4);
	rule startFlushDma3;
		dmaTwo2ThreePipeQ.deq;
		let pipeData = dmaTwo2ThreePipeQ.first;
		let offset = tpl_1(pipeData);
		let rbuf = tpl_2(pipeData);
		let tag = tpl_3(pipeData);

		//let wr = dmaWriteRefs[rbuf];
		let wr = dmaRefRespQ.first;
		dmaRefRespQ.deq;
		let wrRef = tpl_1(wr);
		let wrOff = tpl_2(wr);
		let burstOff = wrOff + offset;
	  
		if ( offset < fromInteger(pageBytes) ) begin
			engineCmdQ.enq(MemengineCmd{sglId:wrRef, base:zeroExtend(burstOff), len:fromInteger(burstBytes), burstLen:fromInteger(burstBytes)});
			$display("writeEngine enq: wrRef=%x, base=%x, len=%d", wrRef, burstOff, burstBytes);

			dmaWriteLocQ.enq(tuple2(rbuf, tag));
			dmaBurstOffsetQ.enq(offset);
			startWriteTagQ.enq(tag);

			//$display( "Sending burst cmd tag %d rbuf %d offset %dref:%x/%x", tag, rbuf, offset, wrRef, wrOff );
		end else begin
			$display( "EXCEPTION: Offset out of range %d @ %d", offset, rbuf);
		end

/*
		if ( dummyOffset+fromInteger(burstBytes) < fromInteger(pageBytes) ) begin
			dummyOffset <= offset + fromInteger(burstBytes);
		end else dummyOffset <= 0;
*/
	endrule

	rule driveEngineCmd;
		let cmd = engineCmdQ.first;
		engineCmdQ.deq;
		wServer.request.put(cmd);
	endrule

	FIFO#(Bit#(8)) curWriteTagQ <- mkSizedFIFO(8);
	Reg#(Bit#(5)) burstCount <- mkReg(0);
	rule flushDma;
		if ( burstCount+1 >= fromInteger(burstWords) ) begin
			burstCount <= 0;
			startWriteTagQ.deq;
		end else burstCount <= burstCount + 1;
		let tag = startWriteTagQ.first;

		writeBuffer.reqDeq(truncate(tag));
		curWriteTagQ.enq(tag);
		//$display ( "requesting data at tag %d", tag );
	endrule

	FIFO#(Tuple2#(Bit#(8), Bit#(8))) writeDoneQ <- mkFIFO;

	rule flushDma2;
		let tag = curWriteTagQ.first;
		curWriteTagQ.deq;


		let d <- writeBuffer.respDeq;
		//$display ( "enqing data at tag %d %x", tag , d );

		wPipe.enq(d);
	endrule

	rule write_finish;
		dmaBurstOffsetQ.deq;
		dmaWriteLocQ.deq;

		let rv1 <- wServer.response.get;
		let dmaOff = dmaBurstOffsetQ.first;
		let bd = dmaWriteLocQ.first;
		let rbuf = tpl_1(bd);
		let tag = tpl_2(bd);
		
		let wReqBytes = tpl_2(dmaWriteBuf[tag]) * fromInteger(wordBytes);
		let nextOff = dmaOff + fromInteger(burstBytes);
		//$display( "burst for off %d tag %d done (%d/%d)", dmaOff, tag, nextOff, wReqBytes );

		if ( nextOff >= wReqBytes ) begin
			writeDoneQ.enq(tuple2(rbuf, tag));
			//$display( "Sending write done at tag %d", tag );
			//writeCountQ.deq;
		end
	endrule

	FIFO#(Bit#(8)) freeInternalTagQ <- mkSizedFIFO(bufferCount);
	Vector#(WriteBufferCount, Reg#(Bit#(8))) internalTagMap <- replicateM(mkReg(0)); // internal tag -> external tag
	//Vector#(128, Reg#(Bit#(8))) externalTagMap <- replicateM(mkReg(0)); // external tag -> internal tag //FIXME

	Reg#(Bit#(8)) freeInternalTagCounter <- mkReg(0);
	rule fillFreeITag (freeInternalTagCounter < fromInteger(bufferCount));
		freeInternalTagCounter <= freeInternalTagCounter + 1;

		freeInternalTagQ.enq(freeInternalTagCounter);
	endrule
	//TODO set "started" or something once this init is done

	FIFO#(Bit#(wordSz)) writeReqQ <- mkFIFO;
	rule driveWriteBuffer;
		let tp = writeReqQ.first;
		writeReqQ.deq;
		tagTranslateRespQ.deq;
		let tag = tagTranslateRespQ.first;
		writeBuffer.enq(tp,truncate(tag));
		//$display ( "writing word to tag %d", tag );
	endrule

	method Action write(Bit#(wordSz) word, Bit#(8) bufidx); 
		tagTranslateReqQ.enq(bufidx);
		writeReqQ.enq(word);
		//let tag = externalTagMap[bufidx];
		//writeBuffer.enq(word,truncate(tag));
		//$display ( "writing word to bufidx %d", bufidx );
	endmethod
	method Action startWrite(Bit#(8) freeidx, Bit#(32) wordCount);
		
		freeInternalTagQ.deq;
		let tag = freeInternalTagQ.first;

		//externalTagMap[freeidx] <= tag;
		tagTranslateStartQ.enq(tuple2(tag, freeidx));

		dmaWriteBuf[tag] <= tuple2(freeidx, zeroExtend(wordCount));
		dmaWriteOffsetNew[tag] <= dmaWriteOffsetNew[tag] + 1;
		
		//dmaWriteOffset[tag] <= tuple2(0, 0);

		//$display( "Starting writing %d -> %d", freeidx, tag );

		//startWriteTestQ.enq(tag);
	endmethod

	interface FreeBufferClientIfc bufClient;
		method ActionValue#(Bit#(8)) done;
			let dr = writeDoneQ.first;
			let tag = tpl_2(dr);
			freeInternalTagQ.enq(tag);

			writeDoneQ.deq;
			//$display( "Finishing write to tag %d", tag );

			return tpl_1(dr);
		endmethod
		method ActionValue#(Bit#(8)) getDmaRefReq;
			dmaRefReqQ.deq;
			return dmaRefReqQ.first;
		endmethod
		method Action dmaRefResp(Bit#(32) bref, Bit#(32) off);
			dmaRefRespQ.enq(tuple2(bref,off));
		endmethod
		method ActionValue#(Bit#(8)) getTagTranslateReq;
			tagTranslateReqQ.deq;
			return tagTranslateReqQ.first;
		endmethod
		method Action tagTranslateResp(Bit#(8) tag);
			tagTranslateRespQ.enq(tag);
		endmethod
		interface FIFOF tagTranslationStartIfc = tagTranslateStartQ;
		method ActionValue#(Tuple2#(Bit#(8), Bit#(8))) getTagTranslationStart;
			tagTranslateStartQ.deq;
			return tagTranslateStartQ.first;
		endmethod
	endinterface
endmodule

interface FreeBufferManagerIfc;
	method Action addBuffer(Bit#(32) offset, Bit#(32) bref);
	method ActionValue#(Bit#(8)) done;
endinterface
module mkFreeBufferManager#(Vector#(tNumClient, FreeBufferClientIfc) clients) (FreeBufferManagerIfc);
	
	Integer bufferCount = valueOf(WriteBufferCount);
	Integer bufferCountLog = valueOf(WriteBufferCountLog);
	Integer numClient = valueOf(tNumClient);
   
	Vector#(WriteBufferTotal, Reg#(Tuple2#(Bit#(32),Bit#(32)))) dmaWriteRefs <- replicateM(mkReg(?)); //bufferidx -> dmaref,offset
	Vector#(WriteBufferTotal, Reg#(Bit#(8))) externalTagMap <- replicateM(mkReg(0)); // external tag -> internal tag //FIXME
	
	Reg#(Bit#(8)) addBufferIdx <- mkReg(0);

	rule tagTranslateStart;
		Bool wrote = False;
		for ( Integer i = 0; i < numClient; i = i + 1) begin
			if ( !wrote && clients[i].tagTranslationStartIfc.notEmpty) begin
				let tr <- clients[i].getTagTranslationStart;
				externalTagMap[tpl_2(tr)] <= tpl_1(tr);
				wrote = True;
			end
		end
	endrule

	FIFOF#(Bit#(8)) writeDoneQ <- mkFIFOF;
	for ( Integer i = 0; i < numClient; i = i + 1) begin
	/*
		rule checkWriteStart;
			let tr <- clients[i].getTagTranslationStart;
			externalTagMap[tpl_2(tr)] <= tpl_1(tr);
		endrule
		*/
		rule translateTag;
			let req <- clients[i].getTagTranslateReq;
			let res = externalTagMap[req];
			clients[i].tagTranslateResp(res);
		endrule

		FIFOF#(Tuple2#(Bit#(8), Bit#(8))) writeDoneQ1 <- mkFIFOF;
		rule checkDone1;
			let done1 <- clients[i].done;
			writeDoneQ.enq(done1);
		endrule
	
	
		rule getDmaRef;
			let idx <- clients[i].getDmaRefReq;

			let wr = dmaWriteRefs[idx];
			let wrRef = tpl_1(wr);
			let wrOff = tpl_2(wr);
			clients[i].dmaRefResp(wrRef, wrOff);
		endrule
	end

	method Action addBuffer(Bit#(32) offset, Bit#(32) bref);
		addBufferIdx <= addBufferIdx + 1;
		dmaWriteRefs[addBufferIdx] <= tuple2(bref, offset);
	endmethod

	method ActionValue#(Bit#(8)) done;
			writeDoneQ.deq;
			return writeDoneQ.first;
	endmethod
endmodule









typedef 32 StorageBridgeBufferCount;

interface StorageBridgeDmaManagerIfc#(numeric type wordSz);
	method Action addBridgeBuffer(Bit#(32) pointer, Bit#(32) offset, Bit#(8) idx);
	method Action readBufferReady(Bit#(8) bufidx, Bit#(8) targetbuf);
	method ActionValue#(Bit#(8)) getFreeBufIdx;
	method Action returnFreeBufIdx(Bit#(8) idx);
	
	method Action readPage(Bit#(64) pageIdx, Bit#(8) tag);
	method ActionValue#(Tuple2#(Bit#(wordSz), Bit#(8))) readWord;
	method Action writePage (Bit#(8) bufidx);
	method Action writeWord (Bit#(wordSz) data);//, Bit#(8) tag);
	method ActionValue#(Bit#(8)) writeDone;
endinterface

module mkStorageBridgeManager#(
	Server#(MemengineCmd, Bool) wServer,
	PipeIn#(Bit#(wordSz)) wPipe,
	Server#(MemengineCmd,Bool) rServer,
	PipeOut#(Bit#(wordSz)) rPipe
	) (StorageBridgeDmaManagerIfc#(wordSz));
	Integer storageBridgeBufferCount = valueOf(StorageBridgeBufferCount);
	
	Integer pageBytes = valueOf(PageBytes);
	
	Integer wordBytes = valueOf(WordBytes); 
	Integer burstBytes = 16*8;
	Integer burstWords = burstBytes/wordBytes;

	Vector#(StorageBridgeBufferCount, Reg#(Tuple2#(Bit#(32), Bit#(32)))) bridgeDmaRefs <- replicateM(mkReg(?));
	FIFO#(Bit#(8)) freeBufIdxQ <- mkSizedFIFO(storageBridgeBufferCount);

	FIFO#(Tuple2#(Bit#(8), Bit#(8))) readBufferReadyQ <- mkSizedFIFO(4);
	Reg#(Bit#(32)) pageReadOffset <- mkReg(65535);
	Reg#(Bit#(8)) pageReadBufIdx <- mkReg(0);
	Reg#(Bit#(8)) targetBufIdx <- mkReg(0);
	Reg#(Bit#(32)) pageReadRef <- mkReg(0);
	Reg#(Bit#(32)) pageReadRefOff <- mkReg(0);

	FIFO#(Maybe#(Bit#(8))) readDoneQ <- mkSizedFIFO(1);
	
	rule read_finish;
		let rv0 <- rServer.response.get;

		readDoneQ.deq;
		let pd = readDoneQ.first;
		if ( isValid(pd) ) begin
			freeBufIdxQ.enq(fromMaybe(0,pd));
		end
	endrule

	//TODO: take page size as input! like the other dma helpers
	rule startPageRead(pageReadOffset >= fromInteger(pageBytes));
		pageReadOffset <= 0;

		readBufferReadyQ.deq;
		let bufs = readBufferReadyQ.first;
		let bufidx = tpl_1(bufs);
		let targetbuf = tpl_2(bufs);
		pageReadBufIdx <= bufidx;
		targetBufIdx <= targetbuf;
		let rt = bridgeDmaRefs[bufidx];
		pageReadRef <= tpl_1(rt);
		pageReadRefOff <= tpl_2(rt);
		
		$display ( "Starting page read bufidx:%d", bufidx );
	endrule

	FIFO#(Bit#(8)) readBurstIdxQ <- mkSizedFIFO(8);
	
	Integer readQSize = 64;
	Reg#(Bit#(8)) readQInTotal <- mkReg(0);
	Reg#(Bit#(8)) readQOutTotal <- mkReg(0);


	rule driveBurstCmd(pageReadOffset < fromInteger(pageBytes) &&
		(readQInTotal - readQOutTotal + fromInteger(burstWords) < fromInteger(readQSize)) );
		let dmaReadOffset = pageReadRefOff+pageReadOffset;

		rServer.request.put(MemengineCmd{sglId:pageReadRef, base:extend(dmaReadOffset), len:fromInteger(burstBytes), burstLen:fromInteger(burstBytes)});

		readQInTotal <= readQInTotal + fromInteger(burstWords);

		pageReadOffset <= pageReadOffset + fromInteger(burstBytes);

		if ( pageReadOffset + fromInteger(burstBytes) >= fromInteger(pageBytes) ) begin
			readDoneQ.enq(tagged Valid pageReadBufIdx);
		end else begin
			readDoneQ.enq(tagged Invalid);
		end

		readBurstIdxQ.enq(targetBufIdx);

		//$display ( "Starting burst %d @ %d", pageReadOffset, pageReadBufIdx );
	endrule

	FIFO#(Tuple2#(Bit#(wordSz), Bit#(8))) readQ <- mkSizedFIFO(readQSize);
	Reg#(Bit#(8)) dmaReadBurstCount <- mkReg(0);
	rule recvDmaRead;
		if ( dmaReadBurstCount + 1 >= fromInteger(burstWords) )
		begin
			dmaReadBurstCount <= 0;
			readBurstIdxQ.deq;
		end else begin
			dmaReadBurstCount <= dmaReadBurstCount + 1;
		end
		
		let bufidx = readBurstIdxQ.first;
		let v <- toGet(rPipe).get;

		readQ.enq(tuple2(v, bufidx));
	endrule

	FIFO#(Bit#(wordSz)) writeQ <- mkSizedFIFO(32);
	Reg#(Bit#(8)) writeInTotal <- mkReg(0);
	Reg#(Bit#(8)) writeOutTotal <- mkReg(0);
	Reg#(Bit#(32)) dmaWriteOffset <- mkReg(0);

	Reg#(Bit#(8)) curWriteBufIdx <- mkReg(0);

	Reg#(Bit#(32)) pageWriteRef <- mkReg(0);
	Reg#(Bit#(32)) pageWriteRefOff <- mkReg(0);
	
	FIFO#(Maybe#(Bit#(8))) writeDoneQ <- mkSizedFIFO(1);
	FIFO#(Bit#(8)) writeDoneIdxQ <- mkFIFO;

	function Bit#(8) writeDataCount();
		return writeInTotal - writeOutTotal;

	endfunction
	
	rule recvDmaWrite;
		let rv1 <- wServer.response.get;
		writeDoneQ.deq;
		let wd = writeDoneQ.first;
		if ( isValid(wd) ) begin
			writeDoneIdxQ.enq(fromMaybe(0, wd));
		end
	endrule

	rule driveDmaWrite (dmaWriteOffset > 0 && writeDataCount() >= 8 );
		let burstOff = dmaWriteOffset + fromInteger(pageBytes) - dmaWriteOffset;

		wServer.request.put(MemengineCmd{sglId:pageWriteRef, base:zeroExtend(burstOff), len:fromInteger(burstBytes), burstLen:fromInteger(burstBytes)});

		let nextWriteOffset = dmaWriteOffset - fromInteger(burstBytes);
		dmaWriteOffset <= nextWriteOffset;
		writeOutTotal <= writeOutTotal + fromInteger(burstWords);

		if ( nextWriteOffset == 0 ) begin
			writeDoneQ.enq(tagged Valid curWriteBufIdx);
		end else begin
			writeDoneQ.enq(tagged Invalid);
		end
	endrule

	rule writeWordR;
		wPipe.enq(writeQ.first);
		writeQ.deq;
	endrule


	method Action addBridgeBuffer(Bit#(32) pointer, Bit#(32) offset, Bit#(8) idx);
		bridgeDmaRefs[idx] <= tuple2(pointer, offset);
		freeBufIdxQ.enq(idx);
	endmethod
	method Action readBufferReady(Bit#(8) bufidx, Bit#(8) targetbuf);
		readBufferReadyQ.enq(tuple2(bufidx, targetbuf));
	endmethod
	method ActionValue#(Bit#(8)) getFreeBufIdx;
		Bit#(8) bufidx = freeBufIdxQ.first;
		freeBufIdxQ.deq;
		return bufidx;
	endmethod
	method Action returnFreeBufIdx(Bit#(8) idx);
		freeBufIdxQ.enq(idx);
	endmethod
	method Action readPage(Bit#(64) pageIdx, Bit#(8) tag);
	endmethod
	method ActionValue#(Tuple2#(Bit#(wordSz), Bit#(8))) readWord;
		readQOutTotal <= readQOutTotal + 1;
		readQ.deq;
		return readQ.first;
	endmethod
	method Action writePage (Bit#(8) bufidx) if ( dmaWriteOffset == 0 );
		dmaWriteOffset <= fromInteger(pageBytes);
		let rt = bridgeDmaRefs[bufidx];
		pageWriteRef <= tpl_1(rt);
		pageWriteRefOff <= tpl_2(rt);
		curWriteBufIdx <= bufidx;
	endmethod
	method Action writeWord (Bit#(wordSz) data);//, Bit#(8) tag);
		writeQ.enq(data);
		writeInTotal <= writeInTotal + 1;
	endmethod
	method ActionValue#(Bit#(8)) writeDone;
		let d = writeDoneIdxQ.first;
		writeDoneIdxQ.deq;
		return d;
	endmethod
endmodule
