//RS(n, k) = RS(255, 243) 
import GetPut::*;
import Vector       :: *;
import FIFOF        :: *;
import FIFO::*;
import SpecialFIFOs :: *;
import PAClib       :: *;
import FShow        :: *;

import GFArith      :: *;
import GFTypes      :: *;
`include "RSParameters.bsv"

interface RSEncoderIfc;
	interface Put#(Byte) rs_k_in;
	interface Put#(Byte) rs_enc_in;
	interface Get#(Byte) rs_enc_out;
endinterface

(* synthesize *)
module mkRSEncoder (RSEncoderIfc);

	FIFO#(Byte) k_in <- mkSizedFIFO(32);
	FIFO#(Byte) enc_in <- mkFIFO();
	FIFO#(Byte) enc_out <- mkFIFO();

	Vector#(TwoT, Reg#(Byte)) encodeReg <- replicateM(mkReg(0));
	Reg#(Bit#(32)) countIn <- mkReg(0);
	Reg#(Bit#(32)) countOut <- mkReg(0);


	//Generator polynomial coefficients. Constants.
	//Generated using rsgenpoly(255,243) in Matlab. In order from lowest to highest degree. 
	//Note: this polynomial is different for diff values of t
	Byte gen_poly_coeff[valueOf(TwoT)] = {120, 252, 175, 132, 170, 167, 147, 130, 51, 34, 193, 136};

	rule doEncode if (countIn < fromInteger(valueOf(K)));
		Byte enc_data;
		//zero pad if needed
		if ( fromInteger(valueOf(K)) - zeroExtend(k_in.first) > countIn ) begin
			enc_data = 0;
		end
		else begin
			enc_data = enc_in.first();
			enc_out.enq(enc_in.first()); //enq the original data
			enc_in.deq;
		end

		/*
		if (countIn < zeroExtend(k_in.first)) begin
			enc_data = enc_in.first();
			enc_out.enq(enc_in.first()); //enq the original data
			enc_in.deq;
		end
		else begin
			enc_data = 0;
		end
		*/

		$display("@%t\t%m: Processing [%d] = %x", $time, countIn, enc_data);
		let enc_in_sub = gf_add(enc_data, encodeReg[valueOf(TwoT)-1]);
		//calculation for the first register differs from the rest
		encodeReg[0] <= gf_mult(enc_in_sub, gen_poly_coeff[0]);

		//the other registers
		Integer i;
		for (i=1; i<valueOf(TwoT); i=i+1) begin
			let enc_product = gf_mult(enc_in_sub, gen_poly_coeff[i]);
			encodeReg[i] <= gf_add(enc_product, encodeReg[i-1]);
		end
		
		countIn <= countIn + 1;
	endrule

	rule doOutputParity if (countIn == fromInteger(valueOf(K)));
		//if (countOut < fromInteger(valueOf(TwoT))) begin
			//enq the parity bits
			Bit#(32) ind = fromInteger(valueOf(TwoT)) - 1 - countOut;
			enc_out.enq(encodeReg[ind]);
			$display("@%t\t%m: Parity [%d] = %x\n", $time, countOut, encodeReg[ind]);
			if (countOut < fromInteger(valueOf(TwoT) - 1)) begin
				countOut <= countOut + 1;
			end
			else begin
				countOut <= 0;
				countIn <= 0;
				k_in.deq;
				writeVReg(encodeReg, replicate(0));
			end
		//end
		//else begin
		//end
	endrule

	interface Put rs_k_in		= toPut(k_in);
	interface Put rs_enc_in		= toPut(enc_in);
	interface Get rs_enc_out	= toGet(enc_out);

endmodule


