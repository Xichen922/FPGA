`timescale 1ns/1ps
// Fixed16-byte full-duplex packets. MSB first, mode0, independent of audio.
module latb_db_spi_master #(parameter HALF_CYCLES=25,POLL_CYCLES=50000)(
 input wire clk,rst,input wire [127:0] tx_packet,input wire miso,
 output reg cs_n,output wire sclk,output wire mosi,output reg [127:0] rx_packet,output reg rx_valid);
 reg sclk_phase;
 (* syn_preserve=1 *)reg forwarded_sclk;
 assign sclk=forwarded_sclk;
 reg [127:0] tx_shift,rx_shift;reg [6:0] bit_index;reg [31:0] poll_count,half_count;reg busy;
 (* syn_preserve=1 *)reg mi_meta,mi_sync;
 assign mosi=tx_shift[127];
 always @(posedge clk)begin
  if(rst)begin cs_n<=1;sclk_phase<=0;forwarded_sclk<=0;tx_shift<=0;rx_shift<=0;bit_index<=0;poll_count<=0;half_count<=0;busy<=0;rx_packet<=0;rx_valid<=0;mi_meta<=0;mi_sync<=0;end
  else begin
   mi_meta<=miso;mi_sync<=mi_meta;rx_valid<=0;
   if(poll_count<POLL_CYCLES-1)poll_count<=poll_count+1'b1;else poll_count<=0;
   if(!busy)begin
    if(poll_count==0)begin cs_n<=0;sclk_phase<=0;forwarded_sclk<=0;busy<=1;tx_shift<=tx_packet;rx_shift<=0;bit_index<=0;half_count<=0;end
   end else if(half_count==HALF_CYCLES-1)begin
    half_count<=0;sclk_phase<=!sclk_phase;forwarded_sclk<=!sclk_phase;
    if(!sclk_phase)rx_shift<={rx_shift[126:0],mi_sync};
    else if(bit_index==127)begin cs_n<=1;sclk_phase<=0;forwarded_sclk<=0;busy<=0;rx_packet<=rx_shift;rx_valid<=1;end
    else begin bit_index<=bit_index+1'b1;tx_shift<={tx_shift[126:0],1'b0};end
   end else half_count<=half_count+1'b1;
  end
 end
endmodule
module latb_db_spi_slave(input wire clk,rst,cs_n,sclk,mosi,input wire [127:0] tx_packet,
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
