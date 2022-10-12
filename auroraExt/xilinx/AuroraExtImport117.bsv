package AuroraExtImport117;

import FIFO::*;
import Vector::*;

import Clocks :: *;
import ClockImport :: *;
import DefaultValue :: *;

import AuroraCommon::*;
import AuroraExtImportCommon::*;


interface ClockDiv4Ifc;
	interface Clock slowClock;
endinterface
(* synthesize *)
module mkClockDiv4#(Clock fastClock) (ClockDiv4Ifc);
	MakeResetIfc fastReset <- mkReset(8, True, fastClock);
	ClockDividerIfc clockdiv4 <- mkClockDivider(4, clocked_by fastClock, reset_by fastReset.new_rst);

	interface slowClock = clockdiv4.slowClock;
endmodule


(* synthesize *)
module mkAuroraExt117#(Clock gtx_clk_p, Clock gtx_clk_n, Clock clk200) (AuroraExtIfc);
	Reset defaultReset <- exposeCurrentReset;
	Clock defaultClock <- exposeCurrentClock;
`ifndef BSIM
	//ClockDividerIfc auroraExtClockDiv4 <- mkDCMClockDivider(4, 5, clocked_by clk200);
	//Clock clk50 = auroraExtClockDiv4.slowClock;
	ClockDiv4Ifc auroraExt117ClockDiv <- mkClockDiv4(clk200);
	Clock clk50 = auroraExt117ClockDiv.slowClock;

	ClockGenIfc clk_import_quad117 <- mkClockIBUFDS_GTE2Import(gtx_clk_p, gtx_clk_n);
	Clock gtx_clk_quad117 = clk_import_quad117.gen_clk;
	Clock auroraExt117_gtx_clk = gtx_clk_quad117;

	MakeResetIfc rst50ifc <- mkReset(8, True, clk50);
	MakeResetIfc rst50ifc2 <- mkReset(16384, True, clk50);
	Reset rst50 <- mkAsyncReset(2, defaultReset, clk50);
	Reset rst50_2 = rst50ifc.new_rst;
	Reset rst50_3 = rst50ifc2.new_rst;
	Reset rst50_3a <- mkAsyncReset(2, rst50_3, clk50);
		
	MakeResetIfc rstgtpifc2 <- mkReset(8, True, auroraExt117_gtx_clk);
	Reset rstgtp = rstgtpifc2.new_rst;

	AuroraExtImportIfc#(AuroraExtPerQuad) auroraExtImport <- mkAuroraExtImport117(auroraExt117_gtx_clk, clk50, rst50, rstgtp);
`else
	AuroraExtImportIfc#(AuroraExtPerQuad) auroraExtImport <- mkAuroraExtImport_bsim(defaultClock, defaultClock, defaultReset, defaultReset);
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
		, auroraClk[0], auroraRst[0], 0);
	auroraExt[1] <- mkAuroraExtFlowControl(auroraExtImport.user1
		, auroraClk[1], auroraRst[1], 1);
	auroraExt[2] <- mkAuroraExtFlowControl(auroraExtImport.user2
		, auroraClk[2], auroraRst[2], 2);
	auroraExt[3] <- mkAuroraExtFlowControl(auroraExtImport.user3
		, auroraClk[3], auroraRst[3], 3 );


	Vector#(AuroraExtPerQuad, AuroraExtUserIfc) userifcs;
	for ( Integer idx = 0; idx < valueOf(AuroraExtPerQuad); idx = idx + 1 ) begin
		userifcs[idx] = interface AuroraExtUserIfc;
					method Action send(AuroraSend data);
						auroraExt[idx].send(data);
						$display( "AuroraExt Port[%d] sent %x", idx, data );
					endmethod
					method ActionValue#(AuroraIfcType) receive;
						let d <- auroraExt[idx].receive;
						$display( "AuroraExt Port[%d] received %x", idx, d );
						return d;
					endmethod
					method Bit#(1) lane_up = auroraExt[idx].lane_up;
					method Bit#(1) channel_up = auroraExt[idx].channel_up;
				endinterface: AuroraExtUserIfc;
	end
	interface user = userifcs;
	interface aurora = auroraPins;
endmodule


import "BVI" aurora_64b66b_117_exdes =
module mkAuroraExtImport117#(Clock gtx_clk_in, Clock init_clk, Reset init_rst_n, Reset gt_rst_n) (AuroraExtImportIfc#(AuroraExtPerQuad));
	default_clock no_clock;
	default_reset no_reset;

	input_clock (INIT_CLK_IN) = init_clk;
	input_reset (RESET_N) = init_rst_n;
	input_clock (GTX_CLK) = gtx_clk_in;
	input_reset (GT_RESET_N) = gt_rst_n;

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
endpackage: AuroraExtImport117
