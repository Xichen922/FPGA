// 13/14/15/16选择钢琴、单簧管、风琴、八音盒音色。
// 同时新按时按13、14、15、16顺序优先；按住不会重复触发。
// 增益256为满音量。先逐采样淡出，零音量切换频谱，再逐采样淡入。
module timbre_control #(parameter integer REMOTE_CONTROL_ENABLE=0,
    parameter integer EXTERNAL_CONTROL_ENABLE=0) (
    input wire clk, rst, sample_tick, key_valid,
    input wire [15:0] key_mask,
    input wire light_select,
    input wire [1:0] light_timbre,
    input wire external_select,
    input wire [1:0] external_timbre,
    input wire remote_timbre_enable,
    input wire [1:0] remote_timbre,
    output wire [1:0] requested_timbre,
    output reg [1:0] active_timbre,
    output reg [8:0] gain
);
    // Manual selection is updated even while the score owns the effective target.
    reg [1:0] manual_requested_timbre;
    assign requested_timbre=(REMOTE_CONTROL_ENABLE!=0 && remote_timbre_enable) ?
        remote_timbre : manual_requested_timbre;
    reg [3:0] previous_keys;
    wire [3:0] down=key_mask[15:12] & ~previous_keys;
    always @(posedge clk) begin
        if(rst) begin
            previous_keys<=0;
            manual_requested_timbre<=0;
            active_timbre<=0;
            gain<=9'd256;
        end else begin
            if(key_valid) previous_keys<=key_mask[15:12];
            // A fresh manual key wins if a light event arrives on the same clk.
            if(key_valid && down[0]) manual_requested_timbre<=2'd0;
            else if(key_valid && down[1]) manual_requested_timbre<=2'd1;
            else if(key_valid && down[2]) manual_requested_timbre<=2'd2;
            else if(key_valid && down[3]) manual_requested_timbre<=2'd3;
            else if(EXTERNAL_CONTROL_ENABLE!=0 && external_select)
                manual_requested_timbre<=external_timbre;
            else if(light_select)
                manual_requested_timbre<=light_timbre;
            if(sample_tick) begin
                if(requested_timbre!=active_timbre) begin
                    if(gain!=0) gain<=gain-1'b1;
                    else active_timbre<=requested_timbre;
                end else if(gain<9'd256) gain<=gain+1'b1;
            end
        end
    end
endmodule

