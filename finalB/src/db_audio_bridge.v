`timescale 1ns/1ps
module db_reset_sync(input wire clk,arst,output wire rst);
 (* syn_preserve=1,async_reg="true" *) reg [1:0] pipe;
 always @(posedge clk or posedge arst)if(arst)pipe<=3;else pipe<={pipe[0],1'b0};
 assign rst=pipe[1];
endmodule
module db_i2s_rx(input wire bclk,rst,ws,sd,output reg [47:0] data,output reg valid,output reg framing_error);
 reg previous_ws,left_complete,aligned;reg [5:0] bit_count;reg [23:0] shift,left_word;
 always @(posedge bclk or posedge rst)begin
  if(rst)begin previous_ws<=1;left_complete<=0;aligned<=0;bit_count<=0;shift<=0;left_word<=0;data<=0;valid<=0;framing_error<=0;end
  else begin
   valid<=0;previous_ws<=ws;
   if(ws!=previous_ws)begin
    bit_count<=0;
    if(!ws)left_complete<=0;
    else if(bit_count!=31)begin left_complete<=0;if(aligned)framing_error<=1;end
   end else begin
    if(bit_count<31)bit_count<=bit_count+1'b1;
    if(bit_count<24)begin
     shift<={shift[22:0],sd};
     if(bit_count==23)begin
      if(!ws)begin left_word<={shift[22:0],sd};left_complete<=1;end
      else if(left_complete)begin data<={left_word,shift[22:0],sd};valid<=1;left_complete<=0;aligned<=1;end
     end
    end
   end
  end
 end
endmodule
// All state/FIFO reads use incoming BCLK rising edges. Output bits are registered
// on falling edges. WS is retimed by half a bit; its MSB delay remains exactly1 bit.
module db_i2s_tx(input wire bclk,rst,ws,input wire [47:0] fifo_data,input wire fifo_valid,fifo_empty,
 output wire fifo_read,output reg out_ws,out_sd,output reg primed,output reg underrun);
 reg previous_ws,prepared_ws,prepared_sd,pair_valid,read_pending;
 reg [47:0] pair;reg [23:0] left_word,right_word;reg [5:0] bit_count;
 assign fifo_read=!rst && !pair_valid && !read_pending && !fifo_empty;
 always @(posedge bclk or posedge rst)begin
  if(rst)begin previous_ws<=1;prepared_ws<=1;prepared_sd<=0;pair_valid<=0;read_pending<=0;pair<=0;
   left_word<=0;right_word<=0;bit_count<=0;primed<=0;underrun<=0;end
  else begin
   previous_ws<=ws;prepared_ws<=ws;
   if(fifo_read)read_pending<=1;
   if(fifo_valid)begin pair<=fifo_data;pair_valid<=1;read_pending<=0;end
   if(ws!=previous_ws)begin
    bit_count<=0;prepared_sd<=0;
    if(!ws)begin
     // At startup keep two complete words in flight; never chase a partial frame.
     if(pair_valid && (primed || !fifo_empty))begin left_word<=pair[47:24];right_word<=pair[23:0];pair_valid<=0;primed<=1;end
     else begin left_word<=0;right_word<=0;if(primed)underrun<=1;primed<=0;end
    end
   end else begin
    if(bit_count<31)bit_count<=bit_count+1'b1;
    prepared_sd<=0;
    if(bit_count<24)prepared_sd<=ws ? right_word[23-bit_count] : left_word[23-bit_count];
   end
  end
 end
 always @(negedge bclk or posedge rst)begin
  if(rst)begin out_ws<=1;out_sd<=0;end
  else begin out_ws<=prepared_ws;out_sd<=prepared_sd;end
 end
endmodule
