`timescale 1ns/1ps
// Fixed16-byte full-duplex packets. MSB first, mode0, independent of audio.
module db_spi_master #(parameter HALF_CYCLES=25,POLL_CYCLES=50000)(
 input wire clk,rst,input wire [127:0] tx_packet,input wire miso,
 output reg cs_n,output wire sclk,output wire mosi,output reg [127:0] rx_packet,output reg rx_valid);
 reg sclk_phase;
 (* syn_preserve=1 *)reg forwarded_sclk;
 assign sclk=forwarded_sclk;
 reg [127:0] tx_shift,rx_shift;reg [6:0] bit_index;localparam integer POLL_BITS=(POLL_CYCLES<2) ? 1 : $clog2(POLL_CYCLES);
 localparam integer HALF_BITS=(HALF_CYCLES<2) ? 1 : $clog2(HALF_CYCLES);
 reg [POLL_BITS-1:0] poll_count;reg [HALF_BITS-1:0] half_count;reg busy;
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
