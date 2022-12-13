import FIFO::*;
import FIFOF::*;
import Clocks::*;
import Vector::*;

import FloatingPoint::*;
import Float32::*;
import Float64::*;

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

interface HwMainIfc;
endinterface

Integer idxFPGA1 = 0;
Integer idxFPGA2 = 1;

Integer pubKeyFPGA1 = 1;
Integer pubKeyFPGA2 = 2;

Integer totalParticles = 16*1024*1024;
Integer totalMemWorRWords = 7*1024*1024;
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

	FpPairIfc#(32) fpSub32 <- mkFpSub32;
	FpPairIfc#(32) fpAdd32 <- mkFpAdd32;
	FpPairIfc#(32) fpMult32 <- mkFpMult32;
	FpPairIfc#(32) fpDiv32 <- mkFpDiv32;
	FpPairIfc#(32) fpSqrt32 <- mkFpSqrt32;

	DRAMArbiterRemoteIfc#(4) dramArbiterRemote <- mkDRAMArbiterRemote;
	
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
	Reg#(Bit#(12)) toMemPayloadQCnt <- mkReg(0);
	Reg#(Bit#(5)) toMemPayloadCnt <- mkReg(0);
	
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
	Reg#(Bit#(24)) memWriteCnt <- mkReg(0);
	rule fpga1MemWriter( startMemWrite );
		if ( memWriteCnt != 0 ) begin
			toMemPayloadQ.deq;
			let payload = toMemPayloadQ.first;
			dramArbiterRemote.users[0].write(payload);
			if ( memWriteCnt == fromInteger(totalMemWorRWords) ) begin
				memWriteCnt <= 0;
			end else begin
				memWriteCnt <= memWriteCnt + 1;
			end
		end else begin
			dramArbiterRemote.users[0].cmd(0, fromInteger(totalMemWorRWords), fromInteger(write), fromInteger(local));
			memWriteCnt <= memWriteCnt + 1;
		end
	endrule
	FIFO#(Bit#(512)) fromMemPayloadQ <- mkSizedBRAMFIFO(64);
	Reg#(Bit#(24)) memReadCnt <- mkReg(0);
	Reg#(Bool) stopMemRead <- mkReg(True);
	rule fpga1MemReader( stopMemRead );
		if ( memReadCnt != 0 ) begin
			let payload <- dramArbiterRemote.users[0].read;
			fromMemPayloadQ.enq(payload);
			if ( memReadCnt == fromInteger(totalMemWorRWords) ) begin
				memReadCnt <= 0;
			end else begin
				memReadCnt <= memReadCnt + 1;
			end
		end else begin
			dramArbiterRemote.users[0].cmd(0, fromInteger(totalMemWorRWords), fromInteger(read), fromInteger(local));
			memReadCnt <= memReadCnt + 1;
		end
	endrule
	FIFO#(Vector#(4, Bit#(32))) originDataPMQ <- mkSizedBRAMFIFO(512);
	FIFO#(Vector#(3, Bit#(32))) originDataVQ <- mkSizedBRAMFIFO(512);
	Reg#(Maybe#(Bit#(512))) fromMemPayloadBufferV <- mkReg(tagged Invalid);
	Reg#(Bit#(512)) fromMemPayloadBufferPM <- mkReg(0);
	Reg#(Bit#(24)) dataPMCnt <- mkReg(0);
	Reg#(Bit#(24)) dataVCnt <- mkReg(0);
	Reg#(Bit#(4)) originDataPMLeft <- mkReg(0);
	Reg#(Bit#(4)) originDataVLeft <- mkReg(0);
	Reg#(Bool) dataPM <- mkReg(True);
	Reg#(Bool) dataV <- mkReg(False);
	rule fpga1DataOrganizer;
		Vector#(4, Bit#(32)) pm = replicateM(0);
		Vector#(3, Bit#(32)) v = replicateM(0);
		if ( dataPM ) begin
			if ( originDataPMLeft < 4 ) begin
				fromMemPayloadQ.deq;
				let d = fromMemPayloadQ.first;
				pm[0] = d[31:0]; // Position X 
				pm[1] = d[63:32]; // Position Y
				pm[2] = d[95:64]; // Position Z
				pm[3] = d[127:96]; // Mass
				originDataPMQ.enq(pm);
				fromMemPayloadBufferPM <= zeroExtend(d >> 128);
				originDataPMLeft <= (16 - 4);
				dataPMCnt <= dataPMCnt + 1;
			end else begin
				let d = fromMemPayloadBuffer;
				pm[0] = d[31:0]; // Position X 
				pm[1] = d[63:32]; // Position Y
				pm[2] = d[95:64]; // Position Z
				pm[3] = d[127:96]; // Mass
				originDataPMQ.enq(pm);
				fromMemPayloadBufferPM <= zeroExtend(d >> 128);
				originDataPMLeft <= originDataPMLeft - 4;
				if ( dataPMCnt == (fromInteger(totalParticles) - 1) ) begin
					dataPMCnt <= 0;
					dataPM <= False;
					dataV <= True;
				end else begin
					dataPMCnt <= dataPMCnt + 1;
				end
			end
		end else if ( dataV ) begin
			if ( isValid(fromMemPayloadBufferV) ) begin
				if ( originDataVLeft < 3 ) begin
					fromMemPayloadQ.deq;
					let currD = fromMemPayloadQ.first;
					let prevD = fromMaybe(?, fromMemPayloadBufferV);
					Bit#(640) d = (zeroExtend(currD) << (originDataVLeft * 32)) | (prevD);
					v[0] = d[31:0]; // Velocity X
					v[1] = d[63:32]; // Velocity Y
					v[2] = d[95:64]; // Velocity Z
					originDataVQ.enq(v);
					fromMemPayloadBufferV <= tagged valid (d >> 96);
					originDataVLeft <= originDataVLeft + 16 - 3;
					dataVCnt <= dataVCnt + 1;
				end else begin
					let d = fromMaybe(?, fromMemPayloadBufferV);
					v[0] = d[31:0]; // Velocity X
					v[1] = d[63:32]; // Velocity Y
					v[2] = d[95:64]; // Velocity Z
					originDataVQ.enq(v);
					fromMemPayloadBufferV <= tagged valid (d >> 96);
					originDataVLeft <= originDataVLeft - 3;
					if ( dataVCnt == (fromInteger(totalParticles) - 1) ) begin
						dataVCnt <= 0;
						dataPM <= True;
						dataV <= False;
					end else begin
						dataVCnt <= dataVCnt + 1;
					end
				end
				let d = fromMaybe(?, fromMemPayloadBufferV);

			end else begin
				fromMemPayloadQ.deq;
				let d = fromMemPayloadQ.first;
				v[0] = d[31:0]; // Velocity X
				v[1] = d[63:32]; // Velocity Y
				v[2] = d[95:64]; //  Velocity Z
				originDataVQ.enq(v);
				fromMemPayloadBufferV <= tagged valid zeroExtend(d >> 96);
				originDataVLeft <= originDataVLeft - 3;
				dataVCnt <= dataVCnt + 1;
			end
		end
	endrule
	//--------------------------------------------------------------------------------------------
	// Calculation of N-body problem
	//--------------------------------------------------------------------------------------------
	Reg#(Bool) relayPayloadPM <- mkReg(True);
	Reg#(Bool) relayPayloadV <- mkReg(False);
	rule fpga1Nbody;
		if ( relayPayloadPM ) begin
			originDataPMQ.deq;
			let p = originDataPMQ.first;
			...
			if ( relayPayloadCnt == (fromInteger(totalParticles) - 1) ) begin
				relayPayloadPM <= False;
				relayPayloadV <= True;
				relayPayloadCnt <= 0;
			end else begin
				relayPayloadCnt <= relayPayloadCnt + 1;
			end
		end else if (relayPayloadV) begin
			originDataVQ.deq;
			let p = originDataVQ.first;
			...
			if ( relayPayloadCnt == (fromInteger(totalParticles) - 1) ) begin
				relayPayloadPM <= True;
				relayPayloadV <= False;
				relayPayloadCnt <= 0;
			end else begin
				relayPayloadCnt <= relayPayloadCnt + 1;
			end
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
