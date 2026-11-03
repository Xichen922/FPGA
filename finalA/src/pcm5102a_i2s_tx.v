// 【PCM转I2S串行信号】将一对24位左右声道采样按位发给DAC。
// 50MHz / 8 = 6.25MHz BCLK；每帧64个BCLK，Fs=97656.25Hz。
// 一帧分左/右各32个槽位：每声道24位数据，其余槽位填0。
// I2S要求LRCK切换后一位才发MSB：左声道在槽1..24，右声道在槽33..56。
// DIN/LRCK在BCLK下降沿更新，DAC在上升沿读取，数据有半个周期的稳定时间。
// 这里的左右声道是物理输出通道，十二个声部已经在上游混成一个PCM采样。
`timescale 1ns/1ps
// 50 MHz only. BCLK=clk/8, Fs=clk/512. No fabric-clocked logic.
// Philips I2S: slot 0/32 changes WS; slot 1/33 carries the MSB.
module pcm5102a_i2s_tx (
    input  wire               clk,
    input  wire               rst,          // synchronous, active high
    input  wire signed [23:0] pcm_left,
    input  wire signed [23:0] pcm_right,
    input  wire               pcm_valid,    // hold pair until ready
    output wire               pcm_ready,    // one clk BEFORE capture edge
    output reg                frame_tick,
    output reg                underrun,     // sticky until reset
    output wire               i2s_bclk,
    output reg                i2s_lrck,
    output reg                i2s_dout
);
    // 3位分频计数器0..7循环：BCLK低4拍、高4拍；一周期8个系统时钟。
    reg [2:0] div_count;
    // Dedicated forwarded-clock register. Do not let synthesis merge it
    // into the divider bit that also feeds internal data/enable logic.
    (* syn_preserve = 1 *) reg bclk_out;
    // bit_index记录当前64位帧槽0..63；left_hold/right_hold在整帧期间保持不变。
    reg [5:0] bit_index;
    reg signed [23:0] left_hold, right_hold;
    // 6位加法从63溢出回0；在下降沿切换到下一个槽并准备该槽的数据。
    wire [5:0] next_index = bit_index + 6'd1;

    assign i2s_bclk = bclk_out;
    // 即将从槽63进入槽0时拉高ready；下一个clk边沿捕获生产者的左右采样。
    assign pcm_ready = !rst && (div_count == 3'd7) &&
                       (bit_index == 6'd63);

    always @(posedge clk) begin
        if (rst) begin
            div_count <= 3'd0;
            bclk_out <= 1'b0;
            // 从63开始，使第一个有效BCLK下降沿进入槽0，形成完整左声道帧头。
            bit_index <= 6'd63;
            left_hold <= 24'sd0;
            right_hold <= 24'sd0;
            i2s_lrck <= 1'b1;
            i2s_dout <= 1'b0;
            frame_tick <= 1'b0;
            underrun <= 1'b0;
        end else begin
            div_count <= div_count + 3'd1;
            // 对外BCLK用专用寄存器转发，但本模块always仍只由系统clk驱动。
            if (div_count == 3'd3) bclk_out <= 1'b1;
            if (div_count == 3'd7) bclk_out <= 1'b0;
            frame_tick <= 1'b0;
            // DIN and LRCK update ONLY on a BCLK falling edge.
            if (div_count == 3'd7) begin
                bit_index <= next_index;
                // 槽0..31最高位为0（左声道），槽32..63最高位为1（右声道）。
                i2s_lrck <= next_index[5];
                // 一帧开始：取走已准备的旧采样，同时通知合成器计算供下一帧使用的采样。
                // 合成器有512个clk的时间准备，不需要等到最后一个槽才计算。
                if (next_index == 6'd0) begin
                    frame_tick <= 1'b1;
                    if (pcm_valid) begin
                        left_hold <= pcm_left;
                        right_hold <= pcm_right;
                    // 欠载时用0填本帧，并锁存underrun=1；不会发送未定义或旧脏数据。
                    end else begin
                        left_hold <= 24'sd0;
                        right_hold <= 24'sd0;
                        underrun <= 1'b1;
                    end
                end
                // 左槽1发bit23(MSB)，槽24发bit0(LSB)；右槽33..56同理。
                // 槽0/32是I2S一位延迟，其余非数据槽也发0。
                if ((next_index >= 6'd1) && (next_index <= 6'd24))
                    i2s_dout <= left_hold[24 - next_index];
                else if ((next_index >= 6'd33) && (next_index <= 6'd56))
                    i2s_dout <= right_hold[56 - next_index];
                else
                    i2s_dout <= 1'b0;
            end
        end
    end
endmodule
