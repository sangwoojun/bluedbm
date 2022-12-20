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

import AuroraCommon::*;
import AuroraExtImportCommon::*;
import AuroraExtImport117::*;
import AuroraExtImport119::*;

import Nbody::*;

interface HwMainIfc;
endinterface

Integer idxFPGA1 = 0;
Integer idxFPGA2 = 1;

Integer pubKeyFPGA1 = 1;
Integer pubKeyFPGA2 = 2;

Integer byteTotal = 16*1024*1024*4;
Integer 64ByteWordsTotal = 7*1024*1024;
Integer 64ByteWordsPm = 4*1024*1024;
Integer 64ByteWordsV = 3*1024*1024;
Integer 64ByteWordsPmHalf = 4*1024*512;
Integer 64ByteWordsVHalf = 3*1024*512;

function Bit#(8) cycleDeciderExt(Bit#(8) routeCnt, Bit#(8) payloadByte);
	Bit#(8) auroraExtCnt = 0;
	if ( routeCnt == 0 ) begin
		Bit#(8) totalByte = 4+payloadByte;
		Bit#(16) totalBits = zeroExtend(totalByte) * 8;
		Bit#(16) decidedCycle = cycleDecider(totalBits);
		auroraExtCnt = truncate(decidedCycle);
	end else begin
		Bit#(8) totalByte = 4+2+payloadByte;
		Bit#(16) totalBits = zeroExtend(totalByte) * 8;
		Bit#(16) decidedCycle = cycleDecider(totalBits);
		auroraExtCnt = truncate(decidedCycle);
	end
	return auroraExtCnt;
endfunction

