`timescale 1ns/1ps
// Digital sensor DO is digitized by MCP3008, not interpreted as lux/AO.
// Counters advance ONLY on valid ADC snapshots. Default scan period: 1ms.
module ref51_fill_light_control #(
    parameter integer ENABLE=1, DARK_HIGH=1,
    parameter integer LOW_THRESHOLD=256, HIGH_THRESHOLD=640,
    parameter integer DARK_CONFIRM=300, BRIGHT_CONFIRM=1000,
    parameter integer MIN_HOLD=1000
) (
    input wire clk, rst, snapshot_valid,
    input wire [9:0] adc_do,
    output reg led_enable
);
    function integer width;
        input integer value;
        begin width=1; while ((value>>width)!=0) width=width+1; end
    endfunction
    localparam integer MAX_CONFIRM=(DARK_CONFIRM>BRIGHT_CONFIRM)?DARK_CONFIRM:BRIGHT_CONFIRM;
    localparam integer CW=width(MAX_CONFIRM), HW=width(MIN_HOLD);
    reg [CW-1:0] confirm_count;
    reg [HW-1:0] hold_count;
    wire known_high=adc_do>=HIGH_THRESHOLD;
    wire known_low=adc_do<=LOW_THRESHOLD;
    wire known=known_high || known_low;
    wire dark=(DARK_HIGH!=0)?known_high:known_low;
    wire [CW-1:0] confirm_target=dark ? DARK_CONFIRM : BRIGHT_CONFIRM;
    always @(posedge clk) begin
        if (rst || ENABLE==0) begin
            led_enable<=0; confirm_count<=0; hold_count<=0;
        end else if (snapshot_valid) begin
            if (hold_count!=0) begin
                hold_count<=hold_count-1'b1;
                confirm_count<=0;
            end else if (!known || dark==led_enable) confirm_count<=0;
            else if (confirm_count>=confirm_target-1'b1) begin
                led_enable<=dark;
                confirm_count<=0;
                hold_count<=MIN_HOLD;
            end else confirm_count<=confirm_count+1'b1;
        end
    end
endmodule
