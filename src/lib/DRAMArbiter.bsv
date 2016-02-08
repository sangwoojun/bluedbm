import ClientServer::*;
import GetPut::*;
import Clocks          :: *;

import Vector::*;
import FIFO::*;

import DRAMImporter::*;

interface DRAMCommandIfc;
	method ActionValue#(Tuple3#(Bit#(32), Bit#(512), Bool)) request;
	method Action read_data(Bit#(512) data);
endinterface
interface DRAMEndpointIfc;
	interface DRAM_User user;
	interface DRAMCommandIfc cmd;
endinterface

interface DRAMArbiterIfc;
endinterface

//module mkDRAMArbiter#(Vector#(portCount, Client#(Bit#(64), Bit#(512))) userList) (DRAMArbiterIfc#(portNum));
module mkDRAMArbiter#(DRAM_User dram, Vector#(tPortCount, DRAMCommandIfc) userList) (DRAMArbiterIfc);
	Integer portCount = valueOf(tPortCount);
	FIFO#(Bit#(8)) reqUserQ <- mkSizedFIFO(32);

	Reg#(Bit#(8)) curExUserIdx <- mkReg(0);
	rule incCurEx;
		if ( curExUserIdx +1 >= fromInteger(portCount) ) begin
			curExUserIdx <= 0;
		end else begin
			curExUserIdx <= curExUserIdx + 1;
		end
	endrule
	for ( Integer uidx = 0; uidx < portCount; uidx = uidx + 1) begin
		let user = userList[uidx];

		rule applycmd (curExUserIdx != fromInteger(uidx));
			let cmd <- user.request;
			let addr = tpl_1(cmd);
			let data = tpl_2(cmd);
			let write = tpl_3(cmd);
			dram.request(addr, data, write);
			if ( write == False ) begin
				reqUserQ.enq(fromInteger(uidx));
			end
		endrule
	end


	FIFO#(Tuple2#(Bit#(512), Bit#(8))) readBufferQ <- mkFIFO;
	rule bufferRdata;
		let res <- dram.read_data;
		let uidx = reqUserQ.first;
		reqUserQ.deq;
		readBufferQ.enq(tuple2(res, uidx));
	endrule
	rule readRData;
		let rr = readBufferQ.first;
		readBufferQ.deq;

		let data = tpl_1(rr);
		let uidx = tpl_2(rr);

		userList[uidx].read_data(data);
	endrule
endmodule


module mkDRAMUser (DRAMEndpointIfc);
	FIFO#(Tuple3#(Bit#(32), Bit#(512), Bool)) cmdQ <- mkFIFO;
	FIFO#(Bit#(512)) dataQ <- mkFIFO;

	interface DRAM_User user;
		method Action request(Bit#(32) addr, Bit#(512) data, Bool write);
			cmdQ.enq(tuple3(addr, data, write));
		endmethod
		method ActionValue#(Bit#(512)) read_data;
			dataQ.deq;
			return dataQ.first;
		endmethod
	endinterface
	interface DRAMCommandIfc cmd;
		method ActionValue#(Tuple3#(Bit#(32), Bit#(512), Bool)) request;
			cmdQ.deq;
			return cmdQ.first;
		endmethod
		method Action read_data(Bit#(512) data);
			dataQ.enq(data);
		endmethod
	endinterface
endmodule
