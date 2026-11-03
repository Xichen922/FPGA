`timescale 1ns/1ps
module db_uart_rx #(parameter CLK_HZ=50000000,BAUD=115200)(
 input wire clk,rst,rx,output reg [7:0] data,output reg valid,output reg framing_error);
 localparam integer CPB=(CLK_HZ+BAUD/2)/BAUD;
 (* syn_preserve=1 *)reg meta,sync;
 reg [31:0] timer;reg [3:0] bit_index;reg [7:0] shift;reg [1:0] state;
 always @(posedge clk)begin
  if(rst)begin meta<=1;sync<=1;timer<=0;bit_index<=0;shift<=0;state<=0;data<=0;valid<=0;framing_error<=0;end
  else begin
   meta<=rx;sync<=meta;valid<=0;
   case(state)
    0:if(!sync)begin timer<=CPB/2-1;state<=1;end
    1:if(timer==0)begin if(!sync)begin timer<=CPB-1;bit_index<=0;state<=2;end else state<=0;end else timer<=timer-1'b1;
    2:if(timer==0)begin shift[bit_index]<=sync;timer<=CPB-1;if(bit_index==7)state<=3;else bit_index<=bit_index+1'b1;end else timer<=timer-1'b1;
    3:if(timer==0)begin if(sync)begin data<=shift;valid<=1;end else framing_error<=1;state<=0;end else timer<=timer-1'b1;
   endcase
  end
 end
endmodule
module db_hmi_commands #(parameter TIMEOUT_CYCLES=2500000)(
 input wire clk,rst,byte_valid,input wire [7:0] byte_data,
 output reg valid,output reg [7:0] opcode,value,output reg checksum_error);
 reg [1:0] state;reg [7:0] op,val;reg [31:0] timeout;
 always @(posedge clk)begin
  if(rst)begin state<=0;op<=0;val<=0;timeout<=0;valid<=0;opcode<=0;value<=0;checksum_error<=0;end
  else begin
   valid<=0;
   if(state!=0)begin if(timeout==TIMEOUT_CYCLES-1)begin state<=0;timeout<=0;end else timeout<=timeout+1'b1;end
   if(byte_valid)begin timeout<=0;
    case(state)
     0:if(byte_data==8'ha5)state<=1;
     1:begin op<=byte_data;state<=2;end
     2:begin val<=byte_data;state<=3;end
     3:begin
      if(byte_data==(8'ha5^op^val))begin opcode<=op;value<=val;valid<=1;end else checksum_error<=1;
      state<=0;
     end
    endcase
   end
  end
 end
endmodule
