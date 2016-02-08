//----------------------------------------------------------------------//
// The MIT License 
// 
// Copyright (c) 2008 Abhinav Agarwal, Alfred Man Cheuk Ng
// Contact: abhiag@gmail.com
// 
// Permission is hereby granted, free of charge, to any person 
// obtaining a copy of this software and associated documentation 
// files (the "Software"), to deal in the Software without 
// restriction, including without limitation the rights to use,
// copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the
// Software is furnished to do so, subject to the following conditions:
// 
// The above copyright notice and this permission notice shall be
// included in all copies or substantial portions of the Software.
// 
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
// OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
// NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
// HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
// WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
// OTHER DEALINGS IN THE SOFTWARE.
//----------------------------------------------------------------------//

package ErrorMagnitude;

import FIFOF        :: *;
import SpecialFIFOs :: *;
import Vector       :: *;
import PAClib       :: *;
import StmtFSM      :: *;

import GFArith      :: *;
import GFTypes      :: *;

// ---------------------------------------------------------
// Reed-Solomon Error Magnitude computer module 
// ---------------------------------------------------------

module mkErrorMagnitude
   #(PipeOut #(Byte)           k_in,
     PipeOut #(Bool)           no_error_flag_in,
     PipeOut #(Maybe #(Byte))  loc_in_0,
     PipeOut #(Maybe #(Byte))  alpha_inv_in_0,
     PipeOut #(Syndrome #(T))  lambda_in,
     PipeOut #(Syndrome #(T))  omega_in)
   (PipeOut #(Byte));                // error_out
   
   PipeOut #(Maybe #(Byte)) loc_in       <- mkBuffer_n (valueOf(TwoT), loc_in_0);
   PipeOut #(Maybe #(Byte)) alpha_inv_in <- mkBuffer_n (valueOf(T),    alpha_inv_in_0);

   // output queue
   FIFOF #(Byte)            err_q           <- mkPipelineFIFOF;
   
   // internal queue
   FIFOF #(Byte)            int_err_q       <- mkSizedFIFOF (valueOf (T));
   
   // ----------------
   // Stage 1: produces err values from lambda, omega and alpha_inv inputs

   Reg #(Byte)              omega_val       <- mkReg(0);
   Reg #(Byte)              lambda_d_val    <- mkReg(0);

   Reg #(Byte)              count           <- mkReg(0);
   Reg #(Byte)              block_number1   <- mkReg(1);
   
   // variables
   Byte t = fromInteger (valueOf (T));    // TODO: Shouldn't this be a dynamic input?
 
   rule rl_valid_alpha_inv (alpha_inv_in.first matches tagged Valid .alpha_inv &&& (count < t));
      // Derivative of Lambda is done by dropping even terms and shifting odd terms by one
      // So count is incremented by 2
      // valid_t - 2 is the index used as the final term since valid_t - 1 term gets dropped
      Byte i1 = (t - 1) - count;
      Byte lambda_add_val = (((count & 8'd1) == 8'd1) ? lambda_in.first [i1] : 0);
      let new_lambda_d_val = gf_add (gf_mult (lambda_d_val, alpha_inv), lambda_add_val);
      let new_omega_val    = gf_mult (omega_val, alpha_inv) ^ (omega_in.first [i1]);
      $display ("  [errMag %0d] Evaluating Lambda_der count: %0d, lambda_d_val[prev]: %0d, lambda_add_val: %0d, i1: %0d",
		block_number1, count, lambda_d_val, lambda_add_val, i1);
      $display ("  [errMag %0d]  Evaluating Omega count : %0d, omega_val[prev] : %0d",
		block_number1, count, omega_val); 

      lambda_d_val <= new_lambda_d_val;
      omega_val    <= new_omega_val;
      count        <= count + 1;
   endrule

   rule rl_enq_err (alpha_inv_in.first matches tagged Valid .alpha_inv &&& (count == t));
      $display ("  [errMag %0d]  Finish Evaluating Lambda Omega", block_number1);
      let err_val = gf_mult (omega_val, gf_inv (lambda_d_val));
      int_err_q.enq (err_val);
      lambda_d_val  <= 0;
      omega_val     <= 0;
      count         <= 0;
      block_number1 <= block_number1 + 1;
      alpha_inv_in.deq;
   endrule

   rule rl_invalid_alpha_inv (alpha_inv_in.first matches tagged Invalid);
      $display ("  [errMag %0d]  Deq Invalid Alpha Inv", block_number1);
      alpha_inv_in.deq;
      lambda_in.deq;
      omega_in.deq;
   endrule

   // ----------------------------------------------------------------
   // Stage 2: From loc and int_errs, produce output errs
   // Process int_err_q

   Reg #(Byte)  i2             <- mkReg(0);
   Reg #(Byte)  block_number2  <- mkReg(1);

   let k             = k_in.first;
   let no_error_flag = no_error_flag_in.first;
   let loc           = fromMaybe (255, loc_in.first); // next location has no error?

   rule rl_process_error_no_error ((! no_error_flag) && (i2 < k));
      Byte err_val;
      if (i2 == loc) begin
	 $display ("  [errMag %0d]  Processing location %0d which is in error ", block_number2, i2);

	 err_val = int_err_q.first;
	 int_err_q.deq;
	 loc_in.deq;
      end
      else begin
	 $display ("  [errMag %0d]  process location %0d which has no error ", block_number2, i2);

	 err_val = 0;
      end
      err_q.enq (err_val);
      i2 <= i2 + 1;
      $display ("  [errmag_out %0d]  err_out: %h", block_number2, err_val);
   endrule

   rule rl_bypass (no_error_flag && (i2 < k));
      $display ("  [errMag %0d]  process location %0d bypass which has no error ", block_number2, i2);
      i2 <= k;
   endrule

   rule rl_start_next_errMag (i2 == k);
      $display ("Start Next ErrMag");

      k_in.deq;
      no_error_flag_in.deq;
      i2 <= 0;
      block_number2 <= block_number2 + 1;
      if (! no_error_flag)
	 loc_in.deq; // this one should be the Invalid terminator
   endrule

   // ------------------------------------------------
   return f_FIFOF_to_PipeOut (err_q);
endmodule

endpackage
