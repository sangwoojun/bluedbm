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

package ErrorCorrector;

import Vector       :: *;
import FIFOF        :: *;
import SpecialFIFOs :: *;
import PAClib       :: *;

import GFArith      :: *;
import GFTypes      :: *;

// ---------------------------------------------------------
// Reed-Solomon error corrector module 
// ---------------------------------------------------------

module mkErrorCorrector
   #(PipeOut #(Byte) r_in,
     PipeOut #(Byte) e_in,
     PipeOut #(Byte) k_in,
     PipeOut #(Bool) no_error_flag_in)
   (PipeOut #(Byte));

   FIFOF #(Byte)    d_out          <- mkPipelineFIFOF;

   Reg #(Byte)      e_cnt          <- mkReg(0);
   Reg #(Byte)      block_number   <- mkReg(1);

   rule rl_calc_d (e_cnt < k_in.first);
      Byte d;
      if (no_error_flag_in.first) begin
	 $display ("  [error corrector %0d] No Error processing", block_number);
	 d = r_in.first;
      end
      else begin
	 $display ("  [error corrector %0d]  Correction processing", block_number);
	 d = (r_in.first ^ e_in.first);
	 e_in.deq;
      end
      d_out.enq (d);
      $display ("  [errcor_out %0d]  d_out (%h)", block_number, d);

      r_in.deq;
      if (e_cnt == k_in.first - 1) begin
	 block_number <= block_number + 1;
         k_in.deq;
         no_error_flag_in.deq;
         e_cnt <= 0;
      end
      else
         e_cnt <= e_cnt + 1;
   endrule

   // ------------------------------------------------
   return f_FIFOF_to_PipeOut (d_out);

endmodule

endpackage
