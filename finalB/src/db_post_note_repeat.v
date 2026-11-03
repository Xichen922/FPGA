`timescale 1ns/1ps
// Replays a short, recorded piece after the audible release has ended.
// The ring holds the last 250 ms through the audible release. A new key
// cancels playback immediately. Forward echo halves in level until nearly
// silent; reverse mode plays the same recording backwards only once.
module db_post_note_repeat #(
    parameter integer RECORD_FRAMES=24414,
    parameter integer FIRST_GAP_FRAMES=488,
    parameter integer GAP_FRAMES=1953,
    parameter integer SILENCE_FRAMES=976,
    parameter integer SILENCE_THRESHOLD=32768,
    parameter integer FADE_SHIFT=7
)(
    input wire clk,rst,
    input wire enable,reverse_mode,
    input wire [7:0] depth,
    input wire [11:0] keys,
    input wire voice_active,decaying_source,
    input wire signed [23:0] in_left,in_right,
    input wire in_valid,output wire in_ready,
    output reg signed [23:0] out_left,out_right,
    output reg out_valid,input wire out_ready
);
    localparam [1:0] IDLE=0,GAP=1,PLAY=2;
    (* syn_ramstyle="block_ram" *) reg signed [15:0] recording [0:RECORD_FRAMES-1];
    reg signed [15:0] read_sample;
    reg [14:0] write_addr,recorded,frozen_start,frozen_length,play_addr,play_pos;
    reg [11:0] gap_left;
    reg [10:0] quiet_count;
    reg [1:0] state,stage;
    reg [2:0] repeat_index;
    reg was_down,pending,tail_finished,held_playback,active_reverse,active_decaying_source;
    reg [7:0] repeat_gain,held_gain,held_fade;
    reg signed [23:0] held_left,held_right;
    reg signed [24:0] level_product;
    wire keys_down=|keys;
    // Piano and music box have long decays. Keep their attack in the recording.
    wire capture_frame=!decaying_source || !was_down || recorded<RECORD_FRAMES;
    wire accept=in_valid && in_ready;
    wire play_now=(state==PLAY) && !keys_down && enable && tail_finished;
    wire quiet_now=($signed(in_left)<SILENCE_THRESHOLD) &&
                   ($signed(in_left)>-SILENCE_THRESHOLD) &&
                   ($signed(in_right)<SILENCE_THRESHOLD) &&
                   ($signed(in_right)>-SILENCE_THRESHOLD);
    assign in_ready=(stage==0) && !out_valid;
    wire [14:0] remaining=frozen_length-15'd1-play_pos;
    wire [14:0] edge_frames=(play_pos<remaining) ? play_pos : remaining;
    wire [14:0] fade_shifted=edge_frames << (8-FADE_SHIFT);
    localparam [14:0] RECORD_LAST=(RECORD_FRAMES-1);
    wire [7:0] fade_now=(edge_frames>=(1<<FADE_SHIFT)) ? 8'd255 :
                         fade_shifted[7:0];
    wire [8:0] depth_twice={depth,1'b0};
    wire [7:0] first_gain=depth_twice[8] ? 8'd255 : depth_twice[7:0];
    wire signed [33:0] fade_product=level_product*$signed({1'b0,held_fade});
    wire signed [33:0] repeated_pcm=fade_product>>>8;
    wire signed [34:0] mixed_left=$signed({{11{held_left[23]}},held_left})+
                                   $signed({repeated_pcm[33],repeated_pcm});
    wire signed [34:0] mixed_right=$signed({{11{held_right[23]}},held_right})+
                                    $signed({repeated_pcm[33],repeated_pcm});
    wire signed [23:0] mixed_left_limited=(mixed_left>35'sd8388607) ? 24'sh7fffff :
        (mixed_left< -35'sd8388608) ? 24'sh800000 : mixed_left[23:0];
    wire signed [23:0] mixed_right_limited=(mixed_right>35'sd8388607) ? 24'sh7fffff :
        (mixed_right< -35'sd8388608) ? 24'sh800000 : mixed_right[23:0];

    // One RAM access per accepted audio frame. Reading and writing never
    // happen together, so Gowin need not infer an unsupported collision mode.
    always @(posedge clk) if(!rst && accept) begin
        if(capture_frame && (keys_down || was_down || (pending && !tail_finished && state==IDLE &&
           voice_active && quiet_count<SILENCE_FRAMES)))
            recording[(keys_down && !was_down) ? 15'd0 : write_addr]<=in_left[23:8];
        else if(play_now) read_sample<=recording[play_addr];
    end

    always @(posedge clk) begin
        if(rst) begin
            write_addr<=0;recorded<=0;frozen_start<=0;frozen_length<=0;
            play_addr<=0;play_pos<=0;gap_left<=0;quiet_count<=0;state<=IDLE;repeat_index<=0;
            was_down<=0;pending<=0;tail_finished<=0;active_reverse<=0;active_decaying_source<=0;
            repeat_gain<=0;held_gain<=0;held_fade<=0;
            held_playback<=0;held_left<=0;held_right<=0;level_product<=0;
            stage<=0;out_left<=0;out_right<=0;out_valid<=0;
        end else begin
            if(out_valid && out_ready)out_valid<=0;
            if(accept) begin
                held_left<=in_left;held_right<=in_right;
                held_playback<=play_now;
                held_gain<=repeat_gain;
                held_fade<=fade_now;
                stage<=1;
                if(keys_down) begin
                    quiet_count<=0;tail_finished<=0;
                    if(!was_down) begin
                        write_addr<=15'd1;recorded<=15'd1;was_down<=1;
                        pending<=0;state<=IDLE;repeat_index<=0;
                    end else if(capture_frame) begin
                        write_addr<=(write_addr==RECORD_FRAMES-1) ? 15'd0 : write_addr+1'b1;
                        if(recorded<RECORD_FRAMES)recorded<=recorded+1'b1;
                    end
                end else if(was_down) begin
                    was_down<=0;
                    quiet_count<=0;tail_finished<=0;
                    if(capture_frame)begin
                        write_addr<=(write_addr==RECORD_FRAMES-1) ? 15'd0 : write_addr+1'b1;
                        if(recorded<RECORD_FRAMES)recorded<=recorded+1'b1;
                    end
                    pending<=enable && (recorded!=0);
                end else if(!enable || (state!=IDLE && reverse_mode!=active_reverse)) begin
                    pending<=0;state<=IDLE;quiet_count<=0;tail_finished<=0;
                end else begin
                    if(pending && !tail_finished) begin
                        if(voice_active && quiet_count<SILENCE_FRAMES && capture_frame) begin
                            write_addr<=(write_addr==RECORD_FRAMES-1) ? 15'd0 : write_addr+1'b1;
                            if(recorded<RECORD_FRAMES)recorded<=recorded+1'b1;
                        end
                        if(!voice_active)quiet_count<=SILENCE_FRAMES;
                        else if(!quiet_now)quiet_count<=0;
                        else if(quiet_count<SILENCE_FRAMES)quiet_count<=quiet_count+1'b1;
                    end
                    case(state)
                    IDLE:if(pending && (decaying_source ?
                        (recorded>=RECORD_FRAMES || !voice_active || quiet_count>=SILENCE_FRAMES) :
                        (!voice_active || quiet_count>=SILENCE_FRAMES))) begin
                        frozen_start<=(recorded==RECORD_FRAMES) ? write_addr : 15'd0;
                        frozen_length<=recorded;
                        active_reverse<=reverse_mode;
                        active_decaying_source<=decaying_source;
                        state<=GAP;gap_left<=FIRST_GAP_FRAMES;repeat_index<=0;
                        tail_finished<=1;
                        play_addr<=reverse_mode ?
                            ((write_addr==0) ? RECORD_LAST : write_addr-1'b1) :
                            ((recorded==RECORD_FRAMES) ? write_addr : 15'd0);
                        play_pos<=0;repeat_gain<=first_gain;
                    end
                    GAP:if(gap_left!=0)gap_left<=gap_left-1'b1;
                        else state<=PLAY;
                    PLAY:if(play_now) begin
                        if(play_pos==frozen_length-1) begin
                            if(active_reverse || repeat_gain<=8'd3) begin state<=IDLE;pending<=0;end
                            else begin
                                state<=GAP;gap_left<=GAP_FRAMES;
                                repeat_index<=repeat_index+1'b1;
                                play_addr<=frozen_start;play_pos<=0;
                                repeat_gain<=repeat_gain>>1;
                            end
                        end else begin
                            play_pos<=play_pos+1'b1;
                            play_addr<=active_reverse ?
                                ((play_addr==0) ? RECORD_LAST : play_addr-1'b1) :
                                ((play_addr==RECORD_FRAMES-1) ? 15'd0 : play_addr+1'b1);
                        end
                    end
                    default:state<=IDLE;
                    endcase
                end
            end else if(stage==1) begin
                level_product<=read_sample*$signed({1'b0,held_gain});
                stage<=2;
            end else if(stage==2) begin
                if(held_playback) begin
                    out_left<=active_decaying_source ? mixed_left_limited : repeated_pcm[23:0];
                    out_right<=active_decaying_source ? mixed_right_limited : repeated_pcm[23:0];
                end else begin
                    out_left<=held_left;
                    out_right<=held_right;
                end
                out_valid<=1;
                stage<=0;
            end
        end
    end
endmodule
