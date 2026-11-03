`timescale 1ns/1ps
// Music-box envelope at Fs=97656.25Hz: 1.31ms rounded onset,
// natural exponential decay (~1.16s to -60dB), then exact digital silence.
// Release rings out gently (~0.58s to -60dB).
// Q16 fractional storage keeps the quiet tail moving without a divider.
module plucked_envelope (
    input wire clk,rst,sample_tick,trigger,gate,
    output wire [15:0] level,
    output wire active,
    output reg [2:0] state
);
    localparam [31:0] PEAK_Q16=32'hffff0000;
    localparam [31:0] ATTACK_STEP=32'd33553920; // PEAK_Q16 / 128
    reg [31:0] level_q16;
    wire releasing=(!gate || state==3'd4);
    wire [31:0] decrement=releasing ?
        (level_q16 >> 13) : (level_q16 >> 14);
    assign level=level_q16[31:16];
    assign active=(state!=0);
    always @(posedge clk) begin
        if(rst) begin level_q16<=0;state<=0;end
        else if(trigger) begin
            level_q16<=0;
            state<=gate ? 3'd1 : 3'd0;
        end else if(sample_tick) begin
            if(state==3'd1 && gate) begin
                if(level_q16>=PEAK_Q16-ATTACK_STEP) begin
                    level_q16<=PEAK_Q16;state<=3'd2;
                end else level_q16<=level_q16+ATTACK_STEP;
            end else if(state!=0) begin
                // Stop below one 16-bit envelope LSB, avoiding a residual plateau.
                if(level_q16<=32'd65536) begin level_q16<=0;state<=0;end
                else begin
                    level_q16<=level_q16-decrement;
                    // A released note stays in release until a fresh trigger.
                    state<=releasing ? 3'd4 : 3'd2;
                end
            end
        end
    end
endmodule
