package AuroraImportFmc2;

import FIFO::*;
import FIFOF::*;
import Clocks :: *;
import DefaultValue :: *;
import Xilinx :: *;
import XilinxCells :: *;

import AuroraCommon::*;

import AuroraGearbox::*;

import AuroraImportFmc1::*;

(* synthesize *)
module mkAuroraIntra2#(Clock gtx_clk_p, Clock gtx_clk_n, Clock clk50) (AuroraIfc);

	Clock cur_clk <- exposeCurrentClock; // assuming 200MHz clock
	Reset cur_rst <- exposeCurrentReset;
	

`ifndef BSIM

	Reset defaultReset <- exposeCurrentReset;
	MakeResetIfc rst50ifc <- mkReset(8, True, clk50);
	MakeResetIfc rst50ifc2 <- mkReset(16384, True, clk50);
	//Reset rst50 = rst50ifc.new_rst;
	Reset rst50 <- mkAsyncReset(2, defaultReset, clk50);
	Reset rst50_2 = rst50ifc2.new_rst;
	Reset rst50_2a <- mkAsyncReset(2, rst50_2, clk50);
	Clock fmc2_gtx_clk_i <- mkClockIBUFDS_GTE2(defaultValue,True, gtx_clk_p, gtx_clk_n);
	//Clock fmc1_gtx_clk_i <- mkClockIBUFDS_GTE2(True, gtx_clk_p, gtx_clk_n);
	AuroraImportIfc#(4) aurora2IntraImport;
	//aurora2IntraImport <- mkAuroraImport_8b10b_fmc1(fmc1_gtx_clk_i, clk50, rst50, /*rst50*/rst50_2a);
	aurora2IntraImport <- mkAuroraImport_8b10b_fmc2(fmc2_gtx_clk_i, clk50, rst50, /*rst50*/rst50_2a);

	Reg#(Bit#(32)) auroraResetCounter <- mkReg(0); //, clocked_by clk50, reset_by rst50ifc.new_rst);
	rule resetAurora;
		if ( auroraResetCounter < 1024*1024*512 ) begin
			auroraResetCounter <= auroraResetCounter +1 ;
			if ( auroraResetCounter < 1024*1024*128 && aurora2IntraImport.user.channel_up == 0 ) begin
				rst50ifc2.assertReset;
			end
		end else begin
			auroraResetCounter <= 0;
		end
	endrule

`else
	//Clock gtx_clk = cur_clk;
	AuroraImportIfc#(4) aurora2IntraImport <- mkAuroraImport_8b10b_bsim;
`endif


	Clock aclk = aurora2IntraImport.aurora_clk;
	Reset arst = aurora2IntraImport.aurora_rst;


	Reg#(Bit#(32)) gearboxSendCnt <- mkReg(0);
	Reg#(Bit#(32)) gearboxRecCnt <- mkReg(0);
	Reg#(Bit#(32)) auroraSendCnt <- mkReg(0, clocked_by aclk, reset_by arst);
	Reg#(Bit#(32)) auroraRecCnt <- mkReg(0, clocked_by aclk, reset_by arst);
	Reg#(Bit#(32)) auroraSendCntCC <- mkSyncRegToCC(0, aclk, arst);
	Reg#(Bit#(32)) auroraRecCntCC <- mkSyncRegToCC(0, aclk, arst);
	rule syncCnt;
		auroraSendCntCC <= auroraSendCnt;
		auroraRecCntCC <= auroraRecCnt;
	endrule


	Reg#(Bit#(64)) auroraInitCnt <- mkReg(0, clocked_by aclk, reset_by arst);
`ifndef BSIM
	Integer auroraInitWait = 1024*1024*125*16;
