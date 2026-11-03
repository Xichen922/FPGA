`timescale 1ns/1ps
// HC-06 transparent SPP at 9600 8N1. Text lines:
// NN,DDD (legacy) or NN,DDD,O,T,E where O=3/4/5/-, T=0..3/-,
// E=0/1/2/-. A dash leaves that control under manual hardware control.
// Every accepted line replies K\n; E=syntax, F=full, B=busy, Z=empty.
// Query replies N=DDD\n with a decimal score length. CR before LF is ignored.
module db_score_serial #(
    parameter integer CLK_HZ=50000000,
    parameter integer BAUD=9600,
    parameter integer MAX_NOTES=512
)(
    input wire clk,rst,rx,
    input wire [9:0] score_count,
    input wire playing,
    output wire tx,
    output reg clear_cmd,append_cmd,play_cmd,stop_cmd,guide_cmd,
    output reg [3:0] append_note,
    output reg [11:0] append_mask,
    output reg append_is_mask,
    output reg [9:0] append_duration,
    output reg append_octave_enable,output reg [1:0] append_octave_code,
    output reg append_timbre_enable,output reg [1:0] append_timbre_code,
    output reg append_effect_enable,output reg [1:0] append_effect_code
);
    wire [7:0] byte_data;
    wire byte_valid,framing_error;
    db_uart_rx #(.CLK_HZ(CLK_HZ),.BAUD(BAUD)) u_rx(
        .clk(clk),.rst(rst),.rx(rx),.data(byte_data),.valid(byte_valid),
        .framing_error(framing_error));
    wire tx_ready;
    reg [7:0] tx_data;
    reg tx_valid;
    uart_tx #(.CLK_HZ(CLK_HZ),.BAUD(BAUD)) u_tx(
        .clk(clk),.rst_n(!rst),.data(tx_data),.valid(tx_valid),
        .ready(tx_ready),.tx(tx),.done());

    localparam [4:0] START=0,NOTE_UNIT=1,COMMA=2,DUR_HUNDRED=3,
                     DUR_TEN=4,DUR_UNIT=5,END_NOTE=6,END_COMMAND=7,
                     DISCARD=8,AUTO_OCTAVE=9,AUTO_COMMA1=10,
                     AUTO_TIMBRE=11,AUTO_COMMA2=12,AUTO_EFFECT=13,AUTO_END=14,
                     MASK_HI=15,MASK_MID=16,MASK_LO=17;
    reg [4:0] parse_state;
    reg [7:0] command_char;
    reg [3:0] note_tens,note_value;
    reg [3:0] duration_hundreds,duration_tens;
    reg [9:0] duration_value;
    reg mask_mode;
    reg [11:0] mask_value;
    reg octave_enable,timbre_enable,effect_enable;
    reg [1:0] octave_code,timbre_code,effect_code;
    reg response_valid;
    reg [2:0] response_code;
    reg [9:0] response_count;
    localparam [2:0] OK=0,BAD=1,FULL=2,BUSY=3,EMPTY=4,COUNT=5,VERSION=6;
    wire is_digit=byte_data>=8'h30 && byte_data<=8'h39;
    wire is_hex=is_digit || (byte_data>=8'h41 && byte_data<=8'h46) ||
                (byte_data>=8'h61 && byte_data<=8'h66);
    function [3:0] hex_digit;
        input [7:0] c;
        begin
            if(c>=8'h30 && c<=8'h39)hex_digit=c[3:0];
            else if(c>=8'h41 && c<=8'h46)hex_digit=c[3:0]+4'd9;
            else hex_digit=c[3:0]+4'd9;
        end
    endfunction
    always @(posedge clk) begin
        if(rst)begin
            parse_state<=START;command_char<=0;note_tens<=0;note_value<=0;
            duration_hundreds<=0;duration_tens<=0;duration_value<=0;
            response_valid<=0;response_code<=OK;response_count<=0;
            clear_cmd<=0;append_cmd<=0;play_cmd<=0;stop_cmd<=0;guide_cmd<=0;
            append_note<=0;append_mask<=0;append_is_mask<=0;append_duration<=0;
            mask_mode<=0;mask_value<=0;
            append_octave_enable<=0;append_octave_code<=0;
            append_timbre_enable<=0;append_timbre_code<=0;
            append_effect_enable<=0;append_effect_code<=0;
            octave_enable<=0;timbre_enable<=0;effect_enable<=0;
            octave_code<=0;timbre_code<=0;effect_code<=0;
        end else begin
            clear_cmd<=0;append_cmd<=0;play_cmd<=0;stop_cmd<=0;guide_cmd<=0;response_valid<=0;
            if(byte_valid && byte_data!=8'h0d)case(parse_state)
                START:begin
                    if(byte_data==8'h0a)parse_state<=START;
                    else if(byte_data==8'h4d)begin
                        mask_mode<=1;mask_value<=0;
                        octave_enable<=0;timbre_enable<=0;effect_enable<=0;
                        octave_code<=0;timbre_code<=0;effect_code<=0;
                        parse_state<=MASK_HI;
                    end else if(byte_data==8'h30 || byte_data==8'h31)begin
                        mask_mode<=0;
                        note_tens<=byte_data[3:0];
                        octave_enable<=0;timbre_enable<=0;effect_enable<=0;
                        octave_code<=0;timbre_code<=0;effect_code<=0;
                        parse_state<=NOTE_UNIT;
                    end else if(byte_data==8'h43 || byte_data==8'h50 ||
                                byte_data==8'h53 || byte_data==8'h3f ||
                                byte_data==8'h56 || byte_data==8'h47)begin
                        command_char<=byte_data;parse_state<=END_COMMAND;
                    end else parse_state<=DISCARD;
                end
                NOTE_UNIT:if(is_digit && (note_tens==0 || byte_data<=8'h32))begin
                    note_value<=note_tens*4'd10+byte_data[3:0];
                    parse_state<=COMMA;
                end else parse_state<=DISCARD;
                COMMA:if(byte_data==8'h2c)parse_state<=DUR_HUNDRED;
                      else parse_state<=DISCARD;
                MASK_HI:if(is_hex)begin mask_value[11:8]<=hex_digit(byte_data);parse_state<=MASK_MID;end
                        else parse_state<=DISCARD;
                MASK_MID:if(is_hex)begin mask_value[7:4]<=hex_digit(byte_data);parse_state<=MASK_LO;end
                         else parse_state<=DISCARD;
                MASK_LO:if(is_hex)begin mask_value[3:0]<=hex_digit(byte_data);parse_state<=COMMA;end
                        else parse_state<=DISCARD;
                DUR_HUNDRED:if(is_digit)begin
                    duration_hundreds<=byte_data[3:0];parse_state<=DUR_TEN;
                end else parse_state<=DISCARD;
                DUR_TEN:if(is_digit)begin
                    duration_tens<=byte_data[3:0];parse_state<=DUR_UNIT;
                end else parse_state<=DISCARD;
                DUR_UNIT:if(is_digit)begin
                    duration_value<=duration_hundreds*10'd100+
                                    duration_tens*10'd10+(byte_data-8'h30);
                    parse_state<=END_NOTE;
                end else parse_state<=DISCARD;
                END_NOTE:if(byte_data==8'h2c)parse_state<=AUTO_OCTAVE;
                else if(byte_data==8'h0a)begin
                    parse_state<=START;response_valid<=1;
                    if((!mask_mode && note_value>12) || duration_value==0 || duration_value>999)
                        response_code<=BAD;
                    else if(playing)response_code<=BUSY;
                    else if(score_count>=MAX_NOTES)response_code<=FULL;
                    else begin
                        append_note<=mask_mode ? 4'd0 : note_value;
                        append_mask<=mask_mode ? mask_value :
                            ((note_value==0) ? 12'd0 : (12'b1 << (note_value-1'b1)));
                        append_is_mask<=mask_mode;append_duration<=duration_value;
                        append_octave_enable<=octave_enable;
                        append_octave_code<=octave_code;
                        append_timbre_enable<=timbre_enable;
                        append_timbre_code<=timbre_code;
                        append_effect_enable<=effect_enable;
                        append_effect_code<=effect_code;
                        append_cmd<=1;response_code<=OK;
                    end
                end else parse_state<=DISCARD;
                AUTO_OCTAVE:begin
                    if(byte_data==8'h2d)begin octave_enable<=0;parse_state<=AUTO_COMMA1;end
                    else if(byte_data>=8'h33 && byte_data<=8'h35)begin
                        octave_enable<=1;
                        case(byte_data)
                            8'h33:octave_code<=2'd0;
                            8'h34:octave_code<=2'd1;
                            default:octave_code<=2'd2;
                        endcase
                        parse_state<=AUTO_COMMA1;
                    end else parse_state<=DISCARD;
                end
                AUTO_COMMA1:if(byte_data==8'h2c)parse_state<=AUTO_TIMBRE;
                            else parse_state<=DISCARD;
                AUTO_TIMBRE:begin
                    if(byte_data==8'h2d)begin timbre_enable<=0;parse_state<=AUTO_COMMA2;end
                    else if(byte_data>=8'h30 && byte_data<=8'h33)begin
                        timbre_enable<=1;timbre_code<=byte_data[1:0];
                        parse_state<=AUTO_COMMA2;
                    end else parse_state<=DISCARD;
                end
                AUTO_COMMA2:if(byte_data==8'h2c)parse_state<=AUTO_EFFECT;
                            else parse_state<=DISCARD;
                AUTO_EFFECT:begin
                    if(byte_data==8'h2d)begin effect_enable<=0;parse_state<=AUTO_END;end
                    else if(byte_data>=8'h30 && byte_data<=8'h32)begin
                        effect_enable<=1;effect_code<=byte_data[1:0];
                        parse_state<=AUTO_END;
                    end else parse_state<=DISCARD;
                end
                AUTO_END:if(byte_data==8'h0a)begin
                    parse_state<=START;response_valid<=1;
                    if((!mask_mode && note_value>12) || duration_value==0 || duration_value>999)
                        response_code<=BAD;
                    else if(playing)response_code<=BUSY;
                    else if(score_count>=MAX_NOTES)response_code<=FULL;
                    else begin
                        append_note<=mask_mode ? 4'd0 : note_value;
                        append_mask<=mask_mode ? mask_value :
                            ((note_value==0) ? 12'd0 : (12'b1 << (note_value-1'b1)));
                        append_is_mask<=mask_mode;append_duration<=duration_value;
                        append_octave_enable<=octave_enable;
                        append_octave_code<=octave_code;
                        append_timbre_enable<=timbre_enable;
                        append_timbre_code<=timbre_code;
                        append_effect_enable<=effect_enable;
                        append_effect_code<=effect_code;
                        append_cmd<=1;response_code<=OK;
                    end
                end else parse_state<=DISCARD;
                END_COMMAND:if(byte_data==8'h0a)begin
                    parse_state<=START;response_valid<=1;
                    case(command_char)
                        8'h43:begin clear_cmd<=1;response_code<=OK;end
                        8'h50:if(score_count!=0)begin play_cmd<=1;response_code<=OK;end
                                else response_code<=EMPTY;
                        8'h47:if(score_count!=0)begin guide_cmd<=1;response_code<=OK;end
                                else response_code<=EMPTY;
                        8'h53:begin stop_cmd<=1;response_code<=OK;end
                        8'h3f:begin response_code<=COUNT;response_count<=score_count;end
                        8'h56:response_code<=VERSION;
                        default:response_code<=BAD;
                    endcase
                end else parse_state<=DISCARD;
                DISCARD:if(byte_data==8'h0a)begin
                    parse_state<=START;response_valid<=1;response_code<=BAD;
                end
                default:parse_state<=START;
            endcase
        end
    end

    reg [2:0] tx_state;
    reg [2:0] tx_index,tx_code;
    reg [9:0] tx_count;
    reg pending_valid;
    reg [2:0] pending_code;
    reg [9:0] pending_count;
    function [3:0] decimal_hundreds;
        input [9:0] number;
        begin
            decimal_hundreds=(number>=900)?9:(number>=800)?8:
                             (number>=700)?7:(number>=600)?6:
                             (number>=500)?5:(number>=400)?4:
                             (number>=300)?3:(number>=200)?2:
                             (number>=100)?1:0;
        end
    endfunction
    function [3:0] decimal_tens;
        input [9:0] number;
        begin
            decimal_tens=(number>=90)?9:(number>=80)?8:
                         (number>=70)?7:(number>=60)?6:
                         (number>=50)?5:(number>=40)?4:
                         (number>=30)?3:(number>=20)?2:
                         (number>=10)?1:0;
        end
    endfunction
    wire [3:0] hundreds=decimal_hundreds(tx_count);
    wire [9:0] after_hundreds=tx_count-({6'd0,hundreds}*10'd100);
    wire [3:0] tens=decimal_tens(after_hundreds);
    wire [9:0] ones_full=after_hundreds-({6'd0,tens}*10'd10);
    wire [3:0] ones=ones_full[3:0];
    function [7:0] response_byte;
        input [2:0] code,index;
        input [3:0] decimal_hundreds,decimal_tens,decimal_ones;
        begin
            if(code==COUNT || code==VERSION)case(index)
                0:response_byte=(code==COUNT) ? "N" : "V";
                1:response_byte="=";
                2:response_byte=(code==COUNT) ? 8'h30+decimal_hundreds : "0";
                3:response_byte=(code==COUNT) ? 8'h30+decimal_tens : "4";
                4:response_byte=(code==COUNT) ? 8'h30+decimal_ones : "2";
                default:response_byte=8'h0a;
            endcase
            else if(index==1)response_byte=8'h0a;
            else case(code)
                OK:response_byte="K";BAD:response_byte="E";
                FULL:response_byte="F";BUSY:response_byte="B";
                EMPTY:response_byte="Z";default:response_byte="E";
            endcase
        end
    endfunction
    always @(posedge clk)begin
        if(rst)begin
            tx_state<=0;tx_index<=0;tx_code<=OK;tx_count<=0;
            pending_valid<=0;pending_code<=OK;pending_count<=0;
            tx_data<=8'hff;tx_valid<=0;
        end else begin
            tx_valid<=0;
            if(response_valid && tx_state!=0 && !pending_valid)begin
                pending_valid<=1;pending_code<=response_code;
                pending_count<=response_count;
            end
            case(tx_state)
                0:if(pending_valid || response_valid)begin
                    if(pending_valid)begin
                        tx_code<=pending_code;tx_count<=pending_count;
                        pending_valid<=0;
                        tx_data<=response_byte(pending_code,0,4'd0,4'd0,4'd0);
                    end else begin
                    tx_code<=response_code;tx_count<=response_count;
                        tx_data<=response_byte(response_code,0,4'd0,4'd0,4'd0);
                    end
                    tx_index<=0;
                    tx_valid<=1;tx_state<=1;
                end
                1:tx_state<=2;
                2:if(!tx_ready)tx_state<=3;
                3:if(tx_ready)begin
                    if(tx_index==(((tx_code==COUNT)||(tx_code==VERSION))?3'd5:3'd1))tx_state<=0;
                    else begin
                        tx_index<=tx_index+1'b1;
                        tx_data<=response_byte(tx_code,tx_index+1'b1,hundreds,tens,ones);
                        tx_valid<=1;tx_state<=1;
                    end
                end
                default:tx_state<=0;
            endcase
        end
    end
endmodule
