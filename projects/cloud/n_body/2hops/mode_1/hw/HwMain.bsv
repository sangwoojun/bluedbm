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


Integer byteTotal = 16*1024*1024*4;
Integer wordsTotal64Byte = 7*1024*1024;
Integer wordsPm64Byte = 4*1024*1024;
Integer wordsV64Byte = 3*1024*1024;


interface HwMainIfc;
endinterface
module mkHwMain#(PcieUserIfc pcie, DRAMUserIfc dram) (HwMainIfc);

	Clock curClk <- exposeCurrentClock;
	Reset curRst <- exposeCurrentReset;

	Clock pcieclk = pcie.user_clk;
	Reset pcierst = pcie.user_rst;	

	Reg#(Bit#(32)) cycleCount <- mkReg(0);
	Reg#(Bit#(32)) cycleStart <- mkReg(0);
	Reg#(Bit#(32)) cycleEnd <- mkReg(0);
	rule incCycleCount;
		cycleCount <= cycleCount + 1;
	endrule

	DeSerializerIfc#(32, 16) deserializer32b <- mkDeSerializer;
	DeSerializerIfc#(128, 4) deserializer128bPm <- mkDeSerializer;
	DeSerializerIfc#(128, 4) deserializer128bV <- mkDeSerializer;
	SerializerIfc#(512, 4) serializer128bPm <- mkSerializer;
	SerializerIfc#(512, 4) serializer128bV <- mkSerializer;

	DRAMArbiterRemoteIfc#(2) dramArbiterRemote <- mkDRAMArbiterRemote(dram);
	NbodyIfc nbody <- mkNbody;
	//--------------------------------------------------------------------------------------
	// Pcie Read and Write
	//--------------------------------------------------------------------------------------
	SyncFIFOIfc#(Tuple2#(IOReadReq, Bit#(32))) pcieRespQ <- mkSyncFIFOFromCC(64, pcieclk);
	SyncFIFOIfc#(IOReadReq) pcieReadReqQ <- mkSyncFIFOToCC(64, pcieclk, pcierst);
	SyncFIFOIfc#(IOWrite) pcieWriteQ <- mkSyncFIFOToCC(64, pcieclk, pcierst);	
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
	Reg#(Bool) fpga1MemReaderOn <- mkReg(False);
	Reg#(Bool) fpga1DataOrganizerOn <- mkReg(False);
	Reg#(Bool) fpga1RelayDataOn <- mkReg(False);
	Reg#(Bool) fpga1RecvRsltOn <- mkReg(False);
	rule getCmd;
		pcieWriteQ.deq;
		let w = pcieWriteQ.first;

		let d = w.data;
		let a = w.addr;
		let off = (a >> 2);

		if ( off == 0 ) begin // Initial Set
			deserializer32b.put(d);			
		end else if ( off == 1 ) begin
			fpga1MemReaderOn <= True;
			fpga1DataOrganizerOn <= True;
			fpga1RelayDataOn <= True;
			fpga1RecvRsltOn <= True;

			cycleStart <= cycleCount;
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
	// DRAM Writer
	//--------------------------------------------------------------------------------------------
	FIFOF#(Bit#(32)) cycleQ <- mkFIFOF;
	FIFOF#(Bit#(32)) validCheckerQ <- mkFIFOF;

	Reg#(Bit#(32)) memWrCntIni <- mkReg(0);

	Reg#(Bool) fpga1MemWrInit <- mkReg(True);
	Reg#(Bool) fpga1MemWrRslt <- mkReg(False);

	Reg#(Bool) toNbodyPm <- mkReg(True);
	Reg#(Bool) fromNbodyPm <- mkReg(False);

	Reg#(Bool) toNbodyV <- mkReg(True);
	Reg#(Bool) fromNbodyV <- mkReg(False);
	rule fpga1MemWriterInit( fpga1MemWrInit );
		if ( memWrCntIni != 0 ) begin
			let payload <- deserializer32b.get;
			dramArbiterRemote.access[0].users[0].write(payload);
			if ( memWrCntIni == fromInteger(wordsTotal64Byte) ) begin
				memWrCntIni <= 0;

				fpga1MemWrInit <= False;
				fpga1MemWrRslt <= True;

				validCheckerQ.enq(1); // Check dram writer initial set done
			end else begin
				memWrCntIni <= memWrCntIni + 1;
			end
		end else begin
			dramArbiterRemote.access[0].users[0].cmd(0, fromInteger(wordsTotal64Byte), True);
			memWrCntIni <= memWrCntIni + 1;
		end
	endrule

	Reg#(Bit#(64)) memWrRsltAddPm <- mkReg(469762048);
	Reg#(Bit#(64)) memWrRsltAddV <- mkReg(738197504);
	Reg#(Bit#(8)) memWrRsltCntPm <- mkReg(0);
	Reg#(Bit#(8)) memWrRsltCntV <- mkReg(0);	
	Reg#(Bool) memWrPm <- mkReg(True);
	Reg#(Bool) memWrV <- mkReg(False);
	rule fpga1MemWriterRslt( fpga1MemWrRslt );
		if ( memWrPm ) begin
			if ( memWrRsltCntPm != 0 ) begin
				let payload <- deserializer128bPm.get;
				dramArbiterRemote.access[0].users[0].write(payload);
				if ( memWrRsltCntPm == 64 ) begin
					if ( (memWrRsltAddPm + (256*4*4)) == 738197504 ) begin
						memWrRsltAddPm <= 469762048;
					end else begin
						memWrRsltAddPm <= memWrRsltAddPm + (256*4*4);
					end
					memWrRsltCntPm <= 0;
					
					memWrPm <= False;
					memWrV <= True;
					
					toNbodyPm <= True;
					fromNbodyPm <= False;
				end else begin
					memWrRsltCntPm <= memWrRsltCntPm + 1;
				end
			end else begin
				dramArbiterRemote.access[0].users[0].cmd(memWrRsltAddPm, 64, True);
				memWrRsltCntPm <= memWrRsltCntPm + 1;
			end
		end else if ( memWrV ) begin
			if ( memWrRsltCntV != 0 ) begin
				let payload <- deserializer128bV.get;
				dramArbiterRemote.access[0].users[0].write(payload);
				if ( memWrRsltCntV == 48 ) begin
					if ( (memWrRsltAddV + (256*3*4)) == 939524096 ) begin
						memWrRsltAddV <= 738197504;
						
						fpga1MemWrInit <= True;
						fpga1MemWrRslt <= False;

						cycleEnd <= cycleCount;
						Bit#(32) cycleRslt = cycleEnd - cycleStart;
						cycleQ.enq(cycleRslt);
					end else begin
						memWrRsltAddV <= memWrRsltAddV + (256*3*4);				
					end
					memWrRsltCntV <= 0;
					
					memWrPm <= True;
					memWrV <= False;
					
					toNbodyV <= True;
					fromNbodyV <= False;

					validCheckerQ.enq(1); // Write 256 updated particel values done
				end else begin
					memWrRsltCntV <= memWrRsltCntV + 1;
				end
			end else begin
				dramArbiterRemote.access[0].users[0].cmd(memWrRsltAddV, 48, True);
				memWrRsltCntV <= memWrRsltCntV + 1;
			end
		end
	endrule
	//--------------------------------------------------------------------------------------------
	// DRAM Reader
	//--------------------------------------------------------------------------------------------
	Reg#(Bit#(64)) memRdAddPm <- mkReg(0);
	Reg#(Bit#(64)) memRdAddV <- mkReg(268435456);

	Reg#(Bit#(32)) memRdPmCnt_1 <- mkReg(0);
	Reg#(Bit#(16)) memRdPmCnt_2 <- mkReg(0);
	
	Reg#(Bit#(8)) memRdVCnt_1 <- mkReg(0);
	Reg#(Bit#(32)) memRdVCnt_2 <- mkReg(0);
	
	Reg#(Bool) memRdPm <- mkReg(True);
	Reg#(Bool) memRdV <- mkReg(False);
	rule fpga1MemReader( fpga1MemReaderOn );
		if ( memRdPm ) begin
			if ( memRdPmCnt_1 != 0 ) begin
				let payload <- dramArbiterRemote.access[0].users[0].read;
				serializer128bPm.put(payload);
				if ( memRdPmCnt_1 == fromInteger(wordsPm64Byte) ) begin
					if ( memRdPmCnt_2 == 255 ) begin
						memRdPmCnt_2 <= 0;

						memRdPm <= False;
						memRdV <= True;
					end else begin
						memRdPmCnt_2 <= memRdPmCnt_2 + 1;
					end
					memRdPmCnt_1 <= 0;
				end else begin
					memRdPmCnt_1 <= memRdPmCnt_1 + 1;
				end
			end else begin
				dramArbiterRemote.access[0].users[0].cmd(memRdAddPm, fromInteger(wordsPm64Byte), False);
				memRdPmCnt_1 <= memRdPmCnt_1 + 1;
			end
		end else if ( memRdV ) begin
			if ( memRdVCnt_1 != 0 ) begin
				let payload <- dramArbiterRemote.access[0].users[0].read;
				serializer128bV.put(payload);
				if ( memRdVCnt_1 == 48 ) begin
					if ( memRdVCnt_2 == (fromInteger(wordsV64Byte) - 1) ) begin
						memRdAddV <= 268435456;
						memRdVCnt_2 <= 0;
					end else begin
						memRdAddV <= memRdAddV + (256*3*4);
						memRdVCnt_2 <= memRdVCnt_2 + 1;
					end
					memRdVCnt_1 <= 0;

					memRdPm <= True;
					memRdV <= False;
				end else begin
					memRdVCnt_2 <= memRdVCnt_2 + 1;
					memRdVCnt_1 <= memRdVCnt_1 + 1;
				end
			end else begin
				dramArbiterRemote.access[0].users[0].cmd(memRdAddV, 48, False);
				memRdVCnt_1 <= memRdVCnt_1 + 1;
			end
		end
	endrule
	//-------------------------------------------------------------------------------------------------
	// FPGA1 (Data Organizer) Split the 512-bit payload to 32-bit data or Merge the datas to a payload
	//-------------------------------------------------------------------------------------------------
	FIFO#(Vector#(4, Bit#(32))) originDataPmQ <- mkSizedBRAMFIFO(256);
	FIFO#(Vector#(4, Bit#(32))) updatedDataPmQ <- mkSizedBRAMFIFO(256);
	rule fpga1DataOrganizerPm( fpga1DataOrganizerOn );
		if ( toNbodyPm ) begin
			Vector#(4, Bit#(32)) pm = replicate(0);
			let d <- serializer128bPm.get;
			
			pm[0] = d[31:0]; // Position X 
			pm[1] = d[63:32]; // Position Y
			pm[2] = d[95:64]; // Position Z
			pm[3] = d[127:96]; // Mass
			
			originDataPmQ.enq(pm);

		end else if ( fromNbodyPm ) begin
			updatedDataPmQ.deq;
			Vector#(4, Bit#(32)) v = updatedDataPmQ.first;
			Bit#(128) d = (zeroExtend(v[3])) | (zeroExtend(v[2])) | (zeroExtend(v[1])) | (zeroExtend(v[0]));
			
			deserializer128bPm.put(d);
		end
	endrule
	
	FIFO#(Vector#(3, Bit#(32))) originDataVQ <- mkSizedBRAMFIFO(256);
	FIFO#(Vector#(3, Bit#(32))) updatedDataVQ <- mkSizedBRAMFIFO(256);
	Reg#(Bit#(96)) toNbodyVBuffer <- mkReg(0);
	Reg#(Bit#(96)) fromNbodyVBuffer <- mkReg(0);
	Reg#(Bit#(4)) toNbodyVCnt <- mkReg(0);
	Reg#(Bit#(4)) fromNbodyVCnt <- mkReg(0);
	rule fpga1DataOrganizerV( fpga1DataOrganizerOn );
		if ( toNbodyV ) begin
			Vector#(3, Bit#(32)) v = replicate(0);
			if ( toNbodyVCnt == 0 ) begin
				let d <- serializer128bV.get;
				v[0] = d[31:0]; // Velocity X
				v[1] = d[63:32]; // Velocity Y
				v[2] = d[95:64]; //  Velocity Z
				toNbodyVBuffer <= zeroExtend(d[127:96]);	
				toNbodyVCnt <= toNbodyVCnt + 1;			
			end else if ( toNbodyVCnt == 1 ) begin
				let d <- serializer128bV.get;
				Bit#(32) b = truncate(toNbodyVBuffer);
				v[0] = b;
				v[1] = d[31:0];
				v[2] = d[63:32];
				toNbodyVBuffer <= zeroExtend(d[127:64]);
				toNbodyVCnt <= toNbodyVCnt + 1;
			end else if ( toNbodyVCnt == 2 ) begin
				let d <- serializer128bV.get;
				Bit#(64) b = truncate(toNbodyVBuffer);
				v[0] = b[31:0];
				v[1] = b[63:32];
				v[2] = d[31:0];
				toNbodyVBuffer <= d[127:32];
				toNbodyVCnt <= toNbodyVCnt + 1;
			end else if ( toNbodyVCnt == 3 ) begin
				let b = toNbodyVBuffer;
				v[0] = b[31:0];
				v[1] = b[63:32];
				v[2] = b[95:64];
				toNbodyVBuffer <= 0;
				toNbodyVCnt <= 0;
			end
			originDataVQ.enq(v);
		end else if ( fromNbodyV ) begin
			updatedDataVQ.deq;
			let v = updatedDataVQ.first;
			Bit#(96) d = (zeroExtend(v[2])) | (zeroExtend(v[1])) | (zeroExtend(v[0]));

			if ( fromNbodyVCnt == 0 ) begin
				fromNbodyVBuffer <= d;
				fromNbodyVCnt <= fromNbodyVCnt + 1;
			end else if ( fromNbodyVCnt == 1 ) begin
				Bit#(128) b = zeroExtend(fromNbodyVBuffer);
				Bit#(128) d_0 = zeroExtend(d[31:0]);
				Bit#(128) p = (d_0 << 96) | (b);
				deserializer128bV.put(p);
				fromNbodyVBuffer <= (d >> 32);
				fromNbodyVCnt <= fromNbodyVCnt + 1;
			end else if ( fromNbodyVCnt == 2 ) begin
				Bit#(128) b = zeroExtend(fromNbodyVBuffer);
				Bit#(128) d_01 = zeroExtend(d[63:0]);
				Bit#(128) p = (d_01 << 64) | (b);
				deserializer128bV.put(p);
				fromNbodyVBuffer <= (d >> 64);
				fromNbodyVCnt <= fromNbodyVCnt + 1;
			end else if ( fromNbodyVCnt == 3 ) begin
				Bit#(128) b = zeroExtend(fromNbodyVBuffer);
				Bit#(128) d_012 = zeroExtend(d);
				Bit#(128) p = (d_012 << 32) | (b);
				deserializer128bV.put(p);
				fromNbodyVBuffer <= 0;
				fromNbodyVCnt <= 0;
			end
		end
	endrule
	//--------------------------------------------------------------------------------------------
	// FPGA1 (A Part of Computing N-body problem)
	//--------------------------------------------------------------------------------------------
	// Relay Data to Nbody
	//--------------------------------------------------------------------------------------------
	Reg#(Bit#(32)) relayDataPmCnt_1 <- mkReg(0);
	Reg#(Bit#(16)) relayDataPmCnt_2 <- mkReg(0);
	Reg#(Bit#(16)) relayDataVCnt_1 <- mkReg(0);
	Reg#(Bit#(32)) relayDataVCnt_2 <- mkReg(0);
	Reg#(Bool) relayDataPm <- mkReg(True);
	Reg#(Bool) relayDataV <- mkReg(False);
	rule fpga1RelayData( fpga1RelayDataOn );
		if ( relayDataPm ) begin
			originDataPmQ.deq;
			let p = originDataPmQ.first;
	
			nbody.dataPmIn(p, relayDataPmCnt_1);	

			if ( relayDataPmCnt_1 == (fromInteger(totalParticles) - 1) ) begin
				if ( relayDataPmCnt_2 == 255 ) begin
					relayDataPmCnt_2 <= 0;

					relayDataPm <= False;
					relayDataV <= True;
				end else begin
					relayDataPmCnt_2 <= relayDataPmCnt_2 + 1;
				end
				relayDataPmCnt_1 <= 0;
			end else begin
				relayDataPmCnt_1 <= relayDataPmCnt_1 + 1;
			end
		end else if ( relayDataV ) begin
			originDataVQ.deq;
			let p = originDataVQ.first;

			nbody.dataVIn(p);
			
			if ( relayDataVCnt_1 == 255 ) begin
				if ( relayDataVCnt_2 == (fromInteger(totalParticles) - 1) ) begin
					relayDataVCnt_2 <= 0;
				end else begin
					relayDataVCnt_2 <= relayDataVCnt_2 + 1;
				end
				relayDataVCnt_1 <= 0;

				relayDataPm <= True;
				relayDataV <= False;
			end else begin
				relayDataVCnt_1 <= relayDataVCnt_1 + 1;
				relayDataVCnt_2 <= relayDataVCnt_2 + 1;
			end
		end
	endrule
	//--------------------------------------------------------------------------------------------
	// Receive results from Nbody
	//--------------------------------------------------------------------------------------------
	Reg#(Bit#(8)) recvDataPmCnt <- mkReg(0);
	Reg#(Bit#(8)) recvDataVCnt <- mkReg(0);
	Reg#(Bool) recvDataPm <- mkReg(True);
	Reg#(Bool) recvDataV <- mkReg(False);
	rule fpga1RecvResult( fpga1RecvRsltOn );
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
			let d <- nbody.dataOutV;
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
		if ( a < 2 ) begin
			if ( validCheckerQ.notEmpty ) begin
				pcieRespQ.enq(tuple2(r, validCheckerQ.first));
				validCheckerQ.deq;
			end else begin 
				pcieRespQ.enq(tuple2(r, 32'hffffffff));
			end
		end else begin
			if ( cycleQ.notEmpty ) begin
				pcieRespQ.enq(tuple2(r, cycleQ.first));
				cycleQ.deq;
			end else begin 
				pcieRespQ.enq(tuple2(r, 32'hffffffff));
			end
		end
	endrule
endmodule
