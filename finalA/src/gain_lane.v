`timescale 1ns/1ps
// Three voices arrive at separate times; one DSP replaces three serial multipliers.
// Signed24 x unsigned16, exact Q13 truncation and24-bit saturation as51.
module gain_lane(input wire clk,rst,input wire [71:0] samples,
 input wire [2:0] valid,input wire [47:0] gains,
 output reg [71:0] result,output reg [2:0] result_valid);
 wire [1:0] index=valid[0]?2'd0:valid[1]?2'd1:2'd2;
 wire signed [23:0] sample_selected=samples[index*24+:24];
 wire signed [16:0] gain_selected=$signed({1'b0,gains[index*16+:16]});
 reg signed [40:0] product;
 reg [1:0] output_index;reg pending;
 wire signed [40:0] scaled=product>>>13;
 wire signed [23:0] limited=scaled>41'sd8388607 ? 24'sh7fffff:
  scaled< -41'sd8388608 ? 24'sh800000:scaled[23:0];
 always @(posedge clk)begin
  product<=sample_selected*gain_selected;
  if(rst)begin result<=0;result_valid<=0;output_index<=0;pending<=0;end
  else begin
   pending<=|valid;output_index<=index;result_valid<=0;
   if(pending)begin result[output_index*24+:24]<=limited;result_valid[output_index]<=1;end
  end
 end
 // synthesis translate_off
 always @(posedge clk)if(!rst && valid!=0 && valid!=1 && valid!=2 && valid!=4)
  $fatal(1,"shared gain lane received simultaneous voices");
 // synthesis translate_on
endmodule

