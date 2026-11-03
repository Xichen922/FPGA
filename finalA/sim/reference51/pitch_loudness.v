`timescale 1ns/1ps
// Four independent Q13 gain profiles (unity=8192, range up to almost8x).
// Match the louder original v5 profile at each note; no original timbre is turned down.
// v8 music-box coefficients are recalibrated at the common played register.
// v5 example33 piano: match the unchanged other instruments over80..500ms of held tone.
// Offline calibration folds into constants; the 16-clock multiplier is retained.
// SMOOTH_STEP remains in Q15 units; slew is converted to Q13 without extra DSP.
// Saturate amplified voice samples to24 bits before the widened final mix.
module ref51_pitch_loudness #(
    parameter integer NOTE_INDEX=0,
    parameter integer ENABLE=1,
    parameter integer SMOOTH_STEP=32
) (
    input wire clk, rst, sample_tick, trigger,
    input wire [1:0] timbre_select,
    input wire [3:0] octave,
    input wire signed [23:0] sample_in,
    input wire sample_in_valid,
    output reg signed [23:0] sample_out,
    output reg sample_out_valid
);
    reg [15:0] current_gain, frame_gain;
    function [15:0] gain_coefficient;
        input integer index;
        input [1:0] timbre;
        begin
            case(timbre)
                2'd1: begin
                    case(index)
                        0: gain_coefficient=16'd7782;
                        1: gain_coefficient=16'd7488;
                        2: gain_coefficient=16'd7207;
                        3: gain_coefficient=16'd6935;
                        4: gain_coefficient=16'd6674;
                        5: gain_coefficient=16'd6882;
                        6: gain_coefficient=16'd6622;
                        7: gain_coefficient=16'd6376;
                        8: gain_coefficient=16'd6134;
                        9: gain_coefficient=16'd5884;
                        10: gain_coefficient=16'd5660;
                        11: gain_coefficient=16'd5447;
                        12: gain_coefficient=16'd5260;
                        13: gain_coefficient=16'd5063;
                        14: gain_coefficient=16'd4860;
                        15: gain_coefficient=16'd4675;
                        16: gain_coefficient=16'd4491;
                        17: gain_coefficient=16'd4317;
                        18: gain_coefficient=16'd4147;
                        19: gain_coefficient=16'd3984;
                        20: gain_coefficient=16'd3802;
                        21: gain_coefficient=16'd3630;
                        22: gain_coefficient=16'd3485;
                        23: gain_coefficient=16'd3343;
                        24: gain_coefficient=16'd3098;
                        25: gain_coefficient=16'd2981;
                        26: gain_coefficient=16'd2869;
                        27: gain_coefficient=16'd2761;
                        28: gain_coefficient=16'd2657;
                        29: gain_coefficient=16'd2557;
                        30: gain_coefficient=16'd2461;
                        31: gain_coefficient=16'd2368;
                        32: gain_coefficient=16'd2279;
                        33: gain_coefficient=16'd2193;
                        34: gain_coefficient=16'd2111;
                        35: gain_coefficient=16'd2031;
                        36: gain_coefficient=16'd1952;
                        37: gain_coefficient=16'd1878;
                        38: gain_coefficient=16'd1808;
                        39: gain_coefficient=16'd1740;
                        40: gain_coefficient=16'd1674;
                        41: gain_coefficient=16'd1611;
                        42: gain_coefficient=16'd1551;
                        43: gain_coefficient=16'd1492;
                        44: gain_coefficient=16'd1436;
                        45: gain_coefficient=16'd1382;
                        46: gain_coefficient=16'd1330;
                        47: gain_coefficient=16'd1280;
                        48: gain_coefficient=16'd1230;
                        49: gain_coefficient=16'd1184;
                        50: gain_coefficient=16'd1139;
                        51: gain_coefficient=16'd1096;
                        52: gain_coefficient=16'd1055;
                        53: gain_coefficient=16'd1015;
                        54: gain_coefficient=16'd977;
                        55: gain_coefficient=16'd940;
                        56: gain_coefficient=16'd905;
                        57: gain_coefficient=16'd871;
                        58: gain_coefficient=16'd838;
                        59: gain_coefficient=16'd807;
                        default: gain_coefficient=16'd807;
                    endcase
                end
                2'd2: begin
                    case(index)
                        0: gain_coefficient=16'd7579;
                        1: gain_coefficient=16'd7303;
                        2: gain_coefficient=16'd7034;
                        3: gain_coefficient=16'd6773;
                        4: gain_coefficient=16'd6522;
                        5: gain_coefficient=16'd4687;
                        6: gain_coefficient=16'd4511;
                        7: gain_coefficient=16'd4343;
                        8: gain_coefficient=16'd4177;
                        9: gain_coefficient=16'd4023;
                        10: gain_coefficient=16'd3869;
                        11: gain_coefficient=16'd3726;
                        12: gain_coefficient=16'd3585;
                        13: gain_coefficient=16'd3449;
                        14: gain_coefficient=16'd3319;
                        15: gain_coefficient=16'd3195;
                        16: gain_coefficient=16'd3073;
                        17: gain_coefficient=16'd2958;
                        18: gain_coefficient=16'd2846;
                        19: gain_coefficient=16'd2740;
                        20: gain_coefficient=16'd2637;
                        21: gain_coefficient=16'd2537;
                        22: gain_coefficient=16'd2442;
                        23: gain_coefficient=16'd2350;
                        24: gain_coefficient=16'd2352;
                        25: gain_coefficient=16'd2266;
                        26: gain_coefficient=16'd2183;
                        27: gain_coefficient=16'd2090;
                        28: gain_coefficient=16'd2011;
                        29: gain_coefficient=16'd2076;
                        30: gain_coefficient=16'd1997;
                        31: gain_coefficient=16'd1918;
                        32: gain_coefficient=16'd1841;
                        33: gain_coefficient=16'd1770;
                        34: gain_coefficient=16'd1698;
                        35: gain_coefficient=16'd1628;
                        36: gain_coefficient=16'd1482;
                        37: gain_coefficient=16'd1428;
                        38: gain_coefficient=16'd1376;
                        39: gain_coefficient=16'd1317;
                        40: gain_coefficient=16'd1267;
                        41: gain_coefficient=16'd1308;
                        42: gain_coefficient=16'd1259;
                        43: gain_coefficient=16'd1209;
                        44: gain_coefficient=16'd1160;
                        45: gain_coefficient=16'd1116;
                        46: gain_coefficient=16'd1070;
                        47: gain_coefficient=16'd1026;
                        48: gain_coefficient=16'd934;
                        49: gain_coefficient=16'd900;
                        50: gain_coefficient=16'd867;
                        51: gain_coefficient=16'd830;
                        52: gain_coefficient=16'd799;
                        53: gain_coefficient=16'd824;
                        54: gain_coefficient=16'd793;
                        55: gain_coefficient=16'd762;
                        56: gain_coefficient=16'd731;
                        57: gain_coefficient=16'd703;
                        58: gain_coefficient=16'd674;
                        59: gain_coefficient=16'd647;
                        default: gain_coefficient=16'd647;
                    endcase
                end
                2'd3: begin
                    case(index)
                        0: gain_coefficient=16'd7005;
                        1: gain_coefficient=16'd6986;
                        2: gain_coefficient=16'd7015;
                        3: gain_coefficient=16'd7055;
                        4: gain_coefficient=16'd7024;
                        5: gain_coefficient=16'd6388;
                        6: gain_coefficient=16'd6590;
                        7: gain_coefficient=16'd6771;
                        8: gain_coefficient=16'd6935;
                        9: gain_coefficient=16'd7086;
                        10: gain_coefficient=16'd7197;
                        11: gain_coefficient=16'd7183;
                        12: gain_coefficient=16'd7197;
                        13: gain_coefficient=16'd7279;
                        14: gain_coefficient=16'd7372;
                        15: gain_coefficient=16'd7442;
                        16: gain_coefficient=16'd7507;
                        17: gain_coefficient=16'd7553;
                        18: gain_coefficient=16'd7608;
                        19: gain_coefficient=16'd7670;
                        20: gain_coefficient=16'd7679;
                        21: gain_coefficient=16'd7706;
                        22: gain_coefficient=16'd7739;
                        23: gain_coefficient=16'd7752;
                        24: gain_coefficient=16'd7786;
                        25: gain_coefficient=16'd7781;
                        26: gain_coefficient=16'd7778;
                        27: gain_coefficient=16'd7763;
                        28: gain_coefficient=16'd7750;
                        29: gain_coefficient=16'd7734;
                        30: gain_coefficient=16'd7725;
                        31: gain_coefficient=16'd7720;
                        32: gain_coefficient=16'd7704;
                        33: gain_coefficient=16'd7696;
                        34: gain_coefficient=16'd7674;
                        35: gain_coefficient=16'd7671;
                        36: gain_coefficient=16'd7909;
                        37: gain_coefficient=16'd7641;
                        38: gain_coefficient=16'd7381;
                        39: gain_coefficient=16'd7092;
                        40: gain_coefficient=16'd6848;
                        41: gain_coefficient=16'd7100;
                        42: gain_coefficient=16'd6858;
                        43: gain_coefficient=16'd6616;
                        44: gain_coefficient=16'd6376;
                        45: gain_coefficient=16'd6151;
                        46: gain_coefficient=16'd5917;
                        47: gain_coefficient=16'd5686;
                        48: gain_coefficient=16'd4983;
                        49: gain_coefficient=16'd4813;
                        50: gain_coefficient=16'd4650;
                        51: gain_coefficient=16'd4468;
                        52: gain_coefficient=16'd4314;
                        53: gain_coefficient=16'd4473;
                        54: gain_coefficient=16'd4320;
                        55: gain_coefficient=16'd4168;
                        56: gain_coefficient=16'd4017;
                        57: gain_coefficient=16'd3875;
                        58: gain_coefficient=16'd3728;
                        59: gain_coefficient=16'd3582;
                        default: gain_coefficient=16'd3582;
                    endcase
                end
                default: begin
                    case(index)
                        0: gain_coefficient=16'd12156;
                        1: gain_coefficient=16'd12103;
                        2: gain_coefficient=16'd12018;
                        3: gain_coefficient=16'd13041;
                        4: gain_coefficient=16'd12705;
                        5: gain_coefficient=16'd9310;
                        6: gain_coefficient=16'd9113;
                        7: gain_coefficient=16'd8934;
                        8: gain_coefficient=16'd8759;
                        9: gain_coefficient=16'd10460;
                        10: gain_coefficient=16'd10335;
                        11: gain_coefficient=16'd10217;
                        12: gain_coefficient=16'd10122;
                        13: gain_coefficient=16'd10015;
                        14: gain_coefficient=16'd9912;
                        15: gain_coefficient=16'd7542;
                        16: gain_coefficient=16'd7415;
                        17: gain_coefficient=16'd7297;
                        18: gain_coefficient=16'd7178;
                        19: gain_coefficient=16'd7084;
                        20: gain_coefficient=16'd7005;
                        21: gain_coefficient=16'd9847;
                        22: gain_coefficient=16'd9926;
                        23: gain_coefficient=16'd9983;
                        24: gain_coefficient=16'd10465;
                        25: gain_coefficient=16'd10572;
                        26: gain_coefficient=16'd10666;
                        27: gain_coefficient=16'd7719;
                        28: gain_coefficient=16'd7806;
                        29: gain_coefficient=16'd8492;
                        30: gain_coefficient=16'd8622;
                        31: gain_coefficient=16'd8782;
                        32: gain_coefficient=16'd8949;
                        33: gain_coefficient=16'd10744;
                        34: gain_coefficient=16'd11004;
                        35: gain_coefficient=16'd11253;
                        36: gain_coefficient=16'd6431;
                        37: gain_coefficient=16'd6511;
                        38: gain_coefficient=16'd6588;
                        39: gain_coefficient=16'd4787;
                        40: gain_coefficient=16'd4856;
                        41: gain_coefficient=16'd5298;
                        42: gain_coefficient=16'd5395;
                        43: gain_coefficient=16'd5511;
                        44: gain_coefficient=16'd5627;
                        45: gain_coefficient=16'd6770;
                        46: gain_coefficient=16'd6944;
                        47: gain_coefficient=16'd7108;
                        48: gain_coefficient=16'd4051;
                        49: gain_coefficient=16'd4102;
                        50: gain_coefficient=16'd4150;
                        51: gain_coefficient=16'd3016;
                        52: gain_coefficient=16'd3059;
                        53: gain_coefficient=16'd3338;
                        54: gain_coefficient=16'd3399;
                        55: gain_coefficient=16'd3472;
                        56: gain_coefficient=16'd3546;
                        57: gain_coefficient=16'd4266;
                        58: gain_coefficient=16'd4375;
                        59: gain_coefficient=16'd4478;
                        default: gain_coefficient=16'd4478;
                    endcase
                end
            endcase
        end
    endfunction
    localparam [15:0] T0_O3=gain_coefficient(0+NOTE_INDEX,2'd0);
    localparam [15:0] T0_O4=gain_coefficient(12+NOTE_INDEX,2'd0);
    localparam [15:0] T0_O5=gain_coefficient(24+NOTE_INDEX,2'd0);
    localparam [15:0] T0_O6=gain_coefficient(36+NOTE_INDEX,2'd0);
    localparam [15:0] T0_O7=gain_coefficient(48+NOTE_INDEX,2'd0);
    // Compile-time constants avoid adding a per-voice runtime multiplier or adder.
    // Piano table already contains the complete Q13 gain, including register calibration.
    localparam [15:0] K0_O4=T0_O4;
    // Final decoded piano coefficients: no additional runtime register trim.
    localparam [15:0] K0_O5=T0_O5;
    localparam [15:0] K0_O6=T0_O6;
    localparam [15:0] K0_O7=T0_O7;
    localparam [15:0] T1_O3=gain_coefficient(0+NOTE_INDEX,2'd1);
    localparam [15:0] T1_O4=gain_coefficient(12+NOTE_INDEX,2'd1);
    localparam [15:0] T1_O5=gain_coefficient(24+NOTE_INDEX,2'd1);
    localparam [15:0] T1_O6=gain_coefficient(36+NOTE_INDEX,2'd1);
    localparam [15:0] T1_O7=gain_coefficient(48+NOTE_INDEX,2'd1);
    localparam [15:0] T2_O3=gain_coefficient(0+NOTE_INDEX,2'd2);
    localparam [15:0] T2_O4=gain_coefficient(12+NOTE_INDEX,2'd2);
    localparam [15:0] T2_O5=gain_coefficient(24+NOTE_INDEX,2'd2);
    localparam [15:0] T2_O6=gain_coefficient(36+NOTE_INDEX,2'd2);
    localparam [15:0] T2_O7=gain_coefficient(48+NOTE_INDEX,2'd2);
    // Music-box calibration is folded into constants; no runtime multiply.
    localparam [15:0] T3_O3=gain_coefficient(0+NOTE_INDEX,2'd3);
    localparam [15:0] T3_O4=gain_coefficient(12+NOTE_INDEX,2'd3);
    localparam [15:0] T3_O5=gain_coefficient(24+NOTE_INDEX,2'd3);
    localparam [15:0] T3_O6=gain_coefficient(36+NOTE_INDEX,2'd3);
    localparam [15:0] T3_O7=gain_coefficient(48+NOTE_INDEX,2'd3);
    localparam [15:0] SLEW_STEP=(SMOOTH_STEP+3)/4;
    reg [15:0] target_gain;
    reg [15:0] profile_gain;
    always @* begin
        case(timbre_select)
            2'd0: profile_gain=
                octave==3 ? T0_O3 :
                octave==4 ? K0_O4 :
                octave==5 ? K0_O5 :
                octave==6 ? K0_O6 :
                octave==7 ? K0_O7 : K0_O4;
            2'd1: profile_gain=
                octave==3 ? T1_O3 :
                octave==4 ? T1_O4 :
                octave==5 ? T1_O5 :
                octave==6 ? T1_O6 :
                octave==7 ? T1_O7 : T1_O4;
            2'd2: profile_gain=
                octave==3 ? T2_O3 :
                octave==4 ? T2_O4 :
                octave==5 ? T2_O5 :
                octave==6 ? T2_O6 :
                octave==7 ? T2_O7 : T2_O4;
            default: profile_gain=
                octave==3 ? T3_O3 :
                octave==4 ? T3_O4 :
                octave==5 ? T3_O5 :
                octave==6 ? T3_O6 :
                octave==7 ? T3_O7 : T3_O4;
        endcase
    end
    wire [15:0] decoded_gain=ENABLE ?
        profile_gain
        : 16'd8192;
    // Register the small octave mux ahead of the audio-rate slew arithmetic.
    // A confirmed octave propagates here in one 50MHz clock, before next frame.
    always @(posedge clk)
        if(rst) target_gain<=16'd8192;
        else target_gain<=decoded_gain;
    // One signed difference replaces the two opposite-direction subtractions.
    // The 17-bit range holds every unsigned-16 gain difference exactly.
    wire signed [16:0] gain_delta=
        $signed({1'b0,target_gain})-$signed({1'b0,current_gain});
    wire [15:0] next_gain=(gain_delta>$signed({1'b0,SLEW_STEP})) ?
        current_gain+SLEW_STEP :
        (gain_delta<-$signed({1'b0,SLEW_STEP})) ?
        current_gain-SLEW_STEP : target_gain;
    // Combined multiplier/product register; exact signed24 x unsigned16 in 16 clocks.
    reg signed [23:0] multiplicand;
    reg signed [39:0] accumulator;
    reg [3:0] bit_count;
    reg busy;
    wire signed [24:0] partial_sum=$signed({accumulator[39],accumulator[39:16]})+
        (accumulator[0] ? $signed({multiplicand[23],multiplicand}) : 25'sd0);
    wire signed [39:0] sum_next={partial_sum,accumulator[15:1]};
    wire signed [39:0] scaled=sum_next >>> 13;
    always @(posedge clk) begin
        if(rst) begin
            current_gain<=16'd8192; frame_gain<=16'd8192;
            sample_out<=0; sample_out_valid<=0;
            multiplicand<=0; accumulator<=0; bit_count<=0; busy<=0;
        end else begin
            sample_out_valid<=0;
            // New notes start at the correct gain while their envelope is zero.
            // Held-note octave/timbre changes retain bounded slew.
            if(trigger) current_gain<=decoded_gain;
            else if(sample_tick) current_gain<=next_gain;
            // Never change the gain of an already-rendering frame on an async key event.
            if(sample_tick) frame_gain<=trigger ? decoded_gain : next_gain;
            if(sample_in_valid) begin
                multiplicand<=sample_in;
                accumulator<={24'd0,frame_gain}; bit_count<=0; busy<=1;
            end else if(busy) begin
                accumulator<=sum_next;
                if(bit_count==15) begin
                    sample_out<=(scaled>40'sd8388607)?24'sh7fffff:
                        (scaled < -40'sd8388608)?24'sh800000:scaled[23:0];
                    sample_out_valid<=1;
                    busy<=0;
                end else bit_count<=bit_count+1'b1;
            end
        end
    end
    // synthesis translate_off
    always @(posedge clk) if(!rst) begin
        if(sample_in_valid && busy) $fatal(1,"gain input overlaps pending sample");
        if(sample_tick && busy) $fatal(1,"gain calculation exceeds frame budget");
    end
    initial if(NOTE_INDEX<0 || NOTE_INDEX>11 || SMOOTH_STEP<1 || SMOOTH_STEP>32768)
        $fatal(1,"invalid ref51_pitch_loudness parameter");
    // synthesis translate_on
endmodule
