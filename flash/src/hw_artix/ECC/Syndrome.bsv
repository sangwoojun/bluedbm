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

package Syndrome;

import Vector       :: *;
import FIFOF        :: *;
import SpecialFIFOs :: *;
import PAClib       :: *;
import FShow        :: *;

import GFArith      :: *;
import GFTypes      :: *;

// ---------------------------------------------------------
// Reed-Solomon Syndrome calculation module 
// ---------------------------------------------------------

module mkSyndrome
   #(PipeOut #(Byte) n_in, PipeOut #(Byte) ri_in)
   (PipeOut #(Syndrome #(TwoT)));

   Reg #(Byte)             i              <- mkReg (0);
   Reg #(Syndrome #(TwoT)) syndrome       <- mkReg (replicate (0));
   Reg #(Byte)             block_number   <- mkReg (1);    // just for info displays

   FIFOF #(Syndrome #(TwoT)) syndrome_out <- mkPipelineFIFOF;

   function Byte f_sj (Integer j) = gf_add (times_alpha_n (syndrome [j],
							   fromInteger (j+1)),
					    ri_in.first);

   rule rl_for_i_0_to_n_minus_1;
      if (i == 0) $display ("  [syndrome_in %0d]  n_in : %0d", block_number, n_in.first);
      $display ("  [syndrome_in %0d]  r_in (%0d): %h", block_number, i, ri_in.first);
      
      Syndrome #(TwoT) new_syndrome = genWith (f_sj);
      ri_in.deq;
      if (i < (n_in.first - 1)) begin
	 syndrome <= new_syndrome;
	 i <= i + 1;
      end
      else begin
	 $display ("  [syndrome_out %0d]  s_out", block_number, fshow (new_syndrome));
	 syndrome_out.enq (new_syndrome);
	 n_in.deq;
	 i <= 0;
	 syndrome <= replicate (0);
	 block_number <= block_number + 1;
      end
   endrule

   // ----------------
   return f_FIFOF_to_PipeOut (syndrome_out);
endmodule

endpackage
