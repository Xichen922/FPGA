`timescale 1ns/1ps
// HMI page0: t0..t11 keys, t12 timbre, t13 octave, t14 effect, s0 waveform.
// The optional extended display uses the screen's 115200/8N1 setting.
// This block never stalls the audio path. Status labels are refreshed periodically.
module latb_db_hmi_tx #(
    parameter integer CLK_HZ=50000000,
    parameter integer BAUD=115200,
    parameter integer STARTUP_CYCLES=50000000,
    parameter integer STATUS_REFRESH_CYCLES=150000000,
    parameter integer WAVE_CYCLES=2000000
) (
    input wire clk, rst_n,
    input wire [11:0] keys,
    input wire [1:0] timbre,
    input wire [1:0] effect_mode,
    input wire [3:0] octave,
    input wire sound_active,
    input wire vibrato_active, wave_ready,
    input wire [7:0] effect_depth,wave_data,
    output wire [6:0] wave_address,output reg wave_ack,
    output wire tx
);
    localparam [3:0] KEY=4'd1, TIMBRE=4'd2, OCTAVE=4'd3, WAVE=4'd4,
                     KEY_REF=4'd5, TIMBRE_REF=4'd6, OCTAVE_REF=4'd7,
                     EFFECT=4'd8, EFFECT_REF=4'd9, KEY_TEXT=4'd10;
    localparam [1:0] IDLE=2'd0, ISSUE=2'd1, WAIT_DONE=2'd2;
    reg [1:0] state;
    reg [3:0] kind;
    reg [5:0] pos, length;
    reg [3:0] key_index, octave_value;
    reg key_on;
    reg [1:0] timbre_value, effect_value, sent_effect;
    reg force_effect;
    wire [1:0] display_effect=effect_mode;
    reg [6:0] wave_index;assign wave_address=wave_index;
    reg [7:0] depth_value,sent_depth;reg vibrato_value,sent_vibrato;
    reg [7:0] wave_value;
    reg [5:0] wave_phase;
    reg [11:0] sent_keys, force_keys;
    reg [1:0] sent_timbre;
    reg [3:0] sent_octave;
    reg force_timbre, force_octave;
    reg [31:0] boot_counter, status_refresh_counter, wave_counter;
    reg wave_due;
    reg [7:0] tx_data;
    reg tx_valid;
    wire tx_ready, tx_done;
    latb_uart_tx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) u_tx (
        .clk(clk), .rst_n(rst_n), .data(tx_data), .valid(tx_valid),
        .ready(tx_ready), .tx(tx), .done(tx_done));

    wire [11:0] pending_keys=(keys ^ sent_keys) | force_keys;
    reg key_pending;
    reg [3:0] next_key;
    integer i;
    always @* begin
        key_pending=1'b0;
        next_key=4'd0;
        for(i=0;i<12;i=i+1)
            if(pending_keys[i] && !key_pending) begin
                key_pending=1'b1;
                next_key=i;
            end
    end

    function [7:0] timbre_char;
        input [1:0] choice;
        input [2:0] index;
        begin
            timbre_char=8'h20;
            // GB2312: 钢琴 / 单簧管 / 风琴 / 八音盒.
            case(choice)
                2'd0: case(index)
                    0:timbre_char=8'hB8;1:timbre_char=8'hD6;
                    2:timbre_char=8'hC7;3:timbre_char=8'hD9;
                endcase
                2'd1: case(index)
                    0:timbre_char=8'hB5;1:timbre_char=8'hA5;
                    2:timbre_char=8'hBB;3:timbre_char=8'hC9;
                    4:timbre_char=8'hB9;5:timbre_char=8'hDC;
                endcase
                2'd2: case(index)
                    0:timbre_char=8'hB7;1:timbre_char=8'hE7;
                    2:timbre_char=8'hC7;3:timbre_char=8'hD9;
                endcase
                2'd3: case(index)
                    0:timbre_char=8'hB0;1:timbre_char=8'hCB;
                    2:timbre_char=8'hD2;3:timbre_char=8'hF4;
                    4:timbre_char=8'hBA;5:timbre_char=8'hD0;
                endcase
            endcase
        end
    endfunction

    // GB2312: 自然 / 回声 / 倒放尾音, written to page0.t14.
    function [7:0] effect_char;
        input [1:0] choice; input [2:0] index;
        begin
            effect_char=8'h20;
            case(choice)
                2'd0:case(index) 0:effect_char=8'hd7; 1:effect_char=8'hd4; 2:effect_char=8'hc8; 3:effect_char=8'hbb; endcase
                2'd1:case(index) 0:effect_char=8'hbb; 1:effect_char=8'hd8; 2:effect_char=8'hc9; 3:effect_char=8'hf9; endcase
                2'd2:case(index)
                    0:effect_char=8'hb5;1:effect_char=8'hb9;
                    2:effect_char=8'hb7;3:effect_char=8'hc5;
                    4:effect_char=8'hce;5:effect_char=8'hb2;
                    6:effect_char=8'hd2;7:effect_char=8'hf4;
                endcase
            endcase
        end
    endfunction

    function [7:0] octave_char;
        input [3:0] choice;
        input [2:0] index;
        begin
            octave_char=8'h20;
            // GB2312: 低八度 / 中八度 / 高八度.
            case(index)
                0:case(choice)
                    4'd3:octave_char=8'hB5;
                    4'd5:octave_char=8'hB8;
                    default:octave_char=8'hD6;
                endcase
                1:case(choice)
                    4'd3:octave_char=8'hCD;
                    4'd5:octave_char=8'hDF;
                    default:octave_char=8'hD0;
                endcase
                2:octave_char=8'hB0;
                3:octave_char=8'hCB;
                4:octave_char=8'hB6;
                5:octave_char=8'hC8;
            endcase
        end
    endfunction

    // Legacy demo helpers below are unused; production s0 points come from actual PCM. The
    // 252x245 widget is only an illustrative display, not live PCM.
    function [7:0] quarter_magnitude;
        input [4:0] index;
        begin
            case(index)
                0:quarter_magnitude=0;   1:quarter_magnitude=11;
                2:quarter_magnitude=21;  3:quarter_magnitude=32;
                4:quarter_magnitude=42;  5:quarter_magnitude=52;
                6:quarter_magnitude=61;  7:quarter_magnitude=70;
                8:quarter_magnitude=78;  9:quarter_magnitude=85;
                10:quarter_magnitude=91; 11:quarter_magnitude=97;
                12:quarter_magnitude=102;13:quarter_magnitude=105;
                14:quarter_magnitude=108;15:quarter_magnitude=109;
                default:quarter_magnitude=110;
            endcase
        end
    endfunction
    // Illustrative curve, not downsampled PCM audio.
    function [7:0] demo_point;
        input [5:0] phase;
        reg [4:0] quarter_index;
        reg [7:0] magnitude;
        begin
            if(phase[4]) quarter_index=5'd16-{1'b0,phase[3:0]};
            else quarter_index={1'b0,phase[3:0]};
            magnitude=quarter_magnitude(quarter_index);
            if(phase[5]) demo_point=8'd128-magnitude;
            else demo_point=8'd128+magnitude;
        end
    endfunction
    function [23:0] demo_digits;
        input [7:0] value;
        reg [7:0] remainder;
        reg [3:0] hundreds, tens;
        begin
            remainder=value;
            hundreds=0;
            tens=0;
            if(remainder>=8'd200) begin
                hundreds=2;
                remainder=remainder-8'd200;
            end else if(remainder>=8'd100) begin
                hundreds=1;
                remainder=remainder-8'd100;
            end
            if(remainder>=8'd80) begin
                tens=tens+4'd8;
                remainder=remainder-8'd80;
            end
            if(remainder>=8'd40) begin
                tens=tens+4'd4;
                remainder=remainder-8'd40;
            end
            if(remainder>=8'd20) begin
                tens=tens+4'd2;
                remainder=remainder-8'd20;
            end
            if(remainder>=8'd10) begin
                tens=tens+4'd1;
                remainder=remainder-8'd10;
            end
            demo_digits={8'd48+hundreds,8'd48+tens,8'd48+remainder};
        end
    endfunction
    wire [23:0] point_ascii=demo_digits(wave_value);
    wire [15:0] depth_percent=(depth_value*16'd100)>>7;
    wire [23:0] depth_ascii=demo_digits(depth_percent[7:0]);

    reg [7:0] command_byte;
    reg [4:0] key_prefix;
    reg [4:0] offset;
    reg [4:0] word_length;
    always @* begin
        command_byte=8'hFF;
        key_prefix=(key_index<10) ? 2 : 3;
        offset=0;
        word_length=(timbre_value==2'd0 || timbre_value==2'd2) ? 4 : 6;
        case(kind)
            KEY, KEY_TEXT: begin
                if(pos==0) command_byte="t";
                else if(pos==1)
                    command_byte=(key_index<10) ? (8'h30+key_index) : "1";
                else if(key_index>=10 && pos==2)
                    command_byte=8'h30+(key_index-10);
                else if(pos<key_prefix+5) begin
                    offset=pos-key_prefix;
                    case(offset)
                        0:command_byte=".";1:command_byte=(kind==KEY_TEXT) ? "p" : "b";
                        2:command_byte="c";3:command_byte="o";
                        4:command_byte="=";
                    endcase
                end else if(pos<key_prefix+((kind==KEY_TEXT && !key_on) ? 10 : 9)) begin
                    offset=pos-key_prefix-5;
                    case(offset)
                        // RGB565: pressed bco=9942, pco=4292 (mint/dark).
                        // Released bco=6471, pco=61343 (navy/light).
                        0:command_byte=(kind==KEY_TEXT) ?
                            (key_on ? "4" : "6") : (key_on ? "9" : "6");
                        1:command_byte=(kind==KEY_TEXT) ?
                            (key_on ? "2" : "1") : (key_on ? "9" : "4");
                        2:command_byte=(kind==KEY_TEXT) ?
                            (key_on ? "9" : "3") : (key_on ? "4" : "7");
                        3:command_byte=(kind==KEY_TEXT) ?
                            (key_on ? "2" : "4") : (key_on ? "2" : "1");
                        4:command_byte="3";
                    endcase
                end
            end
            TIMBRE, OCTAVE, EFFECT: begin
                case(pos)
                    0:command_byte="t";1:command_byte="1";
                    2:command_byte=(kind==TIMBRE)?"2":(kind==OCTAVE)?"3":"4";
                    3:command_byte=".";4:command_byte="t";5:command_byte="x";6:command_byte="t";7:command_byte="=";8:command_byte="\"";
                    default:begin
                        if(kind==EFFECT)begin
                            if(pos<9+((effect_value==2)?8:4))command_byte=effect_char(effect_value,pos-9);
                            else if(pos==9+((effect_value==2)?8:4))command_byte=" ";
                            else if(pos==10+((effect_value==2)?8:4))command_byte=depth_ascii[23:16];
                            else if(pos==11+((effect_value==2)?8:4))command_byte=depth_ascii[15:8];
                            else if(pos==12+((effect_value==2)?8:4))command_byte=depth_ascii[7:0];
                            else if(pos==13+((effect_value==2)?8:4))command_byte="%";
                            else if(pos==14+((effect_value==2)?8:4))command_byte="\"";
                        end else if(kind==OCTAVE)begin
                            if(pos<15)command_byte=octave_char(octave_value,pos-9);
                            else case(pos)15:command_byte=" ";16:command_byte="V";17:command_byte=vibrato_value?"1":"0";18:command_byte="\"";endcase
                        end else if(pos<9+word_length)command_byte=timbre_char(timbre_value,pos-9);
                        else if(pos==9+word_length)command_byte="\"";
                    end
                endcase
            end
            WAVE: begin
                case(pos)
                    0:command_byte="a";1:command_byte="d";
                    2:command_byte="d";3:command_byte=" ";
                    4:command_byte="s";5:command_byte="0";
                    6:command_byte=".";7:command_byte="i";
                    8:command_byte="d";9:command_byte=",";
                    10:command_byte="0";11:command_byte=",";
                    12:command_byte=point_ascii[23:16];
                    13:command_byte=point_ascii[15:8];
                    14:command_byte=point_ascii[7:0];
                endcase
            end
            KEY_REF, TIMBRE_REF, OCTAVE_REF, EFFECT_REF: begin
                case(pos)
                    0:command_byte="r";1:command_byte="e";
                    2:command_byte="f";3:command_byte=" ";
                    4:command_byte="t";
                    5:command_byte=(kind==KEY_REF && key_index<10) ?
                        (8'h30+key_index) : "1";
                    6:if(kind==TIMBRE_REF) command_byte="2";
                       else if(kind==OCTAVE_REF) command_byte="3";
                       else if(kind==EFFECT_REF) command_byte="4";
                       else if(key_index>=10) command_byte=8'h30+(key_index-10);
                endcase
            end
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=IDLE; kind<=0; pos<=0; length<=0;
            key_index<=0; key_on<=0; timbre_value<=0; octave_value<=4;
            wave_value<=128; wave_phase<=0;wave_index<=0;wave_ack<=0;depth_value<=0;sent_depth<=0;vibrato_value<=0;sent_vibrato<=0;
            sent_keys<=0; force_keys<=12'hFFF;
            sent_timbre<=0; sent_octave<=4;
            force_timbre<=1; force_octave<=1;force_effect<=1;effect_value<=0;sent_effect<=0;
            boot_counter<=0; status_refresh_counter<=0;
            wave_counter<=0; wave_due<=0;
            tx_data<=0; tx_valid<=0;
        end else begin
            tx_valid<=0;wave_ack<=0;
            if(boot_counter<STARTUP_CYCLES)
                boot_counter<=boot_counter+1'b1;
            // Refresh the labels occasionally so an independently restarted
            // HMI recovers even when the selected values have not changed.
            if(status_refresh_counter>=STATUS_REFRESH_CYCLES-1) begin
                status_refresh_counter<=0;
                force_timbre<=1;
                force_octave<=1;force_effect<=1;
            end else status_refresh_counter<=status_refresh_counter+1'b1;
            if(wave_counter>=WAVE_CYCLES-1) begin
                wave_counter<=0;
                wave_due<=1;
            end else wave_counter<=wave_counter+1'b1;
            case(state)
                IDLE: if(boot_counter>=STARTUP_CYCLES) begin
                    pos<=0;
                    // The default labels must appear before the 12 key
                    // backgrounds are refreshed over the slow 9600-baud link.
                    if(force_timbre || timbre!=sent_timbre) begin
                        kind<=TIMBRE;
                        timbre_value<=timbre;
                        length<=(timbre==2'd0 || timbre==2'd2) ? 6'd17 : 6'd19;
                        state<=ISSUE;
                    end else if(force_octave || octave!=sent_octave || vibrato_active!=sent_vibrato) begin
                        kind<=OCTAVE;
                        octave_value<=octave;vibrato_value<=vibrato_active;
                        length<=6'd22;
                        state<=ISSUE;
                    end else if(force_effect || display_effect!=sent_effect || effect_depth!=sent_depth) begin
                        kind<=EFFECT;effect_value<=display_effect;depth_value<=effect_depth;
                        length<=display_effect==2 ? 6'd26 : 6'd22;state<=ISSUE;
                    end else if(key_pending) begin
                        kind<=KEY;
                        key_index<=next_key;
                        key_on<=keys[next_key];
                        length<=(next_key<10) ? 6'd14 : 6'd15;
                        state<=ISSUE;
                    end else if(wave_ready && !wave_ack) begin
                        kind<=WAVE;
                        wave_value<=wave_data;
                        wave_phase<=wave_phase+1'b1;
                        length<=6'd18;
                        wave_due<=0;
                        state<=ISSUE;
                    end
                end
                ISSUE: if(tx_ready) begin
                    tx_data<=command_byte;
                    tx_valid<=1;
                    state<=WAIT_DONE;
                end
                WAIT_DONE: if(tx_done) begin
                    if(pos+1'b1<length) begin
                        pos<=pos+1'b1;
                        state<=ISSUE;
                    end else begin
                        case(kind)
                            KEY:begin
                                // Finish both colors using the captured key state,
                                // then refresh and acknowledge this key together.
                                kind<=KEY_TEXT;
                                pos<=0;
                                length<=(key_index<10) ?
                                    (key_on ? 6'd14 : 6'd15) :
                                    (key_on ? 6'd15 : 6'd16);
                                state<=ISSUE;
                            end
                            KEY_TEXT:begin
                                kind<=KEY_REF;
                                pos<=0;
                                length<=(key_index<10) ? 6'd9 : 6'd10;
                                state<=ISSUE;
                            end
                            TIMBRE:begin
                                kind<=TIMBRE_REF;
                                pos<=0;
                                length<=6'd10;
                                state<=ISSUE;
                            end
                            OCTAVE:begin
                                kind<=OCTAVE_REF;
                                pos<=0;
                                length<=6'd10;
                                state<=ISSUE;
                            end
                            EFFECT:begin
                                kind<=EFFECT_REF;pos<=0;length<=6'd10;state<=ISSUE;
                            end
                            EFFECT_REF:begin
                                sent_effect<=effect_value;sent_depth<=depth_value;force_effect<=0;state<=IDLE;
                            end
                            KEY_REF:begin
                                sent_keys[key_index]<=key_on;
                                force_keys[key_index]<=0;
                                state<=IDLE;
                            end
                            TIMBRE_REF:begin
                                sent_timbre<=timbre_value;
                                force_timbre<=0;
                                state<=IDLE;
                            end
                            OCTAVE_REF:begin
                                sent_octave<=octave_value;sent_vibrato<=vibrato_value;
                                force_octave<=0;
                                state<=IDLE;
                            end
                            WAVE:begin
                                if(wave_index==127)begin wave_index<=0;wave_ack<=1;end else wave_index<=wave_index+1'b1;
                                state<=IDLE;
                            end
                            default:state<=IDLE;
                        endcase
                    end
                end
            endcase
        end
    end
endmodule
