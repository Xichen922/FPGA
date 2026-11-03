`timescale 1ns/1ps
// SPI mode 0, MSB first. One byte per start pulse; chip select is external.
module w25q64_spi_byte #(
    parameter integer HALF_CYCLES = 25
)(input wire clk, rst_n, start, input wire [7:0] tx_data,
  input wire miso, output reg sclk, mosi, busy, done,
  output reg [7:0] rx_data);
  reg [15:0] divider;
  reg falling;
  reg [2:0] bit_index;
  reg [7:0] tx_shift, rx_shift;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      sclk<=0;mosi<=0;busy<=0;done<=0;rx_data<=0;
      divider<=0;falling<=0;bit_index<=0;tx_shift<=0;rx_shift<=0;
    end else begin
      done<=0;
      if (!busy) begin
        sclk<=0;
        if (start) begin
          busy<=1;divider<=HALF_CYCLES-1;falling<=0;
          bit_index<=3'd7;tx_shift<=tx_data;rx_shift<=0;mosi<=tx_data[7];
        end
      end else if (divider!=0) divider<=divider-1'b1;
      else begin
        divider<=HALF_CYCLES-1;
        if (!falling) begin
          sclk<=1;rx_shift[bit_index]<=miso;falling<=1;
        end else begin
          sclk<=0;falling<=0;
          if (bit_index==0) begin
            busy<=0;done<=1;rx_data<=rx_shift;
          end else begin
            bit_index<=bit_index-1'b1;
            mosi<=tx_shift[bit_index-1'b1];
          end
        end
      end
    end
  end
endmodule
