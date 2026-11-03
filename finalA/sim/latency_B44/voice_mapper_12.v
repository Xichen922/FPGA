// 【琴键固定对应声部】键1 -> 声部0，键2 -> 声部1，...，键12 -> 声部11。
// 同时检测到几个音符键，就更新几个对应声部；十二键可以一起触发。
// 每个物理键只有一个声部。松开后重新按同一个键，会重启它自己的声音。
// voice_steps共384位：12个32位相位步进；voice_octaves共48位：12个4位八度。
`timescale 1ns/1ps
// Permanent one-to-one mapping: physical key 1..12 owns voice 0..11.
// Every key has an independent NCO/envelope; no priority or stealing.
// The glide path is bypassed. All notes use their target pitches.
// Octave events update pitch without pulsing trigger or resetting phase.
module latb_voice_mapper_12 #(
    parameter integer PORTAMENTO_ENABLE=0 // Temporarily disabled
) (
    input wire clk, rst, control_valid, sample_tick,
    input wire [14:0] glide_samples,
    input wire [11:0] note_gate, note_press,
    input wire [47:0] note_octaves,
    output reg [11:0] voice_gate, voice_trigger,
    output wire [383:0] voice_steps,
    output reg [47:0] voice_octaves
);
    wire [383:0] target_steps;
    // PORTAMENTO_ENABLE remains accepted for interface compatibility. Glide was
    // already disconnected in the baseline; gates/triggers/octaves retain their exact timing.
    // Each physical voice has a constant note number. Resolve it at elaboration,
    // avoiding twelve disposable generic LUT module latb_instances (NL0002).
    function [31:0] fixed_c4_step;
        input integer index;
        begin
            case(index)
                0: fixed_c4_step=32'd11506414;
                1: fixed_c4_step=32'd12190621;
                2: fixed_c4_step=32'd12915513;
                3: fixed_c4_step=32'd13683509;
                4: fixed_c4_step=32'd14497173;
                5: fixed_c4_step=32'd15359220;
                6: fixed_c4_step=32'd16272527;
                7: fixed_c4_step=32'd17240142;
                8: fixed_c4_step=32'd18265294;
                9: fixed_c4_step=32'd19351405;
                10: fixed_c4_step=32'd20502099;
                11: fixed_c4_step=32'd21721217;
                default: fixed_c4_step=0;
            endcase
        end
    endfunction
    genvar g;
    generate for(g=0;g<12;g=g+1) begin: phase_luts
        localparam [31:0] C4_STEP=fixed_c4_step(g);
        reg [31:0] octave_step;
        always @* begin
            case(voice_octaves[g*4+:4])
                4'd2: octave_step=C4_STEP>>2;
                4'd3: octave_step=C4_STEP>>1;
                4'd5: octave_step=C4_STEP<<1;
                4'd6: octave_step=C4_STEP<<2;
                default: octave_step=C4_STEP;
            endcase
        end
        assign target_steps[g*32+:32]=octave_step;
        // 暂停滑音：琴键/摇杆八度的目标步进直接送入声部。
        assign voice_steps[g*32+:32]=target_steps[g*32+:32];
    end endgenerate
    always @(posedge clk) begin
        if(rst) begin
            voice_gate<=0;
            voice_trigger<=0;
            voice_octaves<={12{4'd4}};
        end else begin
            voice_trigger<=0;
            if(control_valid) begin
                voice_gate<=note_gate;
                voice_trigger<=note_press;
                voice_octaves<=note_octaves;
            end
        end
    end
endmodule
