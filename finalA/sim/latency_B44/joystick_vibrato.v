`timescale 1ns/1ps
// CH0 distance from centre sets sine vibrato depth. 50MHz/512 audio frames.
// Gentle string-like vibrato: about +/-16 cents maximum, 3..7 Hz.
// Q16 is a relative frequency offset; no change to the base note pitch.
module latb_joystick_vibrato #(
    parameter integer CENTER=512, DEAD_ZONE=32, EXTERNAL_ENABLE=0,
    parameter [31:0] LFO_STEP=32'd219902
) (
    input wire clk, rst, sample_tick, snapshot_valid,
    input wire [9:0] adc_value,
    input wire signed [7:0] encoder_delta,
    input wire encoder_valid, enable,
    output reg [3:0] speed_hz,
    output wire signed [11:0] vibrato_q16
);
    reg [9:0] target_depth, depth;
    reg [3:0] depth_slew_divider;
    reg [31:0] lfo_phase;
    reg [31:0] current_lfo_step;
    wire signed [10:0] proposed_speed=$signed({7'd0,speed_hz})+
        $signed({{3{encoder_delta[7]}},encoder_delta});
    wire [3:0] next_speed=proposed_speed<11'sd3 ? 4'd3 :
        proposed_speed>11'sd7 ? 4'd7 : proposed_speed[3:0];
    // LFO_STEP defines the 5 Hz reference. One Hz is exactly one fifth of it.
    function [31:0] step_for_speed;
        input [3:0] hz;
        begin step_for_speed=(LFO_STEP/5)*hz; end
    endfunction
    localparam [10:0] CENTER_VALUE=CENTER, DEAD_ZONE_VALUE=DEAD_ZONE;
    wire [10:0] distance_from_center = ({1'b0,adc_value} >= CENTER_VALUE) ?
        {1'b0,adc_value}-CENTER_VALUE : CENTER_VALUE-{1'b0,adc_value};
    wire [10:0] outside_distance=distance_from_center-DEAD_ZONE_VALUE;
    // Five sixteenths of the old joystick depth; maximum 150 instead of 480.
    wire [10:0] gentle_depth=(outside_distance >> 2)+(outside_distance >> 4);
    wire signed [23:0] lfo_wave;
    wire signed [34:0] depth_product = lfo_wave * $signed({1'b0,depth});
    latb_sine_rom_256 u_lfo_rom(.address(lfo_phase[31:24]), .sample(lfo_wave));
    // Multiplication is shared by all 12 voices; silence exactly at depth=0.
    assign vibrato_q16 = depth_product[28:17];
    always @(posedge clk) begin
        if(rst) begin
            target_depth<=0; depth<=0; lfo_phase<=0; depth_slew_divider<=0;
            speed_hz<=5; current_lfo_step<=LFO_STEP;
        end
        else begin
            if(encoder_valid) begin
                speed_hz<=next_speed;
                current_lfo_step<=step_for_speed(next_speed);
            end
            if(EXTERNAL_ENABLE!=0 && !enable)target_depth<=0;
            else if(snapshot_valid) begin
                if(distance_from_center<=DEAD_ZONE) target_depth<=0;
                else target_depth<=gentle_depth[9:0];
            end
            if(sample_tick) begin
                lfo_phase<=lfo_phase+current_lfo_step;
                // One depth unit every 16 samples: maximum fade ~24.6 ms.
                depth_slew_divider<=depth_slew_divider+1'b1;
                if(depth_slew_divider==0) begin
                    if(depth<target_depth) depth<=depth+1'b1;
                    else if(depth>target_depth) depth<=depth-1'b1;
                end
            end
        end
    end
endmodule
