`timescale 1ns/1ps
module db_spi_slave(input wire clk,rst,cs_n,sclk,mosi,input wire [127:0] tx_packet,
 output wire miso,output reg [127:0] rx_packet,output reg rx_valid,output reg framing_error);
 (* syn_preserve=1 *)reg cs_meta,cs_sync,ck_meta,ck_sync,mo_meta,mo_sync;
 reg cs_previous,ck_previous;reg [127:0] tx_shift,rx_shift;reg [7:0] bit_count;
 // MISO is a dedicated point-to-point wire; A samples it only while CS is
 // active. Keeping the output driven avoids a slow CS-to-output path.
 assign miso=tx_shift[127];
 always @(posedge clk)begin
  if(rst)begin cs_meta<=1;cs_sync<=1;ck_meta<=0;ck_sync<=0;mo_meta<=0;mo_sync<=0;cs_previous<=1;ck_previous<=0;
   tx_shift<=0;rx_shift<=0;bit_count<=0;rx_packet<=0;rx_valid<=0;framing_error<=0;end
  else begin
   cs_meta<=cs_n;cs_sync<=cs_meta;ck_meta<=sclk;ck_sync<=ck_meta;mo_meta<=mosi;mo_sync<=mo_meta;
   cs_previous<=cs_sync;ck_previous<=ck_sync;rx_valid<=0;
   if(cs_previous && !cs_sync)begin tx_shift<=tx_packet;rx_shift<=0;bit_count<=0;end
   else if(!cs_previous && cs_sync)begin
    if(bit_count==128)begin rx_packet<=rx_shift;rx_valid<=1;end else framing_error<=1;
   end else if(!cs_sync)begin
    if(!ck_previous && ck_sync)begin rx_shift<={rx_shift[126:0],mo_sync};if(bit_count<129)bit_count<=bit_count+1'b1;end
    if(ck_previous && !ck_sync)tx_shift<={tx_shift[126:0],1'b0};
   end
  end
 end
endmodule

