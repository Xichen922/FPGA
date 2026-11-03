`timescale 1ns/1ps
// MCP3008 CH1/Y selects 3/4/5 octave for new notes. Valid snapshots only.
// Hysteresis and consecutive confirmation reject ADC noise; no division.
module ref51_joystick_octave #(
    parameter integer LOW_ENTER=256, LOW_EXIT=320,
    parameter integer HIGH_EXIT=704, HIGH_ENTER=768,
    parameter integer CONFIRM_SAMPLES=4
) (
    input wire clk, rst,
    input wire [9:0] adc_value,
    input wire snapshot_valid,
    output reg [3:0] octave
);
    function integer count_width;
        input integer samples;
        integer value;
        begin
            count_width=1;
            value=samples-1;
            while (value>1) begin
                count_width=count_width+1;
                value=value >> 1;
            end
        end
    endfunction
    localparam integer COUNT_WIDTH=count_width(CONFIRM_SAMPLES);
    reg [COUNT_WIDTH-1:0] confirm_count;
    reg [3:0] pending_octave;
    reg [3:0] candidate_octave;
    always @* begin
        candidate_octave=4'd4;
        case (octave)
            4'd3: begin
                if (adc_value>=HIGH_ENTER) candidate_octave=4'd5;
                else if (adc_value<LOW_EXIT) candidate_octave=4'd3;
            end
            4'd5: begin
                if (adc_value<=LOW_ENTER) candidate_octave=4'd3;
                else if (adc_value>HIGH_EXIT) candidate_octave=4'd5;
            end
            default: begin
                if (adc_value<=LOW_ENTER) candidate_octave=4'd3;
                else if (adc_value>=HIGH_ENTER) candidate_octave=4'd5;
            end
        endcase
    end
    always @(posedge clk) begin
        if (rst) begin
            octave<=4'd4;
            pending_octave<=4'd4;
            confirm_count<=0;
        end else if (snapshot_valid) begin
            if (candidate_octave==octave) begin
                pending_octave<=octave;
                confirm_count<=0;
            end else if (CONFIRM_SAMPLES<=1) begin
                octave<=candidate_octave;
                pending_octave<=candidate_octave;
                confirm_count<=0;
            end else if (candidate_octave!=pending_octave) begin
                pending_octave<=candidate_octave;
                confirm_count<=1;
            end else if (confirm_count==CONFIRM_SAMPLES-1) begin
                octave<=candidate_octave;
                confirm_count<=0;
            end else begin
                confirm_count<=confirm_count+1'b1;
            end
        end
    end
endmodule
