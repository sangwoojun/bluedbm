// The MIT License

// Copyright (c) 2014 Massachusetts Institute of Technology

// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:

// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

// Author: Richard Uhler ruhler@mit.edu
// Modified by: Shuotao Xu shuotao@mit.edu

import Clocks::*;
import FIFO::*;
import Vector::*;
import RegFile::*;

//import XilinxVC707DDR3::*;

typedef Bit#(29) DDR3Address;
typedef Bit#(64) ByteEn;
typedef Bit#(512) DDR3Data;

interface DDR3_User_VC707_Sim;
   interface Clock clock;
   interface Reset reset_n;
   method Bool init_done;
   method Action request(DDR3Address addr, ByteEn writeen, DDR3Data datain);
   method ActionValue#(DDR3Data) read_data;
endinterface
     

module mkDDR3Simulator(DDR3_User_VC707_Sim);
   RegFile#(Bit#(26), DDR3Data) data <- mkRegFileFull();
   FIFO#(DDR3Data) responses <- mkFIFO();
   
   Clock user_clock <- exposeCurrentClock;
   Reset user_reset_n <- exposeCurrentReset;
   
   // Rotate 512 bit word by offset 64 bit words.
   function Bit#(512) rotate(Bit#(3) offset, Bit#(512) x);
      Vector#(8, Bit#(64)) words = unpack(x);
      Vector#(8, Bit#(64)) rotated = rotateBy(words, unpack((~offset) + 1));
      return pack(rotated);
   endfunction
   
       // Unrotate 512 bit word by offset 64 bit words.
   function Bit#(512) unrotate(Bit#(3) offset, Bit#(512) x);
      Vector#(8, Bit#(64)) words = unpack(x);
      Vector#(8, Bit#(64)) unrotated = rotateBy(words, unpack(offset));
      return pack(unrotated);
          endfunction
   
   interface clock = user_clock;
   interface reset_n = user_reset_n;
   method Bool init_done() = True;
   
   method Action request(DDR3Address addr, ByteEn writeen, DDR3Data datain);
      Bit#(26) burstaddr = addr[28:3];
      Bit#(3) offset = addr[2:0];
      
      Bit#(512) mask = 0;
      for (Integer i = 0; i < 64; i = i+1) begin
         if (writeen[i] == 'b1) begin
            mask[(i*8+7):i*8] = 8'hFF;
         end
      end
      
      Bit#(512) old_rotated = rotate(offset, data.sub(burstaddr));
      Bit#(512) new_masked = mask & datain;
      Bit#(512) old_masked = (~mask) & old_rotated;
      Bit#(512) new_rotated = new_masked | old_masked;
      Bit#(512) new_unrotated = unrotate(offset, new_rotated);
      data.upd(burstaddr, new_unrotated);
      
      if (writeen == 0) begin
         responses.enq(new_rotated);
      end
   endmethod
      
   method ActionValue#(DDR3Data) read_data;
      responses.deq();
      return responses.first();
   endmethod
      
endmodule
