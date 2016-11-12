/***********************************
NOTE: txdiffctrl_in in
./aurora_64b66b_X1Y2?/example_design/gt/aurora_64b66b_X1Y2?_wrapper.v
was changed to 1100 for higher voltage
***********************************/

package AuroraExtImport;

/*
export AuroraPacket, HeaderField, Payload, HeaderFieldSz, PayloadSz, HeaderSz, PacketSz;
export AuroraFCWidth, AuroraFC, AuroraPhysWidth;

export AuroraExtPerQuad;

export AuroraExtUserIfc;
export AuroraExtIfc(..);
export mkAuroraExt;
*/

import FIFO::*;
import Vector::*;
import BRAMFIFO::*;

import Clocks :: *;
import DefaultValue :: *;
import Xilinx :: *;
import XilinxCells :: *;
//import ConnectalXilinxCells::*;

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


/*
interface AuroraExtFlowControlIfc;
	method Action send(AuroraPacket data);
	method ActionValue#(AuroraPacket) recv;

	method Bit#(1) channel_up;
	method Bit#(1) lane_up;
endinterface
*/
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




interface AuroraExtIfc;
	interface Vector#(AuroraExtPerQuad, Aurora_Pins#(1)) aurora;
	interface Vector#(AuroraExtPerQuad, AuroraExtUserIfc) user;
	method Action setNodeIdx(HeaderField idx); 
endinterface

(* synthesize *)
module mkAuroraExt#(Clock gtx_clk_p, Clock gtx_clk_n, Clock clk50) (AuroraExtIfc);
	Reset defaultReset <- exposeCurrentReset;
	Clock defaultClock <- exposeCurrentClock;
`ifndef BSIM
	//ClockDividerIfc auroraExtClockDiv5 <- mkDCMClockDivider(5, 4, clocked_by clk250);
	//Clock clk50 = auroraExtClockDiv5.slowClock;
	Reset rst50 <- mkAsyncReset(2, defaultReset, clk50);
	Clock auroraExt_gtx_clk <- mkClockIBUFDS_GTE2(
`ifdef ClockDefaultParam
						      defaultValue,
`endif
						      True, gtx_clk_p, gtx_clk_n);

	MakeResetIfc rstgtpifc2 <- mkReset(8, True, auroraExt_gtx_clk);
	Reset rstgtp = rstgtpifc2.new_rst;
	AuroraExtImportIfc#(AuroraExtPerQuad) auroraExtImport <- mkAuroraExtImport(auroraExt_gtx_clk, clk50, rst50, rstgtp);
`else
   Clock clk_aurora_user <- mkAbsoluteClock(0, 8);
   Reset rst_aurora_user <- mkSyncResetFromCR(3, clk_aurora_user);
   
	AuroraExtImportIfc#(AuroraExtPerQuad) auroraExtImport <- mkAuroraExtImport_bsim(defaultClock, defaultClock, defaultReset, defaultReset,
           clocked_by clk_aurora_user,
           reset_by rst_aurora_user);
   SyncFIFOIfc#(HeaderField) nodeIdxQ <- mkSyncFIFOFromCC(8, clk_aurora_user);
   rule doSetIdx;
      let idx <- toGet(nodeIdxQ).get();
      auroraExtImport.setNodeIdx(zeroExtend(idx));      
   endrule
