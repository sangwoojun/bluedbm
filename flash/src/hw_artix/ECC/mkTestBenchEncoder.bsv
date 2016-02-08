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

import GetPut::*;
import Vector::*;
import GFTypes::*;
import FIFO::*;
import Assert::*;
import RegFile::*;

import RSEncoder::*;

import "BDPI" function Action loadByteStream ();
import "BDPI" function ActionValue# (Byte) getNextStreamByte ();
import "BDPI" function Action storeByteStream ();
import "BDPI" function Action putNextStreamByte (Byte writeByte);
import "BDPI" function Action putMACData (Byte n, Byte t);
import "BDPI" function ActionValue# (Byte) isStreamActive ();
import "BDPI" function Action closeOutputFile ();
		 
//Polynomial 	primitive_Sypolynomial = 8'b00011101;
		 
module mkTestBenchEncoder (Empty);

   // Define Primitive polynomial
   // P (x) = x**8 + x**4 + x**3 + x**2 + 1 = 0  ; Ignore highest degree (8)
   RSEncoderIfc      rs_enc         <- mkRSEncoder;

   Reg# (Bool)       read_done      <- mkReg (False);
   Reg# (int)        bytes_in       <- mkReg (0);
   Reg# (Bit#(32))   bytes_out      <- mkReg (0);
   Reg# (Bit#(32))   last_bytes_out <- mkReg (0);
   Reg# (int)        last_bytes_in  <- mkReg (0);
   Reg# (int)        watchdog       <- mkReg (0);
   Reg# (Bool)       finished       <- mkReg (False);
   Reg# (int)        state          <- mkReg (0);
   Reg# (Byte)       bytes_in_block <- mkReg (0);
   Reg# (Byte)       t              <- mkReg (0);
   Reg# (Byte)       n              <- mkReg (0);
   Reg# (Bit#(32))   bytes_out_exp  <- mkReg (0);

   FIFO#(Bit#(32))   ff_bytes_out_exp     <- mkSizedFIFO (10);
   FIFO#(Byte)       ff_n                 <- mkSizedFIFO (10);
   FIFO#(Byte)       ff_t                 <- mkSizedFIFO (10);
 

   // ----------------------------------
   // For debugging information only

   Reg#(Bit#(32)) cycle_count          <- mkReg (0);
   rule cycle;
      $display ("%0d: (TestBench)  -------------------------", cycle_count);
      cycle_count <= cycle_count + 1;
   endrule
   
   // -------------------------------------------
   rule init (state==0);
      $display ("%0d: (TestBench) init", cycle_count);
      loadByteStream ();
      storeByteStream ();
      state <= 1;
   endrule
   

	rule input_control_info (state == 1);
		let k_in <-  getNextStreamByte();
		rs_enc.rs_k_in.put(k_in);
		bytes_out_exp <= zeroExtend(k_in + 2 * fromInteger(valueOf(T)));
		state <= 2;
	endrule

   // -------------------------------------------
	/*
   rule input_control_info (state == 1 && read_done == False && bytes_in_block == fromInteger(valueOf(K)));

      //let n_in <- getNextStreamByte ();
      //let t_in <- getNextStreamByte ();
      let not_eof <- isStreamActive ();

      if (not_eof != 0)
      begin
         //n <= n_in;
         //t <= t_in;
         bytes_in_block <= 0;
         
         //rs.rs_t_in.put (t_in);
         //rs.rs_k_in.put (n_in - 2*t_in);

         //Byte temp = n_in - 2*t_in;
         //bytes_out_exp <= bytes_out_exp + zeroExtend(temp);
			bytes_out_exp <= max_block_size; //255

         //ff_bytes_out_exp.enq (bytes_out_exp);
         //ff_n.enq (n_in);
         //ff_t.enq (t_in);

         //$display ("%0d: (TestBench) [mac in] n = %d, t = xx, k = %d", cycle_count, n_in, n_in - 2*t_in);
      end
      else
      begin
         read_done <= True;
         $display ("%0d: (TestBench) [reads done] bytes in : %d", cycle_count, bytes_in - 1);
      end
   endrule
	*/

   // -------------------------------------------
   rule input_data (state == 2 && read_done == False);
      Byte not_eof <- isStreamActive ();
      if (not_eof != 0)
      begin
         Byte datum <- getNextStreamByte ();
         rs_enc.rs_enc_in.put (datum);

         bytes_in_block <= bytes_in_block + 1;

         // the way getNextStreamByte operates, we'll get one more character
         // than what is in the input file. So we need to adjust for this in
         // the way we use bytes_in...                                      
         bytes_in <= bytes_in + 1;
         $display ("%0d: (TestBench) [bytes in]  byte (%d) = %d, block bytes %d", cycle_count, bytes_in, datum, bytes_in_block);
      end
      else
      begin
         read_done <= True;
         $display ("%0d: (TestBench) [reads done] bytes in : %d", cycle_count, bytes_in - 1);
      end
   endrule


   // -------------------------------------------
   rule output_data (state == 2);
      Byte  next_byte <- rs_enc.rs_enc_out.get ();
      putNextStreamByte (next_byte);
      bytes_out <= bytes_out + 1;
      $display ("%0d: (TestBench) [bytes out]  %d / %d", cycle_count, bytes_out, bytes_out_exp);
   endrule


   // -------------------------------------------
   rule watchdog_timer (state == 2);
      if ((last_bytes_out == bytes_out) &&
          (last_bytes_in == bytes_in))
         watchdog <= watchdog + 1;
      else
      begin
         last_bytes_in <= bytes_in;
         last_bytes_out <= bytes_out;
         watchdog <= 0;
      end

      if (watchdog == 2000)
      begin
         $display ("%0d: (TestBench) [WARNING]  Watchdog timer expired.", cycle_count);
         $display ("                 There has been no output in the last 2000 clock cycles; exiting.");

         closeOutputFile ();
         $finish (0);
      end
   endrule


   // -------------------------------------------
   rule exit (read_done == True && bytes_out==bytes_out_exp);
      closeOutputFile ();
      $display ("%0d: (TestBench) [bytes written] %d", cycle_count, bytes_out);
      $finish (0);
   endrule
		 
endmodule
