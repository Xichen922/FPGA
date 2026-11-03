// 【DAC输出包装】内部u_tx负责I2S，本模块额外管理XSMT启动和静音。
// mute=1请求静音；dac_xsmt=0静音，1允许DAC发声。
// 本版上游用“所有声部都结束”作为mute条件，所以松键不会切掉Release尾音。
// 静音期间I2S时钟仍持续输出，DAC接口不会随着按键启停。
`timescale 1ns/1ps
// Reusable output stage. All inputs must belong to the same 50 MHz domain.
// rst: synchronous active-high reset supplied by the instrument top.
// mute: synchronous active-high DAC soft-mute request. Clocks keep running.
module pcm5102a_output (
    input wire clk,
    input wire rst,
    input wire mute,
    input wire signed [23:0] pcm_left,
    input wire signed [23:0] pcm_right,
    input wire pcm_valid,
    output wire pcm_ready,
    output wire frame_tick,
    output wire underrun,
    output wire i2s_bclk,
    output wire i2s_lrck,
    output wire i2s_dout,
    output reg dac_xsmt
);
    // PCM数值已经由上游混音完成，这里只负责发送，不再做音符合成。
    pcm5102a_i2s_tx u_tx (
        .clk(clk), .rst(rst),
        .pcm_left(pcm_left), .pcm_right(pcm_right),
        .pcm_valid(pcm_valid), .pcm_ready(pcm_ready),
        .frame_tick(frame_tick), .underrun(underrun),
        .i2s_bclk(i2s_bclk), .i2s_lrck(i2s_lrck), .i2s_dout(i2s_dout)
    );
    // 用采样帧计数上电等待：第12位变1意味着累计4096帧，约83.886ms。
    // 达到4096后停止累加，防止计数绕回导致DAC周期性重新静音。
    reg [12:0] startup_frames;
    always @(posedge clk) begin
        if (rst) begin
            startup_frames <= 13'd0;
            dac_xsmt <= 1'b0;
        end else begin
            if (frame_tick && !startup_frames[12])
                startup_frames <= startup_frames + 13'd1;
            // 满足启动等待且没有静音请求时才解除静音；这不暂停I2S时钟或PCM握手。
            dac_xsmt <= startup_frames[12] && !mute;
        end
    end
endmodule