`else
	Integer auroraInitWait = 512;
`endif
	AuroraGearboxIfc auroraGearbox <- mkAuroraGearbox(aclk, arst);
	rule auroraInit ( auroraInitCnt < fromInteger(auroraInitWait) );
		auroraInitCnt <= auroraInitCnt + 1;
	endrule
	rule auroraOut if (aurora2IntraImport.user.channel_up==1 && auroraInitCnt >= fromInteger(auroraInitWait));
		let d <- auroraGearbox.auroraSend;
		//if ( aurora2IntraImport.user.channel_up == 1 ) begin
			$display("Gearbox send out: %x", d);
			auroraSendCnt <= auroraSendCnt + 1;
			aurora2IntraImport.user.send(d);
		//end
	endrule
	/*
	rule resetDeadLink ( aurora2IntraImport.user.channel_up == 0 );
		auroraGearbox.resetLink;
		$display("Gearbox reset link");
	endrule
	*/
	FIFO#(Bit#(AuroraWidth)) auroraRecvQ <- mkSizedFIFO(8, clocked_by aclk, reset_by arst);
	rule auroraR;
		let d <- aurora2IntraImport.user.receive;
		Bit#(8) header = truncate(d>>valueOf(BodySz));
		Bit#(1) idx = header[7];
		Bit#(1) control = header[6];
		if ( auroraInitCnt >= fromInteger(auroraInitWait) || control == 1 ) begin
			auroraRecvQ.enq(d);
		end
	endrule
	rule auroraIn( auroraInitCnt >= fromInteger(auroraInitWait));
		let d = auroraRecvQ.first;
		auroraRecvQ.deq;

		$display("Gearbox received: %x", d);
		auroraRecCnt <= auroraRecCnt + 1;
		auroraGearbox.auroraRecv(d);
	endrule

	ReadOnly#(Bit#(16)) aSendB <- mkNullCrossingWire(noClock, auroraGearbox.curSendBudget);

	method Tuple4#(Bit#(32), Bit#(32), Bit#(32), Bit#(32)) getDebugCnts;
		return tuple4(gearboxSendCnt, gearboxRecCnt, auroraSendCntCC, auroraRecCntCC);
	endmethod

	method Action send(DataIfc data, PacketType ptype);
		auroraGearbox.send(data, ptype);
		gearboxSendCnt <= gearboxSendCnt + 1;
	endmethod
	method ActionValue#(Tuple2#(DataIfc, PacketType)) receive;
		let d <- auroraGearbox.recv;
		gearboxRecCnt <= gearboxRecCnt + 1;
		return d;
	endmethod

	method channel_up = aurora2IntraImport.user.channel_up;
	method lane_up = aurora2IntraImport.user.lane_up;
	method hard_err = aurora2IntraImport.user.hard_err;
	method soft_err = aurora2IntraImport.user.soft_err;
	method data_err_count = aurora2IntraImport.user.data_err_count;

	interface Clock clk = aurora2IntraImport.aurora_clk;
	interface Reset rst = aurora2IntraImport.aurora_rst;

	interface Aurora_Pins aurora = aurora2IntraImport.aurora;
	method Bit#(16) curSendBudget;
		return aSendB;
	endmethod
endmodule

import "BVI" aurora_8b10b_fmc2_exdes =
module mkAuroraImport_8b10b_fmc2#(Clock gtx_clk_in, Clock init_clk, Reset init_rst_n, Reset gt_rst_n) (AuroraImportIfc#(4));
	default_clock no_clock;
	default_reset no_reset;

	input_clock (INIT_CLK_IN) = init_clk;
	input_reset (RESET_N) = init_rst_n;
	input_reset (GT_RESET_N) = gt_rst_n;

	output_clock aurora_clk(USER_CLK);
	output_reset aurora_rst(USER_RST_N) clocked_by (aurora_clk);

	input_clock (GTX_CLK) = gtx_clk_in;

	interface Aurora_Pins aurora;
		method rxn_in(RXN) enable((*inhigh*) rx_n_en) reset_by(no_reset) clocked_by(gtx_clk_in);
		method rxp_in(RXP) enable((*inhigh*) rx_p_en) reset_by(no_reset) clocked_by(gtx_clk_in);
		method TXN txn_out() reset_by(no_reset) clocked_by(gtx_clk_in); 
		method TXP txp_out() reset_by(no_reset) clocked_by(gtx_clk_in);
	endinterface

	interface AuroraControllerIfc user;
		output_reset aurora_rst_n(USER_RST) clocked_by (aurora_clk);

		method CHANNEL_UP channel_up;
		method LANE_UP lane_up;
		method HARD_ERR hard_err;
		method SOFT_ERR soft_err;
		method ERR_COUNT data_err_count;

		method send(TX_DATA) enable(tx_en) ready(tx_rdy) clocked_by(aurora_clk) reset_by(aurora_rst);
		method RX_DATA receive() enable((*inhigh*) rx_en) ready(rx_rdy) clocked_by(aurora_clk) reset_by(aurora_rst);
	endinterface
	
	schedule (aurora_rxn_in, aurora_rxp_in, aurora_txn_out, aurora_txp_out, user_channel_up, user_lane_up, user_hard_err, user_soft_err, user_data_err_count) CF 
	(aurora_rxn_in, aurora_rxp_in, aurora_txn_out, aurora_txp_out, user_channel_up, user_lane_up, user_hard_err, user_soft_err, user_data_err_count);
	schedule (user_send) CF (aurora_rxn_in, aurora_rxp_in, aurora_txn_out, aurora_txp_out, user_channel_up, user_lane_up, user_hard_err, user_soft_err, user_data_err_count);

	schedule (user_receive) CF (aurora_rxn_in, aurora_rxp_in, aurora_txn_out, aurora_txp_out, user_channel_up, user_lane_up, user_hard_err, user_soft_err, user_data_err_count);

	schedule (user_receive) SB (user_send);
	schedule (user_send) C (user_send);
	schedule (user_receive) C (user_receive);

endmodule

endpackage: AuroraImportFmc2
