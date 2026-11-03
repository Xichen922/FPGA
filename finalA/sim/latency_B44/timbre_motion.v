`timescale 1ns/1ps
// Shared per-sample expression gain. Pure deterministic HDL; no PCM playback.
// Keyboard/clarinet: unity; organ retains its gentle breathing gain.
// Organ: ~0.600Hz sine breathing, gain 0.8755..0.9995, no pitch modulation.
module latb_timbre_motion (
    input wire clk, rst, sample_tick,
    input wire [1:0] timbre_select,
    output reg [15:0] gain_q15
);
    reg [23:0] breath_phase;
    wire [6:0] quarter_index=breath_phase[22] ?
        7'd64-{1'b0,breath_phase[21:16]} : {1'b0,breath_phase[21:16]};
    reg [6:0] magnitude;
    wire signed [7:0] breath_sine=breath_phase[23] ?
        -$signed({1'b0,magnitude}) : $signed({1'b0,magnitude});
    wire signed [16:0] organ_gain=17'sd30720+
        ($signed({{9{breath_sine[7]}},breath_sine}) <<< 4);
    always @* begin
        case(quarter_index)
            7'd0: magnitude=7'd0;
            7'd1: magnitude=7'd3;
            7'd2: magnitude=7'd6;
            7'd3: magnitude=7'd9;
            7'd4: magnitude=7'd12;
            7'd5: magnitude=7'd16;
            7'd6: magnitude=7'd19;
            7'd7: magnitude=7'd22;
            7'd8: magnitude=7'd25;
            7'd9: magnitude=7'd28;
            7'd10: magnitude=7'd31;
            7'd11: magnitude=7'd34;
            7'd12: magnitude=7'd37;
            7'd13: magnitude=7'd40;
            7'd14: magnitude=7'd43;
            7'd15: magnitude=7'd46;
            7'd16: magnitude=7'd49;
            7'd17: magnitude=7'd51;
            7'd18: magnitude=7'd54;
            7'd19: magnitude=7'd57;
            7'd20: magnitude=7'd60;
            7'd21: magnitude=7'd63;
            7'd22: magnitude=7'd65;
            7'd23: magnitude=7'd68;
            7'd24: magnitude=7'd71;
            7'd25: magnitude=7'd73;
            7'd26: magnitude=7'd76;
            7'd27: magnitude=7'd78;
            7'd28: magnitude=7'd81;
            7'd29: magnitude=7'd83;
            7'd30: magnitude=7'd85;
            7'd31: magnitude=7'd88;
            7'd32: magnitude=7'd90;
            7'd33: magnitude=7'd92;
            7'd34: magnitude=7'd94;
            7'd35: magnitude=7'd96;
            7'd36: magnitude=7'd98;
            7'd37: magnitude=7'd100;
            7'd38: magnitude=7'd102;
            7'd39: magnitude=7'd104;
            7'd40: magnitude=7'd106;
            7'd41: magnitude=7'd107;
            7'd42: magnitude=7'd109;
            7'd43: magnitude=7'd111;
            7'd44: magnitude=7'd112;
            7'd45: magnitude=7'd113;
            7'd46: magnitude=7'd115;
            7'd47: magnitude=7'd116;
            7'd48: magnitude=7'd117;
            7'd49: magnitude=7'd118;
            7'd50: magnitude=7'd120;
            7'd51: magnitude=7'd121;
            7'd52: magnitude=7'd122;
            7'd53: magnitude=7'd122;
            7'd54: magnitude=7'd123;
            7'd55: magnitude=7'd124;
            7'd56: magnitude=7'd125;
            7'd57: magnitude=7'd125;
            7'd58: magnitude=7'd126;
            7'd59: magnitude=7'd126;
            7'd60: magnitude=7'd126;
            7'd61: magnitude=7'd127;
            7'd62: magnitude=7'd127;
            7'd63: magnitude=7'd127;
            7'd64: magnitude=7'd127;
            default: magnitude=0;
        endcase
        case(timbre_select)
            2'd2: gain_q15=organ_gain[15:0];
            default: gain_q15=16'd32768;
        endcase
    end
    always @(posedge clk) begin
        if(rst) breath_phase<=0;
        else if(sample_tick) breath_phase<=breath_phase+24'd103;
    end
endmodule
