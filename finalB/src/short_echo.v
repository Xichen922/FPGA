`timescale 1ns/1ps
// 1172 frames = 12.00128 ms at 50 MHz / 512. Feedback is 23/128 (17.96875%).
// Wet/dry is 7/32 : 25/32 (21.875% : 78.125%). The wet path uses a gentle
// one-pole low-pass: y[n]=(3*x[n]+y[n-1])/4.
// The dry setting preserves every input PCM bit. RAM is deliberately not reset;
// old samples are masked until the first full pass has filled it. Read and
// write are on separate clocks because this Gowin SP RAM cannot use WRITE_MODE=10.
module short_echo (
    input wire clk, rst, frame_tick, enable, voice_active,
    input wire signed [23:0] in_left, in_right,
    input wire in_valid,
    output wire in_ready,
    output reg signed [23:0] out_left, out_right,
    output reg out_valid,
    input wire out_ready,
    output wire audio_active
);
    localparam integer DELAY_FRAMES=1172;
    localparam integer TAIL_FRAMES=4689; // four delay laps after voice release
    (* syn_ramstyle="block_ram" *) reg signed [15:0] delay_ram [0:DELAY_FRAMES-1];
    reg [10:0] addr;
    reg [10:0] filled;
    reg signed [15:0] delayed;
    reg signed [15:0] lowpass_prev;
    reg signed [23:0] held_left, held_right;
    reg held_enable, held_filled;
    reg stage;
    reg [12:0] tail_frames;
    wire accept=in_valid && in_ready;
    assign in_ready=!stage && !out_valid;
    assign audio_active=voice_active || (enable && tail_frames!=0);

    function [23:0] clip24;
        input signed [24:0] value;
        begin
            if(value>25'sd8388607) clip24=24'h7fffff;
            else if(value< -25'sd8388608) clip24=24'h800000;
            else clip24=value[23:0];
        end
    endfunction
    function [15:0] clip16;
        input signed [17:0] value;
        begin
            if(value>18'sd32767) clip16=16'h7fff;
            else if(value< -18'sd32768) clip16=16'h8000;
            else clip16=value[15:0];
        end
    endfunction
    wire signed [16:0] old_echo=$signed({delayed[15],delayed});
    wire signed [16:0] old_filter=$signed({lowpass_prev[15],lowpass_prev});
    wire signed [17:0] echo_extended=$signed({old_echo[16],old_echo});
    wire signed [17:0] filter_sum=(echo_extended <<< 1)+echo_extended+
                                   $signed({old_filter[16],old_filter});
    wire signed [15:0] filtered=held_filled ? (filter_sum >>> 2) : 16'sd0;
    wire signed [24:0] wet_full=$signed({{9{filtered[15]}},filtered});
    wire signed [24:0] wet_term=(wet_full <<< 6)-(wet_full <<< 3); // 7/32 of 24-bit PCM
    wire signed [24:0] left_full=$signed({held_left[23],held_left});
    wire signed [24:0] right_full=$signed({held_right[23],held_right});
    wire signed [24:0] dry_left=left_full-(left_full >>> 2)+(left_full >>> 5);
    wire signed [24:0] dry_right=right_full-(right_full >>> 2)+(right_full >>> 5);
    wire signed [24:0] sum_left=dry_left+wet_term;
    wire signed [24:0] sum_right=dry_right+wet_term;
    wire signed [20:0] filtered_wide=$signed({{5{filtered[15]}},filtered});
    wire signed [20:0] feedback_term=((filtered_wide <<< 4)+(filtered_wide <<< 2)+
                                      (filtered_wide <<< 1)+filtered_wide) >>> 7;
    wire signed [17:0] feedback_sum=$signed({{2{held_left[23]}},held_left[23:8]})+
                                    $signed(feedback_term[17:0]);
    wire signed [15:0] write_sample=held_enable ? clip16(feedback_sum) : held_left[23:8];

    // One memory access per clock: read old echo sample on accept, write the
    // current sample on the following stage. No read-during-write mode needed.
    always @(posedge clk) begin
        if(!rst) begin
            if(stage) delay_ram[addr]<=write_sample;
            else if(accept) delayed<=delay_ram[addr];
        end
    end

    always @(posedge clk) begin
        if(rst) begin
            addr<=0;filled<=0;lowpass_prev<=0;held_left<=0;held_right<=0;
            held_enable<=0;held_filled<=0;stage<=0;
            out_left<=0;out_right<=0;out_valid<=0;tail_frames<=0;
        end else begin
            if(frame_tick) begin
                if(enable && voice_active) tail_frames<=TAIL_FRAMES;
                else if(tail_frames!=0) tail_frames<=tail_frames-1'b1;
            end
            if(out_valid && out_ready) out_valid<=0;
            if(accept) begin
                held_left<=in_left;held_right<=in_right;
                held_enable<=enable;held_filled<=(filled==DELAY_FRAMES);
                stage<=1;
            end else if(stage) begin
                addr<=(addr==DELAY_FRAMES-1) ? 11'd0 : addr+1'b1;
                if(filled<DELAY_FRAMES) filled<=filled+1'b1;
                lowpass_prev<=filtered;
                if(held_enable && held_filled) begin
                    out_left<=clip24(sum_left);
                    out_right<=clip24(sum_right);
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
