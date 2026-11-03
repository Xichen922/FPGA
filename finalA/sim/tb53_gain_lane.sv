`timescale 1ns/1ps
module tb53_gain_lane;
 reg clk=0,rst=1;always #10 clk=~clk;
 reg [71:0] samples=0;reg [47:0] gains=0;reg [2:0] valid=0;
 wire [71:0] result;wire [2:0] result_valid;
 gain_lane dut(clk,rst,samples,valid,gains,result,result_valid);
 integer i,j;reg signed [23:0] x,expected;reg [15:0] gain;
 reg signed [63:0] product,scaled;
 initial begin
  repeat(4)@(negedge clk);rst=0;
  for(i=0;i<2048;i=i+1)begin
   j=i%3;x=$random;gain=$random;
   case(i)
    0:begin x=-8388608;gain=65535;end
    1:begin x=8388607;gain=65535;end
    2:begin x=-8388608;gain=8192;end
    3:begin x=8388607;gain=8192;end
    4:begin x=-1;gain=1;end
    5:begin x=8388607;gain=0;end
   endcase
   product=$signed(x)*$signed({1'b0,gain});scaled=product>>>13;
   expected=scaled>8388607 ? 24'sh7fffff:scaled< -8388608 ? 24'sh800000:scaled[23:0];
   samples[j*24+:24]=x;gains[j*16+:16]=gain;valid=1<<j;
   @(negedge clk);valid=0;@(negedge clk);
   if(result_valid!==(1<<j) || result[j*24+:24]!==expected)
    $fatal(1,"gain mismatch i=%0d sample=%0d gain=%0d got=%0d expected=%0d",i,x,gain,$signed(result[j*24+:24]),expected);
   @(negedge clk);
  end
  $display("PASS shared gain:2048 random/boundary signed samples,all3 slots,exact Q13 and both saturation limits");$finish;
 end
endmodule
