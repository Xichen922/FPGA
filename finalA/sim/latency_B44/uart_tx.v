`timescale 1ns/1ps
// 8N1 UART transmitter with ready/valid byte handshake.
module latb_uart_tx #(
    parameter integer CLK_HZ = 50000000,
    parameter integer BAUD = 115200
) (
    input wire clk,
    input wire rst_n,
    input wire [7:0] data,
    input wire valid,
    output wire ready,
    output reg tx,
    output reg done
);
    localparam integer DIVISOR = (CLK_HZ + BAUD / 2) / BAUD;
    reg busy;
    reg [31:0] timer;
    reg [3:0] bit_index;
    reg [9:0] shift;
    assign ready = ~busy;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy <= 0;
            tx <= 1;
            done <= 0;
            timer <= 0;
            bit_index <= 0;
            shift <= 10'h3FF;
        end else begin
            done <= 0;
            if (!busy) begin
                tx <= 1;
                if (valid) begin
                    shift <= {1'b1, data, 1'b0};
                    tx <= 0;
                    busy <= 1;
                    bit_index <= 0;
                    timer <= DIVISOR - 1;
                end
            end else if (timer != 0) timer <= timer - 1'b1;
            else if (bit_index == 9) begin
                tx <= 1;
                busy <= 0;
                done <= 1;
            end else begin
                shift <= {1'b1, shift[9:1]};
                tx <= shift[1];
                bit_index <= bit_index + 1'b1;
                timer <= DIVISOR - 1;
            end
        end
    end
endmodule
