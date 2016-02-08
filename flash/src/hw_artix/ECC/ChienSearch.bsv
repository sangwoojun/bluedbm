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

package ChienSearch;

import FIFOF          :: *;
import SpecialFIFOs   :: *;
import UniqueWrappers :: *;
import Vector         :: *;
import PAClib         :: *;
import StmtFSM        :: *;
import FShow          :: *;

import GFArith        :: *;
import GFTypes        :: *;

// ---------------------------------------------------------
// Auxiliary Function
// ---------------------------------------------------------
(* noinline *)
function Syndrome#(T) times_alpha_n_v(Syndrome#(T) lambda_a, Byte t);
   Syndrome#(T) lambda_a_new = lambda_a;
   for (Byte x = 0; x < fromInteger(valueOf(T)); x = x + 1)
      lambda_a_new[x] = times_alpha_n(lambda_a[x], x + 1) & ((x < t)? 8'hFF : 8'h00);
   return lambda_a_new;
endfunction 

// ---------------------------------------------------------
// Reed-Solomon Chien Error Magnitude computer module 
// ---------------------------------------------------------

module mkChienSearch
   #(PipeOut #(Byte) t_in,
     PipeOut #(Byte) k_in,
     PipeOut #(Bool) no_error_flag_in,
     PipeOut #(Syndrome #(T)) lambda_in,
  	  PipeOut #(Byte) deg_in)
   (Tuple4 #(PipeOut #(Maybe #(Byte)),      // loc
	     PipeOut #(Maybe #(Byte)),      // alpha_inv
	     PipeOut #(Bool),               // cant_correct_flag
	     PipeOut #(Syndrome #(T))));    // lambda
   
   // comb. circuit sharing
   Wrapper2 #(Syndrome #(T),Byte,
	      Syndrome #(T))       times_alpha_n_vec   <- mkUniqueWrapper2(times_alpha_n_v);

   // output queues
   FIFOF #(Bool)                    cant_correct_flag_q <- mkPipelineFIFOF;
   FIFOF #(Maybe #(Byte))           loc_q               <- mkPipelineFIFOF;
   FIFOF #(Maybe #(Byte))           alpha_inv_q         <- mkPipelineFIFOF;
   FIFOF #(Syndrome #(T))           lambda_out_q        <- mkPipelineFIFOF;
   
   // book-keep state
   Reg #(Byte)                      i                   <- mkRegU;
   Reg #(Byte)                      count_error         <- mkRegU;
   Reg #(Bool)                      loop_done           <- mkRegU;
   Reg #(Byte)                      block_number        <- mkReg (1);
   Reg #(Byte)                      alpha_inv           <- mkRegU;
   Reg #(Syndrome #(T))             lambda_a            <- mkRegU;

   // variables   
   let no_error_flag = no_error_flag_in.first;
   let t = t_in.first;
   let k = k_in.first;
	let deg = deg_in.first;
   
   // ------------------------------------------------

   mkAutoFSM (
      seq
	 while (True)
	    if (no_error_flag) action
	       $display ("  [chien %0d]  start: no_error_flag = True", block_number);
	       t_in.deq;
	       k_in.deq;
	       no_error_flag_in.deq;
			 deg_in.deq;
	       cant_correct_flag_q.enq (False);
	       block_number <= block_number + 1;
	    endaction
	    else seq
	       action
				  $display ("  [chien %0d]  start: no_error_flag = False", block_number);
				  i <= 254;
				  loop_done <= False;
				  count_error <= 0;
				  lambda_out_q.enq (lambda_in.first);
				  let lambda_a_new <- times_alpha_n_vec.func (lambda_in.first, t);
				  lambda_a <= lambda_a_new;
				  alpha_inv <= 2; // = alpha^(1) = alpha^(-254)
				  lambda_in.deq;
	       endaction
	       while (! loop_done) action    // for i = 254 downto 0
				  $display ("  [chien %0d]  calc_loc, i = %0d", block_number, i);

				  Byte result_location = fold (gf_add, cons (1, lambda_a)); // lambda_a add up + 1
				  alpha_inv <= times_alpha (alpha_inv);
				  $display ("  [chien %0d]  calc_loc, result location = %0d", block_number, result_location);
				  let is_no_error = (result_location != 0);
				
				  let count_error_curr = count_error;
				  if (! is_no_error) begin
					  count_error_curr = count_error + 1;
					  count_error <= count_error_curr;
					  $display ("  [chien %0d]  count_error = ", block_number, count_error+1);
				  end

				  if (i == 0) begin
					  loop_done <= True;
					  //ML: can't correct if 
					  // (1) the number of roots of lamda is != the degree of lamda
					  // (2) degree of lamda is > T (note: max # of errors from RSParameters.bsv)
					  // TODO: can probably fast track the second condition
					  cant_correct_flag_q.enq ( (count_error_curr != deg) || (deg > fromInteger(valueOf(T))) ); 
					  $display("count_error_curr=%d, deg=%d", count_error_curr, deg);
					  t_in.deq;
					  k_in.deq;
					  no_error_flag_in.deq;
					  deg_in.deq;
					  block_number <= block_number + 1;
									loc_q.enq (tagged Invalid);
									alpha_inv_q.enq (tagged Invalid);
				  end
				  else begin
									let lambda_a_new <- times_alpha_n_vec.func (lambda_a, t);
									lambda_a <= lambda_a_new;
									$display ("  [chien %0d]  calc_loc, lambda_a = ", block_number, fshow (lambda_a_new));
					  if ((i < k + 2 * t) && (i >= 2 * t) && (! is_no_error)) begin
					alpha_inv_q.enq (tagged Valid alpha_inv);
					loc_q.enq (tagged Valid (k + 2 * t - i - 1)); // process range 1 - k
					  end
					  i <= i - 1;
				  end
	       endaction // while (! loop_done)
	    endseq // if (no_error_flag) ... else begin
      endseq
      );

   // ----------------------------------------------------------------

   function Action fn_show_loc (Maybe #(Byte) loc) =
      $display ("  [chien_out %d]  loc_out : ", block_number, fshow (loc));

   function Action fn_show_alpha_inv (Maybe #(Byte) alpha_inv_show) =
      $display ("  [chien_out %d]  alpha_inv_out : ", block_number, fshow (alpha_inv_show));

   function Action fn_show_cant_correct_flag (Bool cant_correct_flag) =
      $display ("  [chien_out %d]  Can't Correct Flag : ", block_number, fshow (cant_correct_flag));

   function Action fn_show_lambda (Syndrome #(T) lambda) =
      $display ("  [chien_out %d]  lambda_out : ", block_number, fshow (lambda));

   return tuple4 (fn_tee_to_Action (fn_show_loc, f_FIFOF_to_PipeOut (loc_q)),
		  fn_tee_to_Action (fn_show_alpha_inv, f_FIFOF_to_PipeOut (alpha_inv_q)),
		  fn_tee_to_Action (fn_show_cant_correct_flag, f_FIFOF_to_PipeOut (cant_correct_flag_q)),
		  fn_tee_to_Action (fn_show_lambda, f_FIFOF_to_PipeOut (lambda_out_q)));
endmodule

endpackage
