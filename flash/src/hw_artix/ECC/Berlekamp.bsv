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

package Berlekamp;

import FIFOF          :: *;
import SpecialFIFOs   :: *;
import UniqueWrappers :: *;
import Vector         :: *;
import PAClib         :: *;
import StmtFSM        :: *;
import FShow          :: *;

import GFArith::*;
import GFTypes::*;

// ---------------------------------------------------------
// Reed-Solomon Berlekamp module 
// ---------------------------------------------------------

module mkBerlekamp
   #(PipeOut #(Byte) t_in,  PipeOut #(Syndrome #(TwoT)) syndrome_in)
   (Tuple4 #(
		  PipeOut #(Byte),
		  PipeOut #(Bool),
	     PipeOut #(Syndrome #(T)),
	     PipeOut #(Syndrome #(T))));

   // outputs
   FIFOF #(Syndrome #(T))       c_q             <- mkPipelineFIFOF; // lambda
   FIFOF #(Syndrome #(T))       w_q             <- mkPipelineFIFOF; // omega
   FIFOF #(Byte)                l_q             <- mkPipelineFIFOF; // l (degree of lambda)
   FIFOF #(Bool)                no_error_flag_q <- mkPipelineFIFOF;
  
   // Local state
   Reg #(Byte)                  block_number    <- mkReg (0);    // for bookkeeping only
   Reg #(Byte)                  i               <- mkRegU;
   Reg #(Syndrome #(TPlusTwo))  p               <- mkRegU;
   Reg #(Syndrome #(TPlusTwo))  a               <- mkRegU;
   Reg #(Syndrome #(TPlusTwo))  c               <- mkRegU;
   Reg #(Syndrome #(TPlusTwo))  w               <- mkRegU;
   Reg #(Syndrome #(TPlusTwo))  syn_shift_reg   <- mkRegU;
   Reg #(Bool)                  no_error_flag   <- mkRegU;
   Reg #(Byte)                  l               <- mkRegU;
   Reg #(Byte)                  d               <- mkRegU;
   Reg #(Byte)                  dstar           <- mkRegU;
   Reg #(Byte)                  d_dstar         <- mkRegU;

   Action initialize_local_state = action
				      block_number  <= block_number + 1;
				      i             <= 0;
				      p             <= shiftInAt0 (replicate (0), 1);
				      a             <= shiftInAt0 (replicate (0), 1);
				      c             <= shiftInAt0 (replicate (0), 1);
				      w             <= replicate (0);
				      syn_shift_reg <= replicate (0);
				      no_error_flag <= True;
				      l             <= 0;
				      d             <= 0;
				      dstar         <= 1;
				   endaction;

   // function wrapper (for resource sharing)
   // ------------------------------------------------
   Wrapper2 #(Syndrome #(TPlusTwo),
	      Syndrome #(TPlusTwo),
	      Syndrome #(TPlusTwo))    gf_mult_vec  <- mkUniqueWrapper2 (zipWith (gf_mult_inst));
   Wrapper2 #(Syndrome #(TPlusTwo),
	      Syndrome #(TPlusTwo),
	      Syndrome #(TPlusTwo))    gf_add_vec   <- mkUniqueWrapper2 (zipWith (gf_add_inst));
   
   // define constants
   // ------------------------------------------------
   let t        = t_in.first;
   let syndrome = syndrome_in.first;

   Reg #(Syndrome #(TPlusTwo)) rg_d_vec <- mkRegU;

   // ------------------------------------------------
   mkAutoFSM (
      seq
	 initialize_local_state;
	 while (True) seq
	    while (i < (2 * t)) seq
	       action    // CALC_D
		  if (i==0) $display ("  [berlekamp_in %d] start_new_syndrome t : %d, s : ", block_number, t, fshow (syndrome));
		  let newSynShiftReg  = shiftInAt0 (syn_shift_reg, syndrome [i]);  // shift in one syndrome input to syn
		  let d_vec          <- gf_mult_vec.func (c, newSynShiftReg);      // get convolution
		  rg_d_vec           <= d_vec;

		  syn_shift_reg      <= newSynShiftReg;
		  no_error_flag      <= no_error_flag && (syndrome [i] == 0);
		  i                  <= i + 1;
	       endaction
	       action    // CALC_LAMBDA
		  let new_d           = fold ( \^ , rg_d_vec);
		  d_dstar <= gf_mult_inst (new_d, dstar);  // d_dstar = d * dstar
		  d       <= new_d;
		  p       <= shiftInAt0 (p, 0);        // increase polynomial p degree by 1
		  a       <= shiftInAt0 (a, 0);        // increase polynomial a degree by 1
	       endaction
	       if (d != 0) seq
		  action // CALC_LAMBDA_2
		     let d_dstar_p <- gf_mult_vec.func (replicate (d_dstar), p);
		     if (i > 2 * l) // p = old_c only if i + 1 > 2 * l
			p <= c;
		     let new_c <- gf_add_vec.func (c, d_dstar_p);
		     c <= new_c;
		     //$display ("  [berlekamp %0d] calc_lambda_2. c (%x) = d_d* (%x) x p (%x)", block_number, new_c, d_dstar, p);
		  endaction
		  action // CALC_LAMBDA_3
		     let d_dstar_a <- gf_mult_vec.func (replicate (d_dstar), a);
		     if (i > 2 * l) begin // a = old_w only if i + 1 > 2 * l
			a     <= w;
			l     <= i - l;
			dstar <= gf_inv (d);
		     end
		     let new_w <- gf_add_vec.func (w, d_dstar_a);
		     w <= new_w;
		     //$display ("  [berlekamp %0d] calc_lambda_3. w (%x) = d_d* (%x) x a (%x)", block_number, new_w, d_dstar, a);
		  endaction
	       endseq    // if (d != 0)
	    endseq    // while (i < (2 * t))
	    action    // loop postlude
	       t_in.deq;
	       syndrome_in.deq;
			 l_q.enq(l);
	       $display ("  [berlekamp_out %0d]  l degree: ", block_number, l);
	       no_error_flag_q.enq (no_error_flag);
	       $display ("  [berlekamp_out %0d]  no_error_flag_out : ", block_number, fshow (no_error_flag));
	       if (! no_error_flag) begin // send lambda and omega only if error
		  Syndrome #(T) lambda = take (tail (c));
		  $display ("  [berlekamp_out %0d]  lambda_out : ", block_number, fshow (lambda));
		  c_q.enq (lambda);

		  Syndrome #(T) omega = take (tail (w));
		  $display ("  [berlekamp_out %0d]  omega_out : ", block_number, fshow (omega));
		  w_q.enq (take (tail (w)));
	       end
	    endaction
	    initialize_local_state;    // for next syndrome
	 endseq // while (True)
      endseq
      );

   // ------------------------------------------------
   return tuple4 (
			f_FIFOF_to_PipeOut (l_q),
			f_FIFOF_to_PipeOut (no_error_flag_q),
			f_FIFOF_to_PipeOut (c_q),
			f_FIFOF_to_PipeOut (w_q));

endmodule

endpackage