`endif

	Vector#(AuroraExtPerQuad, AuroraExtUserIfc) auroraExt;
	Vector#(AuroraExtPerQuad, Aurora_Pins#(1)) auroraPins;
	Vector#(AuroraExtPerQuad, Clock) auroraClk;
	Vector#(AuroraExtPerQuad, Reset) auroraRst;
	auroraPins[0] = auroraExtImport.aurora0;
	auroraPins[1] = auroraExtImport.aurora1;
	auroraPins[2] = auroraExtImport.aurora2;
	auroraPins[3] = auroraExtImport.aurora3;
	auroraClk[0] = auroraExtImport.aurora_clk0;
	auroraClk[1] = auroraExtImport.aurora_clk1;
	auroraClk[2] = auroraExtImport.aurora_clk2;
	auroraClk[3] = auroraExtImport.aurora_clk3;
	auroraRst[0] = auroraExtImport.aurora_rst0;
	auroraRst[1] = auroraExtImport.aurora_rst1;
	auroraRst[2] = auroraExtImport.aurora_rst2;
	auroraRst[3] = auroraExtImport.aurora_rst3;
	
	auroraExt[0] <- mkAuroraExtFlowControl(auroraExtImport.user0
		, defaultClock, defaultReset, 0
		, clocked_by auroraClk[0], reset_by auroraRst[0] );
	auroraExt[1] <- mkAuroraExtFlowControl(auroraExtImport.user1
		, defaultClock, defaultReset, 1
		, clocked_by auroraClk[1], reset_by auroraRst[1] );
	auroraExt[2] <- mkAuroraExtFlowControl(auroraExtImport.user2
		, defaultClock, defaultReset, 2
		, clocked_by auroraClk[2], reset_by auroraRst[2] );
	auroraExt[3] <- mkAuroraExtFlowControl(auroraExtImport.user3
		, defaultClock, defaultReset, 3
		, clocked_by auroraClk[3], reset_by auroraRst[3] );

	Vector#(AuroraExtPerQuad, AuroraExtUserIfc) userifcs;
	for ( Integer idx = 0; idx < valueOf(AuroraExtPerQuad); idx = idx + 1 ) begin
		userifcs[idx] = interface AuroraExtUserIfc;
	                           method Action send(AuroraPacket data);
                                   //method Action send(AuroraIfcType data);
				      auroraExt[idx].send(data);
			           endmethod
	                           method ActionValue#(AuroraPacket) receive;
                                   //method ActionValue#(Aurora) receive;
				let d <- auroraExt[idx].receive;
                      	   //$display( "(%t) %m, AuroraExt[%d] received %x", $time, idx, d );
				return d;
			endmethod
			method Bit#(1) lane_up = auroraExt[idx].lane_up;
			method Bit#(1) channel_up = auroraExt[idx].channel_up;
		endinterface: AuroraExtUserIfc;
	end
	interface user = userifcs;
	interface Vector aurora = auroraPins;
	method Action setNodeIdx(HeaderField idx); 
		`ifdef BSIM
	   //auroraExtImport.setNodeIdx(zeroExtend(idx));
           nodeIdxQ.enq(zeroExtend(idx));
		`endif
	endmethod
endmodule

// ifndef is necessary because AuroraExtImportIfc is different for bsim
`ifdef BSIM 
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
`endif

// ifndef is necessary because AuroraExtImportIfc is different for bsim
`ifndef BSIM 
import "BVI" aurora_64b66b_exdes =
module mkAuroraExtImport#(Clock gtx_clk_in, Clock init_clk, Reset init_rst_n, Reset gt_rst_n) (AuroraExtImportIfc#(AuroraExtPerQuad));
	default_clock no_clock;
	default_reset no_reset;

	input_clock (INIT_CLK_IN) = init_clk;
	input_reset (RESET_N) = init_rst_n;
	input_clock (GTX_CLK) = gtx_clk_in;
	input_reset (GT_RESET_N) clocked_by (gtx_clk_in) = gt_rst_n;

	output_clock aurora_clk0(USER_CLK_0);
	output_reset aurora_rst0(USER_RST_N_0) clocked_by (aurora_clk0);
	output_clock aurora_clk1(USER_CLK_1);
	output_reset aurora_rst1(USER_RST_N_1) clocked_by (aurora_clk1);
	output_clock aurora_clk2(USER_CLK_2);
	output_reset aurora_rst2(USER_RST_N_2) clocked_by (aurora_clk2);
	output_clock aurora_clk3(USER_CLK_3);
	output_reset aurora_rst3(USER_RST_N_3) clocked_by (aurora_clk3);

	interface Aurora_Pins aurora0;
		method rxn_in(RXN_0) enable((*inhigh*) rx_n_en_0) reset_by(no_reset) clocked_by(gtx_clk_in);
		method rxp_in(RXP_0) enable((*inhigh*) rx_p_en_0) reset_by(no_reset) clocked_by(gtx_clk_in);
		method TXN_0 txn_out() reset_by(no_reset) clocked_by(gtx_clk_in); 
		method TXP_0 txp_out() reset_by(no_reset) clocked_by(gtx_clk_in);
	endinterface//: Aurora_Pins;
	interface Aurora_Pins aurora1;
		method rxn_in(RXN_1) enable((*inhigh*) rx_n_en_1) reset_by(no_reset) clocked_by(gtx_clk_in);
		method rxp_in(RXP_1) enable((*inhigh*) rx_p_en_1) reset_by(no_reset) clocked_by(gtx_clk_in);
		method TXN_1 txn_out() reset_by(no_reset) clocked_by(gtx_clk_in); 
		method TXP_1 txp_out() reset_by(no_reset) clocked_by(gtx_clk_in);
	endinterface//: Aurora_Pins;
	interface Aurora_Pins aurora2;
		method rxn_in(RXN_2) enable((*inhigh*) rx_n_en_2) reset_by(no_reset) clocked_by(gtx_clk_in);
		method rxp_in(RXP_2) enable((*inhigh*) rx_p_en_2) reset_by(no_reset) clocked_by(gtx_clk_in);
		method TXN_2 txn_out() reset_by(no_reset) clocked_by(gtx_clk_in); 
		method TXP_2 txp_out() reset_by(no_reset) clocked_by(gtx_clk_in);
	endinterface//: Aurora_Pins;
	interface Aurora_Pins aurora3;
		method rxn_in(RXN_3) enable((*inhigh*) rx_n_en_3) reset_by(no_reset) clocked_by(gtx_clk_in);
		method rxp_in(RXP_3) enable((*inhigh*) rx_p_en_3) reset_by(no_reset) clocked_by(gtx_clk_in);
		method TXN_3 txn_out() reset_by(no_reset) clocked_by(gtx_clk_in); 
		method TXP_3 txp_out() reset_by(no_reset) clocked_by(gtx_clk_in);
	endinterface//: Aurora_Pins;

	interface AuroraControllerIfc user0;
		output_reset aurora_rst_n(USER_RST_0) clocked_by (aurora_clk0);

		method CHANNEL_UP_0 channel_up;
		method LANE_UP_0 lane_up;
		method HARD_ERR_0 hard_err;
		method SOFT_ERR_0 soft_err;
		method DATA_ERR_COUNT_0 data_err_count;

		method send(TX_DATA_0) enable(tx_en_0) ready(tx_rdy_0) clocked_by(aurora_clk0) reset_by(aurora_rst0);
		method RX_DATA_0 receive() enable((*inhigh*) rx_en_0) ready(rx_rdy_0) clocked_by(aurora_clk0) reset_by(aurora_rst0);
	endinterface
	interface AuroraControllerIfc user1;
		output_reset aurora_rst_n(USER_RST_1) clocked_by (aurora_clk1);

		method CHANNEL_UP_1 channel_up;
		method LANE_UP_1 lane_up;
		method HARD_ERR_1 hard_err;
		method SOFT_ERR_1 soft_err;
		method DATA_ERR_COUNT_1 data_err_count;

		method send(TX_DATA_1) enable(tx_en_1) ready(tx_rdy_1) clocked_by(aurora_clk1) reset_by(aurora_rst1);
		method RX_DATA_1 receive() enable((*inhigh*) rx_en_1) ready(rx_rdy_1) clocked_by(aurora_clk1) reset_by(aurora_rst1);
	endinterface
	interface AuroraControllerIfc user2;
		output_reset aurora_rst_n(USER_RST_2) clocked_by (aurora_clk2);

		method CHANNEL_UP_2 channel_up;
		method LANE_UP_2 lane_up;
		method HARD_ERR_2 hard_err;
		method SOFT_ERR_2 soft_err;
		method DATA_ERR_COUNT_2 data_err_count;

		method send(TX_DATA_2) enable(tx_en_2) ready(tx_rdy_2) clocked_by(aurora_clk2) reset_by(aurora_rst2);
		method RX_DATA_2 receive() enable((*inhigh*) rx_en_2) ready(rx_rdy_2) clocked_by(aurora_clk2) reset_by(aurora_rst2);
	endinterface
	interface AuroraControllerIfc user3;
		output_reset aurora_rst_n(USER_RST_3) clocked_by (aurora_clk3);

		method CHANNEL_UP_3 channel_up;
		method LANE_UP_3 lane_up;
		method HARD_ERR_3 hard_err;
		method SOFT_ERR_3 soft_err;
		method DATA_ERR_COUNT_3 data_err_count;

		method send(TX_DATA_3) enable(tx_en_3) ready(tx_rdy_3) clocked_by(aurora_clk3) reset_by(aurora_rst3);
		method RX_DATA_3 receive() enable((*inhigh*) rx_en_3) ready(rx_rdy_3) clocked_by(aurora_clk3) reset_by(aurora_rst3);
	endinterface

	schedule (
		user0_receive, user1_receive, user2_receive, user3_receive
	) CF (
		user0_send, user1_send, user2_send, user3_send
	);
	
	schedule (user0_send) C (user0_send);
	schedule (user0_receive) C (user0_receive);

	schedule (user1_send) C (user1_send);
	schedule (user1_receive) C (user1_receive);
	
	schedule (user2_send) C (user2_send);
	schedule (user2_receive) C (user2_receive);

	schedule (user3_send) C (user3_send);
	schedule (user3_receive) C (user3_receive);

