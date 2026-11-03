`timescale 1ns/1ps
module adc_scan_check #(parameter COMPACT=1)(output reg done=0);
 reg clk=0,rst_n=0,miso=0;always #10 clk=~clk;
 wire cs,sclk,mosi,valid;wire [9:0] c0,c1,c2,c3,c4,c5,c6,c7;
 mcp3008_scan #(.SCAN_CYCLES(5000),.SPI_HALF_CYCLES(5),.CS_GAP_CYCLES(50),.SCAN_MODE_014(COMPACT)) dut(
 .clk(clk),.rst_n(rst_n),.miso(miso),.cs_n(cs),.sclk(sclk),.mosi(mosi),
 .ch0(c0),.ch1(c1),.ch2(c2),.ch3(c3),.ch4(c4),.ch5(c5),.ch6(c6),.ch7(c7),.snapshot_valid(valid));
 integer bits=0,transactions=0,snapshots=0,expected=0,index=0,last_snapshot=0,cycles=0;
 reg [23:0] command=0;reg [9:0] response=0;reg [79:0] previous=0;
 always @(negedge cs) begin bits=0;command=0;miso=0;end
 always @(posedge sclk)begin
   command={command[22:0],mosi};bits=bits+1;
   if(bits==16)begin
    expected=COMPACT?((transactions%3==0)?0:(transactions%3==1)?1:4):(transactions%8);
    if(command[15:0] !== (16'h0180|(expected<<4)))$fatal(1,"MCP command/order %h expectedCH%0d",command,expected);
    response=10'd100+expected;
   end
 end
 always @(negedge sclk) if(!cs)begin
   // Last ten serial edges carry B9..B0; matches actual SPI receiver.
   if(bits>=14 && bits<24)miso=response[23-bits];else miso=0;
 end
 // The channel command finishes before response bit9 (edge15); prepare
 // the response from expected bus order, independently of DUT internals.
 always @(negedge cs)begin
  index=COMPACT?((transactions%3==0)?0:(transactions%3==1)?1:4):(transactions%8);
  response=10'd100+index;
 end
 always @(posedge cs)if(rst_n)begin
  if(bits!=24)$fatal(1,"not24 SPI bits");transactions=transactions+1;
 end
 always @(posedge clk)if(rst_n)begin
  cycles=cycles+1;#1;
  if(valid)begin
   if(c0!=100 || c1!=101 || c4!=104)$fatal(1,"bad CH014 sample %d %d %d",c0,c1,c4);
   if(!COMPACT && (c2!=102 || c3!=103 || c5!=105 || c6!=106 || c7!=107))$fatal(1,"legacy eight-channel failure");
   if(COMPACT && (c2||c3||c5||c6||c7))$fatal(1,"unused output changed");
   if(snapshots && cycles-last_snapshot!=5000)$fatal(1,"snapshot cadence changed");
   last_snapshot=cycles;snapshots=snapshots+1;
   if(transactions!=(snapshots*(COMPACT?3:8)))$fatal(1,"unexpected number of conversions");
   if(snapshots==3)done=1;
  end else if({c0,c1,c2,c3,c4,c5,c6,c7}!==previous)$fatal(1,"non-atomic snapshot");
  previous={c0,c1,c2,c3,c4,c5,c6,c7};
 end
 initial begin repeat(5)@(negedge clk);rst_n=1;end
endmodule
module tb47_adc;
 wire a,b;adc_scan_check #(.COMPACT(1)) compact(a);adc_scan_check #(.COMPACT(0)) legacy(b);
 initial begin wait(a&&b);$display("PASS real MCP3008 serial bus: CH0/1/4 only, command bytes,10bit data, atomic publish, fixed scan cadence; legacy CH0..7 unchanged");$finish;end
 initial begin #5000000;$fatal(1,"ADC timeout");end
endmodule
