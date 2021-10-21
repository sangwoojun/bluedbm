/***********************************
NOTE: txdiffctrl_in in
./aurora_64b66b_X1Y2?/example_design/gt/aurora_64b66b_X1Y2?_wrapper.v
was changed to 1100 for higher voltage
***********************************/

package AuroraExtImportCommon;

import FIFO::*;
import Vector::*;
import BRAMFIFO::*;

import Clocks :: *;
import ClockImport :: *;
import DefaultValue :: *;

import AuroraCommon::*;
import GetPut::*;


import "BDPI" function Bool bdpiSendAvailable(Bit#(8) nidx, Bit#(8) pidx);
import "BDPI" function Bool bdpiRecvAvailable(Bit#(8) nidx, Bit#(8) pidx);
import "BDPI" function Bit#(64) bdpiRead(Bit#(8) nidx, Bit#(8) pidx);
import "BDPI" function Bool bdpiWrite(Bit#(8) nidx, Bit#(8) pidx, Bit#(64) data);


typedef 4 AuroraExtPerQuad;

typedef 64 AuroraPhysWidth;
typedef TSub#(AuroraPhysWidth, 1) AuroraFCWidth;
typedef Bit#(AuroraFCWidth) AuroraFC;


// 
typedef 5 HeaderFieldSz;
typedef Bit#(HeaderFieldSz) HeaderField;
typedef TMul#(HeaderFieldSz, 3) HeaderSz; // src, dst, ptype
typedef TMul#(AuroraFCWidth, 3) PacketSz; // 128 might be a bit suboptimal...
typedef TSub#(PacketSz, HeaderSz) PayloadSz;
typedef Bit#(PayloadSz) Payload;

typedef struct {
	HeaderField src;
	HeaderField dst;
	HeaderField ptype;
//	HeaderField bytes; // TODO so that less flits can be used if payload is smaller
	Payload payload;
} AuroraPacket deriving (Bits,Eq);


interface AuroraExtIfc;
	interface Vector#(AuroraExtPerQuad, Aurora_Pins#(1)) aurora;
	interface Vector#(AuroraExtPerQuad, AuroraExtUserIfc) user;
	method Action setNodeIdx(HeaderField idx); 
endinterface

interface AuroraExtUserIfc;
	method Action send(AuroraPacket data);
	method ActionValue#(AuroraPacket) receive;
   	// method Action send(AuroraIfcType data);
	// method ActionValue#(AuroraIfcType) receive;

	method Bit#(1) lane_up;
	method Bit#(1) channel_up;
	//interface Clock clk;
	//interface Reset rst;
endinterface


module mkAuroraExtFlowControl#(AuroraControllerIfc#(AuroraPhysWidth) user, Clock uclk, Reset urst, Integer idx) (AuroraExtUserIfc);
	Integer recvQDepth = 200;
	Integer windowSize = 100;

	FIFO#(AuroraFC) recvQ <- mkSizedBRAMFIFO(recvQDepth);

	SyncFIFOIfc#(AuroraPacket) outPacketQ <- mkSyncFIFOToCC(8, uclk, urst);
	SyncFIFOIfc#(AuroraPacket) inPacketQ <- mkSyncFIFOFromCC(8, uclk);


	Reg#(Bit#(16)) maxInFlightUp <- mkReg(0);
	Reg#(Bit#(16)) maxInFlightDown <- mkReg(0);
	Reg#(Bit#(16)) curInQUp <- mkReg(0);
	Reg#(Bit#(16)) curInQDown <- mkReg(0);
	Reg#(Bit#(16)) curSendBudgetUp <- mkReg(0);
	Reg#(Bit#(16)) curSendBudgetDown <- mkReg(0);

	FIFO#(AuroraFC) sendQ <- mkSizedFIFO(32);

	rule sendPacket;
		let curSendBudget = curSendBudgetUp - curSendBudgetDown;
		if ((maxInFlightUp-maxInFlightDown)
			+(curInQUp-curInQDown)
			+fromInteger(windowSize) < fromInteger(recvQDepth)) begin
		
			//flowControlQ.enq(fromInteger(windowSize));
			user.send({fromInteger(windowSize),1'b1});
			maxInFlightUp <= maxInFlightUp + fromInteger(windowSize);
		end else if ( curSendBudget > 0 ) begin
			sendQ.deq;
			user.send({sendQ.first, 1'b0});
			curSendBudgetDown <= curSendBudgetDown + 1;
		end
	endrule

	rule recvPacket;
		let d <- user.receive;
	   //$display( "(%t) %m, AuroraExtFlowControl idx = %d, received %x", $time, idx, d );
		Bit#(1) control = d[0];
		AuroraFC data = truncate(d>>1);

		if ( control == 1 ) begin
			curSendBudgetUp <= curSendBudgetUp + truncate(data);
		end else begin
			recvQ.enq(data);
			curInQUp <= curInQUp + 1;
			maxInFlightDown <= maxInFlightDown + 1;
		end
	endrule

	// Flow control end
	//////////////////////////////////////////////////// TODO maybe separate gearbox into separate module?
	// Gearbox start

	Integer headInternalOffset = valueOf(AuroraFCWidth) - valueOf(HeaderSz);

	Reg#(Bit#(2)) outPacketOffset <- mkReg(0);
	Reg#(Bit#(2)) inPacketOffset <- mkReg(0);
	Vector#(3, Reg#(AuroraFC)) vOutFlits <- replicateM(mkReg(0)); 
	Reg#(AuroraPacket) inPacketBuffer <- mkReg(?);

	rule serOutPacket;
		if ( outPacketOffset == 0 ) begin
			outPacketQ.deq;
			let d = outPacketQ.first;
			AuroraFC d1 = {truncate(d.payload), d.ptype, d.dst, d.src};
			AuroraFC d2 = truncate(d.payload>>headInternalOffset);
			AuroraFC d3 = truncate(d.payload>>(headInternalOffset+valueOf(AuroraFCWidth)));
			vOutFlits[0] <= d1; vOutFlits[1] <= d2; vOutFlits[2] <= d3;
			sendQ.enq(d1);
			outPacketOffset <= 1;
		end
		else if ( outPacketOffset == 1 ) begin
			sendQ.enq(vOutFlits[1]);
			outPacketOffset <= 2;
		end else begin
			sendQ.enq(vOutFlits[2]);
			outPacketOffset <= 0;
		end
	endrule

	rule desInPacket;
		curInQDown <= curInQDown + 1;
		recvQ.deq;

		let d = recvQ.first;
		if ( inPacketOffset == 0 ) begin
			inPacketOffset <= 1;
			HeaderField src = truncate(d);
			HeaderField dst = truncate(d>>valueOf(HeaderFieldSz));
			HeaderField ptype = truncate(d>>(valueOf(HeaderFieldSz)*2));
			Bit#(TSub#(AuroraFCWidth, HeaderSz)) payload = truncate(d>>(valueOf(HeaderFieldSz)*3));
			inPacketBuffer <= AuroraPacket{src: src, dst:dst, ptype:ptype, payload: zeroExtend(payload)};
		end else if ( inPacketOffset == 1 ) begin
			inPacketOffset <= 2;
			Payload t = inPacketBuffer.payload | (zeroExtend(d) <<headInternalOffset);
			inPacketBuffer <= AuroraPacket{src: inPacketBuffer.src, dst:inPacketBuffer.dst, ptype:inPacketBuffer.ptype, payload: t};
		end else begin
			inPacketOffset <= 0;
			Payload t = inPacketBuffer.payload | (zeroExtend(d) <<(headInternalOffset+valueOf(AuroraFCWidth)));
			inPacketQ.enq(AuroraPacket{src: inPacketBuffer.src, dst:inPacketBuffer.dst, ptype:inPacketBuffer.ptype, payload: t});
		end
	endrule
	
	method Action send(AuroraPacket data);
		outPacketQ.enq(data);
	endmethod
	method ActionValue#(AuroraPacket) receive;
		inPacketQ.deq;
		return inPacketQ.first;
	endmethod
	method Bit#(1) channel_up = user.channel_up;
	method Bit#(1) lane_up = user.lane_up;
endmodule

 
module mkAuroraExtImport_bsim#(Clock gtx_clk_in, Clock init_clk, Reset init_rst_n, Reset gt_rst_n) (AuroraExtImportIfc#(AuroraExtPerQuad));
   Clock clk <- exposeCurrentClock;
   Reset rst <- exposeCurrentReset;

	Reg#(Bit#(8)) nodeIdx <- mkReg(255);
	
   Vector#(4, FIFO#(Bit#(AuroraPhysWidth))) writeQ <- replicateM(mkFIFO);
   Vector#(4, FIFO#(Bit#(AuroraPhysWidth))) mirrorQ <- replicateM(mkFIFO);

   for (Integer i = 0; i < 4; i = i + 1) begin
	rule m0 if ( bdpiRecvAvailable(nodeIdx, fromInteger(i) ));
		let d = bdpiRead(nodeIdx, fromInteger(i));
		mirrorQ[i].enq(d);
	   //$display( "(%t) AuroraExtImport \t\tread %x %d", $time, d, i );
	endrule
	rule w0 if ( bdpiSendAvailable(nodeIdx, fromInteger(i)));
		let d = writeQ[i].first;
		if ( bdpiWrite(nodeIdx, fromInteger(i), d) ) begin
		   //$display( "(%t) AuroraExtImport \t\twrite %x %d", $time, d, i );
			writeQ[i].deq;
		end
	endrule
   end
	
   function AuroraControllerIfc#(AuroraPhysWidth) auroraController(Integer i);
      return (interface AuroraControllerIfc;
		 interface Reset aurora_rst_n = rst;

		 method Bit#(1) channel_up;
		    return 1;
		 endmethod
		 method Bit#(1) lane_up;
		    return 1;
		 endmethod
		 method Bit#(1) hard_err;
		    return 0;
		 endmethod
		 method Bit#(1) soft_err;
		    return 0;
		 endmethod
		 method Bit#(8) data_err_count;
		    return 0;
		 endmethod

		 method Action send(Bit#(64) data);// if ( bdpiSendAvailable(nodeIdx, 0) );
		    //$display("aurora.send port %d data %h", i, data);
		    writeQ[i].enq(data);
		 endmethod
		 method ActionValue#(Bit#(64)) receive;
		    let data = mirrorQ[i].first;
		    mirrorQ[i].deq;
		    //$display("aurora.receive port %d data %h", i, data);
		    return data;
		 endmethod
	 endinterface);
   endfunction

	interface Clock aurora_clk0 = clk;
	interface Clock aurora_clk1 = clk;
	interface Clock aurora_clk2 = clk;
	interface Clock aurora_clk3 = clk;

	interface Reset aurora_rst0 = rst;
	interface Reset aurora_rst1 = rst;
	interface Reset aurora_rst2 = rst;
	interface Reset aurora_rst3 = rst;
	
	
	interface AuroraControllerIfc user0 = auroraController(0);
	interface AuroraControllerIfc user1 = auroraController(1);
	interface AuroraControllerIfc user2 = auroraController(2);
	interface AuroraControllerIfc user3 = auroraController(3);
	method Action setNodeIdx(Bit#(8) idx);
	   $display( "aurora node idx set to %d", idx);
		nodeIdx <= idx;
	endmethod

endmodule
endpackage: AuroraExtImportCommon
