`timescale 1ns/1ps
// MCP3008单次转换，SPI Mode 0：SCLK空闲低，下降沿改变MOSI，上升沿采样MISO。
// 24位命令为01 (80 | channel<<4) 00；接收最后10位，避开null bit。
// 50MHz / (2*25)=1MHz。CS下降后等待500ns；最后一位后保持500ns再释放CS。
// ready=1时start高一拍启动，channel在启动沿锁存。result_valid高一拍。
module ref51_mcp3008_spi #(
    parameter integer HALF_CYCLES=25
) (
    input wire clk, rst_n, start,
    input wire [2:0] channel,
    input wire miso,
    output wire ready,
    output reg cs_n, sclk, mosi,
    output reg [9:0] result,
    output reg result_valid
);
    (* syn_preserve=1 *) reg miso_meta, miso_sync;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin miso_meta<=0; miso_sync<=0; end
        else begin miso_meta<=miso; miso_sync<=miso_meta; end
    end
    reg busy;
    reg [31:0] half_timer;
    reg [4:0] bit_index;
    reg [23:0] tx_shift;
    reg [9:0] rx_shift;
    assign ready=!busy;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy<=0; half_timer<=0; bit_index<=0; tx_shift<=0; rx_shift<=0;
            cs_n<=1; sclk<=0; mosi<=0; result<=0; result_valid<=0;
        end else begin
            result_valid<=0;
            if (!busy) begin
                cs_n<=1; sclk<=0; mosi<=0;
                if (start) begin
                    busy<=1; cs_n<=0; half_timer<=HALF_CYCLES-1;
                    bit_index<=0; rx_shift<=0;
                    tx_shift<={8'h01,1'b1,channel,4'b0000,8'h00};
                    mosi<=0; // 24位命令的最高位固定为0。
                end
            end else if (half_timer!=0) half_timer<=half_timer-1'b1;
            else begin
                half_timer<=HALF_CYCLES-1;
                if (!sclk) begin
                    sclk<=1;
                    rx_shift<={rx_shift[8:0],miso_sync};
                end else begin
                    sclk<=0;
                    if (bit_index==23) begin
                        // 最后上升沿已经收下B0，现在结束完整24个时钟。
                        busy<=0; cs_n<=1; mosi<=0;
                        result<=rx_shift; result_valid<=1;
                    end else begin
                        bit_index<=bit_index+1'b1;
                        tx_shift<={tx_shift[22:0],1'b0};
                        mosi<=tx_shift[22];
                    end
                end
            end
        end
    end
endmodule