module mkHwMain#(PcieUserIfc pcie, DRAMUserIfc dram, Vector#(2, AuroraExtIfc) auroraQuads) (HwMainIfc);

	Clock curClk <- exposeCurrentClock;
	Reset curRst <- exposeCurrentReset;

	Clock pcieclk = pcie.user_clk;
	Reset pcierst = pcie.user_rst;	

	DRAMArbiterRemoteIfc#(4) dramArbiterRemote <- mkDRAMArbiterRemote;
	NbodyIfc nbody <- mkNbody;
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

	Reg#(Bool) useFpga2ModeInitOn <- mkReg(False);
	Reg#(Bool) useFpga2ModeCompOn <- mkReg(False);
	Reg#(Bool) fpga1 <- mkReg(False);
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
				fpga1 <= True;
			end
		end else if begin // Mode 1 ~ 5
			if ( off == 1 ) begin // Mode 1
				memWrRsltAddPm <= 469762048;
				memWrRsltAddV <= 738197504;
				memRdWordsPm <= fromInteger(64ByteWordsPm);
				memRdWordsV <= fromInteger(64ByteWordsV);
				fpga1MemReaderOn <= True;
				runMode <= truncate(off);
			end else begin // Mode 2 ~ 5
				if ( useFpga2ModeInitOn ) begin
					memWrRsltAddPm <= 134217728;
					memWrRsltAddV <= 369098752;
					memRdWordsPm <= fromInteger(64ByteWordsPmHalf);
					memRdWordsV <= fromInteger(64ByteWordsVHalf);
					useFpga2ModeInitOn <= False;
					useFpga2ModeCompOn <= True;
					runMode <= truncate(off);
				end else begin
					useFpga2ModeInitOn <= True;
					fpga1MemReaderOn <= True;
				end
			end
		end
	endrule
	/*//Generate a source routing packet
	// Information
	Bit#(32) address = 0;
	Bit#(32) aom = 420000000; // 0.42GB
	Bit#(1) header = 0; // 0: Write, 1: Read
	Bit#(32) aomNheader = (aom << 1) | zeroExtend(header);
	// Header Part
	Bit#(8) payloadByte = 8;
	Bit#(8) startPoint = fromInteger(idxFPGA1);
	Bit#(8) routeCnt = 0;
	Bit#(1) sdFlag = 0;
	Bit#(8) numHops = 0;
	Bit#(32) headerPartSR = (zeroExtend(payloadByte) << 24) | (zeroExtend(startPoint) << 16) | 
				(zeroExtend(routeCnt) << 9) | (zeroExtend(sdFlag) << 8) | 
				(zeroExtend(numHops));

	// Encryption
	// Payload
	Bit#(32) encAddress = address ^ fromInteger(pubKeyFPGA2);
	Bit#(32) encAomNheader = aomNheader ^ fromInteger(pubKeyFPGA2);
	// Header Part
	Bit#(32) encHeaderPartSR = headerPartSR ^ fromInteger(pubKeyFPGA2);

	// Final
	AuroraIfcType srPacket = (zeroExtend(encAddress) << 64) | (zeroExtend(encAomNheader) << 32) | (zeroExtend(encHeaderPartSR));
	sendPacketByAuroraFPGA1Q.enq(tuple2(srPacket, off));*/
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
				if ( memWrCntIni == fromInteger(64ByteWordsTotal) ) begin
					memWrCntIni <= 0;
					validCheckerQ.enq(1);
				end else begin
					memWrCntIni <= memWrCntIni + 1;
				end
			end else begin
				dramArbiterRemote.users[0].cmd(0, fromInteger(64ByteWordsTotal), 1, 0);
				memWrCntIni <= memWrCntIni + 1;
			end
		end else if ( fpga1MemWrRslt ) begin
			if ( memWrPm ) begin
				if ( memWrCntPm != 0 ) begin
					toMemDataPmQ.deq;
					let payload = toMemDataPmQ.first;
					dramArbiterRemote.users[0].write(payload);
					if ( memWrCntPm == 64 ) begin
						memWrRsltAddPm <= memWrRsltAddPm + (256*4*4);
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
						memWrRsltAddV <= memWrRsltAddV + (256*3*4);
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
	FIFOF#(AuroraIfcType) sendPacketByAuroraFPGA1Q <- mkFIFOF;
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
		if ( useFPGA2ModeInitOn ) begin
			if ( memRdPm ) begin
				if ( memRdPmCnt1 != 0 ) begin
					let payload <- dramArbiterRemote.users[0].read;
					sendPacketByAuroraFPGA1Q.enq(payload);
					if ( memRdPmCnt1 == fromInteger(64ByteWordsPmHalf) ) begin
						memRdPm <= False;
						memRdV <= True;
						memRdPmCnt1 <= 0;
					end else begin
						memRdPmCnt1 <= memRdPmCnt1 + 1;
					end
				end else begin
					dramArbiterRemote.users[0].cmd(memRdStrtAddPm, fromInteger(64ByteWordsPmHalf), 0, 0);
					memRdPmCnt1 <= memRdPmCnt1 + 1;
				end
			end else if ( memRdV ) begin
				if ( memRdVCnt2 != 0 ) begin
					let payload <- dramArbiterRemote.users[0].read;
					sendPacketByAuroraFPGA1Q.enq(payload);
					if ( memRdVCnt1 == fromInteger(64ByteWordsVHalf) ) begin
						memRdPm <= True;
						memRdV <= False;
						memRdVCnt1 <= 0;
					end else begin
						memRdVCnt1 <= memRdVCnt1 + 1;
					end
				end else begin
					dramArbiterRemote.users[0].cmd(memRdStrtAddV, fromInteger(64ByteWordsVHalf), 0, 0);
					memRdVCnt1 <= memRdVCnt1 + 1;
				end
			end
		end else begin
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
						if ( memRdVCnt1 == memRdWordsV - 1)) begin
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
	// FPGA1 (Aurora Part)
	//-------------------------------------------------------------------------------------------------
	rule fpga1AuroraPacketSender( sendPacketByAuroraFPGA1Q.notEmpty );
		sendPacketByAuroraFPGA1Q.deq;
		let packet = sendPacketByAuroraFPGA1Q.first;

		auroraQuads[0].user[0].send(AuroraSend{packet:sendPacket,num:8});
	endrule
	FIFOF#(AuroraIfcType) recvPacketByAuroraFPGA1Port0Q <- mkFIFOF;
	rule fpga1Receiver_Port0;
		Bit#(8) inPortFPGA1_0 = 0;
		Bit#(1) qidIn = inPortFPGA1_0[2];
		Bit#(2) pidIn = truncate(inPortFPGA1_0);

		let recvPacket <- auroraQuads[qidIn].user[pidIn].receive;
		recvPacketByAuroraFPGA1Port0Q.enq(recvPacket);
	endrule
	FIFOF#(AuroraIfcType) recvPacketByAuroraFPGA1Port1Q <- mkFIFOF;
	rule fpga1Receiver_Port1;
		Bit#(8) inPortFPGA1_1 = 0;
		Bit#(1) qidIn = inPortFPGA1_1[2];
		Bit#(2) pidIn = truncate(inPortFPGA1_1);

		let recvPacket <- auroraQuads[qidIn].user[pidIn].receive;
		recvPacketByAuroraFPGA1Port1Q.enq(recvPacket);
	endrule
	FIFOF#(AuroraIfcType) recvPacketByAuroraFPGA1Port2Q <- mkFIFOF;
	rule fpga1Receiver_Port2;
		Bit#(8) inPortFPGA1_2 = 0;
		Bit#(1) qidIn = inPortFPGA1_2[2];
		Bit#(2) pidIn = truncate(inPortFPGA1_2);

		let recvPacket <- auroraQuads[qidIn].user[pidIn].receive;
		recvPacketByAuroraFPGA1Port2Q.enq(recvPacket);
	endrule
	FIFOF#(AuroraIfcType) recvPacketByAuroraFPGA1Port3Q <- mkFIFOF;
	rule fpga1Receiver_Port3;
		Bit#(8) inPortFPGA1_3 = 0;
		Bit#(1) qidIn = inPortFPGA1_3[2];
		Bit#(2) pidIn = truncate(inPortFPGA1_3);

		let recvPacket <- auroraQuads[qidIn].user[pidIn].receive;
		recvPacketByAuroraFPGA1Port3Q.enq(recvPacket);
	endrule

	rule fpga1Decrypter( openConnect );
		Integer privKeyFPGA1 = 1;

		recvPacketByAuroraFPGA1Q.deq;
		let recvPacket = recvPacketByAuroraFPGA1Q.first;

		Bit#(32) headerPart = recvPacket[31:0] ^ fromInteger(privKeyFPGA1);
		Bit#(8) numHops = headerPart[7:0];
		Bit#(24) packetHeader = headerPart[31:8];
		Bit#(8) routeCnt = zeroExtend(packetHeader[7:1]);
		Bit#(8) payloadByte = packetHeader[23:16];

		AuroraIfcType payload = recvPacket >> 32;
		if ( packetHeader[0] == 0 ) begin // Source Routing
			Bit#(32) aomNheader = payload[31:0] ^ fromInteger(privKeyFPGA1);
			Bit#(32) address = payload[63:32] ^ fromInteger(privKeyFPGA1); 

			if ( aomNheader[0] == 0 ) begin // Write
				if ( aomNheader[31:1] == 4*1024 ) begin
					validCheckConnectionFPGA1Q.enq(1);
				end else begin
					validCheckConnectionFPGA1Q.enq(0);
				end		
			end	
		end else if ( packetHeader[0] == 1 ) begin // Data Sending
			Bit#(64) data = payload[63:0] ^ fromInteger(privKeyFPGA1);

			if ( data == 4294967296 ) begin
				validCheckConnectionFPGA1Q.enq(1);
			end else begin
				validCheckConnectionFPGA1Q.enq(0);
			end
		end
	endrule
	//--------------------------------------------------------------------------------------------
	// FPGA2
	//--------------------------------------------------------------------------------------------
	Vector#(4, FIFOF#(AuroraIfcType)) recvPacketByAuroraFPGA2Q <- replicateM( mkFIFOF );
	FIFOF#(AuroraIfcType) validCheckConnectionFPGA2Q <- mkFIFOF;
	rule fpga2Receiver_Port4( !openConnect );
		Bit#(8) inPortFPGA2_1 = 4;
		Bit#(1) qidIn = inPortFPGA2_1[2];
		Bit#(2) pidIn = truncate(inPortFPGA2_1);

		for ( Integer i = 0; i < 4; i = i + 1 ) begin
			let recvPacket <- auroraQuads[1].user[i].receive;
			recvPacketByAuroraFPGA2Q[i].enq(recvPacket);
		end
	endrule
	rule fpga2Decrypter( !openConnect );
		Integer privKeyFPGA2 = 2;

		recvPacketByAuroraFPGA2Q[0].deq;
		let recvPacket = recvPacketByAuroraFPGA2Q[0].first;

		Bit#(32) headerPart = recvPacket[31:0] ^ fromInteger(privKeyFPGA2);
		Bit#(8) numHops = headerPart[7:0];
		Bit#(24) packetHeader = headerPart[31:8];
		Bit#(8) routeCnt = zeroExtend(packetHeader[7:1]);
		Bit#(8) payloadByte = packetHeader[23:16];

		AuroraIfcType payload = recvPacket >> 32;
		if ( packetHeader[0] == 0 ) begin // Source Routing
			Bit#(32) aomNheader = payload[31:0] ^ fromInteger(privKeyFPGA2);
			Bit#(32) address = payload[63:32] ^ fromInteger(privKeyFPGA2); 

			if ( aomNheader[0] == 0 ) begin // Write
				if ( aomNheader[31:1] == 4*1024 ) begin
					validCheckConnectionFPGA2Q.enq(1);
				end else begin
					validCheckConnectionFPGA2Q.enq(0);
				end			
			end
		end else if ( packetHeader[0] == 1 ) begin // Data Sending
			Bit#(64) data = payload[63:0] ^ fromInteger(privKeyFPGA2);

			if ( data == 4294967296 ) begin
				validCheckConnectionFPGA2Q.enq(1);
			end else begin
				validCheckConnectionFPGA2Q.enq(0);
			end
		end
	endrule
	//--------------------------------------------------------------------------------------------
	// Send the packets to the host
	//--------------------------------------------------------------------------------------------
	FIFOF#(Bit#(32)) validCheckConnectionQ <- mkFIFOF;
	rule validCheckerFPGA1( openConnect );
		Bit#(8) validCheckPort = 1;
		Bit#(1) qidIn = validCheckPort[2];
		Bit#(2) pidIn = truncate(validCheckPort);

		let recvPacket <- auroraQuads[qidIn].user[pidIn].receive;

		if ( recvPacket == 1 ) begin
			validCheckConnectionQ.enq(1);
		end else if ( recvPacket == 0 ) begin
			validCheckConnectionQ.enq(0);
		end
	endrule
	rule validCheckerFPGA2( !openConnect );
		Bit#(8) validCheckPort = 5;
		Bit#(1) qidOut = validCheckPort[2];
		Bit#(2) pidOut = truncate(validCheckPort);

		validCheckConnectionFPGA2Q.deq;
		let sendPacket = validCheckConnectionFPGA2Q.first;

		auroraQuads[qidOut].user[pidOut].send(AuroraSend{packet:sendPacket,num:2});
	endrule
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
