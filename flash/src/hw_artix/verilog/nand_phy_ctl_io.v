`timescale 1ns/1ps


//add flip flops at the IOB 
module nand_phy_ctl_io #
	(
		parameter CENS_PER_BUS = 8
		//parameter RBS_PER_IO = 4
	)
	(
	
	//nand interface for half of a NAND package
	//x8 DQ interface
	output cle,
	output ale,
	output wrn,
	output wpn,
	output [CENS_PER_BUS-1:0] cen,
	//input  [RBS_PER_IO-1:0] rb,
		
	//controller facing interface
	input ctrl_cle,
	input ctrl_ale,
	input ctrl_wrn,
	input ctrl_wpn,
	input [CENS_PER_BUS-1:0] ctrl_cen,
	//output [RBS_PER_IO-1:0] ctrl_rb,
	
	//clock and reset
	input clk0,
	input rst0
	);

//ce. Active low. 
genvar ce_i;
  generate
    for(ce_i = 0; ce_i < CENS_PER_BUS; ce_i = ce_i + 1) begin: gen_ce_n
      (* IOB = "FORCE" *) FDCPE #(
				.INIT(1'b1)
			) u_ff_ce_n (
         .Q   (cen[ce_i]),
         .C   (clk0),
         .CE  (1'b1),
         .CLR (1'b0),
         .D   (ctrl_cen[ce_i]),
         .PRE (rst0)
         );
    end
  endgenerate
  
//ale. active high
  (* IOB = "FORCE" *) FDCPE u_ff_ale
    (
     .Q   (ale),
     .C   (clk0),
     .CE  (1'b1),
     .CLR (rst0),
     .D   (ctrl_ale),
     .PRE (1'b0)
     );


//cle
  (* IOB = "FORCE" *) FDCPE u_ff_cle
    (
     .Q   (cle),
     .C   (clk0),
     .CE  (1'b1),
     .CLR (rst0),
     .D   (ctrl_cle),
     .PRE (1'b0)
     );


//wrn
  (* IOB = "FORCE" *) FDCPE u_ff_wrn
    (
     .Q   (wrn),
     .C   (clk0),
     .CE  (1'b1),
     .CLR (1'b0),
     .D   (ctrl_wrn),
     .PRE (rst0)
     );

//wpn
  (* IOB = "FORCE" *) FDCPE #(
		.INIT(1'b0)
	) u_ff_wpn (
     .Q   (wpn),
     .C   (clk0),
     .CE  (1'b1),
     .CLR (rst0),
     .D   (ctrl_wpn),
     .PRE (1'b0)
     );
	  
	  
	  
//rb. Note the direction flip
//
//genvar rb_i;
//  generate
//    for(rb_i = 0; rb_i < RBS_PER_IO; rb_i = rb_i + 1) begin: gen_rb
//      (* IOB = "FORCE" *) FDCPE u_ff_rb
//        (
//         .Q   (ctrl_rb[rb_i]),
//         .C   (clk0),
//         .CE  (1'b1),
//         .CLR (1'b0),
//         .D   (rb[rb_i]),
//         .PRE (rst0)
//         ) /* synthesis syn_useioff = 1 */;
//    end
//  endgenerate

endmodule
  
  
  
  
  
  
  
  
  
  
  
