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

package ReedSolomon;

import GetPut       :: *;
import FIFOF        :: *;
import Connectable  :: *;
import SpecialFIFOs :: *;
import StmtFSM      :: *;
import PAClib       :: *;

import GFTypes        :: *;
import GFArith        :: *;

import Splitter       :: *;
import Syndrome       :: *;
import Berlekamp      :: *;
import ChienSearch    :: *;
import ErrorMagnitude :: *;
import ErrorCorrector :: *;

// ---------------------------------------------------------
// Reed-Solomon interface 
// ---------------------------------------------------------
interface IReedSolomon;
   interface Put#(Byte) rs_t_in;
   interface Put#(Byte) rs_k_in;
   interface Put#(Byte) rs_input;
   interface Get#(Byte) rs_output;
   interface Get#(Bool) rs_flag;
endinterface

// ---------------------------------------------------------
// Reed-Solomon module 
// ---------------------------------------------------------
(* synthesize *)
module mkReedSolomon (IReedSolomon);

   // ---------------- Inputs
   FIFOF #(Byte)              t_in                          <- mkPipelineFIFOF;
   FIFOF #(Byte)              k_in                          <- mkPipelineFIFOF;
   FIFOF #(Byte)              stream_in                     <- mkPipelineFIFOF;
   // ---------------- Stage 0 (Splitter)
   match { .k_to_splitter, .k_to_stage_1 } <- mkForkAndBufferRight (f_FIFOF_to_PipeOut (k_in));
   match { .t_to_splitter, .t_to_stage_1 } <- mkForkAndBufferRight (f_FIFOF_to_PipeOut (t_in));
   match { .n_to_syndrome, .r_to_syndrome, .r_to_errorcor } <- mkSplitter (k_to_splitter,
									   t_to_splitter,
									   f_FIFOF_to_PipeOut (stream_in));
   // ---------------- Stage 1 (Syndrome)
   PipeOut #(Byte)              k_to_stage_3 <- mkBuffer_n (2, k_to_stage_1);
   PipeOut #(Byte)              t_to_stage_2 <- mkBuffer (t_to_stage_1);
   PipeOut #(Syndrome #(TwoT))  syndrome     <- mkSyndrome (n_to_syndrome, r_to_syndrome);

   PipeOut #(Byte)              r_to_stage_5 <- mkBuffer_n (3 * max_block_size, r_to_errorcor);

   // ---------------- Stage 2 (Berlekamp)
   match { .t_to_berl, .t_to_stage_3 }       <- mkForkAndBufferRight (t_to_stage_2);
   match { .berl_deg_out, .berl_no_error_flag_out, .berl_lambda_out, .berl_omega_out } <- mkBerlekamp (t_to_berl, syndrome);
   // ---------------- Stage 3 (Chien Search)
   match { .k_to_chien, .k_to_stage_4 } <- mkForkAndBufferRight (k_to_stage_3);
   match { .no_error_flag_to_chien, .no_error_flag_to_stage_4 } <- mkForkAndBufferRight (berl_no_error_flag_out);
   match {.chien_loc_out,
	  .chien_alpha_inv_out,
	  .chien_cant_correct_flag_out,
	  .chien_lambda_out }           <- mkChienSearch (t_to_stage_3,
							  k_to_chien,
							  no_error_flag_to_chien,
							  berl_lambda_out,
						  	  berl_deg_out);
   PipeOut #(Syndrome #(T)) omega_to_errmag <- mkBuffer (berl_omega_out);
   // ---------------- Stage 4 (Error Magnitude)
   match { .k_to_errmag, .k_to_stage_5 } <- mkForkAndBufferRight (k_to_stage_4);
   match { .no_error_flag_to_errmag, .no_error_flag_to_stage_5 } <- mkForkAndBufferRight (no_error_flag_to_stage_4);
   PipeOut #(Byte)  error_magnitude  <- mkErrorMagnitude (k_to_errmag,
							  no_error_flag_to_errmag,
							  chien_loc_out,
							  chien_alpha_inv_out,
							  chien_lambda_out,
							  omega_to_errmag);
   // ---------------- Stage 5 (Error Corrector)
   PipeOut #(Byte)   error_corrector   <- mkErrorCorrector (r_to_stage_5,
							    error_magnitude,
							    k_to_stage_5,
							    no_error_flag_to_stage_5);
   // ----------------------------------
   interface Put rs_t_in     = toPut (t_in);
   interface Put rs_k_in     = toPut (k_in);
   interface Put rs_input    = toPut (stream_in);

   interface Get rs_flag     = toGet (chien_cant_correct_flag_out); // (cant_correct_out);
   interface Get rs_output   = toGet (error_corrector); // (stream_out);
endmodule

endpackage
