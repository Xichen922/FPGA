`timescale 1ns/1ps
// Tang Primer 25K: MX notes + separate TTP229 timbre zones + one DO fill light.
module ref51_example51_top #(
    // 1 ms full matrix scan; each key debounces independently.
    parameter integer KEYBOARD_ROW_CYCLES=12500, KEYBOARD_DEBOUNCE_FRAMES=5,
    parameter integer SPI_HALF_CYCLES=25, SPI_POLL_CYCLES=50000, ENCODER_REVERSE=0,
    parameter integer CONTROL_TIMEOUT_CYCLES=5000000,
    parameter integer ADC_SCAN_CYCLES=50000,
    parameter integer ADC_SPI_HALF_CYCLES=25,
    parameter integer UART_BAUD=9600,
    parameter integer TOUCH_STARTUP_CYCLES=30000000, TOUCH_GAP_CYCLES=150000,
    parameter integer TOUCH_SCL_HZ=100000,
    // Sensor DO -> MCP3008 CH4 only. Confirm at the fixed 1kHz snapshot rate.
    parameter integer FILL_LIGHT_ENABLE=1, LIGHT_DARK_HIGH=1,
    parameter integer LIGHT_HIGH_THRESHOLD=640, LIGHT_LOW_THRESHOLD=256,
    parameter integer LIGHT_DARK_CONFIRM=300, LIGHT_BRIGHT_CONFIRM=1000,
    parameter integer LIGHT_MIN_HOLD=1000,
    // Legacy parameter for non-profile gain settings; keyboard now has its own spectrum.
    parameter integer SOFT_TIMBRE=1,
    // 1: calibrated per-timbre/per-note balance plus4dB/octave tilt. 0: flat gain.
    parameter integer PITCH_BALANCE_ENABLE=1,
    parameter integer BALANCE_SMOOTH_STEP=32,
    parameter integer PORTAMENTO_ENABLE=0, // Temporarily disabled
    parameter integer VIBRATO_CENTER=512, VIBRATO_DEAD_ZONE=32,
    parameter [31:0] VIBRATO_LFO_STEP=32'd219902,
    parameter integer ENCODER_DEBOUNCE_CYCLES=100000,
    parameter integer OCTAVE_LOW_ENTER=256, OCTAVE_LOW_EXIT=320,
    parameter integer OCTAVE_HIGH_EXIT=704, OCTAVE_HIGH_ENTER=768,
    parameter integer OCTAVE_CONFIRM_SAMPLES=4
) (
    input wire clk, reset_n,
    input wire [3:0] kb_col,
    input wire touch_sdo,
    output wire touch_scl, led_fill_en,
    input wire mcp_miso, encoder_s1,encoder_s2,link_miso,
    output wire [3:0] kb_row,
    output wire mcp_cs_n,mcp_sclk,mcp_mosi,
    output wire i2s_bclk,i2s_lrck,i2s_dout,link_cs_n,link_sclk,link_mosi
);
    // 两级同步释放复位：按下复位时立即清零，松开后等待两个clk上升沿。
    // syn_preserve要求综合器保留同步寄存器，降低异步复位释放带来的风险。
    (* syn_preserve=1 *) reg [1:0] reset_pipe=0;
    always @(posedge clk or negedge reset_n)
        if (!reset_n) reset_pipe <= 0;
        else reset_pipe <= {reset_pipe[0],1'b1};
    // 上电后等待32768个系统时钟（约0.655ms），再允许功能模块启动。
    // 这个计数器只负责上电等待；外部复位不会重新启动它，但会复位下游模块。
    reg [15:0] por_count=0;
    always @(posedge clk)
        if (!por_count[15]) por_count <= por_count + 1'b1;
    // 两个条件都满足才解除复位：上电等待结束，且外部复位已经同步释放。
    // 矩阵键盘使用低有效rst_n；合成器/I2S模块使用高有效rst。
    wire rst_n=por_count[15] && reset_pipe[1];
    wire rst=!rst_n;
    // ADC与UART均使用50MHz系统时钟，SPI时钟仅作为外部输出。
    // Every 1ms convert CH0/1/4, then publish one atomic snapshot.
    wire [9:0] adc_ch0, adc_ch1, adc_ch2, adc_ch3, adc_ch4, adc_ch5, adc_ch6, adc_ch7;
    wire adc_valid;
    ref51_mcp3008_scan #(.SCAN_CYCLES(ADC_SCAN_CYCLES),
        .SPI_HALF_CYCLES(ADC_SPI_HALF_CYCLES), .SCAN_MODE_014(1)) u_adc (
        .clk(clk), .rst_n(rst_n), .miso(mcp_miso),
        .cs_n(mcp_cs_n), .sclk(mcp_sclk), .mosi(mcp_mosi),
        .ch0(adc_ch0), .ch1(adc_ch1), .ch2(adc_ch2), .ch3(adc_ch3),
        .ch4(adc_ch4), .ch5(adc_ch5), .ch6(adc_ch6), .ch7(adc_ch7),
        .snapshot_valid(adc_valid));
    ref51_fill_light_control #(.ENABLE(FILL_LIGHT_ENABLE), .DARK_HIGH(LIGHT_DARK_HIGH),
        .LOW_THRESHOLD(LIGHT_LOW_THRESHOLD), .HIGH_THRESHOLD(LIGHT_HIGH_THRESHOLD),
        .DARK_CONFIRM(LIGHT_DARK_CONFIRM), .BRIGHT_CONFIRM(LIGHT_BRIGHT_CONFIRM),
        .MIN_HOLD(LIGHT_MIN_HOLD)) u_fill_light (
        .clk(clk), .rst(rst), .snapshot_valid(adc_valid), .adc_do(adc_ch4),
        .led_enable(led_fill_en));
    wire [15:0] timbre_touch_keys;
    wire timbre_touch_valid, touch_select_valid;
    wire [1:0] touch_timbre;
    ref51_ttp229_driver #(.STARTUP_CYCLES(TOUCH_STARTUP_CYCLES),
        .GAP_CYCLES(TOUCH_GAP_CYCLES), .SCL_HZ(TOUCH_SCL_HZ)) u_touch_timbre (
        .clk(clk), .rst_n(rst_n), .touch_sdo(touch_sdo), .touch_scl(touch_scl),
        .key_mask(timbre_touch_keys), .key_valid(timbre_touch_valid),
        .key_press(), .key_release(), .raw_mask(), .ready());
    ref51_touch_timbre_zones u_touch_zones (.clk(clk), .rst(rst),
        .key_mask(timbre_touch_keys), .key_valid(timbre_touch_valid),
        .select_valid(touch_select_valid), .timbre(touch_timbre));
    // Keep the existing local snapshot names so note/timbre/remote merging
    // retain their exact interfaces. Keys 13..16 still directly select timbres.
    wire [15:0] touch_keys, touch_raw;
    wire touch_valid;
    ref51_keyboard_matrix_scan #(.CLK_HZ(50000000),
        .ROW_CYCLES(KEYBOARD_ROW_CYCLES),
        .DEBOUNCE_FRAMES(KEYBOARD_DEBOUNCE_FRAMES)) u_keyboard (
        .clk(clk), .rst_n(rst_n), .kb_col(kb_col), .kb_row(kb_row),
        .key_mask(touch_keys), .key_valid(touch_valid), .raw_mask(touch_raw));

    // B44 guide mode transmits zero remote keys and disables score overrides.
    // Thus performed_keys[11:0] reports only the debounced physical keys during
    // practice; keep the OR merge for ordinary P playback and manual overlay.
    // Physical keys 13..16 continue to directly select timbre.
    wire [11:0] remote_keys;
    wire remote_octave_enable,remote_timbre_enable;
    wire [3:0] remote_octave;
    wire [1:0] remote_timbre;
    reg [11:0] previous_remote_keys;
    always @(posedge clk)
        if(rst) previous_remote_keys <= 0;
        else previous_remote_keys <= remote_keys;
    wire [15:0] performed_keys = {touch_keys[15:12], touch_keys[11:0] | remote_keys};
    wire performed_valid = touch_valid | (remote_keys != previous_remote_keys);
    wire signed [23:0] pcm_left, pcm_right;
    wire pcm_valid, pcm_ready, frame_tick, underrun, any_active;
    wire vibrato_enable,link_good;
    wire [11:0] active_voices;
    wire [3:0] octave;
    wire [1:0] current_timbre;
    wire hold_enabled;
    // Legacy base gains; TIMBRE_ENABLE profiles in sine_voice override these:
    // harmonics 5..8: 1/64 vs 1/32; 9..16: 1/512 vs 1/128;
    // 17..32: 1/1024 vs 1/256. Harmonics 1..4 are unchanged.
    localparam integer GAIN_5_TO_8=SOFT_TIMBRE ? 6 : 5;
    localparam integer GAIN_9_TO_16=SOFT_TIMBRE ? 9 : 7;
    localparam integer GAIN_17_TO_32=SOFT_TIMBRE ? 10 : 8;
    wire signed [7:0] encoder_delta;
    wire encoder_valid;
    ref51_ec11_encoder #(.DEBOUNCE_CYCLES(ENCODER_DEBOUNCE_CYCLES)) u_encoder (
        .clk(clk), .rst(rst), .s1(encoder_s1), .s2(encoder_s2),
        .step_delta(encoder_delta), .step_valid(encoder_valid));
    // 合成器通过valid/ready交付完整左右采样；frame_tick提供统一采样节拍。
    // CH1迟滞及连续快照选择3/4/5八度；仅新按音符锁存，保持音及尾音不变调。
    // MX13..16 and the separate TTP229 select timbre. Light controls LED only.
    ref51_instrument_core #(
        .REMOTE_CONTROL_ENABLE(1),
        .VIBRATO_SWITCH_ENABLE(0),
        .LIGHT_ENABLE(0), .EXTERNAL_TIMBRE_ENABLE(1),
        .PORTAMENTO_ENABLE(PORTAMENTO_ENABLE),
        .PITCH_BALANCE_ENABLE(PITCH_BALANCE_ENABLE), .BALANCE_SMOOTH_STEP(BALANCE_SMOOTH_STEP),
        .GAIN_SHIFT_5(GAIN_5_TO_8), .GAIN_SHIFT_6(GAIN_5_TO_8),
        .GAIN_SHIFT_7(GAIN_5_TO_8), .GAIN_SHIFT_8(GAIN_5_TO_8),
        .GAIN_SHIFT_9(GAIN_9_TO_16), .GAIN_SHIFT_10(GAIN_9_TO_16),
        .GAIN_SHIFT_11(GAIN_9_TO_16), .GAIN_SHIFT_12(GAIN_9_TO_16),
        .GAIN_SHIFT_13(GAIN_9_TO_16), .GAIN_SHIFT_14(GAIN_9_TO_16),
        .GAIN_SHIFT_15(GAIN_9_TO_16), .GAIN_SHIFT_16(GAIN_9_TO_16),
        .GAIN_SHIFT_17(GAIN_17_TO_32), .GAIN_SHIFT_18(GAIN_17_TO_32),
        .GAIN_SHIFT_19(GAIN_17_TO_32), .GAIN_SHIFT_20(GAIN_17_TO_32),
        .GAIN_SHIFT_21(GAIN_17_TO_32), .GAIN_SHIFT_22(GAIN_17_TO_32),
        .GAIN_SHIFT_23(GAIN_17_TO_32), .GAIN_SHIFT_24(GAIN_17_TO_32),
        .GAIN_SHIFT_25(GAIN_17_TO_32), .GAIN_SHIFT_26(GAIN_17_TO_32),
        .GAIN_SHIFT_27(GAIN_17_TO_32), .GAIN_SHIFT_28(GAIN_17_TO_32),
        .GAIN_SHIFT_29(GAIN_17_TO_32), .GAIN_SHIFT_30(GAIN_17_TO_32),
        .GAIN_SHIFT_31(GAIN_17_TO_32), .GAIN_SHIFT_32(GAIN_17_TO_32),
        .VIBRATO_CENTER(VIBRATO_CENTER), .VIBRATO_DEAD_ZONE(VIBRATO_DEAD_ZONE),
        .VIBRATO_LFO_STEP(VIBRATO_LFO_STEP),.OCTAVE_LOW_ENTER(OCTAVE_LOW_ENTER), .OCTAVE_LOW_EXIT(OCTAVE_LOW_EXIT),
        .OCTAVE_HIGH_EXIT(OCTAVE_HIGH_EXIT), .OCTAVE_HIGH_ENTER(OCTAVE_HIGH_ENTER),
        .OCTAVE_CONFIRM_SAMPLES(OCTAVE_CONFIRM_SAMPLES)) u_instrument (
        .clk(clk), .rst(rst), .touch_keys(performed_keys),
        .external_timbre_valid(touch_select_valid), .external_timbre(touch_timbre),
        .remote_octave_enable(remote_octave_enable),.remote_octave(remote_octave),
        .remote_timbre_enable(remote_timbre_enable),.remote_timbre(remote_timbre),
        .touch_valid(performed_valid), .frame_tick(frame_tick), .pcm_ready(pcm_ready),
        .joystick_x(adc_ch0), .joystick_y(adc_ch1), .joystick_valid(adc_valid),
        .light_1(10'd0), .light_2(10'd0), .light_3(10'd0), .light_4(10'd0),
        .light_valid(1'b0),
        .ultrasonic_distance_mm(16'd0), .ultrasonic_valid(1'b0),
        .encoder_delta(8'sd0), .encoder_valid(1'b0), .encoder_button_press(1'b0), .vibrato_enable(vibrato_enable),
        .pcm_left(pcm_left), .pcm_right(pcm_right), .pcm_valid(pcm_valid),
        .any_active(any_active), .active_voices(active_voices), .octave(octave),
        .current_timbre(current_timbre),
        .hold_enabled(hold_enabled));
    // A owns audio cadence. Existing joystick vibrato remains; EC11 changes effect depth.
    wire [127:0] link_out,link_in;wire link_valid;
    wire signed [7:0] effect_delta=ENCODER_REVERSE ? -encoder_delta : encoder_delta;
    // B44 receives note keys from tx_packet[99:88] and effective octave from
    // [83:80]. In guide mode no remote octave override exists, so octave is the
    // actual joystick selection. Do not return the score target as user input.
    ref51_db_master_controls #(.TIMEOUT_CYCLES(CONTROL_TIMEOUT_CYCLES)) u_link_controls(.clk(clk),.rst(rst),.keys(performed_keys),.octave(octave),.timbre(current_timbre),
        .any_active(any_active),.active_voices(active_voices),.encoder_delta(effect_delta),.encoder_valid(encoder_valid),
        .rx_packet(link_in),.rx_valid(link_valid),.tx_packet(link_out),.vibrato_enable(vibrato_enable),.link_good(link_good),.remote_keys(remote_keys),
        .remote_octave_enable(remote_octave_enable),.remote_octave(remote_octave),
        .remote_timbre_enable(remote_timbre_enable),.remote_timbre(remote_timbre));
    ref51_db_spi_master #(.HALF_CYCLES(SPI_HALF_CYCLES),.POLL_CYCLES(SPI_POLL_CYCLES)) u_link(
        .clk(clk),.rst(rst),.tx_packet(link_out),.miso(link_miso),.cs_n(link_cs_n),.sclk(link_sclk),.mosi(link_mosi),
        .rx_packet(link_in),.rx_valid(link_valid));
    ref51_pcm5102a_i2s_tx u_audio(.clk(clk),.rst(rst),.pcm_left(pcm_left),.pcm_right(pcm_right),.pcm_valid(pcm_valid),
        .pcm_ready(pcm_ready),.frame_tick(frame_tick),.underrun(underrun),
        .i2s_bclk(i2s_bclk),.i2s_lrck(i2s_lrck),.i2s_dout(i2s_dout));
endmodule
