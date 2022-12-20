import FIFO::*;
import FIFOF::*;
import Clocks::*;
import Vector::*;

import Serializer::*;

import BRAM::*;
import BRAMFIFO::*;

import PcieCtrl::*;

import DRAMController::*;
import DRAMArbiterRemote::*;

import Nbody::*;

interface HwMainIfc;
endinterface

Integer idxFPGA1 = 0;
Integer idxFPGA2 = 1;

Integer pubKeyFPGA1 = 1;
Integer pubKeyFPGA2 = 2;

Integer byteTotal = 16*1024*1024*4;
Integer wordsTotal64Byte = 7*1024*1024;
Integer wordsPm64Byte = 4*1024*1024;
Integer wordsV64Byte = 3*1024*1024;


module mkHwMain#(PcieUserIfc pcie, DRAMUserIfc dram) (HwMainIfc);

	Clock curClk <- exposeCurrentClock;
	Reset curRst <- exposeCurrentReset;

	Clock pcieclk = pcie.user_clk;
	Reset pcierst = pcie.user_rst;	

	DRAMArbiterRemoteIfc#(4) dramArbiterRemote <- mkDRAMArbiterRemote;
	NbodyIfc nbody <- mkNbody(FpPairIfc#(32) fpSub32, FpPairIfc#(32) fpAdd32, 
				  FpPairIfc#(32) fpMult32, FpPairIfc#(32) fpDiv32, 
				  FpFilter#(32) fpSqrt32);
	//--------------------------------------------------------------------------------------
	// Pcie Read and Write
	//--------------------------------------------------------------------------------------
	SyncFIFOIfc#(Tuple2#(IOReadReq, Bit#(32))) pcieRespQ <- mkSyncFIFOFromCC(16, pcieclk);
	SyncFIFOIfc#(IOReadReq) pcieReadReqQ <- mkSyncFIFOToCC(16, pcieclk, pcierst);
	SyncFIFOIfc#(IOWrite) pcieWriteQ <- mkSyncFIFOToCC(16, pcieclk, pcierst);	
	rule getReadReq;
		let r <- pcie.dataReq;
		pcieReadReqQ.enq(r);
	endrule
	rule returnReadResp;
		let r_ = pcieRespQ.first;
		pcieRespQ.deq;

		pcie.dataSend(tpl_1(r_), tpl_2(r_));
	endrule
	rule getWriteReq;
		let w <- pcie.dataReceive;
		pcieWriteQ.enq(w);
	endrule
	//--------------------------------------------------------------------------------------------
	// Get Commands from Host via PCIe
	//--------------------------------------------------------------------------------------------
	FIFO#(Bit#(512)) toMemPayloadQ <- mkSizedBRAMFIFO(32);	
	Reg#(Bit#(512)) toMemPayloadBuffer <- mkReg(0);
	Reg#(Bit#(16)) toMemPayloadQCnt <- mkReg(0);
	Reg#(Bit#(8)) toMemPayloadCnt <- mkReg(0);
	Reg#(Bit#(4)) runMode <- mkReg(0);

	Reg#(Bit#(64)) memWrRsltAddPm <- mkReg(0);
	Reg#(Bit#(64)) memWrRsltAddV <- mkReg(0);
	Reg#(Bit#(32)) memRdWordsPm <- mkReg(0);
	Reg#(Bit#(32)) memRdWordsV <- mkReg(0);

	Reg#(Bool) fpga1MemWrOn <- mkReg(False);
	Reg#(Bool) fpga1MemWrInit <- mkReg(False);
	Reg#(Bool) fpga1MemWrRslt <- mkReg(False);

	Reg#(Bool) fpga1MemReaderOn <- mkReg(False);
	rule getCmd;
		pcieWriteQ.deq;
		let w = pcieWriteQ.first;

		let d = w.data;
		let a = w.addr;
		let off = (a >> 2);

		if ( off == 0 ) begin // Initial Set
			if ( toMemPayloadCnt != 0 ) begin
				if ( toMemPayloadCnt == 15 ) begin
					Bit#(512) toMemPayloadPrev = toMemPayloadBuffer;
					Bit#(512) toMemPayload = (zeroExtend(d) << 32) | (toMemPayloadPrev);
					toMemPayloadQ.enq(toMemPayload);

					toMemPayloadBuffer <= 0;	
					toMemPayloadCnt <= 0;

					if ( toMemPayloadQCnt == 15 ) begin // toMemPayloadQ.enq : toMemPayloadQ.deq = 1 : 16
						fpga1MemWrOn <= True;
						fpga1MemWrInit <= True;
						toMemPayloadQCnt <= 0;
					end else begin
						toMemPayloadQCnt <= toMemPayloadQCnt + 1;
					end
				end else begin
					Bit#(512) toMemPayloadPrev = toMemPayloadBuffer;
					toMemPayloadBuffer <= (zeroExtend(d) << 32) | (toMemPayloadPrev);
					toMemPayloadCnt <= toMemPayloadCnt + 1;
				end
			end else begin
				toMemPayloadBuffer <= zeroExtend(d);
				toMemPayloadCnt <= toMemPayloadCnt + 1;
			end
		end else if ( off == 1 ) begin
			memWrRsltAddPm <= 469762048;
			memWrRsltAddV <= 738197504;
			memRdWordsPm <= fromInteger(wordsPm64Byte);
			memRdWordsV <= fromInteger(wordsV64Byte);
			fpga1MemReaderOn <= True;
			runMode <= truncate(off);
		end
	endrule
	//--------------------------------------------------------------------------------------------
	// Connection
	//  FPGA1(0) <-> (4)FPGA2
	//  FPGA1(1) <-> (5)FPGA2
	//  FPGA1(2) <-> (6)FPGA2
	//  FPGA1(3) <-> (7)FPGA2
	//--------------------------------------------------------------------------------------------
	// Usage of the entire memory
	//  Initial Set
	//   OriginPmAdd => 0 ~ 268,435,455                  OriginVAdd => 268,435,456 ~ 469,762,047
	//  For Mode 1
	//   OriginPmAdd => 0 ~ 268,435,455                  OriginVAdd => 268,435,456 ~ 469,762,047
	//   UpdatedPmAdd => 469,762,048 ~ 738,197,503       UpdatedVAdd => 738,197,504 ~ 939,524,095
	//  For Mode 2 ~ 5
	//   FPGA1
	//   OriginPmAdd => 0 ~ 134,217,727                  OriginVAdd => 268,435,456 ~ 369,098,751
	//   UpdatedPmAdd => 134,217,728 ~ 268,435,455       UpdatedVAdd => 369,098,752 ~ 467,762,047
	//   FPGA2
	//   OriginPmAdd => 0 ~ 134,217,727                  OriginVAdd => 268,435,456 ~ 369,098,751
	//   UpdatedPmAdd => 134,217,728 ~ 268,435,455       UpdatedVAdd => 369,098,752 ~ 467,762,047
	//--------------------------------------------------------------------------------------------
	// FPGA1 (Memory Part)
	//--------------------------------------------------------------------------------------------
	FIFOF#(Bit#(32)) validCheckerQ <- mkFIFOF;
	FIFO#(Bit#(512)) toMemDataPmQ <- mkSizedBRAMFIFO(64);
	FIFO#(Bit#(512)) toMemDataVQ <- mkSizedBRAMFIFO(48);
	Reg#(Bit#(32)) memWrCntIni <- mkReg(0);
	Reg#(Bit#(8)) memWrCntPm <- mkReg(0);
	Reg#(Bit#(8)) memWrCntV <- mkReg(0);
	Reg#(Bool) toNbodyPm <- mkReg(True);
	Reg#(Bool) fromNbodyPm <- mkReg(False);
	Reg#(Bool) toNbodyV <- mkReg(True);
	Reg#(Bool) fromNbodyV <- mkReg(False);
	Reg#(Bool) memWrPm <- mkReg(True);
	Reg#(Bool) memWrV <- mkReg(False);
	rule fpga1MemWriter( fpga1MemWrOn );
		if ( fpga1MemWrInit ) begin
			if ( memWrCntIni != 0 ) begin
				toMemPayloadQ.deq;
				let payload = toMemPayloadQ.first;
				dramArbiterRemote.users[0].write(payload);
				if ( memWrCntIni == fromInteger(wordsTotal64Byte) ) begin
					memWrCntIni <= 0;
					fpga1MemWrInit <= False;
					fpga1MemWrRslt <= True;
					validCheckerQ.enq(1);
				end else begin
					memWrCntIni <= memWrCntIni + 1;
				end
			end else begin
				dramArbiterRemote.users[0].cmd(0, fromInteger(wordsTotal64Byte), 1, 0);
				memWrCntIni <= memWrCntIni + 1;
			end
		end else if ( fpga1MemWrRslt ) begin
			if ( memWrPm ) begin
				if ( memWrCntPm != 0 ) begin
					toMemDataPmQ.deq;
					let payload = toMemDataPmQ.first;
					dramArbiterRemote.users[0].write(payload);
					if ( memWrCntPm == 64 ) begin
						if ( (memWrRsltAddPm + (256*4*4)) == 738197504 ) begin
							memWrRsltAddPm <= 469762048;
						end else begin
							memWrRsltAddPm <= memWrRsltAddPm + (256*4*4);
						end
						memWrCntPm <= 0;
						partPm <= False;
						partV <= True;
						toNbodyPm <= True;
						fromNbodyPm <= False;
					end else begin
						memWrCntPm <= memWrCntPm + 1;
					end
				end else begin
					dramArbiterRemote.users[0].cmd(memWrRsltAddPm, 64, 1, 0);
					memWrCntPm <= memWrCntPm + 1;
				end
			end else if ( memWrV ) begin
				if ( memWrCntV != 0 ) begin
					toMemDataVQ.deq;
					let payload = toMemDataVQ.first;
					dramArbiterRemote.users[0].write(payload);
					if ( memWrCntV == 48 ) begin
						if ( (memWrRsltAddV + (256*3*4)) == 939524096 ) begin
							memWrRsltAddV <= 738197504;
							fpga1MemWrInit <= True;
							fpga1MemWrRslt <= False;
							validCheckerQ.enq(1);
						end else begin
							memWrRsltAddV <= memWrRsltAddV + (256*3*4);				
						end
						memWrCntV <= 0;
						partPm <= True;
						partV <= False;
						toNbodyV <= True;
						fromNbodyV <= False;
					end else begin
						memWrCntV <= memWrCntV + 1;
					end
				end else begin
					dramArbiterRemote.users[0].cmd(memWrRsltAddV, 48, 1, 0);
					memWrCntV <= memWrCntV + 1;
				end
			end
		end
	endrule
	FIFO#(Bit#(512)) fromMemDataPmQ <- mkSizedBRAMFIFO(64);
	FIFO#(Bit#(512)) fromMemDataVQ <- mkSizedBRAMFIFO(48);
	Reg#(Bit#(64)) memRdStrtAddPm <- mkReg(0);
	Reg#(Bit#(64)) memRdStrtAddV <- mkReg(268435456);
	Reg#(Bit#(32)) memRdPmCnt1 <- mkReg(0);
	Reg#(Bit#(16)) memRdPmCnt2 <- mkReg(0);
	Reg#(Bit#(32)) memRdVCnt1 <- mkReg(0);
	Reg#(Bit#(8)) memRdVCnt2 <- mkReg(0);
	Reg#(Bool) memRdPm <- mkReg(True);
	Reg#(Bool) memRdV <- mkReg(False);
	rule fpga1MemReader( fpga1MemReaderOn );
		if ( memRdPm ) begin
			if ( memRdPmCnt1 != 0 ) begin
				let payload <- dramArbiterRemote.users[0].read;
				fromMemDataPmQ.enq(payload);
				if ( memRdPmCnt1 == memRdWordsPm ) begin
					if ( memRdPmCnt2 == 255 ) begin
						memRdPmCnt2 <= 0;
						memRdPm <= False;
						memRdV <= True;
					end else begin
						memRdPmCnt2 <= memRdPmCnt2 + 1;
					end
					memRdPmCnt1 <= 0;
				end else begin
					memRdPmCnt1 <= memRdPmCnt1 + 1;
				end
			end else begin
				dramArbiterRemote.users[0].cmd(memRdStrtAddPm, memRdWordsPm, 0, 0);
				memRdPmCnt1 <= memRdPmCnt1 + 1;
			end
		end else if ( memRdV ) begin
			if ( memRdVCnt2 != 0 ) begin
				let payload <- dramArbiterRemote.users[0].read;
				fromMemDataVQ.enq(payload);
				if ( memRdVCnt2 == 48 ) begin
					if ( memRdVCnt1 == memRdWordsV - 1 ) begin
						memRdStrtAddV <= 268435456;
						memRdVCnt1 <= 0;
						memRdPm <= False;
					end else begin
						memRdStrtAddV <= memRdStrtAddV + (256*3*4);
						memRdVCnt1 <= memRdVCnt1 + 1;
						memRdPm <= True;
					end
					memRdVCnt2 <= 0;
					memRdV <= False;
				end else begin
					memRdVCnt1 <= memRdVCnt1 + 1;
					memRdVCnt2 <= memRdVCnt2 + 1;
				end
			end else begin
				dramArbiterRemote.users[0].cmd(memRdStrtAddV, 48, 0, 0);
				memRdVCnt2 <= memRdVCnt2 + 1;
			end
		end
	endrule
	//-------------------------------------------------------------------------------------------------
	// FPGA1 (Data Organizer) Split the 512-bit payload to 32-bit data or Merge the datas to a payload
	//-------------------------------------------------------------------------------------------------
	FIFO#(Vector#(4, Bit#(32))) originDataPmQ <- mkSizedBRAMFIFO(64);
	FIFO#(Vector#(4, Bit#(32))) updatedDataPmQ <- mkSizedBRAMFIFO(256);
	Reg#(Bit#(512)) fromMemDataPmBuffer <- mkReg(0);
	Reg#(Bit#(512)) tomemDataPmBuffer <- mkReg(0);
	Reg#(Bit#(8)) originDataPmLeft <- mkReg(0);
	Reg#(Bit#(8)) updatedDataPmLeft <- mkReg(16);
	rule fpga1DataOrganizerPm;
		if ( toNbodyPm ) begin
			Vector#(4, Bit#(32)) pm = replicateM(0);
			if ( originDataPmLeft < 4 ) begin
				fromMemDataPmQ.deq;
				let d = fromMemDataPmQ.first;
				pm[0] = d[31:0]; // Position X 
				pm[1] = d[63:32]; // Position Y
				pm[2] = d[95:64]; // Position Z
				pm[3] = d[127:96]; // Mass
				originDataPmQ.enq(pm);
				fromMemDataPmBuffer <= zeroExtend(d >> 128);
				originDataPmLeft <= (16 - 4);
			end else begin
				let d = fromMemDataPmBuffer;
				pm[0] = d[31:0]; // Position X 
				pm[1] = d[63:32]; // Position Y
				pm[2] = d[95:64]; // Position Z
				pm[3] = d[127:96]; // Mass
				originDataPmQ.enq(pm);
				fromMemDataPmBuffer <= zeroExtend(d >> 128);
				originDataPmLeft <= originDataPmLeft - 4;
			end
		end else if ( fromNbodyPm ) begin
			updatedDataPmQ.deq;
			Vector#(4, Bit#(32)) d = updatedDataPmQ.first;
			Bit#(512) currP = (zeroExtend(d[3])) | (zeroExtend(d[2])) | (zeroExtend(d[1])) | (zeroExtend(d[0]));

			if ( updatedDataPmLeft == 4 ) begin
				let prevP = toMemDataPmBuffer;
				Bit#(512) finalP = (currP << 128) | (prevP);
				toMemDataPmQ.enq(finalP);
				updatedDataPmLeft <= 16; 
			end else begin
				if ( updatedDataPmLeft == 16 ) begin
					toMemDataPmBuffer <= currP;
				end else begin
					let prevP = toMemDataPmBuffer;
					Bit#(512) p = (currP << 128) | (prevP);
					toMemDataPmBuffer <= p;
				end
				updatedDataPmLeft <= updatedDataPmLeft - 4;
			end
		end
	endrule
	FIFO#(Vector#(3, Bit#(32))) originDataVQ <- mkSizedBRAMFIFO(256);
	FIFO#(Vector#(3, Bit#(32))) updatedDataVQ <- mkSizedBRAMFIFO(256);
	Reg#(Maybe#(Bit#(512))) fromMemDataVBuffer <- mkReg(tagged Invalid);
	Reg#(Bit#(512)) toMemDataVBuffer <- mkReg(0);
	Reg#(Bit#(8)) originDataVLeft <- mkReg(0);
	Reg#(Bit#(8)) updatedDataVStacked <- mkReg(0);
	rule fpga1DataOrganizerV;
		if ( toNbodyV ) begin
			Vector#(3, Bit#(32)) v = replicateM(0);
			if ( isValid(fromMemDataVBuffer) ) begin
				if ( originDataVLeft < 3 ) begin
					fromMemDataVQ.deq;
					let currD = fromMemDataVQ.first;
					let prevD = fromMaybe(?, fromMemDataVBuffer);
					Bit#(576) d = (zeroExtend(currD) << (originDataVLeft * 32)) | (zeroExtend(prevD));
					v[0] = d[31:0]; // Velocity X
					v[1] = d[63:32]; // Velocity Y
					v[2] = d[95:64]; // Velocity Z
					originDataVQ.enq(v);
					fromMemDataVBuffer <= tagged Valid truncate(d >> 96);
					originDataVLeft <= originDataVLeft + 16 - 3;
				end else begin
					let d = fromMaybe(?, fromMemDataVBuffer);
					v[0] = d[31:0]; // Velocity X
					v[1] = d[63:32]; // Velocity Y
					v[2] = d[95:64]; // Velocity Z
					originDataVQ.enq(v);
					if ( originDataVLeft == 3 ) begin
						fromMemDataBufferV <= tagged Invalid;
						originDataVLeft <= 16;
					end else begin
						fromMemDataBufferV <= tagged Valid (d >> 96);
						originDataVLeft <= originDataVLeft - 3;
					end
				end
			end else begin
				fromMemDataVQ.deq;
				let d = fromMemDataVQ.first;
				v[0] = d[31:0]; // Velocity X
				v[1] = d[63:32]; // Velocity Y
				v[2] = d[95:64]; //  Velocity Z
				originDataVQ.enq(v);
				fromMemDataVBuffer <= tagged Valid (d >> 96);
				originDataVLeft <= originDataVLeft - 3;
			end
		end else if ( fromNbodyV ) begin
			updatedDataVQ.deq;
			Vector#(3, Bit#(32)) d = updatedDataVQ.first;
			Bit#(576) currP = (zeroExtend(d[2])) | (zeroExtend(d[1])) | (zeroExtend(d[0]));

			if ( updatedDataVStacked > 12 ) begin
				let prevP = toMemDataVBuffer;
				Bit#(576) totalP = (currP << 32) | (prevP);
				toMemDataVQ.enq(truncate(totalP));
				updatedDataVStacked <= (3 - (16-updatedDataVStacked)); 
				toMemDataVBuffer <= (totalP >> 512);
			end else begin
				if ( updatedDataVStacked == 0 ) begin
					toMemDataVBuffer <= currP;
				end else begin
					let prevP = toMemDataVBuffer;
					Bit#(576) p = (currP << 32) | (prevP);
					toMemDataVBuffer <= p;
				end
				updatedDataVStacked <= updatedDataVStacked + 3;
			end
		end
	endrule
	//--------------------------------------------------------------------------------------------
	// FPGA1 (A Part of Computing N-body problem)
	//--------------------------------------------------------------------------------------------
	Reg#(Bit#(32)) relayDataPMCnt1 <- mkReg(0);
	Reg#(Bit#(16)) relayDataPMCnt2 <- mkReg(0);
	Reg#(Bit#(32)) relayDataVCnt1 <- mkReg(0);
	Reg#(Bit#(16)) relayDataVCnt2 <- mkReg(0);
	Reg#(Bool) relayDataPM <- mkReg(True);
	Reg#(Bool) relayDataV <- mkReg(False);
	rule fpga1RelayDataToNbody;
		if ( relayDataPM ) begin
			originDataPMQ.deq;
			let p = originDataPMQ.first;
	
			nbody.dataPMIn(p, relayDataPMCnt1);	

			if ( relayDataPMCnt1 == (fromInteger(totalParticles) - 1) ) begin
				if ( relayDataPMCnt2 == 255 ) begin
					relayDataPMCnt2 <= 0;
					relayDataPM <= False;
					relayDataV <= True;
				end else begin
					relayDataPMCnt2 <= relayDataPMCnt2 + 1;
				end
				relayDataPMCnt1 <= 0;
			end else begin
				relayDataPMCnt1 <= relayDataPMCnt1 + 1;
			end
		end else if ( relayDataV ) begin
			originDataVQ.deq;
			let p = originDataVQ.first;

			nbody.dataVIn(p, relayDataCnt1);
			
			if ( relayDataVCnt2 == 255 ) begin
				if ( relayDataVCnt1 == (fromInteger(totalParticles) - 1) ) begin
					relayDataVCnt1 <= 0;
				end else begin
					relayDataVCnt1 <= relayDataVCnt1 + 1;
				end
				relayDataPM <= True;
				relayDataV <= False;
				relayDataCnt2 <= 0;
			end else begin
				relayDataCnt1 <= relayDataCnt1 + 1;
				relayDataCnt2 <= relayDataCnt2 + 1;
			end
		end
	endrule
	Reg#(Bit#(8)) recvDataPmCnt <- mkReg(0);
	Reg#(Bit#(8)) recvDataVCnt <- mkReg(0);
	Reg#(Bool) recvDataPm <- mkReg(True);
	Reg#(Bool) recvDataV <- mkReg(False);
	rule fpga1RecvResult;
		if ( recvDataPm ) begin
			let d <- nbody.dataOutPm;
			updatedDataPmQ.enq(d);
			if ( recvDataPmCnt != 0 ) begin
				if ( recvDataPmCnt == 255 ) begin
					recvDataPmCnt <= 0;
					recvDataPm <= False;
					recvDataV <= True;
				end else begin
					recvDataPmCnt <= recvDataPmCnt + 1;
				end
			end else begin
				recvDataPmCnt <= recvDataPmCnt + 1;
				toNbodyPm <= False;
				fromNbodyPm <= True;
			end
		end else if ( recvDataV ) begin
			let d <- nbody.dataOuV;
			updatedDataVQ.enq(d);
			if ( recvDataVCnt != 0 ) begin
				if ( recvDataVCnt == 255 ) begin
					recvDataVCnt <= 0;
					recvDataPm <= True;
					recvDataV <= False;
				end else begin
					recvDataVCnt <= recvDataVCnt + 1;
				end
			end else begin
				recvDataVCnt <= recvDataVCnt + 1;
				toNbodyV <= False;
				fromNbodyV <= True;
			end
		end
	endrule
	//-------------------------------------------------------------------------------------------------
	// FPGA1 (A Part of Checking Status)
	//-------------------------------------------------------------------------------------------------
	rule getStatus;
		pcieReadReqQ.deq;
		let r = pcieReadReqQ.first;
		Bit#(4) a = truncate(r.addr>>2);
		if ( a == 0 ) begin
			if ( validCheckerQ.notEmpty ) begin
				pcieRespQ.enq(tuple2(r, validCheckerQ.first));
				validCheckerQ.deq;
			end else begin 
				pcieRespQ.enq(tuple2(r, 32'hffffffff));
			end
		end
	endrule
endmodule