/*
	schedule (
		aurora0_rxn_in, aurora0_rxp_in, aurora0_txn_out, aurora0_txp_out,
		aurora1_rxn_in, aurora1_rxp_in, aurora1_txn_out, aurora1_txp_out,
		aurora2_rxn_in, aurora2_rxp_in, aurora2_txn_out, aurora2_txp_out,
		aurora3_rxn_in, aurora3_rxp_in, aurora3_txn_out, aurora3_txp_out
		) CF (
		aurora0_rxn_in, aurora0_rxp_in, aurora0_txn_out, aurora0_txp_out,
		aurora1_rxn_in, aurora1_rxp_in, aurora1_txn_out, aurora1_txp_out,
		aurora2_rxn_in, aurora2_rxp_in, aurora2_txn_out, aurora2_txp_out,
		aurora3_rxn_in, aurora3_rxp_in, aurora3_txn_out, aurora3_txp_out
		);
		*/
	
	schedule (
		aurora0_rxn_in, aurora0_rxp_in, aurora0_txn_out, aurora0_txp_out,
		aurora1_rxn_in, aurora1_rxp_in, aurora1_txn_out, aurora1_txp_out,
		aurora2_rxn_in, aurora2_rxp_in, aurora2_txn_out, aurora2_txp_out,
		aurora3_rxn_in, aurora3_rxp_in, aurora3_txn_out, aurora3_txp_out,

		user0_channel_up,
		user0_lane_up,
		user0_hard_err,
		user0_soft_err,
		user0_data_err_count,
		user1_channel_up,
		user1_lane_up,
		user1_hard_err,
		user1_soft_err,
		user1_data_err_count,
		user2_channel_up,
		user2_lane_up,
		user2_hard_err,
		user2_soft_err,
		user2_data_err_count,
		user3_channel_up,
		user3_lane_up,
		user3_hard_err,
		user3_soft_err,
		user3_data_err_count
		) CF (
		aurora0_rxn_in, aurora0_rxp_in, aurora0_txn_out, aurora0_txp_out,
		aurora1_rxn_in, aurora1_rxp_in, aurora1_txn_out, aurora1_txp_out,
		aurora2_rxn_in, aurora2_rxp_in, aurora2_txn_out, aurora2_txp_out,
		aurora3_rxn_in, aurora3_rxp_in, aurora3_txn_out, aurora3_txp_out,

		user0_channel_up,
		user0_lane_up,
		user0_hard_err,
		user0_soft_err,
		user0_data_err_count,
		user1_channel_up,
		user1_lane_up,
		user1_hard_err,
		user1_soft_err,
		user1_data_err_count,
		user2_channel_up,
		user2_lane_up,
		user2_hard_err,
		user2_soft_err,
		user2_data_err_count,
		user3_channel_up,
		user3_lane_up,
		user3_hard_err,
		user3_soft_err,
		user3_data_err_count
		);
endmodule
`endif
endpackage: AuroraExtImport
