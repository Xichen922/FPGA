`timescale 1ns/1ps
// B stores score events, then sends key gates to A over the existing SPI link.
// Score entries are {note[3:0], duration_10ms[9:0],
//                    octave_enable,octave_code[1:0],
//                    timbre_enable,timbre_code[1:0],
//                    effect_enable,effect_code[1:0]}.
// Note 0 is a rest; 1..12 are the physical note keys. A generates the sound.
module latb_db_score_player #(
    parameter integer CLK_HZ=50000000,
    parameter integer MAX_NOTES=512
)(
    input wire clk,rst,clock_present,
    input wire clear_cmd,append_cmd,play_cmd,stop_cmd,guide_cmd,
    input wire [11:0] physical_keys,
    input wire [3:0] physical_octave,
    input wire [3:0] append_note,
    input wire [11:0] append_mask,
    input wire append_is_mask,
    input wire [9:0] append_duration,
    input wire append_octave_enable,input wire [1:0] append_octave_code,
    input wire append_timbre_enable,input wire [1:0] append_timbre_code,
    input wire append_effect_enable,input wire [1:0] append_effect_code,
    output reg [9:0] score_count,
    output reg playing,
    output reg guiding,
    output reg [11:0] guide_keys,
    output reg [3:0] current_note,
    output wire [11:0] current_keys,
    output reg current_octave_enable,output reg [1:0] current_octave_code,
    output reg current_timbre_enable,output reg [1:0] current_timbre_code,
    output reg current_effect_enable,output reg [1:0] current_effect_code,
    output wire note_gate
);
    localparam integer MS_DIV=CLK_HZ/1000;
    localparam [2:0] IDLE=0,READ=1,LOAD=2,PREP=3,RUN=4,
                     GUIDE_READ=5,GUIDE_LOAD=6,GUIDE_WAIT=7;
    // One entry stores an absolute 12-key state for a 10 ms based duration.
    // In mask mode, unchanged keys stay held across adjacent entries.
    (* syn_ramstyle="block_ram" *) reg [31:0] score [0:MAX_NOTES-1];
    reg [31:0] read_entry;
    reg [11:0] held_keys;
    reg [11:0] prep_keys;
    reg prep_keep_keys;
    reg current_is_mask;
    reg [9:0] index;
    reg [2:0] state;
    reg [13:0] remaining_ms;
    reg [15:0] ms_counter;
    reg [3:0] prep_ms;
    reg [5:0] guide_match_ms;
    integer k;
    wire timbre_preload=read_entry[5] &&
        (!current_timbre_enable || current_timbre_code!=read_entry[4:3]);
    wire octave_preload=((read_entry[8]!=current_octave_enable) ||
        (read_entry[8] && current_octave_code!=read_entry[7:6])) &&
        ((read_entry[30:19] & ~held_keys)!=0);
    // Two milliseconds low between notes ensure A's 1 ms SPI poll sees a
    // release, including when two adjacent score entries use the same key.
    assign current_keys=(playing && (state==RUN || state==READ || state==LOAD) &&
        (current_is_mask || remaining_ms>14'd2)) ? held_keys :
        (playing && state==PREP && prep_keep_keys) ? prep_keys : 12'd0;
    assign note_gate=|current_keys;

    // One clocked read lets Gowin infer block RAM. Upload and playback are
    // mutually exclusive at the serial parser, but keep write priority here.
    always @(posedge clk) begin
        if(append_cmd && !playing && !guiding && score_count<MAX_NOTES)
            score[score_count]<={append_is_mask,append_mask,append_duration,
                append_octave_enable,append_octave_code,
                append_timbre_enable,append_timbre_code,
                append_effect_enable,append_effect_code};
        else if(state==READ || state==GUIDE_READ)read_entry<=score[index];
    end

    always @(posedge clk) begin
        if(rst) begin
            score_count<=0;playing<=0;guiding<=0;guide_keys<=0;
            guide_match_ms<=0;current_note<=0;held_keys<=0;
            prep_keys<=0;prep_keep_keys<=0;
            current_is_mask<=0;index<=0;
            state<=IDLE;remaining_ms<=0;ms_counter<=0;prep_ms<=0;
            current_octave_enable<=0;current_octave_code<=0;
            current_timbre_enable<=0;current_timbre_code<=0;
            current_effect_enable<=0;current_effect_code<=0;
        end else begin
            if(!clock_present || ms_counter==MS_DIV-1)ms_counter<=0;
            else ms_counter<=ms_counter+1'b1;
            if(clear_cmd)begin
                score_count<=0;playing<=0;guiding<=0;guide_keys<=0;
                guide_match_ms<=0;current_note<=0;held_keys<=0;
                prep_keys<=0;prep_keep_keys<=0;
                state<=IDLE;remaining_ms<=0;prep_ms<=0;
                current_octave_enable<=0;current_timbre_enable<=0;
                current_effect_enable<=0;
            end else if(stop_cmd)begin
                playing<=0;guiding<=0;guide_keys<=0;guide_match_ms<=0;
                current_note<=0;held_keys<=0;prep_keys<=0;
                prep_keep_keys<=0;state<=IDLE;remaining_ms<=0;prep_ms<=0;
                current_octave_enable<=0;current_timbre_enable<=0;
                current_effect_enable<=0;
            end else if(append_cmd && !playing && !guiding && score_count<MAX_NOTES)
                score_count<=score_count+1'b1;
            else if(guide_cmd && score_count!=0)begin
                playing<=0;guiding<=1;guide_keys<=0;guide_match_ms<=0;
                held_keys<=0;prep_keys<=0;prep_keep_keys<=0;
                current_note<=0;index<=0;state<=GUIDE_READ;
                current_octave_enable<=0;current_timbre_enable<=0;
                current_effect_enable<=0;
            end
            else if(play_cmd && score_count!=0)begin
                playing<=1;guiding<=0;guide_keys<=0;index<=0;
                current_note<=0;held_keys<=0;
                prep_keys<=0;prep_keep_keys<=0;state<=READ;
                current_octave_enable<=0;current_timbre_enable<=0;
                current_effect_enable<=0;
            end else case(state)
                GUIDE_READ:state<=GUIDE_LOAD;
                GUIDE_LOAD:begin
                    guide_keys<=read_entry[30:19];
                    current_octave_enable<=read_entry[8];
                    current_octave_code<=read_entry[7:6];
                    guide_match_ms<=0;
                    state<=GUIDE_WAIT;
                end
                GUIDE_WAIT:if(clock_present && ms_counter==MS_DIV-1)begin
                    // Exact physical key match for 50 ms. Rest/release entries
                    // require all keys up; score durations do not pace practice.
                    if(physical_keys==guide_keys &&
                       (!current_octave_enable ||
                        physical_octave=={2'b00,current_octave_code}+4'd3))begin
                        if(guide_match_ms==6'd49)begin
                            guide_match_ms<=0;
                            if(index+1'b1<score_count)begin
                                index<=index+1'b1;state<=GUIDE_READ;
                            end else begin
                                guiding<=0;guide_keys<=0;state<=IDLE;
                                current_octave_enable<=0;
                            end
                        end else guide_match_ms<=guide_match_ms+1'b1;
                    end else guide_match_ms<=0;
                end
                READ:state<=LOAD;
                LOAD:begin
                    // During an octave change, only the intersection may stay
                    // active before A receives the new octave control.  Newly
                    // added keys become visible after the SPI settling window.
                    prep_keys<=held_keys & read_entry[30:19];
                    held_keys<=read_entry[30:19];
                    current_is_mask<=read_entry[31];
                    // Legacy observability: the single-key format retains its note number.
                    if(!read_entry[31])begin
                        for(k=0;k<12;k=k+1)
                            if(read_entry[19+k])current_note<=k+1;
                        if(read_entry[30:19]==0)current_note<=0;
                    end else current_note<=0;
                    current_octave_enable<=read_entry[8];
                    current_octave_code<=read_entry[7:6];
                    current_timbre_enable<=read_entry[5];
                    current_timbre_code<=read_entry[4:3];
                    current_effect_enable<=read_entry[2];
                    current_effect_code<=read_entry[1:0];
                    // M events include the 3 ms octave preload in DDD, so
                    // repeated octave switches do not lengthen the song.
                    remaining_ms<=(({4'd0,read_entry[18:9]}<<3)+
                                   ({4'd0,read_entry[18:9]}<<1))-
                                  ((read_entry[31] && octave_preload &&
                                    !timbre_preload) ? 14'd3 : 14'd0);
                    ms_counter<=0;
                    // A35 switches timbre via fade out/in. Send the new
                    // timbre before the first key gate, including at song start.
                    if(timbre_preload)begin
                        prep_keep_keys<=0;prep_ms<=4'd10;state<=PREP;
                    end else if(octave_preload)begin
                        prep_keep_keys<=read_entry[31];
                        prep_ms<=4'd3;state<=PREP;
                    end else state<=RUN;
                end
                PREP:if(clock_present && ms_counter==MS_DIV-1)begin
                    if(prep_ms>1)prep_ms<=prep_ms-1'b1;
                    else begin prep_ms<=0;state<=RUN;end
                end
                RUN:if(clock_present && ms_counter==MS_DIV-1)begin
                    if(remaining_ms>14'd1)remaining_ms<=remaining_ms-1'b1;
                    else if(index+1'b1<score_count)begin
                        index<=index+1'b1;state<=READ;
                    end else begin
                        current_note<=0;held_keys<=0;prep_keys<=0;
                        prep_keep_keys<=0;playing<=0;state<=IDLE;
                        current_octave_enable<=0;current_timbre_enable<=0;
                        current_effect_enable<=0;
                    end
                end
                default:state<=IDLE;
            endcase
        end
    end
endmodule
