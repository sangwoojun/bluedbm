// ****************************************************************
// Copyright (c) 2009-2011, Bluespec, Inc.  All Rights Reserved.
//
// This Bluespec SystemVerilog Library is provided by Bluespec, Inc. to
// its customers under license agreements.
//
// Version 1.2, August 19, 2011, 23:00 EDT
// ****************************************************************

package PAClib;

import FIFO              :: *;
import FIFOF             :: *;
import SpecialFIFOs      :: *;
import BRAMFIFO          :: *;
import GetPut            :: *;
import ClientServer      :: *;
import Connectable       :: *;
import Vector            :: *;
import CompletionBuffer  :: *;

// ****************************************************************
// Define FPGA_TARGET or not, as desired.
// In the FPGA case, SizedFIFOFs are implemented in BRAMs

// `define FPGA_TARGET

`ifdef FPGA_TARGET

module mkSizedFIFOF_local #(Integer n) (FIFOF #(t))
   provisos (Bits #(t, tsiz),
	     Add  #(1, _any, tsiz));
   let ifc <- mkSizedBRAMFIFOF (n);    // **** when targeting an FPGA
   return ifc;
endmodule

`else

module mkSizedFIFOF_local #(Integer n) (FIFOF #(t))
   provisos (Bits #(t, tsiz));
   let ifc <- mkSizedFIFOF (n);        // **** otherwise
   return ifc;
endmodule

`endif

// ****************************************************************
// **************** TYPES FOR PIPE OUTPUTS AND PIPES
// ****************************************************************

// ----------------------------------------------------------------
// The output of a Pipe component is the output subset of the FIFOF interface,
// with the same semantics

interface PipeOut #(type t);
   method t       first ();
   method Action  deq ();
   method Bool    notEmpty ();
endinterface

// ----------------------------------------------------------------
// A Pipe component is module with a PipeOut parameter and a Pipeout interface
// i.e., a function from Pipeout to Module #(PipeOut)

typedef (function Module #(PipeOut #(tb)) mkFoo (PipeOut #(ta) ifc))
        Pipe#(type ta, type tb);

// ----------------------------------------------------------------
// Some useful utility interface-conversion functions

function PipeOut #(a)  f_FIFOF_to_PipeOut  (FIFOF #(a) fifof);
   return (interface PipeOut;
              method a first ();
                 return fifof.first;
              endmethod
              method Action deq ();
                 fifof.deq;
              endmethod
              method Bool notEmpty ();
                 return fifof.notEmpty ();
              endmethod
           endinterface);
endfunction

module mkFIFOF_to_Pipe
                #(FIFOF #(a)    fifof,
                  PipeOut #(a)  po_in)
                (PipeOut #(a));

   rule rl_input_to_fifo;
      fifof.enq (po_in.first ());  po_in.deq ();
   endrule

   return f_FIFOF_to_PipeOut (fifof);
endmodule: mkFIFOF_to_Pipe

instance ToGet #(PipeOut #(a), a);
   function Get #(a) toGet (PipeOut #(a) po);
      return (interface Get;
                 method ActionValue #(a) get ();
                    po.deq ();
                    return po.first ();
                 endmethod
              endinterface);
   endfunction
endinstance

// ----------------------------------------------------------------
// Convert a Pipe into a server
// Adds a fifo buffer in front of the pipe

module [Module] mkPipe_to_Server
                #(Pipe #(ta, tb) pipe)
                (Server #(ta, tb))
        provisos (Bits #(ta, wd_ta));

   FIFOF #(ta)   fifof  <- mkPipelineFIFOF;
   PipeOut #(tb) po_out <- pipe (f_FIFOF_to_PipeOut (fifof));

   return (interface Server;
              interface Put request  = toPut (fifof);
              interface Get response = toGet (po_out);
           endinterface);
endmodule: mkPipe_to_Server

// ****************************************************************
// **************** SOURCES AND SINKS
// ****************************************************************

// ----------------------------------------------------------------
// Source values from an ActionValue function
// Contains a buffer to hold the value from the function

module mkSource_from_fav
                #(ActionValue #(a) f_avf)
                (PipeOut #(a))
 provisos (Bits #(a, sa));

   FIFOF #(a) fifof <- mkPipelineFIFOF;

   rule rl_source;
      let x <- f_avf ();
      fifof.enq (x);
   endrule

   return f_FIFOF_to_PipeOut (fifof);
endmodule: mkSource_from_fav

// ----------------------------------------------------------------
// Source a constant x

module mkSource_from_constant
                #(a x)
                (PipeOut #(a));
   method a first ();
      return x;
   endmethod

   method Action deq ();
      noAction;
   endmethod

   method Bool notEmpty ();
      return True;
   endmethod
endmodule: mkSource_from_constant

// ----------------------------------------------------------------
// Sinks values and discards them

module mkSink
                #(PipeOut #(a) po_in)
                (Empty);

   rule rl_drain;
      po_in.deq;
   endrule
endmodule: mkSink

// ----------------------------------------------------------------
// Sinks values into an Action function

module mkSink_to_fa
                #(function Action f_a (a x),
                  PipeOut #(a) po_in)
                (Empty);

   rule rl_drain;
      f_a (po_in.first);
      po_in.deq;
   endrule
endmodule: mkSink_to_fa

// ****************************************************************
// **************** SIMPLE PIPELINE BUFFERS
// ****************************************************************
// Simple buffers

// ----------------------------------------------------------------
// 1-stage delay buffer (asynchronous/ flow-controlled/ FIFO-like)

module mkBuffer
                #(PipeOut #(a) po_in)
                (PipeOut #(a))
 provisos (Bits #(a,sa));
   
   FIFOF #(a) fifof <- mkPipelineFIFOF;
   
   rule rl_into_buffer;
      fifof.enq (po_in.first);
      po_in.deq;
   endrule

   return f_FIFOF_to_PipeOut (fifof);
endmodule: mkBuffer

// ----------------------------------------------------------------
// n-stage delay buffer (asynchronous/ flow-controlled/ FIFO-like)

module mkBuffer_n
                #(Integer n,
                  PipeOut #(a) po_in)
                (PipeOut #(a))
`ifdef FPGA_TARGET
   provisos (Bits #(a,sa), Add  #(1,_any,sa));
`else
   provisos (Bits #(a,sa));
`endif
   
   FIFOF #(a) fifof <- mkSizedFIFOF_local (n);
   
   rule rl_into_buffer;
      fifof.enq (po_in.first);
      po_in.deq;
   endrule

   return f_FIFOF_to_PipeOut (fifof);
endmodule: mkBuffer_n

// ----------------------------------------------------------------
// 1-stage synchronous delay buffer (register-like)
// init_value is the value initial value in the buffer register

module mkSynchBuffer
                #(a             init_value,
                  PipeOut #(a)  po_in)
                (PipeOut #(a))
 provisos (Bits #(a,sa));
   
   Reg #(a) rg <- mkReg (init_value);
   
   method a first ();
      return rg;
   endmethod

   method Action deq ();
      rg <= po_in.first ();
      po_in.deq ();
   endmethod

   method Bool notEmpty ();
      return po_in.notEmpty ();
   endmethod
endmodule: mkSynchBuffer

// ----------------------------------------------------------------
// n-stage synchronous delay buffer (register-like)
// init_value is the value initial value in the buffer registers

module mkSynchBuffer_n
                #(Integer n,
                  a             init_value,
                  PipeOut #(a)  po_in)
                (PipeOut #(a))
 provisos (Bits #(a,sa));
   
   PipeOut #(a) po_out = po_in;

   for (Integer j = 0; j < n; j = j + 1)
      po_out <- mkSynchBuffer (init_value, po_out);

   return po_out;
endmodule: mkSynchBuffer_n

// ****************************************************************
// **************** WRAP COMBINATIONAL FUNCTION INTO PIPE
// ****************************************************************

// ----------------------------------------------------------------
// Wrap combinational function fn into a pipe

module mkFn_to_Pipe
                #(function tb fn (ta x),
                  PipeOut #(ta) po_in)
                (PipeOut #(tb))
 provisos (Bits #(ta, wd_ta));
		       
   method tb first ();
      return fn (po_in.first);
   endmethod

   method Action deq ();
      po_in.deq;
   endmethod

   method Bool notEmpty ();
      return po_in.notEmpty;
   endmethod
endmodule: mkFn_to_Pipe

// ----------------------------------------------------------------
// "Tee" the pipe data to an Action function afn
// i.e., apply afn to each value as it passes through.
// (The name comes from the well-known Unix shell "tee" command.)
// No additional buffering.

function PipeOut #(ta) fn_tee_to_Action (function Action  afn (ta x),
					 PipeOut #(ta) po_in)
   = interface PipeOut;
	method ta first = po_in.first;

	method Action deq;
	   afn (po_in.first);
	   po_in.deq;
	endmethod

	method Bool notEmpty = po_in.notEmpty;
     endinterface;

// ----------------------------------------------------------------
// Wrap ActionValue function fn into a pipe; always has buffer after fn

module mkAVFn_to_Pipe
                #(function ActionValue #(tb) avfn (ta x),
                  PipeOut #(ta) po_in)
                (PipeOut #(tb))
 provisos (Bits #(ta, wd_ta),
	   Bits #(tb, wd_tb));
		       
   FIFOF #(tb) fifof <- mkPipelineFIFOF;
   
   rule rl_do_avfn;
      tb y <- avfn (po_in.first);
      fifof.enq (y);
      po_in.deq;
   endrule

   return f_FIFOF_to_PipeOut (fifof);
endmodule: mkAVFn_to_Pipe

// ----------------------------------------------------------------
// Wrap combinational function fn into a pipe, with optional buffering

module mkFn_to_Pipe_Buffered
                #(Bool param_buf_before,
                  function b fn (a x),
                  Bool param_buf_after,
                  PipeOut #(a) po_in)
                (PipeOut #(b))
 provisos (Bits #(a, sa),
           Bits #(b, sb));
		       
   PipeOut #(a) pa = po_in;

   if (param_buf_before)
      pa <- mkBuffer (po_in);

   PipeOut #(b) pb <- mkFn_to_Pipe (fn, pa);

   if (param_buf_after)
      pb <- mkBuffer (pb);

   return pb;
endmodule: mkFn_to_Pipe_Buffered

// ----------------------------------------------------------------
// Wrap combinational function fn into a pipe, with optional synchronous buffering

module mkFn_to_Pipe_SynchBuffered
                #(Maybe #(a) param_buf_before,
                  function b fn (a x),
                  Maybe #(b) param_buf_after,
                  PipeOut #(a) po_in)
                (PipeOut #(b))
 provisos (Bits #(a, sa),
           Bits #(b, sb));
		       
   PipeOut #(a) pa = po_in;

   case (param_buf_before) matches
      tagged Valid .init_value_a : pa <- mkSynchBuffer (init_value_a, po_in);
      tagged Invalid           : begin end
   endcase

   PipeOut #(b) pb <- mkFn_to_Pipe (fn, pa);

   case (param_buf_after) matches
      tagged Valid .init_value_b : pb <- mkSynchBuffer (init_value_b, pb);
      tagged Invalid           : begin end
   endcase

   return pb;
endmodule: mkFn_to_Pipe_SynchBuffered

// ----------------------------------------------------------------
// "Tap" a pipe by applying an Action tap_fn_a () to each value flowing through

module mkTap
                #(function Action tap_fn_a (a x),
                  PipeOut #(a) po_in)
                (PipeOut #(a))
 provisos (Bits #(a, sa));
		       
   method a first ();
      return po_in.first;
   endmethod

   method Action deq ();
      tap_fn_a (po_in.first);
      po_in.deq;
   endmethod

   method Bool notEmpty ();
      return po_in.notEmpty ();
   endmethod
endmodule 

// ****************************************************************
// **************** FUNNELING AND UNFUNNELING
// Terminology:
//  Funneling   "serializes"   an mk-vector down to a k-stream of m-vector slices
//  Unfunneling "unserializes" a  k-stream of m-vector slices up to an mk-vector
// ****************************************************************

// ----------------------------------------------------------------
// Funnel an mk-vector down to a k-stream of m-vector slices

module mkFunnel
                #(PipeOut #(Vector #(mk, a)) po_in)
                (PipeOut #(Vector #(m, a)))

        provisos (Bits #(a, sa),
                  Add #(ignore_1, 1, mk),    // mk > 0               (assert)
                  Add #(ignore_2, 1, m),     // m > 0                (assert)
                  Add #(ignore_3, m, mk),    // m <= mk              (assert)
                  Mul #(m, k, mk),           // m * k == mk          (derive k)
                  Log #(k, logk),            // log (k) == logk      (derive logk)

                  // The following two provisos are redundant, but currently required by bsc
                  // TODO: recheck periodically if bsc improvements make these redundant
                  Mul #(mk, sa, TMul #(k, TMul #(m, sa)))
                 );

   UInt #(logk)                k_minus_1  =  fromInteger (valueof(k) - 1);
   Reg #(UInt #(logk))         index_k    <- mkReg (0);
   Vector #(k, Vector #(m, a)) values     = unpack (pack (po_in.first));

   return (interface PipeOut;
               method Vector #(m,a) first ();
                  return values [index_k];
               endmethod

               method Action deq ();
                  if (index_k == k_minus_1) begin
                     index_k <= 0;
                     po_in.deq ();
                  end
                  else
                     index_k <= index_k + 1;
               endmethod

               method Bool notEmpty ();
                  return  po_in.notEmpty ();
               endmethod
           endinterface);
endmodule: mkFunnel

// ----------------------------------------------------------------
// Funnel an mk-vector down to a k-stream of m-vector slices accompanied by their indexes

module mkFunnel_Indexed
                #(PipeOut #(Vector #(mk, a)) po_in)
                (PipeOut #(Vector #(m, Tuple2 #(a, UInt #(logmk)))))

        provisos (Bits #(a, sa),
                  Add #(ignore_1, 1, mk),    // mk > 0               (assert)
                  Add #(ignore_2, 1, m),     // m > 0                (assert)
                  Add #(ignore_3, m, mk),    // m <= mk              (assert)
                  Log #(mk, logmk),          // log (mk) == logmk    (derive logmk)
                  Mul #(m, k, mk),           // m * k == mk          (derive k)
                  Log #(k, logk),            // log (k) == logk      (derive logk)

                  // The following two provisos are redundant, but currently required by bsc
                  Bits #(Vector #(k, Vector #(m, a)), TMul #(mk, sa)),
                  Bits #(Vector #(mk, a), TMul #(mk, sa)));

   UInt #(logk) k_minus_1 = fromInteger (valueof(k) - 1);

   // This function pairs each input vector element with an index, starting from base
   function Vector #(n, Tuple2 #(a, UInt #(logmk)))
            attach_indexes_from_base (UInt #(logmk) base, Vector #(n, a)  xs);

      function UInt #(logmk) add_base (Integer j) = (base + fromInteger (j));

      let indexes     = genWith (add_base);   // {base,base+1,...,base+n-1}
      let x_index_vec = zip (xs, indexes);    // {(x0,base),(x1,base+11),...,(xmk-1,base+n-1)}
      return x_index_vec;
   endfunction: attach_indexes_from_base

   Reg #(UInt #(logk))                index_k    <- mkReg (0);
   Reg #(UInt #(logmk))               index_mk   <- mkReg (0);

   return (interface PipeOut;
               method Vector #(m, Tuple2 #(a, UInt #(logmk))) first ();
                  Vector #(k, Vector #(m, a)) k_vec_m_vec = unpack (pack (po_in.first ()));
                  return attach_indexes_from_base (index_mk, k_vec_m_vec [index_k]);
               endmethod

               method Action deq ();
                  if (index_k == k_minus_1) begin
                     po_in.deq ();
                     index_k <= 0;
                     index_mk <= 0;
                  end
                  else begin
                     index_k <= index_k + 1;
                     index_mk <= index_mk + fromInteger (valueof (m));
                  end
               endmethod

               method Bool notEmpty ();
                  return po_in.notEmpty ();
               endmethod
           endinterface);
endmodule: mkFunnel_Indexed

// ----------------------------------------------------------------
// Unfunnel a k-stream of m-vector slices up to an mk-vector
// When k > 1, of course one needs buffering
// When k==1, it is conceptually the identity function and buffering is optional
//            and the parameter 'state_if_k_is_1' controls whether to insert a buffer or not

module mkUnfunnel
                #(Bool                      state_if_k_is_1,
                  PipeOut #(Vector #(m,a))  po_in)
                (PipeOut #(Vector #(mk, a)))

        provisos (Bits #(a, sa),
                  Add #(ignore_1, 1, mk),    // assert mk > 0
                  Add #(ignore_2, 1, m),     // assert m > 0
                  Add #(ignore_3, m, mk),    // m <= mk
                  Log #(mk, logmk),          // derive logmk
                  Mul #(m, k, mk));          // derive k
   
   if ((valueof (k) == 1) && (! state_if_k_is_1)) begin
      // ---- Here, m == mk, and don't allocate any registers (bypass straight through)

      function Vector #(mk, a)  f_pseudo_extend (Vector #(m, a)  xs);
          // The following is to appease the typechecker because in general m != mk
          // The 'newVector' below will be empty
          return append (xs, newVector);
      endfunction

      let ifc <- mkFn_to_Pipe (f_pseudo_extend, po_in);
      return ifc;
   end

   else begin
      // ---- Here, m < mk (or m==mk and  'state_if_k_is_1'  is True)

      Vector #(k, Reg #(Vector #(m, a)))  values     <- replicateM (mkRegU);
      Reg #(UInt #(logmk))                index      <- mkReg (0);
      Reg #(Bool)                         full       <- mkReg (False);
      Wire #(Bool)                        is_getting <- mkDWire (False);
      Wire #(Bool)                        is_putting <- mkDWire (False);
   
      UInt #(logmk) k_minus_1 = fromInteger (valueof(k) - 1);

      function Action fa_update_state (UInt #(logmk) put_ix);
         action
            index <= ((put_ix == k_minus_1 ? 0 : put_ix+1));
            full  <= (put_ix == k_minus_1);
         endaction
      endfunction

      (* fire_when_enabled, no_implicit_conditions *)
      rule rUpdate_state;
         if (is_getting && is_putting)
            fa_update_state (0);

         else if (is_putting)
            fa_update_state (index);

         else if (is_getting)
            full <= False;
      endrule

      rule rl_receive ((! full) || is_getting);
         values [index] <= po_in.first ();
         po_in.deq ();
         is_putting <= True;
      endrule

      return (interface PipeOut;
                 method Vector #(mk, a) first () if (full);
                    Vector #(k, Vector #(m,a)) ys = readVReg (values);
                    Vector #(mk, a) result = concat (ys);
                    return  result;
                 endmethod

                 method Action deq () if (full);
                    is_getting <= True;
                 endmethod

                 method Bool notEmpty ();
                    return full;
                 endmethod
              endinterface);
   end
endmodule: mkUnfunnel

// ****************************************************************
// **************** MAPS (PARALLEL POINTWISE APPLICATIONS)
// ****************************************************************

// ----------------------------------------------------------------
// Note: PAClib does not contain a mkMap_fn module because it's easily
// defined with mkFn_to_Pipe:
//
//    mkMap_fn (f) == mkFn_to_Pipe (map (f));
//
// It is functionally equivalent to:   mkMap_pipe (mkFn_to_Pipe (f))
// but a little cheaper since mkMap_pipe also instantiates n BypassFIFOs (see below)

// ----------------------------------------------------------------
// Make a pipe that maps pipe mkP over an n-vector
// I.e., each datum from an input n-vector is fed through a copy of mkP
// and the results are collected in an output n-vector
// The latencies of the different mkP pipes can vary, and can be dynamically data-dependent,
// but if each mkP (is assumed to) maintain FIFO order, the vectors will be in sync

module [Module] mkMap
                #(Pipe #(a,b) mkP,
                  PipeOut #(Vector #(n, a)) po_in)

                (PipeOut #(Vector #(n, b)))

        provisos (Bits #(a, sa));
			    
   Vector #(n, FIFO #(Bit #(0))) taken_signals <- replicateM (mkBypassFIFO);

   rule rl_deq;
      po_in.deq ();
      for (Integer j = 0; j < valueof (n); j = j + 1)
         taken_signals [j].deq;
   endrule

   Vector #(n, PipeOut #(b)) povb = newVector;

   for (Integer j = 0; j < valueof (n); j = j + 1) begin
      PipeOut #(a) ifcj = interface PipeOut;
                             method a first ();
                                return po_in.first [j];
                             endmethod

                             method Action deq ();
                                taken_signals [j].enq (?);
                             endmethod

                             method Bool notEmpty ();
                                return ?;    // don't care
                             endmethod
                          endinterface;

      povb [j] <- mkP (ifcj);
   end

   method Vector #(n, b) first ();
      function b get_first (PipeOut #(b) po) = po.first ();
      return map (get_first, povb);
   endmethod

   method Action deq ();
      for (Integer j = 0; j < valueof (n); j = j + 1)
         povb[j].deq ();
   endmethod

   method Bool notEmpty ();
      return po_in.notEmpty ();
   endmethod
endmodule: mkMap

// ----------------------------------------------------------------
// Make pipe that maps pipe mkP over an mk-vector
// I.e., each datum from the input mk-vector is fed through a copy of mkP
// and the results are collected in the output mk-vector
// The input mk-vector is funneled into a k-stream of m-vectors accompanied by their indexes
//        param_buf_funnel specifies if a buffer is desired when k = 1
// Applies m copies of mkP in parallel
// Unfunnels the k-stream of m-vector results into an mk-vector
//        param_buf_unfunnel specifies if a buffer is desired when k = 1

module [Module] mkMap_with_funnel_indexed
                #(UInt #(m) dummy_m,    // Only used to pass 'm'; dummy_m is ignored
                  Pipe #(Tuple2 #(a, UInt #(logmk)), b) mkP,
                  Bool param_buf_unfunnel,
                  PipeOut #(Vector #(mk, a)) po_in)
                (PipeOut #(Vector #(mk, b)))

        provisos (Bits #(a, sa),
                  Bits #(b, sb),
                  Mul #(m,k,mk),                        // derive k
                  Log #(mk, logmk),                     // derive logmk

                  Bits #(Vector #(k, Vector #(m, a)), TMul #(mk, sa)),
                  Bits #(Vector #(mk, a), TMul #(mk, sa)),

                  Add #(_ignore1, 1, m),                // assert 1 <= m
                  Add #(_ignore2, 1, mk),               // assert 1 <= mk
                  Add #(_ignore3, m, mk));              // assert m <= mk

   if (valueof (m) * valueof (k) != valueof (mk))
      errorM ("mkMap_with_funnel_indexed: m ("   + integerToString (valueof (m))  + ")"
                                    + " * k ("   + integerToString (valueof (k))  + ")"
                                    + " != mk (" + integerToString (valueof (mk)) + ")");

   // ---- Funnel mk-vec into k-stream of m-vecs with indexes (k x m = mk)
   PipeOut #(Vector #(m, Tuple2 #(a, UInt #(logmk))))
      funnel <- mkFunnel_Indexed (po_in);

   // ---- Do the mapping
   PipeOut #(Vector #(m, b))
      mapping <- mkMap (mkP, funnel);

   // ---- Unfunnel k-stream of m-vecs into mk-vec
   PipeOut #(Vector #(mk, b))
      unfunnel <- mkUnfunnel (param_buf_unfunnel, mapping);

   return  unfunnel;
endmodule: mkMap_with_funnel_indexed

// ----------------------------------------------------------------
// The following is functionally equivalent to useing mkMap_with_funnel_indexed,
// but a little cheaper because for the embedded mapping, it just uses map(fn)
// instead of mkMap, which is slightly cheaper (see comment at mkMap)

// Make pipe that maps function fn() over an mk-vector
// I.e., each datum from the input mk-vector is fed through a copy of fn()
// and the results are collected in the output mk-vector
// The input mk-vector is funneled into a k-stream of m-vectors accompanied by their indexes
//        param_buf_funnel specifies if a buffer is desired when k = 1
// Applies m copies of mkP in parallel
// Unfunnels the k-stream of m-vector results into an mk-vector
//        param_buf_unfunnel specifies if a buffer is desired when k = 1

module [Module] mkMap_fn_with_funnel_indexed
                #(UInt #(m) dummy_m,    // Only used to pass 'm'; dummy_m is ignored
                  function b fn (Tuple2 #(a, UInt #(logmk)) xj),
                  Bool param_buf_unfunnel,
                  PipeOut #(Vector #(mk, a)) po_in)
                (PipeOut #(Vector #(mk, b)))

        provisos (Bits #(a, sa),
                  Bits #(b, sb),
                  Mul #(m,k,mk),                        // derive k
                  Log #(mk, logmk),                     // derive logmk

                  Bits #(Vector #(k, Vector #(m, a)), TMul #(mk, sa)),
                  Bits #(Vector #(mk, a), TMul #(mk, sa)),

                  Add #(_ignore1, 1, m),                // assert 1 <= m
                  Add #(_ignore2, 1, mk),               // assert 1 <= mk
                  Add #(_ignore3, m, mk));              // assert m <= mk

   if (valueof (m) * valueof (k) != valueof (mk))
      errorM ("mkMap_with_funnel_indexed: m ("   + integerToString (valueof (m))  + ")"
                                    + " * k ("   + integerToString (valueof (k))  + ")"
                                    + " != mk (" + integerToString (valueof (mk)) + ")");

   // ---- Funnel mk-vec into k-stream of m-vecs with indexes (k x m = mk)
   PipeOut #(Vector #(m, Tuple2 #(a, UInt #(logmk))))
      funnel <- mkFunnel_Indexed (po_in);

   // ---- Do the mapping
   PipeOut #(Vector #(m, b))
      mapping <- mkFn_to_Pipe (map (fn), funnel);

   // ---- Unfunnel k-stream of m-vecs into mk-vec
   PipeOut #(Vector #(mk, b))
      unfunnel <- mkUnfunnel (param_buf_unfunnel, mapping);

   return  unfunnel;
endmodule: mkMap_fn_with_funnel_indexed

// ****************************************************************
// **************** FORKS AND JOINS
// ****************************************************************

// ----------------------------------------------------------------
// mkFork
// Fork an input stream into two output streams
//     fork_fn is used to split each input item va into two output items (vb,vc)

module mkFork
                #(function Tuple2 #(b, c) fork_fn (a va),
                  PipeOut #(a) poa)
                (Tuple2 #(PipeOut #(b), PipeOut #(c)));

   FIFOF #(Bit #(0)) vb_taken_signal <- mkBypassFIFOF;
   FIFOF #(Bit #(0)) vc_taken_signal <- mkBypassFIFOF;

   rule rl_deq;
      poa.deq ();
      vb_taken_signal.deq ();
      vc_taken_signal.deq ();
   endrule

   match { .vb, .vc } = fork_fn (poa.first ());

   PipeOut #(b) pob = interface PipeOut;
                         method b first() if (vb_taken_signal.notFull);
                            return vb;
                         endmethod
                         method Action deq;
                            vb_taken_signal.enq (?);
                         endmethod
                         method Bool notEmpty;
                            return poa.notEmpty && vb_taken_signal.notFull;
                         endmethod
                      endinterface;

   PipeOut #(c) poc = interface PipeOut;
                         method c first() if (vc_taken_signal.notFull);
                            return vc;
                         endmethod
                         method Action deq;
                            vc_taken_signal.enq (?);
                         endmethod
                         method Bool notEmpty;
                            return poa.notEmpty && vc_taken_signal.notFull;
                         endmethod
                      endinterface;

   return tuple2 (pob, poc);
endmodule: mkFork

// ----------------------------------------------------------------
// mkFork2
// Fork an input stream into two output streams
//     fork_fn is used to split each input item va into two output items (vb,vc)

module mkFork2
                #(function Tuple2 #(b, c) fork_fn (a va),
                  PipeOut #(a) poa)
                (Tuple2 #(PipeOut #(b), PipeOut #(c)))
   provisos (Bits #(a, sa),
	     Bits #(b, sb),
	     Bits #(c, sc));

   FIFOF #(b) fifo_b <- mkPipelineFIFOF;
   FIFOF #(c) fifo_c <- mkPipelineFIFOF;

   rule rl_deq;
      match { .vb, .vc } = fork_fn (poa.first); poa.deq;
      fifo_b.enq (vb);
      fifo_c.enq (vc);
   endrule

   PipeOut #(b) pob = f_FIFOF_to_PipeOut (fifo_b);
   PipeOut #(c) poc = f_FIFOF_to_PipeOut (fifo_c);
   return tuple2 (pob, poc);
endmodule: mkFork2

// ----------------------------------------------------------------
// mkForkVector
// Fork an input stream into a vector of output streams (replicating input data)

module mkForkVector
                #(PipeOut #(a) po)
                (Vector #(n, PipeOut #(a)));

   Vector #(n, FIFOF #(Bit #(0))) v_taken_signal <- replicateM (mkBypassFIFOF);

   rule rl_deq;
      po.deq ();
      for (Integer j = 0; j < valueOf (n); j = j + 1)
	 v_taken_signal [j].deq ();
   endrule

   function PipeOut #(a) gen_fn (Integer j) = interface PipeOut;
						 method a first () if (v_taken_signal [j].notFull);
						    return po.first;
						 endmethod
						 method Action deq ();
						    v_taken_signal [j].enq (?);
						 endmethod
						 method Bool notEmpty ();
						    return po.notEmpty () && v_taken_signal [j].notFull;
						 endmethod
					      endinterface;
   return genWith (gen_fn);
endmodule: mkForkVector

// ----------------------------------------------------------------
// mkExplodeVector
// Explode an input stream of vectors into a vector of output streams

module mkExplodeVector
                #(PipeOut #(Vector #(n, a)) po)
                (Vector #(n, PipeOut #(a)));

   Vector #(n, FIFO #(Bit #(0))) v_taken_signal <- replicateM (mkBypassFIFO);

   rule rl_deq;
      po.deq ();
      for (Integer j = 0; j < valueOf (n); j = j + 1)
	 v_taken_signal [j].deq ();
   endrule

   function PipeOut #(a) gen_fn (Integer j) = interface PipeOut;
						 method a first ();
						    return po.first [j];
						 endmethod
						 method Action deq ();
						    v_taken_signal [j].enq (?);
						 endmethod
						 method Bool notEmpty ();
						    return po.notEmpty ();
						 endmethod
					      endinterface;
   return genWith (gen_fn);
endmodule: mkExplodeVector

// ----------------------------------------------------------------
// mkForkAndBufferRight
// Forks an input into two, and buffers one of them
// I.e., allows a copy of the data to be used in current stage (left, unbuffered)
//       and also forwarded to the next stage (right, buffered),
//       a common structure in pipelines

module mkForkAndBufferRight
   #(PipeOut #(a) poa)
   (Tuple2 #(PipeOut #(a), PipeOut #(a)))
   provisos (Bits #(a, sa));

   Vector #(2, PipeOut #(a)) forked <- mkForkVector (poa);
   PipeOut #(a)              right  <- mkBuffer (forked [1]);
   return tuple2 (forked [0], right);
endmodule

// ----------------------------------------------------------------
// mkJoin
// Join two input streams into one output stream
//     join_fn is used to combine two input items (va,vb) into an output item vc

module mkJoin
                #(function c join_fn (a va, b vb),
                  PipeOut #(a) poa,
                  PipeOut #(b) pob)
                (PipeOut #(c));

   method c first ();
      return join_fn (poa.first (), pob.first ());
   endmethod

   method Action deq ();
      poa.deq ();
      pob.deq ();
   endmethod

   method Bool notEmpty ();
      return (poa.notEmpty () && pob.notEmpty ());
   endmethod
endmodule: mkJoin

// ****************************************************************
// **************** LINEAR PIPES
// ****************************************************************

// ----------------------------------------------------------------
// Compose two pipes into a single pipe

module [Module] mkCompose
                #(Pipe #(a, b) pab,
                  Pipe #(b, c) pbc,
                  PipeOut #(a) pa)
                (PipeOut #(c));

   PipeOut #(b) pb <- pab (pa);
   PipeOut #(c) pc <- pbc (pb);
   return pc;
endmodule

// ----------------------------------------------------------------
// Compose two pipes into a single pipe
//     param_with_buffer specifies whether there should be an intervening buffer

module [Module] mkCompose_buffered
                #(Bool param_with_buffer,
                  Pipe #(a, b) pab,
                  Pipe #(b, c) pbc,
                  PipeOut #(a) pa)
                (PipeOut #(c))
        provisos (Bits #(b, sb));

   PipeOut #(b) pb <- pab (pa);

   if (param_with_buffer)
      pb <- mkBuffer (pb);

   PipeOut #(c) pc <- pbc (pb);
   return pc;
endmodule

// ----------------------------------------------------------------
// Build a linear pipeline of n stages (_S is for 'static index')
// The stage index (0..n-1) is a static input (parameter) to mkStage()

module [Module] mkLinearPipe_S
                #(Integer n,
                  function Pipe #(a,a) mkStage (UInt #(logn) j),
                  PipeOut #(a) po_in)
                (PipeOut #(a));

   if (n < 1)
      errorM ("mkLinearPipe_S: iteration count parameter < 1: " + integerToString (n));

   if (n >= (2 ** valueof (logn)))
      errorM ("mkLinearPipe_S: iteration count (" + integerToString (n) +
              ") will not fit in available bits: " + integerToString (valueof (logn)));

   PipeOut #(a) po_out = po_in;

   for (Integer j = 0; j < n; j = j + 1)
      po_out <- mkStage (fromInteger (j), po_out);

   return po_out;
endmodule: mkLinearPipe_S

// ----------------------------------------------------------------
// Build a linear pipeline of n stages (_D is for 'dynamic index')
// The stage index (0..n-1) is a dynamic input to mkStage()
// mkStage takes a 2-tuple (j,x) as input, where j is the stage index and x is data
// TODO: NOT YET TESTED

module [Module] mkLinearPipe_D
                #(Integer n,
                  function Pipe #(Tuple2 #(a, UInt #(logn)), a) mkStage (),
                  PipeOut #(a) po)
                (PipeOut #(a));

   if (n < 0)
      errorM ("mkLinearPipe_D: iteration count parameter < 0: " + integerToString (n));

   if (n >= (2 ** valueof (logn)))
      errorM ("mkLinearPipe_D: iteration count (" + integerToString (n) +
              ") will not fit in available bits: " + integerToString (valueof (logn)));

   PipeOut #(a) po_out = po;

   for (Integer j = 0; j < n; j = j + 1) begin

      PipeOut #(UInt #(logn)) po_const_j <- mkSource_from_constant (fromInteger (j));

      PipeOut #(Tuple2 #(a, UInt #(logn))) po_tup <- mkJoin (tuple2, po_out, po_const_j);

      po_out <- mkStage (po_tup);
   end

   return po_out;
endmodule: mkLinearPipe_D

// ****************************************************************
// **************** CONDITIONAL PIPES
// ****************************************************************

// ----------------------------------------------------------------
// mkIfThenElse
// Stream args 'xs' through either 'pipeT' or 'pipeF' depending on booleans 'bs'
// The arms pipeT and pipeF need not have the same latency; ordering is preserved
//     using the internal pipe 'bools'
// For full pipelinining, the 'latency' parameter should be the max of latencies of pipeT and pipeF

module [Module] mkIfThenElse
                #(Integer latency,
                  Pipe #(a,b)  pipeT,
                  Pipe #(a,b)  pipeF,
                  PipeOut #(Tuple2 #(a, Bool)) poa)
                (PipeOut #(b));

   FIFOF #(Bool) bools <- mkSizedFIFOF_local (latency);

   match { .x, .pred } = poa.first ();

   PipeOut #(a) po_t_in = interface PipeOut;
                             method a first () if (pred);
                                return x;
                             endmethod
                             method Action deq () if (pred);
                                poa.deq ();
                                bools.enq (True);
                             endmethod
                             method Bool notEmpty ();
                                return ( poa.notEmpty () ? pred : False );
                             endmethod
                          endinterface;
   PipeOut #(b) po_t_out <- pipeT (po_t_in);

   PipeOut #(a) po_f_in = interface PipeOut;
                             method a first () if (! pred);
                                return x;
                             endmethod
                             method Action deq () if (! pred);
                                poa.deq ();
                                bools.enq (False);
                             endmethod
                             method Bool notEmpty ();
                                return ( poa.notEmpty () ? (! pred) : False );
                             endmethod
                          endinterface;
   PipeOut #(b) po_f_out <- pipeF (po_f_in);

   method b first ();
      return (bools.first () ? po_t_out.first () : po_f_out.first ());
   endmethod

   method Action deq ();
      if (bools.first ())
         po_t_out.deq ();
      else
         po_f_out.deq ();
      bools.deq ();
   endmethod

   method Bool notEmpty ();
      return (   bools.notEmpty ()
              ?  (   bools.first ()
                  ?  po_t_out.notEmpty ()
                  :  po_f_out.notEmpty () )
              :  False );
   endmethod
endmodule: mkIfThenElse

// ----------------------------------------------------------------
// mkIfThenElse_unordered
// Stream args 'xs' through either 'pipeT' or 'pipeF' depending on booleans 'bs'
// The arms pipeT and pipeF need not have the same latency
// The pipes are drained using a round-robin scheduler

module [Module] mkIfThenElse_unordered
                #(Pipe #(a,b)  pipeT,
                  Pipe #(a,b)  pipeF,
                  PipeOut #(Tuple2 #(a, Bool)) poa)
                (PipeOut #(b))

        provisos (Bits #(b, sb));

   match { .x, .pred } = poa.first ();

   // ---- True side
   PipeOut #(a) po_t_in = interface PipeOut;
                             method a first () if (pred);
                                return x;
                             endmethod
                             method Action deq () if (pred);
                                poa.deq ();
                             endmethod
                             method Bool notEmpty ();
                                return ( poa.notEmpty () ? pred : False );
                             endmethod
                          endinterface;
   PipeOut #(b) po_t_out <- pipeT (po_t_in);

   // ---- False side
   PipeOut #(a) po_f_in = interface PipeOut;
                             method a first () if (! pred);
                                return x;
                             endmethod
                             method Action deq () if (! pred);
                                poa.deq ();
                             endmethod
                             method Bool notEmpty ();
                                return ( poa.notEmpty () ? (! pred) : False );
                             endmethod
                          endinterface;
   PipeOut #(b) po_f_out <- pipeF (po_f_in);

   // ---- Round robin scheduling
   Reg #(Bool) round_robin <- mkReg (False);

   Bool both_ready = (po_t_out.notEmpty && po_f_out.notEmpty);
   Bool choose_t = ( both_ready ? round_robin : po_t_out.notEmpty );

   // ---- Interface
   method b first ();
      return ( choose_t ? po_t_out.first () : po_f_out.first () );
   endmethod

   method Action deq ();
      if (choose_t)
         po_t_out.deq ();
      else
         po_f_out.deq ();
   endmethod

   method Bool notEmpty ();
      return  (po_t_out.notEmpty () || po_f_out.notEmpty ());
   endmethod
endmodule: mkIfThenElse_unordered

// ****************************************************************
// **************** LOOPS
// ****************************************************************

// ----------------------------------------------------------------
// mkWhileLoop

module [Module] mkWhileLoop
                #(Pipe #(a,Tuple2 #(b, Bool))  mkPreTest,
                  Pipe #(b,a)                  mkPostTest,
                  Pipe #(b,c)                  mkFinal,
                  PipeOut #(a) po_in)
                (PipeOut #(c))
        provisos (Bits #(a, sa));


   // --- At the top of the loop is the merge of incoming data and recirculated data
   FIFOF #(a) merge_fifo <- mkFIFOF;  // Note: this cannot be a pipelinefifo (else scheduling loop)

   // ---- Pre test pipeline
   let po_preTest <- mkPreTest (f_FIFOF_to_PipeOut (merge_fifo));

   match { .vb, .vBool } = po_preTest.first ();

   // ---- True output of test
   let po_t = interface PipeOut #(b)
                 method b first () if (vBool);
                    return vb;
                 endmethod
                 method Action deq () if (vBool);
                    po_preTest.deq ();
                 endmethod
                 method Bool notEmpty ();
                    return ( po_preTest.notEmpty () ? vBool : False);
                 endmethod
              endinterface;

   // ---- False output of test
   let po_f = interface PipeOut #(b)
                 method b first () if (! vBool);
                    return vb;
                 endmethod
                 method Action deq () if (! vBool);
                    po_preTest.deq ();
                 endmethod
                 method Bool notEmpty ();
                    return ( po_preTest.notEmpty () ? (! vBool) : False);
                 endmethod
              endinterface;

   // ---- post test loop body
   let po_postTest <- mkPostTest (po_t);

   // ---- Merge loop input or recirc, giving priority to recirc

   (* preempts = "rl_merge_loop_recirc, rl_merge_loop_input" *)
   rule rl_merge_loop_input;
      let x = po_in.first (); po_in.deq ();
      merge_fifo.enq (x);
   endrule

   rule rl_merge_loop_recirc;
      let x = po_postTest.first (); po_postTest.deq ();
      merge_fifo.enq (x);
   endrule

   // ---- loop exit with final pipe
   let po_final <- mkFinal (po_f);
   return po_final;
endmodule: mkWhileLoop

// ----------------------------------------------------------------
// mkForLoop

module [Module] mkForLoop
                #(UInt #(wj)     jmax,
                  Pipe #(Tuple2 #(a, UInt #(wj)), Tuple2 #(a, UInt #(wj)))    mkLoopBody,
                  Pipe #(a,b)    mkFinal,
                  PipeOut #(a)   po_in)
                (PipeOut #(b))
        provisos (Bits #(a, sa));

   // --- At the top of the loop is the merge of incoming data and recirculated data
   // Note: this cannot be a pipelinefifo (else scheduling loop)

   FIFOF #(Tuple3 #(a, UInt #(wj), Bool)) merge_fifo <- mkFIFOF;

   match { .vj, .j, .done } = merge_fifo.first ();

   // ---- True output of test
   let po_t = interface PipeOut #(Tuple2 #(a, UInt #(wj)));
                 method Tuple2 #(a, UInt #(wj))  first () if (! done);
                    return tuple2 (vj, j);
                 endmethod
                 method Action deq () if (! done);
                    merge_fifo.deq ();
                 endmethod
                 method Bool notEmpty ();
                    return ((! done) && merge_fifo.notEmpty ());
                 endmethod
              endinterface;

   let po_body <- mkLoopBody (po_t);    // post test loop body

   // ---- False output of test
   let po_f = interface PipeOut #(a)
                 method a first () if (done);
                    return vj;
                 endmethod
                 method Action deq () if (done);
                    merge_fifo.deq ();
                 endmethod
                 method Bool notEmpty ();
                    return (done && merge_fifo.notEmpty ());
                 endmethod
              endinterface;

   let po_final <- mkFinal (po_f);

   // ---- Merge loop input or recirc, giving priority to recirc

   (* preempts = "rl_merge_loop_recirc, rl_merge_loop_input" *)
   rule rl_merge_loop_input;
      let x = po_in.first (); po_in.deq ();
      let j = 0;
      let done = (j == jmax);
      merge_fifo.enq (tuple3 (x, j, done));
   endrule

   rule rl_merge_loop_recirc;
      match { .x, .j } = po_body.first (); po_body.deq ();
      let done = (j == jmax);
      merge_fifo.enq (tuple3 (x, j+1, done));
   endrule

   // ---- loop exit with final pipe
   return po_final;
endmodule: mkForLoop

// ****************************************************************
// **************** FOLDS
// ****************************************************************

// ----------------------------------------------------------------
// mkWhileFold
// Input po_in is a stream of pairs: (value, End-of-group)
// Combines (accumulates) each group of items using pipe_combine
// Returns accumulated value

module [Module] mkWhileFold
                #(Pipe #(Tuple2 #(a,a), a)  mkCombine,
                  PipeOut #(Tuple2 #(a, Bool)) po_in)
                (PipeOut #(a))
        provisos (Bits #(a, sa));

   FIFO #(Bit #(0))  output_taken_fifo <- mkBypassFIFO;
   Reg #(Bool)       initialized       <- mkReg (False);

   rule rl_initialize (! initialized);
      output_taken_fifo.enq (?);
      initialized <= True;
   endrule

   FIFOF #(a)  accum_fifo  <- mkPipelineFIFOF;
   Reg #(Bool) done_accum  <- mkReg(False);

   // Note: accum_fifo's first/deq SBR enq    (pipeline fifo)
   // In the recirc path, we're both dequeuing and enqueing
   // Because of the SBR, the deq and enq have to be in two rules
   // Thus recirc is split into two rules A and B communicating with an RWire
   // The pulse wires and rl_assert are used to ensure they fire together

   RWire #(a)  recirc_rw  <- mkRWire;
   PulseWire   pw_rl_A    <- mkPulseWire;
   PulseWire   pw_rl_B    <- mkPulseWire;

   match { .x_in,     .done_in }  = po_in.first ();
   let   x_accum                  = accum_fifo.first ();

   rule rl_first_input;
      accum_fifo.enq (x_in);
      done_accum <= done_in;
      output_taken_fifo.deq ();
      po_in.deq ();
   endrule

   PipeOut #(Tuple2 #(a,a)) recirc_ifc =
                   interface PipeOut
                      method Tuple2 #(a,a) first () if (! done_accum);
                         return tuple2 (x_in, x_accum);
                      endmethod
                      method Action deq () if (! done_accum);
                         po_in.deq ();
                         accum_fifo.deq ();
                         done_accum <= done_in;
                      endmethod
                      method Bool notEmpty ();
                         return ((! done_accum) && po_in.notEmpty() && accum_fifo.notEmpty ());
                      endmethod
                   endinterface;

   PipeOut #(a) combine_out <- mkCombine (recirc_ifc);

   rule rl_recirc_A;
      recirc_rw.wset (combine_out.first ());
      combine_out.deq ();
      pw_rl_A.send ();
   endrule

   (* preempts = "rl_first_input, rl_recirc_B" *)
   rule rl_recirc_B (recirc_rw.wget matches tagged Valid .x);
      accum_fifo.enq (x);
      pw_rl_B.send ();
   endrule

   rule rl_assert_A_and_B (pw_rl_A || pw_rl_B);
      if (! pw_rl_A)
         $display ("mkWhileFold: rl_recirc_B firing without rl_recirc_A");
      if (! pw_rl_B)
         $display ("mkWhileFold: rl_recirc_A firing without rl_recirc_B");
   endrule

   return (interface PipeOut;
              method a first () if (initialized && done_accum);
                 return x_accum;
              endmethod
              method Action deq () if (initialized && done_accum);
                 accum_fifo.deq ();
                 output_taken_fifo.enq (?);
              endmethod
              method Bool notEmpty ();
                 return (initialized && done_accum && accum_fifo.notEmpty ());
              endmethod
           endinterface);
endmodule: mkWhileFold

// ----------------------------------------------------------------
// mkForFold
// Input po_in is a stream of values in groups (logically indexed 0..jmax).
// Combines (accumulates) each group of items using pipe_combine.
// Returns accumulated values.

module [Module] mkForFold
                #(UInt #(wj) jmax,
                  Pipe #(Tuple2 #(a,a), a)  mkCombine,
                  PipeOut #(a) po_in)
                (PipeOut #(a))
        provisos (Bits #(a, sa));

   FIFO #(Bit #(0))  output_taken_fifo <- mkBypassFIFO;
   Reg #(Bool)       initialized       <- mkReg (False);

   rule rl_initialize (! initialized);
      output_taken_fifo.enq (?);
      initialized <= True;
   endrule

   FIFOF #(a)         accum_fifo  <- mkPipelineFIFOF;
   Reg #(UInt #(wj))  j           <- mkRegU;

   // Note: accum_fifo's first/deq SBR enq    (pipeline fifo)
   // In the recirc path, we're both dequeuing and enqueing
   // Because of the SBR, the deq and enq have to be in two rules
   // Thus recirc is split into two rules A and B communicating with an RWire
   // The pulse wires and rl_assert are used to ensure they fire together

   RWire #(a)                  recirc_rw  <- mkRWire;
   PulseWire                   pw_rl_A    <- mkPulseWire;
   PulseWire                   pw_rl_B    <- mkPulseWire;

   let x_in     = po_in.first ();
   let x_accum  = accum_fifo.first ();

   rule rl_first_input;
      accum_fifo.enq (x_in);
      j <= 0;
      output_taken_fifo.deq ();
      po_in.deq ();
   endrule

   PipeOut #(Tuple2 #(a,a)) recirc_ifc =
                   interface PipeOut
                      method Tuple2 #(a,a) first () if (j < jmax);
                         return tuple2 (x_in, x_accum);
                      endmethod
                      method Action deq () if (j < jmax);
                         po_in.deq ();
                         accum_fifo.deq ();
                      endmethod
                      method Bool notEmpty ();
                         return ((j < jmax) && po_in.notEmpty () && accum_fifo.notEmpty ());
                      endmethod
                   endinterface;

   PipeOut #(a) combine_out <- mkCombine (recirc_ifc);

   rule rl_recirc_A;
      recirc_rw.wset (combine_out.first ());
      combine_out.deq ();
      pw_rl_A.send ();
   endrule

   (* preempts = "rl_first_input, rl_recirc_B" *)
   rule rl_recirc_B (recirc_rw.wget matches tagged Valid .xb);
      accum_fifo.enq (xb);
      j <= j + 1;
      pw_rl_B.send ();
   endrule

   rule rl_assert_A_and_B (pw_rl_A || pw_rl_B);
      if (! pw_rl_A)
         $display ("mkForFold: rl_recirc_B firing without rl_recirc_A");
      if (! pw_rl_B)
         $display ("mkForFold: rl_recirc_A firing without rl_recirc_B");
   endrule

   return (interface PipeOut;
              method a first () if (initialized && (j == jmax));
                 return x_accum;
              endmethod
              method Action deq () if (initialized && (j == jmax));
                 accum_fifo.deq ();
                 output_taken_fifo.enq (?);
              endmethod
              method Bool notEmpty ();
                 return (initialized && (j == jmax) && accum_fifo.notEmpty ());
              endmethod
           endinterface);
endmodule: mkForFold

// ****************************************************************
// **************** Reordering
// ****************************************************************

// mkReorder restores I/O ordering for a pipe that returns results out of order
// mkBody takes inputs (tag,xa) and returns results (tag,xb), possibly out of order
// This module creates a Pipe#(a,b) that returns outputs in the order of the inputs

module [Module] mkReorder
                #(Pipe #(Tuple2 #(CBToken #(n), a), Tuple2 #(CBToken #(n), b)) mkBody,
                  PipeOut #(a) po_in)
                (PipeOut #(b))

        provisos (Bits #(a, sa),
                  Bits #(b, sb));

   CompletionBuffer #(n, b) cb <- mkCompletionBuffer;

   FIFOF #(Tuple2 #(CBToken #(n), a)) tagged_inputs <- mkPipelineFIFOF;
   FIFOF #(b)                         outputs       <- mkPipelineFIFOF;

   rule rl_tag_inputs;
      let x      =  po_in.first ();  po_in.deq ();
      let cbtok <-  cb.reserve.get ();
      tagged_inputs.enq (tuple2 (cbtok, x));
   endrule

   let body_out <- mkBody (f_FIFOF_to_PipeOut (tagged_inputs));

   rule rl_drain_body;
      cb.complete.put (body_out.first ());  body_out.deq ();
   endrule

   (* descending_urgency = "rl_drain_cb, rl_tag_inputs" *)

   rule rl_drain_cb;
      let z <- cb.drain.get ();
      outputs.enq (z);
   endrule

   return f_FIFOF_to_PipeOut (outputs);
endmodule: mkReorder

// ****************************************************************
// ****************************************************************

endpackage: PAClib
