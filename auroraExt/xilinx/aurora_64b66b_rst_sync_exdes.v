module aurora_64b66b_rst_sync_exdes
   # (
       parameter       c_init_val      = 1'b1,
       parameter [4:0] c_mtbf_stages   = 3    // Number of sync stages needed  max value 31
     )  
     (
       input                           prmry_in,
       input                           scndry_aclk,
       output                          scndry_out
      );

genvar i;



(* ASYNC_REG = "TRUE" *)(* shift_extract = "{no}"*)  reg  stg1_aurora_64b66b_cdc_to = c_init_val;      
(* ASYNC_REG = "TRUE" *)(* shift_extract = "{no}"*)  reg  stg2 = c_init_val;      
(* ASYNC_REG = "TRUE" *)(* shift_extract = "{no}"*)  reg  stg3 = c_init_val;      

                        (* shift_extract = "{no}"*)  reg  stg4 = c_init_val;     
                        (* shift_extract = "{no}"*)  reg  stg5 = c_init_val;     
                        (* shift_extract = "{no}"*)  reg  stg6 = c_init_val;     
                        (* shift_extract = "{no}"*)  reg  stg7 = c_init_val;     
                        (* shift_extract = "{no}"*)  reg  stg8 = c_init_val;     
                        (* shift_extract = "{no}"*)  reg  stg9 = c_init_val;     
                        (* shift_extract = "{no}"*)  reg  stg10 = c_init_val;    
                        (* shift_extract = "{no}"*)  reg  stg11 = c_init_val;    
                        (* shift_extract = "{no}"*)  reg  stg12 = c_init_val;    
                        (* shift_extract = "{no}"*)  reg  stg13 = c_init_val;    
                        (* shift_extract = "{no}"*)  reg  stg14 = c_init_val;    
                        (* shift_extract = "{no}"*)  reg  stg15 = c_init_val;    
                        (* shift_extract = "{no}"*)  reg  stg16 = c_init_val;    
                        (* shift_extract = "{no}"*)  reg  stg17 = c_init_val;    
                        (* shift_extract = "{no}"*)  reg  stg18 = c_init_val;    
                        (* shift_extract = "{no}"*)  reg  stg19 = c_init_val;    
                        (* shift_extract = "{no}"*)  reg  stg20 = c_init_val;    
                        (* shift_extract = "{no}"*)  reg  stg21 = c_init_val;    
                        (* shift_extract = "{no}"*)  reg  stg22 = c_init_val;    
                        (* shift_extract = "{no}"*)  reg  stg23 = c_init_val;    
                        (* shift_extract = "{no}"*)  reg  stg24 = c_init_val;    
                        (* shift_extract = "{no}"*)  reg  stg25 = c_init_val;    
                        (* shift_extract = "{no}"*)  reg  stg26 = c_init_val;    
                        (* shift_extract = "{no}"*)  reg  stg27 = c_init_val;    
                        (* shift_extract = "{no}"*)  reg  stg28 = c_init_val;    
                        (* shift_extract = "{no}"*)  reg  stg29 = c_init_val;    
                        (* shift_extract = "{no}"*)  reg  stg30 = c_init_val;    
                        (* shift_extract = "{no}"*)  reg  stg31 = c_init_val;    

generate 

always @(posedge scndry_aclk)
begin
    stg1_aurora_64b66b_cdc_to <= `DLY prmry_in;
    stg2 <= `DLY stg1_aurora_64b66b_cdc_to;
    stg3 <= `DLY stg2;
    stg4 <= `DLY stg3;
    stg5 <= `DLY stg4;
    stg6 <= `DLY stg5;
    stg7 <= `DLY stg6;
    stg8 <= `DLY stg7;
    stg9 <= `DLY stg8;
    stg10 <= `DLY stg9;
    stg11 <= `DLY stg10; 
    stg12 <= `DLY stg11; 
    stg13 <= `DLY stg12; 
    stg14 <= `DLY stg13; 
    stg15 <= `DLY stg14; 
    stg16 <= `DLY stg15; 
    stg17 <= `DLY stg16; 
    stg18 <= `DLY stg17; 
    stg19 <= `DLY stg18; 
    stg20 <= `DLY stg19; 
    stg21 <= `DLY stg20; 
    stg22 <= `DLY stg21; 
    stg23 <= `DLY stg22; 
    stg24 <= `DLY stg23; 
    stg25 <= `DLY stg24; 
    stg26 <= `DLY stg25; 
    stg27 <= `DLY stg26; 
    stg28 <= `DLY stg27; 
    stg29 <= `DLY stg28; 
    stg30 <= `DLY stg29; 
    stg31 <= `DLY stg30; 
end

if(c_mtbf_stages <= 3)  assign scndry_out = stg3;
if(c_mtbf_stages == 4)  assign scndry_out = stg4;
if(c_mtbf_stages == 5)  assign scndry_out = stg5;
if(c_mtbf_stages == 6)  assign scndry_out = stg6;
if(c_mtbf_stages == 7)  assign scndry_out = stg7;
if(c_mtbf_stages == 8)  assign scndry_out = stg8;
if(c_mtbf_stages == 9)  assign scndry_out = stg9;
if(c_mtbf_stages == 10)  assign scndry_out = stg10;
if(c_mtbf_stages == 11)  assign scndry_out = stg11;
if(c_mtbf_stages == 12)  assign scndry_out = stg12;
if(c_mtbf_stages == 13)  assign scndry_out = stg13;
if(c_mtbf_stages == 14)  assign scndry_out = stg14;
if(c_mtbf_stages == 15)  assign scndry_out = stg15;
if(c_mtbf_stages == 16)  assign scndry_out = stg16;
if(c_mtbf_stages == 17)  assign scndry_out = stg17;
if(c_mtbf_stages == 18)  assign scndry_out = stg18;
if(c_mtbf_stages == 19)  assign scndry_out = stg19;
if(c_mtbf_stages == 20)  assign scndry_out = stg20;
if(c_mtbf_stages == 21)  assign scndry_out = stg21;
if(c_mtbf_stages == 22)  assign scndry_out = stg22;
if(c_mtbf_stages == 23)  assign scndry_out = stg23;
if(c_mtbf_stages == 24)  assign scndry_out = stg24;
if(c_mtbf_stages == 25)  assign scndry_out = stg25;
if(c_mtbf_stages == 26)  assign scndry_out = stg26;
if(c_mtbf_stages == 27)  assign scndry_out = stg27;
if(c_mtbf_stages == 28)  assign scndry_out = stg28;
if(c_mtbf_stages == 29)  assign scndry_out = stg29;
if(c_mtbf_stages == 30)  assign scndry_out = stg30;
if(c_mtbf_stages == 31)  assign scndry_out = stg31;

endgenerate

endmodule
