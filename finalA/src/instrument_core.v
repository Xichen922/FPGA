// Twelve fixed pitch-class voices; one shared40-mode synthesis engine.
// Four lanes each render three voices, then share one gain multiplier per lane.
// Per-key onset octave, envelopes, expression, SPI andI2S behavior are retained.
`timescale 1ns/1ps
module instrument_core #(
    parameter integer REMOTE_CONTROL_ENABLE=0,
    parameter integer EXTERNAL_TIMBRE_ENABLE=0,
    parameter integer LIGHT_ENABLE=0, VIBRATO_SWITCH_ENABLE=0,
    parameter integer LIGHT_ACTIVE_LOW=1,
    parameter integer LIGHT_HIGH_THRESHOLD=640, LIGHT_LOW_THRESHOLD=256,
    parameter integer LIGHT_CONFIRM_SNAPSHOTS=2,
    parameter integer LIGHT1_HIGH_THRESHOLD=LIGHT_HIGH_THRESHOLD, LIGHT1_LOW_THRESHOLD=LIGHT_LOW_THRESHOLD,
    parameter integer LIGHT2_HIGH_THRESHOLD=LIGHT_HIGH_THRESHOLD, LIGHT2_LOW_THRESHOLD=LIGHT_LOW_THRESHOLD,
    parameter integer LIGHT3_HIGH_THRESHOLD=LIGHT_HIGH_THRESHOLD, LIGHT3_LOW_THRESHOLD=LIGHT_LOW_THRESHOLD,
    parameter integer LIGHT4_HIGH_THRESHOLD=LIGHT_HIGH_THRESHOLD, LIGHT4_LOW_THRESHOLD=LIGHT_LOW_THRESHOLD,
    parameter integer PORTAMENTO_ENABLE=0, // Temporarily disabled
    parameter integer PORTAMENTO_MIN_SAMPLES=3000, PORTAMENTO_SAMPLES_PER_MM=80,
    parameter integer PITCH_BALANCE_ENABLE=1, BALANCE_SMOOTH_STEP=32,
    parameter integer ATTACK_SAMPLES=489, DECAY_SAMPLES=7813,
    parameter integer SUSTAIN_LEVEL=45875, RELEASE_SAMPLES=11719,
    parameter integer VIBRATO_CENTER=512, VIBRATO_DEAD_ZONE=32,
    parameter [31:0] VIBRATO_LFO_STEP=32'd219902,
    parameter integer OCTAVE_LOW_ENTER=256, OCTAVE_LOW_EXIT=320,
    parameter integer OCTAVE_HIGH_EXIT=704, OCTAVE_HIGH_ENTER=768,
    parameter integer OCTAVE_CONFIRM_SAMPLES=4
) (
    input wire clk, rst,
    input wire [15:0] touch_keys,
    input wire touch_valid, frame_tick, pcm_ready,
    input wire external_timbre_valid,
    input wire [1:0] external_timbre,
    // Synchronous sensor interfaces. Y/CH1 selects onset octave.
    // Production uses CH0/1 for joystick; CH4 DO controls fill light in the top module.
    // X controls vibrato depth; EC11 controls3..7Hz rate. Ultrasonic input is inactive.
    input wire [9:0] joystick_x, joystick_y,
    input wire joystick_valid,
    input wire [9:0] light_1, light_2, light_3, light_4,
    input wire light_valid,
    input wire [15:0] ultrasonic_distance_mm,
    input wire ultrasonic_valid,
    // Signed debounced EC11 steps, -128..127 accumulated between updates.
    input wire signed [7:0] encoder_delta,
    input wire encoder_valid, encoder_button_press, vibrato_enable,
    input wire remote_octave_enable,remote_timbre_enable,
    input wire [3:0] remote_octave,
    input wire [1:0] remote_timbre,
    output reg signed [23:0] pcm_left, pcm_right,
    output reg pcm_valid,
    output wire any_active,
    output wire [11:0] active_voices,
    output wire [3:0] octave,
    output wire [1:0] current_timbre,
    output wire hold_enabled
);
    // 三种不同信号：press/trigger是一拍事件，gate是持续状态，active是实际声部状态。
    // gate=0以后active仍可能为1，因为ADSR还在播放Release尾音。
    // 13/14/15/16选择音色。选择音色不改变音符gate/trigger或相位。
    wire [1:0] selected_timbre, requested_timbre;
    assign current_timbre=selected_timbre;
    wire [8:0] timbre_gain;
    wire [15:0] motion_gain;
    wire [24:0] combined_gain=timbre_gain*motion_gain;
    reg [15:0] frame_output_gain;
    wire light_select;
    wire [1:0] light_timbre;
    generate if(LIGHT_ENABLE!=0) begin: light_controls
        light_timbre_select #(.ACTIVE_LOW(LIGHT_ACTIVE_LOW),
            .HIGH_THRESHOLD(LIGHT_HIGH_THRESHOLD), .LOW_THRESHOLD(LIGHT_LOW_THRESHOLD),
            .HIGH_THRESHOLD_1(LIGHT1_HIGH_THRESHOLD), .LOW_THRESHOLD_1(LIGHT1_LOW_THRESHOLD),
            .HIGH_THRESHOLD_2(LIGHT2_HIGH_THRESHOLD), .LOW_THRESHOLD_2(LIGHT2_LOW_THRESHOLD),
            .HIGH_THRESHOLD_3(LIGHT3_HIGH_THRESHOLD), .LOW_THRESHOLD_3(LIGHT3_LOW_THRESHOLD),
            .HIGH_THRESHOLD_4(LIGHT4_HIGH_THRESHOLD), .LOW_THRESHOLD_4(LIGHT4_LOW_THRESHOLD),
            .CONFIRM_SNAPSHOTS(LIGHT_CONFIRM_SNAPSHOTS)) u_light (
            .clk(clk), .rst(rst), .snapshot_valid(light_valid),
            .light_1(light_1), .light_2(light_2), .light_3(light_3), .light_4(light_4),
            .select_valid(light_select), .timbre(light_timbre));
    end else begin: no_light_controls
        assign light_select=1'b0;
        assign light_timbre=2'd0;
    end endgenerate
    timbre_motion u_motion(.clk(clk),.rst(rst),.sample_tick(frame_tick),
        .timbre_select(selected_timbre),.gain_q15(motion_gain));
    timbre_control #(.REMOTE_CONTROL_ENABLE(REMOTE_CONTROL_ENABLE),
        .EXTERNAL_CONTROL_ENABLE(EXTERNAL_TIMBRE_ENABLE)) u_timbre(.clk(clk),.rst(rst),.sample_tick(frame_tick),
        .key_mask(touch_keys),.key_valid(touch_valid),
        .external_select(external_timbre_valid), .external_timbre(external_timbre),
        .light_select(light_select), .light_timbre(light_timbre),
        .remote_timbre_enable(remote_timbre_enable),.remote_timbre(remote_timbre),
        .requested_timbre(requested_timbre),.active_timbre(selected_timbre),.gain(timbre_gain));
    always @(posedge clk) begin
        if(rst) begin frame_output_gain<=16'd32768;end
        else if(frame_tick) begin
            frame_output_gain<=combined_gain[23:8];
        end
    end
    wire control_valid;
    wire [11:0] note_gate, note_press;
    wire [47:0] note_octaves;
    wire [11:0] voice_gate, voice_trigger;
    wire [47:0] voice_octaves;
    wire [383:0] voice_steps;
    wire signed [11:0] vibrato_q16;
    wire [14:0] portamento_samples;
    reg signed [15:0] pitch_mod_q16;
    always @(posedge clk) begin
        if(rst) pitch_mod_q16<=0;
        else pitch_mod_q16<={{4{vibrato_q16[11]}},vibrato_q16};
    end
    // 暂停超声波对滑音时间的控制；恢复时删除固定赋值并取消实例注释。
    assign portamento_samples=15'd11000;
    wire [3:0] vibrato_speed_hz;
    joystick_vibrato #(.EXTERNAL_ENABLE(VIBRATO_SWITCH_ENABLE),.CENTER(VIBRATO_CENTER), .DEAD_ZONE(VIBRATO_DEAD_ZONE),
        .LFO_STEP(VIBRATO_LFO_STEP)) u_vibrato (
        .clk(clk), .rst(rst), .sample_tick(frame_tick),
        .snapshot_valid(joystick_valid), .adc_value(joystick_x),
        .encoder_delta(encoder_delta), .encoder_valid(encoder_valid), .enable(vibrato_enable),
        .speed_hz(vibrato_speed_hz), .vibrato_q16(vibrato_q16));
    wire [3:0] manual_octave;
    wire use_remote_octave=(REMOTE_CONTROL_ENABLE!=0) && remote_octave_enable &&
        (remote_octave==3 || remote_octave==4 || remote_octave==5);
    wire [3:0] selected_octave=use_remote_octave ? remote_octave : manual_octave;
    joystick_octave #(.LOW_ENTER(OCTAVE_LOW_ENTER), .LOW_EXIT(OCTAVE_LOW_EXIT),
        .HIGH_EXIT(OCTAVE_HIGH_EXIT), .HIGH_ENTER(OCTAVE_HIGH_ENTER),
        .CONFIRM_SAMPLES(OCTAVE_CONFIRM_SAMPLES)) u_joystick_octave (
        .clk(clk), .rst(rst), .adc_value(joystick_y),
        .snapshot_valid(joystick_valid), .octave(manual_octave));
    // 第一步：完整触摸帧产生新按下、释放和触发时八度。
    touch_note_control u_control (.clk(clk), .rst(rst), .key_mask(touch_keys),
        .key_valid(touch_valid), .selected_octave(selected_octave),
        .control_valid(control_valid), .note_gate(note_gate),
        .note_press(note_press), .note_octaves(note_octaves), .octave(octave),
        .hold_enabled(hold_enabled));
    // 第二步：每个键拥有固定声部，将每组八度转换成32位频率步进。
    voice_mapper_12 #(.PORTAMENTO_ENABLE(PORTAMENTO_ENABLE),.OCTAVE_345_ONLY(1)) u_mapper (
        .clk(clk), .rst(rst), .control_valid(control_valid),
        .sample_tick(frame_tick), .glide_samples(portamento_samples),
        .note_gate(note_gate), .note_press(note_press), .note_octaves(note_octaves),
        .voice_gate(voice_gate), .voice_trigger(voice_trigger),
        .voice_steps(voice_steps), .voice_octaves(voice_octaves));
    wire signed [23:0] voice_sample[0:11];
    wire [287:0] shared_samples;wire [11:0] shared_valid,shared_active;
    wire [11:0] voice_sample_valid;
    wire signed [23:0] balanced_sample[0:11];wire [11:0] balanced_valid;
    wire [191:0] gain_values;wire [287:0] balanced_packed;
    reg [1:0] frame_spectrum;
    always @(posedge clk)if(rst)frame_spectrum<=0;else if(frame_tick)frame_spectrum<=selected_timbre;
    // User-approved switch behavior: fade reaches zero, then held keys re-strike.
    wire [11:0] render_trigger=voice_trigger|((frame_tick && selected_timbre!=frame_spectrum)?voice_gate:12'd0);
    wire [191:0] bank_normal_levels,bank_organ_levels,bank_pluck_levels,bank_piano_levels;
    wire [35:0] bank_normal_states,bank_organ_states,bank_pluck_states,bank_piano_states;
    wire [11:0] bank_normal_active,bank_organ_active,bank_pluck_active,bank_piano_active;
    wire bank_ready;
    // Only clarinet/organ use this envelope bank; percussion decays in the modal core.
    envelope_bank #(.LEGACY_PERCUSSION_ENABLE(0),.ATTACK_SAMPLES(ATTACK_SAMPLES),.DECAY_SAMPLES(DECAY_SAMPLES),
        .SUSTAIN_LEVEL(SUSTAIN_LEVEL),.RELEASE_SAMPLES(RELEASE_SAMPLES)) u_envelope_bank(
        .clk(clk),.rst(rst),.sample_tick(frame_tick),.trigger(render_trigger),.gate(voice_gate),
        .octaves(voice_octaves),.timbre(selected_timbre),.ready(bank_ready),
        .piano_levels(bank_piano_levels),.piano_states(bank_piano_states),.piano_active(bank_piano_active),
        .normal_levels(bank_normal_levels),.normal_states(bank_normal_states),.normal_active(bank_normal_active),
        .organ_levels(bank_organ_levels),.organ_states(bank_organ_states),.organ_active(bank_organ_active),
        .pluck_levels(bank_pluck_levels),.pluck_states(bank_pluck_states),.pluck_active(bank_pluck_active));
    shared_modal_core u_shared32(.clk(clk),.rst(rst),.frame_tick(frame_tick),.timbre(selected_timbre),
        .trigger(render_trigger),.gate(voice_gate),.octaves(voice_octaves),.phase_steps(voice_steps),
        .vibrato_q16(pitch_mod_q16),.normal_levels(bank_normal_levels),.organ_levels(bank_organ_levels),
        .envelopes_ready(bank_ready),.samples(shared_samples),.valid(shared_valid),.active(shared_active),.ready());
    genvar g;
    generate for(g=0;g<12;g=g+1)begin: voices
        assign voice_sample[g]=$signed(shared_samples[g*24+:24]);
        assign voice_sample_valid[g]=shared_valid[g];
        assign active_voices[g]=(frame_spectrum==1)?bank_normal_active[g]:(frame_spectrum==2)?bank_organ_active[g]:shared_active[g];
        gain_profile #(.NOTE_INDEX(g), .ENABLE(PITCH_BALANCE_ENABLE),
            .SMOOTH_STEP(BALANCE_SMOOTH_STEP)) u_balance (
            .clk(clk), .rst(rst), .sample_tick(frame_tick),
            .trigger(voice_trigger[g]),.timbre_select(selected_timbre),
            .octave(voice_octaves[g*4 +: 4]),
            .frame_gain(gain_values[g*16+:16]));
        assign balanced_sample[g]=$signed(balanced_packed[g*24+:24]);
    end endgenerate
    generate for(g=0;g<4;g=g+1)begin: gain_lanes
        gain_lane u_gain(.clk(clk),.rst(rst),.samples(shared_samples[g*72+:72]),
            .valid(shared_valid[g*3+:3]),.gains(gain_values[g*48+:48]),
            .result(balanced_packed[g*72+:72]),.result_valid(balanced_valid[g*3+:3]));
    end endgenerate
    // 一元|是归约或：12位中只要有一位为1，any_active就为1。
    assign any_active = |active_voices;
    // Widen BEFORE summation: three 4-voice groups, then a 28-bit sum.
    // ROM peak is 529285; default harmonic gains sum to 1.
    // Mixing retains 28-bit headroom and an explicit 24-bit saturator.
    // The shared expression gain never exceeds unity.
    // 第四步：每个有符号24位采样先扩展符号位再相加，四路用26位容纳结果。
    // {{2{sample[23]}},sample}把符号位复制两次；负数扩位后仍然是同一个负数。
    wire signed [25:0] mix_group[0:2];
    generate for(g=0; g<3; g=g+1) begin: mix_groups
        assign mix_group[g] = {{2{balanced_sample[g*4][23]}},balanced_sample[g*4]}
            + {{2{balanced_sample[g*4+1][23]}},balanced_sample[g*4+1]}
            + {{2{balanced_sample[g*4+2][23]}},balanced_sample[g*4+2]}
            + {{2{balanced_sample[g*4+3][23]}},balanced_sample[g*4+3]};
    end endgenerate
    // 三组再扩展为28位合并，所以12个声部同时出现峰值也不会在加法中绕回。
    wire signed [27:0] mix = {{2{mix_group[0][25]}},mix_group[0]}
        + {{2{mix_group[1][25]}},mix_group[1]}
        + {{2{mix_group[2][25]}},mix_group[2]};
    // 第五步：限幅到24位有符号范围[-8388608,8388607]，越界取边界值。
    // 本版低幅度正弦表已经有余量，限幅仍保留，便于后续调整音量或音色。
    wire signed [23:0] limited = (mix > 28'sd8388607) ? 24'sh7fffff :
        (mix < -28'sd8388608) ? 24'sh800000 : mix[23:0];
    // 第六步：共享ROM令完成时刻错开。收齐十二路本帧完成脉冲，再提交最新混音。
    // 每通道共用一个响度乘法器；两拍交付，PCM仍须在512clk内提交。
    // 音色切换时约2.62ms淡出、在静音处换谱、约2.62ms淡入。
    // 共享一次主音量乘法；增加一拍输出流水，保持512clk内交付PCM。
    wire signed [40:0] timbre_product=limited*$signed({1'b0,frame_output_gain});
    reg signed [23:0] faded_sample;
    reg mix_pending;
    reg [11:0] completed_voices;
    wire [11:0] next_completed=completed_voices | balanced_valid;
    wire mix_ready=&next_completed;
    always @(posedge clk) begin
        if (rst) begin
            completed_voices <= 0;
            mix_pending<=0; faded_sample<=0;
            pcm_left <= 0;
            pcm_right <= 0;
            pcm_valid <= 1; // Initial valid silence prevents first-frame underrun.
        end else begin
            mix_pending<=mix_ready && !frame_tick;
            if(frame_tick) completed_voices<=0;
            else completed_voices<=next_completed;
            // valid和ready在同一clk上升沿同时为1，意味着I2S已经取走整对左右采样。
            // 在取走之前，生产者保持PCM值稳定；取走后等待本帧生成的下一份采样。
            if (pcm_valid && pcm_ready) pcm_valid <= 0;
            // 当前最后一份valid对应的sample已在前一拍寄存，十二路均为本帧数据。
            if (mix_ready && !frame_tick) begin
                completed_voices<=0;
                // 左右声道复制同一个合成波形，因此两边喇叭都能听到完整十二音混音。
                faded_sample <= timbre_product[38:15]; // Bounded Q15 expression/fade product.
            end
            if(mix_pending) begin
                pcm_left<=faded_sample;
                pcm_right<=faded_sample;
                pcm_valid<=1;
            end
        end
    end
endmodule
