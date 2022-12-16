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

Integer totalMemWorRWords = 7*1024*1024;
Integer pmMemWorRWords = 4*1024*1024;
Integer vMemWorRWords = 3*1024*1024;

Integer read = 0;
Integer write = 1;
Integer local = 0;
Integer remote = 1;

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
	FIFOF#(Tuple2#(AuroraIfcType, Bit#(20))) sendPacketByAuroraFPGA1Q <- mkFIFOF;
	// Mode 0
	FIFO#(Bit#(512)) toMemPayloadQ <- mkSizedBRAMFIFO(32);	
	Reg#(Bit#(512)) toMemPayloadBuffer <- mkReg(0);
	Reg#(Bit#(16)) toMemPayloadQCnt <- mkReg(0);
	Reg#(Bit#(8)) toMemPayloadCnt <- mkReg(0);
	
	Reg#(Bool) startMemWrite <- mkReg(False);
	Reg#(Bool) openConnect <- mkReg(False);
	rule getCmd;
		pcieWriteQ.deq;
		let w = pcieWriteQ.first;

		let d = w.data;
		let a = w.addr;
		let off = (a >> 2);

		if ( off == 5 ) begin // Mode 5: Generate a source routing packet
			/*// Information
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
		end else if ( off == 0 ) begin // Mode 0: Use only FPGA1
			if ( toMemPayloadCnt != 0 ) begin
				if ( toMemPayloadCnt == 16 ) begin
					Bit#(512) payload = toMemPayloadBuffer;
					toMemPayloadQ.enq(payload);

					toMemPayloadBuffer <= 0;	
					toMemPayloadCnt <= 0;

					if ( toMemPayloadQCnt == 16 ) begin // toMemPayloadQ.enq : toMemPayloadQ.deq = 1 : 16
						startMemWrite <= True;
						toMemPayloadQCnt <= 0;
					end else begin
						toMemPayloadQCnt <= toMemPayloadQCnt + 1;
					end
				end else begin
					Bit#(512) toMemPayloadBufferPrev = toMemPayloadBuffer;
					toMemPayloadBuffer <= (zeroExtend(d) << 32) | (toMemPayloadBufferPrev);
					toMemPayloadCnt <= toMemPayloadCnt + 1;
				end
			end else begin
				toMemPayloadBuffer <= zeroExtend(d);
				toMemPayloadCnt <= toMemPayloadCnt + 1;
			end
		end else begin // Mode 1~4: Use both FPGA1 and FPGA2 with up to 4 Aurora lanes
			/*// Send the value of the particles
			if ( inPayloadCnt != 0 ) begin
				if ( inPayloadCnt == 15 ) begin
					// Payload
					Bit#(480) data = inPayload;
					// Header Part
					Bit#(8) payloadByte = 60;
					Bit#(8) startPoint = fromInteger(idxFPGA1);
					Bit#(8) routeCnt = 0;
					Bit#(1) sdFlag = 1;
					Bit#(8) numHops = 0;
					Bit#(32) headerPartDS = (zeroExtend(payloadByte) << 24) | (zeroExtend(startPoint) << 16) | 
								(zeroExtend(routeCnt) << 9) | (zeroExtend(sdFlag) << 8) | 
								(zeroExtend(numHops));
					// Encryption
					// Payload
					Bit#(480) encData = data ^ fromInteger(pubKeyFPGA2);
					// Header Part
					Bit#(32) encHeaderPartDS = headerPartDS ^ fromInteger(pubKeyFPGA2);

					// Final
					AuroraIfcType dsPacket = (zeroExtend(encData) << 32) | (zeroExtend(encHeaderPartDS));
					sendPacketByAuroraFPGA1Q.enq(tuple2(dsPacket, off));			
					
					inPayload <= 0;	
					inPayloadCnt <= 0;
				end else begin
					Bit#(480) inPayloadPrev = inPayload;
					inPayload <= (zeroExtend(d) << 32) | (inPayloadPrev);
					inPayloadCnt <= inPayloadCnt + 1;
				end
			end else begin
				inPayload <= zeroExtend(d);
				inPayloadCnt <= inPayloadCnt + 1;
			end*/
		end
	endrule
	//--------------------------------------------------------------------------------------------
	// FPGA1(0) <-> (4)FPGA2
	// FPGA1(1) <-> (5)FPGA2
	// FPGA1(2) <-> (6)FPGA2
	// FPGA1(3) <-> (7)FPGA2
	//--------------------------------------------------------------------------------------------
	// FPGA1
	//--------------------------------------------------------------------------------------------
	// DRAM of FPGA1
	//--------------------------------------------------------------------------------------------
	FIFO#(Bit#(512)) toMemDataPmQ <- mkSizedBRAMFIFO(64);
	FIFO#(Bit#(512)) toMemDataVQ <- mkSizedBRAMFIFO(48);
	Reg#(Bit#(64)) memWriteResPmAdd <- mkReg(469762048);
	Reg#(Bit#(64)) memWriteResVAdd <- mkReg(738197504);
	Reg#(Bit#(32)) memWriteCntIni <- mkReg(0);
	Reg#(Bit#(8)) memWriteCntPm <- mkReg(0);
	Reg#(Bit#(8)) memWriteCntV <- mkReg(0);
	Reg#(Bool) initialSet <- mkReg(True);
	Reg#(Bool) writeResult <- mkReg(False);
	Reg#(Bool) pmPart <- mkReg(True);
	Reg#(Bool) vPart <- mkReg(False);
	rule fpga1MemWriter( startMemWrite );
		if ( initialSet ) begin
			if ( memWriteCntIni != 0 ) begin
				toMemPayloadQ.deq;
				let payload = toMemPayloadQ.first;
				dramArbiterRemote.users[0].write(payload);
				if ( memWriteCntIni == fromInteger(totalMemWorRWords) ) begin
					memWriteCntIni <= 0;
					initialSet <= False;
				end else begin
					memWriteCntIni <= memWriteCntIni + 1;
				end
			end else begin
				dramArbiterRemote.users[0].cmd(0, fromInteger(totalMemWorRWords), fromInteger(write), fromInteger(local));
				memWriteCntIni <= memWriteCntIni + 1;
			end
		end else if ( writeResult ) begin
			if ( pmPart ) begin
				if ( memWriteCntPm != 0 ) begin
					toMemDataPmQ.deq;
					let payload = toMemDataPmQ.first;
					dramArbiterRemote.users[0].write(payload);
					if ( memWriteCntPm == 64 ) begin
						memWriteResPmAdd <= memWriteResPmAdd + (256*4*4);
						memWriteCntPm <= 0;
						pmPart <= False;
						vPart <= True;
					end else begin
						memWriteCntPm <= memWriteCntPm + 1;
					end
				end else begin
					dramArbiterRemote.users[0].cmd(memWriteResPmAdd, 64, fromInteger(write), fromInteger(local));
					memWriteCntPm <= memWriteCntPm + 1;
				end
			end else if ( vPart ) begin
				if ( memWriteCntV != 0 ) begin
					toMemDataVQ.deq;
					let payload = toMemDataVQ.first;
					dramArbiterRemote.users[0].write(payload);
					if ( memWriteCntV == 48 ) begin
						memWriteResVAdd <= memWriteResVAdd + (256*3*4);
						memWriteCntV <= 0;
						pmPart <= True;
						vPart <= False;
					end else begin
						memWriteCntV <= memWriteCntV + 1;
					end
				end else begin
					dramArbiterRemote.users[0].cmd(memWriteResVAdd, 48, fromInteger(write), fromInteger(local));
					memWriteCntV <= memWriteCntV + 1;
				end
			end
		end
	endrule
	FIFO#(Bit#(512)) fromMemDataPmQ <- mkSizedBRAMFIFO(64);
	FIFO#(Bit#(512)) fromMemDataVQ <- mkSizedBRAMFIFO(48);
	Reg#(Bit#(64)) memReadPmAddress <- mkReg(0);
	Reg#(Bit#(64)) memReadVAddress <- mkReg(268435456);
	Reg#(Bit#(32)) memReadPmCnt1 <- mkReg(0);
	Reg#(Bit#(16)) memReadPmCnt2 <- mkReg(0);
	Reg#(Bit#(32)) memReadVCnt1 <- mkReg(0);
	Reg#(Bit#(8)) memReadVCnt2 <- mkReg(0);
	Reg#(Bool) memReadPm <- mkReg(True);
	Reg#(Bool) memReadV <- mkReg(False);
	rule fpga1MemReader;
		if ( memReadPm ) begin
			if ( memReadPmCnt1 != 0 ) begin
				let payload <- dramArbiterRemote.users[0].read;
				fromMemDataPmQ.enq(payload);
				if ( memReadPmCnt1 == fromInteger(pmMemWorRWords) ) begin
					if ( memReadPmCnt2 == 255 ) begin
						memReadPmCnt2 <= 0;
						memReadPm <= False;
						memReadV <= True;
					end else begin
						memReadPmCnt2 <= memReadPmCnt2 + 1;
					end
					memReadPmCnt1 <= 0;
				end else begin
					memReadPmCnt1 <= memReadPmCnt1 + 1;
				end
			end else begin
				dramArbiterRemote.users[0].cmd(memReadPmAddress, fromInteger(pmMemWorRWords), fromInteger(read), fromInteger(local));
				memReadPmCnt1 <= memReadPmCnt1 + 1;
			end
		end else if ( memReadV ) begin
			if ( memReadVCnt2 != 0 ) begin
				let payload <- dramArbiterRemote.users[0].read;
				fromMemDataVQ.enq(payload);
				if ( memReadVCnt2 == 48 ) begin
					if ( memReadVCnt1 == (fromInteger(vMemWorRWords) - 1)) begin
						memReadVAddress <= 268435456;
						memReadVCnt1 <= 0;
						memReadPm <= False;
					end else begin
						memReadVAddress <= memReadVAddress + (256*3*4);
						memReadVCnt1 <= memReadVCnt1 + 1;
						memReadPm <= True;
					end
					memReadVCnt2 <= 0;
					memReadV <= False;
				end else begin
					memReadVCnt1 <= memReadVCnt1 + 1;
					memReadVCnt2 <= memReadVCnt2 + 1;
				end
			end else begin
				dramArbiterRemote.users[0].cmd(memReadVAddress, 48, fromInteger(read), fromInteger(local));
				memReadVCnt2 <= memReadVCnt2 + 1;
			end
		end
	endrule
	FIFO#(Vector#(4, Bit#(32))) originDataPmQ <- mkSizedBRAMFIFO(64);
	FIFO#(Vector#(4, Bit#(32))) updatedDataPmQ <- mkSizedBRAMFIFO(256);
	Reg#(Bit#(512)) fromMemDataBufferPm <- mkReg(0);
	Reg#(Bit#(512)) tomemDataBufferPm <- mkReg(0);
	Reg#(Bit#(8)) originDataPmLeft <- mkReg(0);
	Reg#(Bit#(8)) updatedDataPmLeft <- mkReg(16);
	Reg#(Bit#(8)) updatedDataPmCnt <- mkReg(0);
	Reg#(Bool) toNbodyPm <- mkReg(True);
	Reg#(Bool) fromNbodyPm <- mkReg(False);
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
				fromMemDataBufferPm <= zeroExtend(d >> 128);
				originDataPmLeft <= (16 - 4);
			end else begin
				let d = fromMemDataBufferPm;
				pm[0] = d[31:0]; // Position X 
				pm[1] = d[63:32]; // Position Y
				pm[2] = d[95:64]; // Position Z
				pm[3] = d[127:96]; // Mass
				originDataPmQ.enq(pm);
				fromMemDataBufferPm <= zeroExtend(d >> 128);
				originDataPmLeft <= originDataPmLeft - 4;
			end
		end else if ( fromNbodyPm ) begin
			updatedDataPmQ.deq;
			Vector#(4, Bit#(32)) d = updatedDataPmQ.first;
			Bit#(512) currP = (zeroExtend(d[3])) | (zeroExtend(d[2])) | (zeroExtend(d[1])) | (zeroExtend(d[0]));

			if ( updatedDataPmLeft == 4 ) begin
				let prevP = toMemDataBufferPm;
				Bit#(512) finalP = (currP << (128*updatedDataPmCnt) | (prevP);
				updatedDataPmQ.enq(finalP);
				updatedDataPmLeft <= 16; 
				updatedDataPmStacked <= 0;
			end else begin
				if ( updatedDataPmLeft == 16 ) begin
					toMemDataBufferPm <= currP;
				end else begin
					let prevP = toMemDataBufferPm;
					Bit#(512) p = (currP << (128*updatedDataPmCnt)) | (prevP);
					toMemDataBufferPm <= p;
				end
				updatedDataPmLeft <= updatedDataPmLeft - 4;
				updatedDataPmCnt <= updatedDataPmCnt + 1;
			end
		end
	endrule
	FIFO#(Vector#(3, Bit#(32))) originDataVQ <- mkSizedBRAMFIFO(256);
	FIFO#(Vector#(3, Bit#(32))) updatedDataVQ <- mkSizedBRAMFIFO(256);
	Reg#(Maybe#(Bit#(512))) fromMemDataBufferV <- mkReg(tagged Invalid);
	Reg#(Bit#(512)) toMemDataBufferV <- mkReg(0);
	Reg#(Bit#(8)) originDataVLeft <- mkReg(0);
	Reg#(Bit#(8)) updatedDataVStacked <- mkReg(0);
	Reg#(Bool) toNbodyV <- mkReg(True);
	Reg#(Bool) fromNbodyV <- mkReg(False);
	rule fpga1DataOrganizerV;
		if ( toNbodyV ) begin
			Vector#(3, Bit#(32)) v = replicateM(0);
			if ( isValid(fromMemDataBufferV) ) begin
				if ( originDataVLeft < 3 ) begin
					fromMemDataVQ.deq;
					let currD = fromMemDataVQ.first;
					let prevD = fromMaybe(?, fromMemDataBufferV);
					Bit#(576) d = (zeroExtend(currD) << (originDataVLeft * 32)) | (prevD);
					v[0] = d[31:0]; // Velocity X
					v[1] = d[63:32]; // Velocity Y
					v[2] = d[95:64]; // Velocity Z
					originDataVQ.enq(v);
					fromMemDataBufferV <= tagged valid truncate(d >> 96);
					originDataVLeft <= originDataVLeft + 16 - 3;
				end else begin
					let d = fromMaybe(?, fromMemDataBufferV);
					v[0] = d[31:0]; // Velocity X
					v[1] = d[63:32]; // Velocity Y
					v[2] = d[95:64]; // Velocity Z
					originDataVQ.enq(v);
					fromMemDataBufferV <= tagged valid (d >> 96);
					originDataVLeft <= originDataVLeft - 3;
				end
			end else begin
				fromMemDataVQ.deq;
				let d = fromMemDataVQ.first;
				v[0] = d[31:0]; // Velocity X
				v[1] = d[63:32]; // Velocity Y
				v[2] = d[95:64]; //  Velocity Z
				originDataVQ.enq(v);
				fromMemDataBufferV <= tagged valid zeroExtend(d >> 96);
				originDataVLeft <= originDataVLeft - 3;
			end
		end else if ( fromNbodyV ) begin
			updatedDataVQ.deq;
			Vector#(3, Bit#(32)) d = updatedDataVQ.first;
			Bit#(576) currP = (zeroExtend(d[2])) | (zeroExtend(d[1])) | (zeroExtend(d[0]));

			if ( updatedDataVStacked > 12 ) begin
				let prevP = toMemDataBufferV;
				Bit#(576) totalP = (currP << (32*updatedDataVStacked)) | (prevP);
				updatedDataVQ.enq(truncate(totalP));
				updatedDataVStacked <= (3 - (16-updatedDataVStacked)); 
				toMemDataBufferV <= (totalP >> 512);
			end else begin
				if ( updatedDataVStacked == 0 ) begin
					toMemDataBufferV <= currP;
				end else begin
					let prevP = toMemDataBufferV;
					Bit#(576) p = (currP << (32*updatedDataVStacked)) | (prevP);
					toMemDataBufferV <= p;
				end
				updatedDataVStacked <= updatedDataVStacked + 3;
			end
		end
	endrule
	//--------------------------------------------------------------------------------------------
	// Calculation of N-body problem
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
	Reg#(Bool) recvDataPm <- mkReg(0);
	Reg#(Bool) recvDataV <- mkReg(0);
	rule fpga1RecvResult;
		if ( recvDataPm ) begin
			let d <- nbody.dataOutPm;

		end else if ( recvDataV ) begin
		end
	endrule
	//--------------------------------------------------------------------------------------------
	FIFOF#(AuroraIfcType) recvPacketByAuroraFPGA1Q <- mkFIFOF;
	FIFOF#(AuroraIfcType) validCheckConnectionFPGA1Q <- mkFIFOF;
	rule fpga1Sender_Port0( openConnect && sendPacketByAuroraFPGA1Q.notEmpty );
		sendPacketByAuroraFPGA1Q.deq;
		let sendPacket = tpl_1(sendPacketByAuroraFPGA1Q.first);

		for ( Integer i = 0; i < 4; i = i + 1 )
			auroraQuads[0].user[i].send(AuroraSend{packet:sendPacket,num:2});
	endrule
	rule fpga1Receiver_Port0( openConnect );
		Bit#(8) inPortFPGA1_1 = 0;
		Bit#(1) qidIn = inPortFPGA1_1[2];
		Bit#(2) pidIn = truncate(inPortFPGA1_1);

		let recvPacket <- auroraQuads[qidIn].user[pidIn].receive;
		recvPacketByAuroraFPGA1Q.enq(recvPacket);
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
	rule getAuroraStatus;
		pcieReadReqQ.deq;
		let r = pcieReadReqQ.first;
		Bit#(4) a = truncate(r.addr>>2);
		if ( a < 8 ) begin
			if ( validCheckConnectionQ.notEmpty ) begin
				pcieRespQ.enq(tuple2(r, validCheckConnectionQ.first));
				validCheckConnectionQ.deq;
			end else begin 
				pcieRespQ.enq(tuple2(r, 32'hffffffff));
			end
		end
	endrule
endmodule
