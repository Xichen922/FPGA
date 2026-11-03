// 【按键变成演奏事件】输入是完整的16位按键快照，不是串行数据。
// 位0..11对应音符键1..12；按键13～16由独立音色控制器处理。
// note_gate[k]：希望第k个音符继续保持；0会让它进入释放尾音。
// note_press[k]：新按下一次产生一个时钟的脉冲，用来重新起音。
// note_octaves：12组4位八度信息；随已确认的摇杆八度实时更新。
// control_valid：告诉下一级，这次note_gate/note_press/note_octaves是一组新控制数据。
`timescale 1ns/1ps
// Keys 1..12: C..B; keys 13..16 select timbre outside this note controller.
// A confirmed joystick octave retunes all voices, including held/release notes.
// A pitch change publishes control without asserting note_press: no ADSR retrigger.
module latb_touch_note_control (
    input wire clk, rst,
    input wire [15:0] key_mask,
    input wire key_valid,
    input wire [3:0] selected_octave,
    output reg control_valid,
    output reg [11:0] note_gate,
    output reg [11:0] note_press,
    output reg [47:0] note_octaves,
    output wire [3:0] octave,
    output wire hold_enabled
);
    reg [11:0] previous_notes;
    reg [3:0] applied_octave;
    // 当前为1且上次为0，才算一次新按下；持续按住不会每帧重新触发。
    wire [11:0] down = key_mask[11:0] & ~previous_notes;
    assign hold_enabled = 1'b0; // Compatibility status; HOLD has been removed.
    assign octave = selected_octave;
    integer k;
    always @(posedge clk) begin
        if (rst) begin
            previous_notes <= 0;
            applied_octave <= 4;
            control_valid <= 0;
            note_gate <= 0;
            note_press <= 0;
            // {12{4'd4}}是重复拼接：将4位的4复制12次，默认全部使用第四八度。
            note_octaves <= {12{4'd4}};
        end else begin
            // 每拍先撤销事件脉冲。note_gate保持原状态，直到下一份完整按键快照。
            control_valid <= 0;
            note_press <= 0;
            // Consume complete touch snapshots only; an octave event is independent.
            if (key_valid) begin
                previous_notes <= key_mask[11:0];
                note_gate <= key_mask[11:0];
                note_press <= down;
                control_valid <= 1;
            end
            if (selected_octave != applied_octave) begin
                applied_octave <= selected_octave;
                note_octaves <= {12{selected_octave}};
                control_valid <= 1;
            end
        end
    end
endmodule
