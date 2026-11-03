`timescale 1ns/1ps
// Embedded contest 3 HMI page0: t0..t11 keys, t12 timbre, t13 octave,
// t14 effect, t15 depth text, j0 depth bar, logarithmic spectrum in s0 area.
// Commands use the screen's 115200/8N1 setting.
// This block never stalls the audio path. Status labels are refreshed periodically.
module latb_tjc_display_uart #(
    parameter integer CLK_HZ=50000000,
    parameter integer BAUD=115200,
    parameter integer STARTUP_CYCLES=50000000,
    parameter integer STATUS_REFRESH_CYCLES=150000000,
    parameter integer WAVE_CYCLES=1250000 // One of 16 bands is checked every 25 ms.
) (
    input wire clk, rst_n,
    input wire [11:0] keys,
    input wire guide_active,
    input wire [11:0] guide_keys,
    input wire [1:0] timbre,
    input wire [1:0] effect_mode,
    input wire [7:0] effect_depth,
    input wire [3:0] octave,
    input wire sound_active,
    input wire wave_ready,
    input wire [7:0] wave_data,
    output wire [6:0] wave_address,
    output reg wave_ack,
    output wire tx
);
    localparam [4:0] KEY=5'd1, TIMBRE=5'd2, OCTAVE=5'd3, BAR_FILL=5'd4,
                     KEY_REF=5'd5, TIMBRE_REF=5'd6, OCTAVE_REF=5'd7,
                     EFFECT=5'd8, EFFECT_REF=5'd9, KEY_TEXT=5'd10,
                     PAGE=5'd11, DEPTH_TEXT=5'd12, DEPTH_REF=5'd13,
                     DEPTH_BAR=5'd14, SCOPE_HIDE=5'd15;
    localparam [1:0] IDLE=2'd0, ISSUE=2'd1, WAIT_DONE=2'd2, CALC=2'd3;
    reg [1:0] state;
    reg page_initialized;
    reg [4:0] kind;
    reg [5:0] pos, length;
    reg [3:0] key_index, octave_value;
    reg key_on;
    reg [1:0] key_color;
    reg [1:0] timbre_value, effect_value, sent_effect;
    reg force_effect;
    reg [7:0] depth_value, sent_depth;
    reg force_depth;
    wire [7:0] display_depth=(effect_mode==1 || effect_mode==2) ?
        ((effect_depth>8'd128) ? 8'd128 : effect_depth) : 8'd0;
    wire [7:0] depth_percent=({5'd0, depth_value} * 8'd25) >> 5;
    wire [1:0] display_effect=(effect_mode==1 || effect_mode==2) ? effect_mode : 2'd0;
    wire [3:0] effect_word_length=(effect_value==2) ? 4'd8 : 4'd4;
    reg [1:0] spectrum_stage;
    reg [3:0] band_index, note_index, harmonic_index;
    reg [11:0] scan_keys;
    reg [1:0] scan_timbre;
    reg [3:0] scan_octave;
    reg [7:0] band_sum;
    reg [7:0] shown_height[0:15];
    reg [9:0] fill_x, fill_y, fill_w, fill_h;
    reg [15:0] fill_color;
    reg render_pending;
    reg [7:0] render_height;
    reg [31:0] wave_counter;
    reg wave_due;
    // The graph uses known note and timbre parameters, not the PCM snapshot.
    assign wave_address=7'd0;
    reg [23:0] sent_key_states;
    reg [11:0] force_keys;
    reg [1:0] sent_timbre;
    reg [3:0] sent_octave;
    reg force_timbre, force_octave;
    reg [31:0] boot_counter, status_refresh_counter;
    integer bar_reset_index;
    reg [7:0] tx_data;
    reg tx_valid;
    wire tx_ready, tx_done;
    latb_uart_tx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) u_tx (
        .clk(clk), .rst_n(rst_n), .data(tx_data), .valid(tx_valid),
        .ready(tx_ready), .tx(tx), .done(tx_done));

    wire [23:0] desired_key_states;
    wire [11:0] pending_keys;
    genvar key_n;
    generate for(key_n=0;key_n<12;key_n=key_n+1)begin: key_visual
        // 0 idle, 1 pressed/correct, 2 prompt, 3 wrong physical key.
        assign desired_key_states[key_n*2+:2]=
            guide_active ? (keys[key_n] ?
                (guide_keys[key_n] ? 2'd1 : 2'd3) :
                (guide_keys[key_n] ? 2'd2 : 2'd0)) :
                (keys[key_n] ? 2'd1 : 2'd0);
        assign pending_keys[key_n]=force_keys[key_n] ||
            desired_key_states[key_n*2+:2]!=sent_key_states[key_n*2+:2];
    end endgenerate
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
        input [1:0] choice;
        input [2:0] index;
        begin
            effect_char=8'h20;
            case(choice)
                2'd0:case(index) 0:effect_char=8'hD7;1:effect_char=8'hD4;2:effect_char=8'hC8;3:effect_char=8'hBB; endcase
                2'd1:case(index) 0:effect_char=8'hBB;1:effect_char=8'hD8;2:effect_char=8'hC9;3:effect_char=8'hF9; endcase
                2'd2:case(index)
                    0:effect_char=8'hB5;1:effect_char=8'hB9;
                    2:effect_char=8'hB7;3:effect_char=8'hC5;
                    4:effect_char=8'hCE;5:effect_char=8'hB2;
                    6:effect_char=8'hD2;7:effect_char=8'hF4;
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

    // Band 0 covers C3-D3; every following band spans three semitones.
    // Eight harmonics are enough for a readable approximation of the four
    // known timbres. The source tables contain more terms and time variation.
    function [5:0] harmonic_offset;
        input [3:0] harmonic;
        begin
            case(harmonic)
                1:harmonic_offset=0; 2:harmonic_offset=12;
                3:harmonic_offset=19;4:harmonic_offset=24;
                5:harmonic_offset=28;6:harmonic_offset=31;
                7:harmonic_offset=34;default:harmonic_offset=36;
            endcase
        end
    endfunction
    function [7:0] harmonic_weight;
        input [1:0] selected_timbre;
        input [3:0] harmonic;
        begin
            case(selected_timbre)
                2'd1:case(harmonic) // Clarinet: mainly odd harmonics.
                    1:harmonic_weight=90;2:harmonic_weight=2;
                    3:harmonic_weight=52;4:harmonic_weight=2;
                    5:harmonic_weight=30;6:harmonic_weight=2;
                    7:harmonic_weight=17;default:harmonic_weight=2;
                endcase
                2'd2:case(harmonic) // Organ: strong octaves.
                    1:harmonic_weight=76;2:harmonic_weight=58;
                    3:harmonic_weight=8;4:harmonic_weight=42;
                    5:harmonic_weight=8;6:harmonic_weight=22;
                    7:harmonic_weight=4;default:harmonic_weight=13;
                endcase
                2'd3:case(harmonic) // Music box / pluck.
                    1:harmonic_weight=92;2:harmonic_weight=22;
                    3:harmonic_weight=9;4:harmonic_weight=38;
                    5:harmonic_weight=5;6:harmonic_weight=14;
                    7:harmonic_weight=2;default:harmonic_weight=9;
                endcase
                default:case(harmonic) // Piano.
                    1:harmonic_weight=80;2:harmonic_weight=60;
                    3:harmonic_weight=42;4:harmonic_weight=28;
                    5:harmonic_weight=20;6:harmonic_weight=15;
                    7:harmonic_weight=11;default:harmonic_weight=8;
                endcase
            endcase
        end
    endfunction
    wire [6:0] current_semitone={3'd0,note_index}+
        ((scan_octave==4'd3) ? 7'd0 : (scan_octave==4'd5) ? 7'd24 : 7'd12)+
        {1'b0,harmonic_offset(harmonic_index)};
    wire harmonic_in_band=scan_keys[note_index] &&
        current_semitone>={1'b0,band_index,1'b0}+{3'd0,band_index} &&
        current_semitone<({1'b0,band_index,1'b0}+{3'd0,band_index}+7'd3);
    wire [8:0] band_added={1'b0,band_sum}+
        (harmonic_in_band ? {1'b0,harmonic_weight(scan_timbre,harmonic_index)} : 9'd0);
    wire [7:0] next_band_sum=(band_added>9'd160) ? 8'd160 : band_added[7:0];
    function [23:0] fill_digits;
        input [9:0] value;
        reg [9:0] rem_value;
        reg [3:0] hundreds,tens;
        begin
            rem_value=value;hundreds=0;tens=0;
            if(rem_value>=10'd400)begin hundreds=hundreds+4'd4;rem_value=rem_value-10'd400;end
            if(rem_value>=10'd200)begin hundreds=hundreds+4'd2;rem_value=rem_value-10'd200;end
            if(rem_value>=10'd100)begin hundreds=hundreds+4'd1;rem_value=rem_value-10'd100;end
            if(rem_value>=10'd80)begin tens=tens+4'd8;rem_value=rem_value-10'd80;end
            if(rem_value>=10'd40)begin tens=tens+4'd4;rem_value=rem_value-10'd40;end
            if(rem_value>=10'd20)begin tens=tens+4'd2;rem_value=rem_value-10'd20;end
            if(rem_value>=10'd10)begin tens=tens+4'd1;rem_value=rem_value-10'd10;end
            fill_digits={8'd48+hundreds,8'd48+tens,8'd48+rem_value[3:0]};
        end
    endfunction
    wire [23:0] x_ascii=fill_digits(fill_x),y_ascii=fill_digits(fill_y);
    wire [23:0] w_ascii=fill_digits(fill_w),h_ascii=fill_digits(fill_h);
    // Decimal conversion for the existing depth indicators.
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
    wire [23:0] depth_ascii=demo_digits(depth_percent);

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
            PAGE: begin
                case(pos)
                    0:command_byte="p";1:command_byte="a";
                    2:command_byte="g";3:command_byte="e";
                    4:command_byte=" ";5:command_byte="0";
                endcase
            end
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
                end else if(pos<key_prefix+((key_color>=2 ||
                    (kind==KEY_TEXT && !key_on)) ? 10 : 9)) begin
                    offset=pos-key_prefix-5;
                    case(offset)
                        // RGB565: pressed bco=9942, pco=4292 (mint/dark).
                        // Released bco=6471, pco=61343 (navy/light).
                        // Guide: yellow 65504/00000; wrong: red 63488/65535.
                        0:command_byte=(key_color==2) ? (kind==KEY_TEXT ? "0" : "6") :
                            (key_color==3) ? "6" : (kind==KEY_TEXT) ?
                            (key_on ? "4" : "6") : (key_on ? "9" : "6");
                        1:command_byte=(key_color==2) ? (kind==KEY_TEXT ? "0" : "5") :
                            (key_color==3) ? (kind==KEY_TEXT ? "5" : "3") : (kind==KEY_TEXT) ?
                            (key_on ? "2" : "1") : (key_on ? "9" : "4");
                        2:command_byte=(key_color==2) ? (kind==KEY_TEXT ? "0" : "5") :
                            (key_color==3) ? (kind==KEY_TEXT ? "5" : "4") : (kind==KEY_TEXT) ?
                            (key_on ? "9" : "3") : (key_on ? "4" : "7");
                        3:command_byte=(key_color==2) ? (kind==KEY_TEXT ? "0" : "0") :
                            (key_color==3) ? (kind==KEY_TEXT ? "3" : "8") : (kind==KEY_TEXT) ?
                            (key_on ? "2" : "4") : (key_on ? "2" : "1");
                        4:command_byte=(key_color==2) ? (kind==KEY_TEXT ? "0" : "4") :
                            (key_color==3) ? (kind==KEY_TEXT ? "5" : "8") : "3";
                    endcase
                end
            end
            TIMBRE, OCTAVE, EFFECT: begin
                case(pos)
                    0:command_byte="t";
                    1:command_byte="1";
                    2:command_byte=(kind==TIMBRE) ? "2" : (kind==OCTAVE) ? "3" : "4";
                    3:command_byte=".";
                    4:command_byte="t";
                    5:command_byte="x";
                    6:command_byte="t";
                    7:command_byte="=";
                    8:command_byte="\"";
                    default:begin
                        if(kind==EFFECT && pos<9+effect_word_length) command_byte=effect_char(effect_value,pos-9);
                        else if(kind==TIMBRE && pos<9+word_length)
                            command_byte=timbre_char(timbre_value,pos-9);
                        else if(kind==OCTAVE && pos<15)
                            command_byte=octave_char(octave_value,pos-9);
                        else if((kind==TIMBRE && pos==9+word_length) ||
                                (kind==OCTAVE && pos==15) || (kind==EFFECT && pos==9+effect_word_length))
                            command_byte="\"";
                    end
                endcase
            end
            SCOPE_HIDE: begin
                case(pos)
                    0:command_byte="v";1:command_byte="i";
                    2:command_byte="s";3:command_byte=" ";
                    4:command_byte="s";5:command_byte="0";
                    6:command_byte=",";7:command_byte="0";
                endcase
            end
            BAR_FILL: begin
                // Fixed-width decimal fields keep the UART encoder small.
                // TJC accepts leading zeroes as decimal numbers.
                case(pos)
                    0:command_byte="f";1:command_byte="i";
                    2:command_byte="l";3:command_byte="l";
                    4:command_byte=" ";
                    5:command_byte=x_ascii[23:16];
                    6:command_byte=x_ascii[15:8];
                    7:command_byte=x_ascii[7:0];
                    8:command_byte=",";
                    9:command_byte=y_ascii[23:16];
                    10:command_byte=y_ascii[15:8];
                    11:command_byte=y_ascii[7:0];
                    12:command_byte=",";
                    13:command_byte=w_ascii[23:16];
                    14:command_byte=w_ascii[15:8];
                    15:command_byte=w_ascii[7:0];
                    16:command_byte=",";
                    17:command_byte=h_ascii[23:16];
                    18:command_byte=h_ascii[15:8];
                    19:command_byte=h_ascii[7:0];
                    20:command_byte=",";
                    21:command_byte=(fill_color==16'd2047) ? "2" : "6";
                    22:command_byte=(fill_color==16'd2047) ? "0" : "4";
                    23:command_byte=(fill_color==16'd2047) ? "4" : "7";
                    24:command_byte=(fill_color==16'd2047) ? "7" : "1";
                endcase
            end
            DEPTH_TEXT: begin
                case(pos)
                    0:command_byte="t";1:command_byte="1";2:command_byte="5";
                    3:command_byte=".";4:command_byte="t";5:command_byte="x";
                    6:command_byte="t";7:command_byte="=";8:command_byte="\"";
                    9:command_byte=(depth_percent<100) ? " " : depth_ascii[23:16];
                    10:command_byte=(depth_percent<10) ? " " : depth_ascii[15:8];
                    11:command_byte=depth_ascii[7:0];
                    12:command_byte="%";13:command_byte="\"";
                endcase
            end
            DEPTH_BAR: begin
                case(pos)
                    0:command_byte="j";1:command_byte="0";2:command_byte=".";
                    3:command_byte="v";4:command_byte="a";5:command_byte="l";
                    6:command_byte="=";7:command_byte=depth_ascii[23:16];
                    8:command_byte=depth_ascii[15:8];9:command_byte=depth_ascii[7:0];
                endcase
            end
            DEPTH_REF: begin
                case(pos)
                    0:command_byte="r";1:command_byte="e";2:command_byte="f";
                    3:command_byte=" ";4:command_byte="t";
                    5:command_byte="1";6:command_byte="5";
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
            page_initialized<=0;
            key_index<=0; key_on<=0;key_color<=0;timbre_value<=0; octave_value<=4;
            spectrum_stage<=0;band_index<=0;note_index<=0;harmonic_index<=1;
            scan_keys<=0;scan_timbre<=0;scan_octave<=4;band_sum<=0;
            fill_x<=25;fill_y<=235;fill_w<=220;fill_h<=200;fill_color<=16'd6471;
            render_pending<=0;render_height<=0;
            for(bar_reset_index=0;bar_reset_index<16;bar_reset_index=bar_reset_index+1)
                shown_height[bar_reset_index]<=0;
            wave_counter<=0;wave_due<=0;
            wave_ack<=0;
            sent_key_states<=0; force_keys<=12'hFFF;
            sent_timbre<=0; sent_octave<=4;
            force_timbre<=1; force_octave<=1;force_effect<=1;effect_value<=0;sent_effect<=0;
            depth_value<=0;sent_depth<=0;force_depth<=1;
            boot_counter<=0; status_refresh_counter<=0;
            tx_data<=0; tx_valid<=0;
        end else begin
            tx_valid<=0;
            wave_ack<=wave_ready;
            if(boot_counter<STARTUP_CYCLES)
                boot_counter<=boot_counter+1'b1;
            // Refresh the labels occasionally so an independently restarted
            // HMI recovers even when the selected values have not changed.
            if(status_refresh_counter>=STATUS_REFRESH_CYCLES-1) begin
                status_refresh_counter<=0;
                force_timbre<=1;
                force_octave<=1;force_effect<=1;force_depth<=1;
            end else status_refresh_counter<=status_refresh_counter+1'b1;
            if(wave_counter>=WAVE_CYCLES-1) begin
                wave_counter<=0;
                wave_due<=1;
            end else wave_counter<=wave_counter+1'b1;
            case(state)
                IDLE: if(boot_counter>=STARTUP_CYCLES) begin
                    pos<=0;
                    // The default labels must appear before the 12 key
                    // backgrounds are refreshed over the UART link.
                    if(!page_initialized) begin
                        kind<=PAGE;length<=6'd9;state<=ISSUE;
                    end else if(spectrum_stage==0) begin
                        // Hide the old scrolling curve widget only once.
                        kind<=SCOPE_HIDE;length<=6'd11;state<=ISSUE;
                    end else if(spectrum_stage==1) begin
                        // Clear only the former s0 rectangle, not the page.
                        kind<=BAR_FILL;fill_x<=25;fill_y<=235;
                        fill_w<=220;fill_h<=200;fill_color<=16'd6471;
                        length<=6'd28;state<=ISSUE;
                    end else if(force_timbre || timbre!=sent_timbre) begin
                        kind<=TIMBRE;
                        timbre_value<=timbre;
                        length<=(timbre==2'd0 || timbre==2'd2) ? 6'd17 : 6'd19;
                        state<=ISSUE;
                    end else if(force_octave || octave!=sent_octave) begin
                        kind<=OCTAVE;
                        octave_value<=octave;
                        length<=6'd19;
                        state<=ISSUE;
                    end else if(force_effect || display_effect!=sent_effect) begin
                        kind<=EFFECT;effect_value<=display_effect;
                        length<=display_effect==2 ? 6'd21 : 6'd17;state<=ISSUE;
                    end else if(force_depth || display_depth!=sent_depth) begin
                        kind<=DEPTH_TEXT;depth_value<=display_depth;
                        length<=6'd17;state<=ISSUE;
                    end else if(key_pending) begin
                        kind<=KEY;
                        key_index<=next_key;
                        key_color<=desired_key_states[next_key*2+:2];
                        key_on<=desired_key_states[next_key*2+:2]==2'd1;
                        length<=(next_key<10) ?
                            (desired_key_states[next_key*2+:2]>=2 ? 6'd15 : 6'd14) :
                            (desired_key_states[next_key*2+:2]>=2 ? 6'd16 : 6'd15);
                        state<=ISSUE;
                    end else if(wave_due) begin
                        scan_keys<=keys;scan_timbre<=timbre;scan_octave<=octave;
                        note_index<=0;harmonic_index<=1;band_sum<=0;
                        wave_due<=0;
                        state<=CALC;
                    end
                end
                CALC: begin
                    band_sum<=next_band_sum;
                    if(harmonic_index==8) begin
                        harmonic_index<=1;
                        if(note_index==11) begin
                            note_index<=0;
                            band_index<=band_index+1'b1;
                            if(next_band_sum!=0 || shown_height[band_index]!=0) begin
                                // Always repaint the full live bar: other HMI
                                // redraws may have erased some of its pixels.
                                // On shrink, erase only the removed top strip.
                                fill_x<=10'd27+{band_index,3'b000}+
                                    {band_index,2'b00}+band_index;
                                fill_w<=10'd10;
                                if(next_band_sum<shown_height[band_index]) begin
                                    fill_y<=10'd430-shown_height[band_index];
                                    fill_h<=shown_height[band_index]-next_band_sum;
                                    fill_color<=16'd6471;
                                    render_pending<=(next_band_sum!=0);
                                    render_height<=next_band_sum;
                                end else begin
                                    fill_y<=10'd430-next_band_sum;
                                    fill_h<=next_band_sum;
                                    fill_color<=16'd2047;
                                    render_pending<=0;
                                end
                                shown_height[band_index]<=next_band_sum;
                                kind<=BAR_FILL;pos<=0;length<=6'd28;
                                state<=ISSUE;
                            end else state<=IDLE;
                        end else note_index<=note_index+1'b1;
                    end else harmonic_index<=harmonic_index+1'b1;
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
                            PAGE:begin
                                page_initialized<=1;
                                force_timbre<=1;force_octave<=1;force_effect<=1;force_depth<=1;
                                force_keys<=12'hFFF;
                                state<=IDLE;
                            end
                            KEY:begin
                                // Finish both colors using the captured key state,
                                // then refresh and acknowledge this key together.
                                kind<=KEY_TEXT;
                                pos<=0;
                                length<=(key_index<10) ?
                                    ((key_color>=2 || !key_on) ? 6'd15 : 6'd14) :
                                    ((key_color>=2 || !key_on) ? 6'd16 : 6'd15);
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
                                sent_effect<=effect_value;force_effect<=0;state<=IDLE;
                            end
                            DEPTH_TEXT:begin
                                kind<=DEPTH_REF;pos<=0;length<=6'd10;state<=ISSUE;
                            end
                            DEPTH_REF:begin
                                kind<=DEPTH_BAR;pos<=0;length<=6'd13;state<=ISSUE;
                            end
                            DEPTH_BAR:begin
                                sent_depth<=depth_value;force_depth<=0;state<=IDLE;
                            end
                            KEY_REF:begin
                                sent_key_states[key_index*2+:2]<=key_color;
                                force_keys[key_index]<=0;
                                state<=IDLE;
                            end
                            TIMBRE_REF:begin
                                sent_timbre<=timbre_value;
                                force_timbre<=0;
                                state<=IDLE;
                            end
                            OCTAVE_REF:begin
                                sent_octave<=octave_value;
                                force_octave<=0;
                                state<=IDLE;
                            end
                            SCOPE_HIDE:begin
                                spectrum_stage<=1;
                                state<=IDLE;
                            end
                            BAR_FILL:begin
                                if(spectrum_stage==1) begin
                                    spectrum_stage<=2;
                                    state<=IDLE;
                                end else if(render_pending) begin
                                    fill_y<=10'd430-render_height;
                                    fill_h<=render_height;
                                    fill_color<=16'd2047;
                                    render_pending<=0;
                                    pos<=0;length<=6'd28;state<=ISSUE;
                                end else state<=IDLE;
                            end
                            default:state<=IDLE;
                        endcase
                    end
                end
            endcase
        end
    end
endmodule
