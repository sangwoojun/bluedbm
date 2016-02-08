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

package Splitter;

import Vector       :: *;
import FIFOF        :: *;
import SpecialFIFOs :: *;
import StmtFSM      :: *;
import PAClib       :: *;

import GFTypes        :: *;
import GFArith        :: *;

// ----------------------------------------------------------------
// Splits/copies data stream for Syndrome and ErrorCorrector modules

module mkSplitter
   #(PipeOut #(Byte) k_in,
     PipeOut #(Byte) t_in,
     PipeOut #(Byte) r_in)
   (Tuple3 #(PipeOut #(Byte),        // n to syndrome
	     PipeOut #(Byte),        // r to syndrome
	     PipeOut #(Byte)));      // r to errorcor

   Reg #(Byte)      rg_k <- mkRegU;
   Reg #(Byte)      rg_n <- mkRegU;
   Reg #(Bit #(9))  rg_i <- mkRegU;

   // Output fifos
   FIFOF #(Byte) ff_n_to_syndrome <- mkPipelineFIFOF;
   FIFOF #(Byte) ff_r_to_syndrome <- mkPipelineFIFOF;
   FIFOF #(Byte) ff_r_to_errorcor <- mkPipelineFIFOF;

   mkAutoFSM (
      seq
	 while (True) seq
	    action    // Get k and t.    Note: n = k + 2t
	       let  k = k_in.first; k_in.deq;
	       let  t = t_in.first; t_in.deq;
	       Byte n = k + 2 * t;
	       rg_k <= k;
	       rg_n <= n;
	       rg_i <= 0;
	       ff_n_to_syndrome.enq (n);
	       $display ("  [reedsol] read_mac z = %d, k = %d, t = %d", 255 - k - 2*t, k, t);
	    endaction
	    while (rg_i < extend (rg_k)) action    // data bytes to both syndrome and errorcorrector modules
	       let datum = r_in.first; r_in.deq;
	       ff_r_to_syndrome.enq (datum);
	       ff_r_to_errorcor.enq (datum);
	       $display ("  [reedsol]  read_input [%d] = %d", (extend (rg_k) - rg_i), datum);
	       rg_i <= rg_i + 1;
	    endaction
	    while (rg_i < extend (rg_n)) action    // parity bytes only to syndrome module
	       let datum = r_in.first; r_in.deq;
	       ff_r_to_syndrome.enq (datum);
	       $display ("  [reedsol]  read_parity [%d] = %d", (extend (rg_n) - rg_i), datum);
	       rg_i <= rg_i + 1;
	    endaction
	 endseq
      endseq
      );

   return (tuple3 (f_FIFOF_to_PipeOut (ff_n_to_syndrome),
		   f_FIFOF_to_PipeOut (ff_r_to_syndrome),
		   f_FIFOF_to_PipeOut (ff_r_to_errorcor)));
endmodule

endpackage
