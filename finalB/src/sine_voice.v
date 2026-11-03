// 每音32个独立32位相位状态，十二声部并行；每声部复用运算器。
// 64x16同步BSRAM交错保存低/高半字，不降低相位精度。
// 帧内锁存步进、包络、复位；高于或等于Fs/2的分量静音，相位继续推进。
`timescale 1ns/1ps
module sine_voice #(
    parameter integer VIBRATO_ENABLE=0,
    parameter integer VOICE_INDEX=0,
    parameter integer SHARED_ROM=0,
    parameter integer SHARED_ENVELOPES=0,
    parameter integer SHARED_GAIN=0, // Shared input already includes this voice's spectral shift.
    parameter integer TIMBRE_ENABLE=0,
    parameter integer ATTACK_SAMPLES=489, DECAY_SAMPLES=7813,
    parameter integer SUSTAIN_LEVEL=45875, RELEASE_SAMPLES=11719,
    parameter integer HARMONIC_1=1, HARMONIC_2=2, HARMONIC_3=3, HARMONIC_4=4,
    parameter integer HARMONIC_5=5, HARMONIC_6=6, HARMONIC_7=7, HARMONIC_8=8,
    parameter integer HARMONIC_9=9, HARMONIC_10=10, HARMONIC_11=11, HARMONIC_12=12,
    parameter integer HARMONIC_13=13, HARMONIC_14=14, HARMONIC_15=15, HARMONIC_16=16,
    parameter integer HARMONIC_17=17, HARMONIC_18=18, HARMONIC_19=19, HARMONIC_20=20,
    parameter integer HARMONIC_21=21, HARMONIC_22=22, HARMONIC_23=23, HARMONIC_24=24,
    parameter integer HARMONIC_25=25, HARMONIC_26=26, HARMONIC_27=27, HARMONIC_28=28,
    parameter integer HARMONIC_29=29, HARMONIC_30=30, HARMONIC_31=31, HARMONIC_32=32,
    parameter integer GAIN_SHIFT_1=1, GAIN_SHIFT_2=3, GAIN_SHIFT_3=4, GAIN_SHIFT_4=4,
    parameter integer GAIN_SHIFT_5=5, GAIN_SHIFT_6=5, GAIN_SHIFT_7=5, GAIN_SHIFT_8=5,
    parameter integer GAIN_SHIFT_9=7, GAIN_SHIFT_10=7, GAIN_SHIFT_11=7, GAIN_SHIFT_12=7,
    parameter integer GAIN_SHIFT_13=7, GAIN_SHIFT_14=7, GAIN_SHIFT_15=7, GAIN_SHIFT_16=7,
    parameter integer GAIN_SHIFT_17=8, GAIN_SHIFT_18=8, GAIN_SHIFT_19=8, GAIN_SHIFT_20=8,
    parameter integer GAIN_SHIFT_21=8, GAIN_SHIFT_22=8, GAIN_SHIFT_23=8, GAIN_SHIFT_24=8,
    parameter integer GAIN_SHIFT_25=8, GAIN_SHIFT_26=8, GAIN_SHIFT_27=8, GAIN_SHIFT_28=8,
    parameter integer GAIN_SHIFT_29=8, GAIN_SHIFT_30=8, GAIN_SHIFT_31=8, GAIN_SHIFT_32=8
) (
    input wire clk, rst, sample_tick, trigger, gate,
    input wire [31:0] phase_step,
    input wire [3:0] octave,
    input wire [1:0] timbre_select, // 0: grand piano; 1: clarinet; 2: organ; 3: plucked
    input wire signed [15:0] vibrato_q16,
    // SHARED_ROM=1时通过请求/授予复用全局查表；=0时保留独立模块的本地ROM。
    input wire shared_wave_grant,
    input wire shared_envelopes_ready,
    input wire [15:0] shared_normal_level,shared_organ_level,shared_pluck_level,
    input wire [2:0] shared_normal_state,shared_organ_state,shared_pluck_state,
    input wire shared_normal_active,shared_organ_active,shared_pluck_active,
    input wire [15:0] shared_piano_level,input wire [2:0] shared_piano_state,
    input wire shared_piano_active,
    input wire signed [23:0] shared_wave,
    output wire shared_wave_request,
    output wire [7:0] shared_wave_address,
    output wire [4:0] shared_gain_shift,
    output wire [8:0] shared_piano_age,output wire [3:0] shared_piano_octave,
    output wire shared_band_boost,
    output wire shared_high_cut, shared_fundamental_body,
    output wire shared_low_body,
    output wire shared_low_harmonic_cut,
    output wire [2:0] shared_low_tail_stage,
    output wire [4:0] shared_wave_oscillator,
    output reg signed [23:0] sample,
    output reg sample_valid,
    output wire active,
    output wire [15:0] envelope_level,
    output wire [2:0] envelope_state
);
    localparam integer OSCILLATORS=32;
    function integer harmonic;
        input integer index;
        begin
            case(index)
                0: harmonic=HARMONIC_1;
                1: harmonic=HARMONIC_2;
                2: harmonic=HARMONIC_3;
                3: harmonic=HARMONIC_4;
                4: harmonic=HARMONIC_5;
                5: harmonic=HARMONIC_6;
                6: harmonic=HARMONIC_7;
                7: harmonic=HARMONIC_8;
                8: harmonic=HARMONIC_9;
                9: harmonic=HARMONIC_10;
                10: harmonic=HARMONIC_11;
                11: harmonic=HARMONIC_12;
                12: harmonic=HARMONIC_13;
                13: harmonic=HARMONIC_14;
                14: harmonic=HARMONIC_15;
                15: harmonic=HARMONIC_16;
                16: harmonic=HARMONIC_17;
                17: harmonic=HARMONIC_18;
                18: harmonic=HARMONIC_19;
                19: harmonic=HARMONIC_20;
                20: harmonic=HARMONIC_21;
                21: harmonic=HARMONIC_22;
                22: harmonic=HARMONIC_23;
                23: harmonic=HARMONIC_24;
                24: harmonic=HARMONIC_25;
                25: harmonic=HARMONIC_26;
                26: harmonic=HARMONIC_27;
                27: harmonic=HARMONIC_28;
                28: harmonic=HARMONIC_29;
                29: harmonic=HARMONIC_30;
                30: harmonic=HARMONIC_31;
                default: harmonic=HARMONIC_32;
            endcase
        end
    endfunction
    function [4:0] gain_shift;
        input integer index;
        begin
            case(index)
                0: gain_shift=GAIN_SHIFT_1;
                1: gain_shift=GAIN_SHIFT_2;
                2: gain_shift=GAIN_SHIFT_3;
                3: gain_shift=GAIN_SHIFT_4;
                4: gain_shift=GAIN_SHIFT_5;
                5: gain_shift=GAIN_SHIFT_6;
                6: gain_shift=GAIN_SHIFT_7;
                7: gain_shift=GAIN_SHIFT_8;
                8: gain_shift=GAIN_SHIFT_9;
                9: gain_shift=GAIN_SHIFT_10;
                10: gain_shift=GAIN_SHIFT_11;
                11: gain_shift=GAIN_SHIFT_12;
                12: gain_shift=GAIN_SHIFT_13;
                13: gain_shift=GAIN_SHIFT_14;
                14: gain_shift=GAIN_SHIFT_15;
                15: gain_shift=GAIN_SHIFT_16;
                16: gain_shift=GAIN_SHIFT_17;
                17: gain_shift=GAIN_SHIFT_18;
                18: gain_shift=GAIN_SHIFT_19;
                19: gain_shift=GAIN_SHIFT_20;
                20: gain_shift=GAIN_SHIFT_21;
                21: gain_shift=GAIN_SHIFT_22;
                22: gain_shift=GAIN_SHIFT_23;
                23: gain_shift=GAIN_SHIFT_24;
                24: gain_shift=GAIN_SHIFT_25;
                25: gain_shift=GAIN_SHIFT_26;
                26: gain_shift=GAIN_SHIFT_27;
                27: gain_shift=GAIN_SHIFT_28;
                28: gain_shift=GAIN_SHIFT_29;
                29: gain_shift=GAIN_SHIFT_30;
                30: gain_shift=GAIN_SHIFT_31;
                default: gain_shift=GAIN_SHIFT_32;
            endcase
        end
    endfunction
// Clarinet: stronger upper odd harmonics (9th through 15th) add a little air.
    function [4:0] clarinet_shift;
        input integer index;
        begin
            if(index[0]) clarinet_shift=14;
            else if(index==0) clarinet_shift=1;
            else if(index==2) clarinet_shift=2;
            else if(index==4) clarinet_shift=4;
            else if(index==6) clarinet_shift=5;
            else if(index<=14) clarinet_shift=6;
            else clarinet_shift=10;
        end
    endfunction
    // Grand piano: strong fundamental, moderate lower partials, airy upper tail.
    function [4:0] keyboard_shift;
        input integer index;
        begin
            if(index==0) keyboard_shift=2;
            else if(index==1) keyboard_shift=3;
            else if(index==2) keyboard_shift=4;
            else if(index<=4) keyboard_shift=5;
            else if(index<=6) keyboard_shift=6;
            else if(index==7) keyboard_shift=7;
            else if(index<=11) keyboard_shift=8;
            else if(index<=15) keyboard_shift=10;
            else if(index<=23) keyboard_shift=12;
            else if(index==31) keyboard_shift=6; // weak unison/body string
            else keyboard_shift=14;
        end
    endfunction
    // Organ: 8'/4'/2'/1' octave ranks dominate; non-octave partials stay soft.
    function [4:0] organ_shift;
        input integer index;
        begin
            case(index)
                0: organ_shift=1;
                1: organ_shift=2;
                3: organ_shift=3;
                7: organ_shift=4;
                15: organ_shift=6;
                5,11: organ_shift=8;
                2,4: organ_shift=9;
                default: organ_shift=14;
            endcase
        end
    endfunction
    // Airier music box: softer fundamental, sparse upper sparkle, less dense body.
    // The slightly detuned fourth partial and octave-up pitch are retained.
    // Static shifts add no multipliers or render cycles; other profiles are unchanged.
    function [4:0] pluck_shift;
        input integer index;
        begin
            case(index)
                0: pluck_shift=2;
                1: pluck_shift=5;
                2: pluck_shift=7;
                3: pluck_shift=4;
                4: pluck_shift=9;
                5: pluck_shift=10;
                6: pluck_shift=11;
                7: pluck_shift=7;
                15: pluck_shift=10;
                default: pluck_shift=18;
            endcase
        end
    endfunction
    function integer bits_for;
        input integer value;
        integer v;
        begin
            bits_for=0;
            v=value;
            while(v>0) begin bits_for=bits_for+1; v=v>>1; end
            if(bits_for==0) bits_for=1;
        end
    endfunction
    function integer max_harmonic;
        input integer unused;
        integer n;
        begin
            max_harmonic=1;
            for(n=0;n<OSCILLATORS;n=n+1)
                if(harmonic(n)>max_harmonic) max_harmonic=harmonic(n);
        end
    endfunction
    function integer sum_bound;
        input integer unused;
        integer n, shift_bound, term_bound;
        begin
            sum_bound=0;
            for(n=0;n<OSCILLATORS;n=n+1) begin
                shift_bound=TIMBRE_ENABLE ? keyboard_shift(n) : gain_shift(n);
                if(TIMBRE_ENABLE && clarinet_shift(n)<shift_bound) shift_bound=clarinet_shift(n);
                if(TIMBRE_ENABLE && organ_shift(n)<shift_bound) shift_bound=organ_shift(n);
                if(TIMBRE_ENABLE && pluck_shift(n)<shift_bound) shift_bound=pluck_shift(n);
                term_bound=(529285+(1<<shift_bound)-1)>>shift_bound;
                sum_bound=sum_bound+term_bound+
                    (TIMBRE_ENABLE ? ((term_bound+3)>>2) : 0)+
                    ((TIMBRE_ENABLE && n==31) ? ((term_bound+7)>>3) : 0);
            end
        end
    endfunction
    localparam integer ACC_WIDTH=1+bits_for(sum_bound(0)+(TIMBRE_ENABLE?32768:0));
    localparam integer PRODUCT_WIDTH=ACC_WIDTH+17;
    function integer max_piano_harmonic;
        input integer unused;
        integer n;
        begin
            max_piano_harmonic=1;
            for(n=0;n<OSCILLATORS-1;n=n+1)
                if(harmonic(n)>max_piano_harmonic)max_piano_harmonic=harmonic(n);
        end
    endfunction
    localparam integer PIANO_FACTOR_BITS=bits_for(max_piano_harmonic(0));
    localparam integer FACTOR_BITS=bits_for(max_harmonic(0));
    localparam integer COUNT_BITS=bits_for(FACTOR_BITS-1);
    // 默认32*(6+7)+1=417clk；最大倍频位数B时延迟32*(B+7)+1clk。
    localparam integer RENDER_CYCLES=OSCILLATORS*(FACTOR_BITS+7)+1+(VIBRATO_ENABLE ? 14 : 0);
    localparam [3:0] IDLE=0, READ_LOW=1, READ_HIGH=2, LOAD=3,
        SCALE=4, APPLY_PHASE=5, STORE_LOW=6, STORE_HIGH=7, SUM=8, OUTPUT_SAMPLE=9, MOD_SCALE=10,
        DETUNE_FOURTH=11,PIANO_STRETCH=12,PIANO_STRETCH_SECOND=13;
    // Per-frame combined ultrasonic bend and vibrato, using Q16 scale.
    // Combined multiplier/product register: same 14 cycles, only a 33-bit adder.
    // The stable frame_step is reused instead of shifting a second 46-bit operand.
    reg [45:0] mod_product;
    reg [3:0] mod_count;
    reg mod_negative;
    reg [31:0] frame_step, operand, phase_work, phase_base;
    wire [15:0] mod_magnitude=vibrato_q16[15] ? -vibrato_q16 : vibrato_q16;
    wire [32:0] mod_sum={1'b0,mod_product[45:14]}+
        (mod_product[0] ? {1'b0,frame_step} : 33'd0);
    wire [45:0] mod_next={mod_sum,mod_product[13:1]};
    wire [31:0] mod_delta=mod_next[45:16];
    reg [3:0] render_stage;
    reg [4:0] oscillator_index;
    reg [COUNT_BITS-1:0] bit_index;
    reg [FACTOR_BITS-1:0] factor;
    wire [31:0] selected_step=(TIMBRE_ENABLE!=0 && timbre_select==2'd3) ?
        (phase_step<<1) : phase_step;
    reg operand_overflow;
    // Q32 phase advance at Fs=50MHz/512: 2kHz and 3kHz boundaries.
    localparam [31:0] BAND_LOW=32'd87960930, BAND_HIGH=32'd131941395;
    localparam [31:0] HIGH_CUT_LOW=32'd263882791, HIGH_CUT_HIGH=32'd351843721;
    localparam [31:0] LOW_BAND_150=32'd6597070;
    localparam [31:0] LOW_HARMONIC_160=32'd7036874,
        LOW_HARMONIC_500=32'd21990233;
    reg band_boost;
    reg high_cut, fundamental_body;
    reg low_body;
    reg low_harmonic_cut;
    reg [2:0] low_tail_stage;
    reg [13:0] low_release_samples;
    reg high_clarinet_octave;
    reg [3:0] frame_octave;
    reg phase_reset_pending, frame_reset, frame_zero;
    reg [16:0] piano_age;
    always @(posedge clk) begin
        if(rst) piano_age<=0;
        else if(sample_tick) begin
            if(phase_reset_pending || trigger) piano_age<=0;
            else if(active && !(&piano_age)) piano_age<=piano_age+1'b1;
        end
    end
    assign shared_piano_age=piano_age[16:8];
    assign shared_piano_octave=frame_octave;
    reg [15:0] render_envelope;
    reg [7:0] rom_address;
    reg signed [ACC_WIDTH-1:0] accumulator;
    // Per-voice pseudo-random breath, high-passed by differencing adjacent bytes.
    // Add before the existing envelope multiplier so attack/release shape it too.
    localparam [15:0] NOISE_SEED=16'hace1 ^ (VOICE_INDEX*16'h0f35);
    reg [15:0] noise_lfsr;
    reg [7:0] previous_noise_byte;
    wire signed [9:0] breath_difference=
        $signed({2'b00,noise_lfsr[15:8]})-$signed({2'b00,previous_noise_byte});
    wire signed [ACC_WIDTH-1:0] breath_noise=$signed(breath_difference) <<< 3;
    // Four-ms hammer pulse, using the existing per-voice high-passed noise.
    // Windowed in amplitude; upper register is 6dB softer. No PCM recording.
    wire signed [23:0] hammer_source=$signed(breath_difference);
    wire signed [23:0] hammer_raw=(piano_age<17'd32)?(hammer_source<<<7):
        (piano_age<17'd98)?(hammer_source<<<6):
        (piano_age<17'd196)?(hammer_source<<<4):
        (piano_age<17'd293)?(hammer_source<<<3):
        (piano_age<17'd391)?(hammer_source<<<2):24'sd0;
    wire signed [23:0] hammer_pulse=(frame_octave>=5)?(hammer_raw>>>1):hammer_raw;
    wire signed [ACC_WIDTH-1:0] hammer_noise=hammer_pulse;
    reg [15:0] phase[0:63] /* synthesis syn_ramstyle="block_ram" */;
    reg [15:0] phase_read;
    reg oscillator_audible;
    reg [1:0] frame_timbre; // Latch once per sample: never mix profiles within one frame.
    wire low_harmonic_selected=(TIMBRE_ENABLE!=0 && frame_timbre==2'd1 &&
        frame_octave==4'd3 && oscillator_index!=0 && !operand_overflow &&
        phase_work>=LOW_HARMONIC_160 && phase_work<LOW_HARMONIC_500);
    // SCALE先用同一个加法器计算频率增量并检测溢出；APPLY_PHASE再加旧相位。
    // 频率结果低32位保留用于相位回绕，>=2^31或更高位丢失时关闭该路音频。
    wire [4:0] piano_stretch_shift=(oscillator_index<3)?5'd9:
        (oscillator_index<15)?5'd8:5'd7;
    wire piano_extra_stretch=(oscillator_index>0 && oscillator_index<3) ||
        (oscillator_index>=7 && oscillator_index<15) ||
        (oscillator_index>=23 && oscillator_index<31);
    wire [4:0] piano_extra_shift=(oscillator_index>=23)?5'd11:5'd10;
    wire [31:0] phase_addend=(render_stage==APPLY_PHASE) ? phase_base :
        (render_stage==PIANO_STRETCH) ? (phase_work>>piano_stretch_shift) : operand;
    wire [32:0] phase_sum={1'b0,phase_work}+{1'b0,phase_addend};
    wire [31:0] phase_result=frame_zero ? 32'd0 : phase_work;
    // 统一的16位地址/数据端口，连续两拍读写一个32位相位；RAM本体不复位。
    wire phase_high=(render_stage==READ_HIGH || render_stage==STORE_HIGH);
    wire [5:0] phase_address={oscillator_index,phase_high};
    always @(posedge clk) begin
        if(!rst && !sample_tick) begin
            if(render_stage==READ_LOW || render_stage==READ_HIGH)
                phase_read <= phase[phase_address];
            if(render_stage==STORE_LOW || render_stage==STORE_HIGH)
                phase[phase_address] <= phase_high ? phase_result[31:16] : phase_result[15:0];
        end
    end
    wire signed [23:0] wave;
    wire [4:0] current_shift=TIMBRE_ENABLE && frame_timbre==2'd1 ?
        clarinet_shift(oscillator_index) :
        TIMBRE_ENABLE && frame_timbre==2'd2 ?
        organ_shift(oscillator_index) :
        TIMBRE_ENABLE && frame_timbre==2'd3 ?
        pluck_shift(oscillator_index) :
        TIMBRE_ENABLE ? keyboard_shift(oscillator_index) : gain_shift(oscillator_index);
    wire signed [23:0] base_wave=$signed(wave) >>> current_shift;
    wire signed [23:0] shifted_wave=base_wave +
        (band_boost ? (base_wave >>> 2) : 24'sd0);
    assign shared_gain_shift=current_shift;
    assign shared_band_boost=band_boost;
    assign shared_high_cut=high_cut;
    assign shared_fundamental_body=fundamental_body;
    assign shared_low_body=low_body;
    assign shared_low_harmonic_cut=low_harmonic_cut;
    assign shared_low_tail_stage=low_tail_stage;
    assign shared_wave_oscillator=oscillator_index;
    wire [15:0] local_piano_gain;
    wire signed [40:0] local_piano_product=shifted_wave*$signed({1'b0,local_piano_gain});
    generate if(SHARED_GAIN==0) begin: local_piano_spectrum
        piano_spectrum_rom u_spectrum(.clk(clk),.age(piano_age[16:8]),
            .octave(frame_octave),.oscillator_index(oscillator_index),.gain(local_piano_gain));
    end else begin: no_local_piano_spectrum
        assign local_piano_gain=16'd32768;
    end endgenerate
    wire signed [23:0] attenuated=(SHARED_ROM!=0 && SHARED_GAIN!=0) ? wave :
        (TIMBRE_ENABLE!=0 && frame_timbre==0) ? local_piano_product[38:15] : shifted_wave;
    // 有符号赋值同时支持窄化和扩位；32路全增益需要26位累加器。
    wire signed [ACC_WIDTH-1:0] weighted_wave;
    generate if(ACC_WIDTH<24) begin: narrow_weight
        assign weighted_wave=attenuated[ACC_WIDTH-1:0];
    end else begin: extend_weight
        assign weighted_wave={{(ACC_WIDTH-24){attenuated[23]}},attenuated};
    end endgenerate
    wire signed [PRODUCT_WIDTH-1:0] product=accumulator*$signed({1'b0,render_envelope});
    wire signed [PRODUCT_WIDTH-1:0] scaled=$signed(product) >>> 16;
    wire signed [23:0] limited=(scaled>8388607) ? 24'sh7fffff :
        (scaled < -8388608) ? 24'sh800000 : scaled[23:0];
    // Request at STORE_LOW so the extra shared-gain pipeline stage finishes
    // before SUM. The phase address is already stable after APPLY_PHASE.
    assign shared_wave_request=(SHARED_ROM!=0) &&
        (render_stage==STORE_LOW || render_stage==STORE_HIGH || render_stage==SUM);
    assign shared_wave_address=(render_stage==STORE_LOW || render_stage==STORE_HIGH) ?
        phase_result[31:24] : rom_address;
    generate if(SHARED_ROM!=0) begin: external_rom
        assign wave=shared_wave;
    end else begin: local_rom
        sine_rom_256 u_rom (.address(rom_address), .sample(wave));
    end endgenerate
    wire [15:0] normal_envelope_level, organ_envelope_level, pluck_envelope_level;
    wire [2:0] normal_envelope_state, organ_envelope_state, pluck_envelope_state;
    wire normal_active, organ_active, pluck_active;
    wire [15:0] piano_envelope_level;
    wire [2:0] piano_envelope_state;
    wire piano_active;
    generate if(SHARED_ENVELOPES!=0) begin: bank_envelopes
        assign piano_envelope_level=shared_piano_level;
        assign piano_envelope_state=shared_piano_state;
        assign piano_active=shared_piano_active;
        assign normal_envelope_level=shared_normal_level;
        assign organ_envelope_level=shared_organ_level;
        assign pluck_envelope_level=shared_pluck_level;
        assign normal_envelope_state=shared_normal_state;
        assign organ_envelope_state=shared_organ_state;
        assign pluck_envelope_state=shared_pluck_state;
        assign normal_active=shared_normal_active;
        assign organ_active=shared_organ_active;
        assign pluck_active=shared_pluck_active;
    end else begin: local_envelopes
    if(TIMBRE_ENABLE!=0) begin: piano_envelope
        piano_context #(.ATTACK_LOW(ATTACK_SAMPLES<391?ATTACK_SAMPLES:391),
            .ATTACK_MID(ATTACK_SAMPLES<391?ATTACK_SAMPLES:391),
            .ATTACK_HIGH(ATTACK_SAMPLES<391?ATTACK_SAMPLES:391)) u_piano(
            .clk(clk),.rst(rst),.sample_tick(sample_tick),.trigger(trigger),.gate(gate),
            .octave(octave),.context_load(1'b0),.context_in(46'd0),.context_out(),
            .level(piano_envelope_level),.state(piano_envelope_state),.active(piano_active));
    end else begin
        assign piano_envelope_level=0;assign piano_envelope_state=0;assign piano_active=0;
    end
    adsr_envelope #(.ATTACK_SAMPLES(ATTACK_SAMPLES),
        .KEYBOARD_ATTACK_SAMPLES((ATTACK_SAMPLES<49) ? ATTACK_SAMPLES : 49),
        .LOW_KEYBOARD_ATTACK_SAMPLES((ATTACK_SAMPLES<98) ? ATTACK_SAMPLES : 98),
        .DECAY_SAMPLES(DECAY_SAMPLES),
        .SUSTAIN_LEVEL(SUSTAIN_LEVEL),.RELEASE_SAMPLES(RELEASE_SAMPLES),
        .KEYBOARD_RELEASE_SAMPLES((RELEASE_SAMPLES<11719) ? RELEASE_SAMPLES : 17578),
        .LOW_KEYBOARD_RELEASE_SAMPLES((RELEASE_SAMPLES<11719) ? RELEASE_SAMPLES : 13183),
        .CLARINET_RELEASE_SAMPLES((RELEASE_SAMPLES<11719) ? RELEASE_SAMPLES : 24414)) u_env (
        .clk(clk),.rst(rst),.sample_tick(sample_tick),.trigger(trigger),.gate(gate),
        .keyboard_mode((TIMBRE_ENABLE!=0) && timbre_select==2'd0),
        .clarinet_mode((TIMBRE_ENABLE!=0) && timbre_select==2'd1),
        .high_clarinet_mode((TIMBRE_ENABLE!=0) && timbre_select==2'd1 && octave==4'd5),
        .low_keyboard_mode((TIMBRE_ENABLE!=0) && timbre_select==2'd0 && octave==4'd3),
        .level(normal_envelope_level),.active(normal_active),.state(normal_envelope_state));
    if(TIMBRE_ENABLE!=0) begin: pluck_envelope
        plucked_envelope u_pluck(.clk(clk),.rst(rst),.sample_tick(sample_tick),
            .trigger(trigger),.gate(gate),.level(pluck_envelope_level),
            .active(pluck_active),.state(pluck_envelope_state));
    end else begin: no_pluck_envelope
        assign pluck_envelope_level=0;
        assign pluck_envelope_state=0;
        assign pluck_active=0;
    end 
    if(TIMBRE_ENABLE!=0) begin: organ_envelope
        // At 97.656 kHz, 68/sample reaches full scale in 964 samples (~9.87 ms);
        // 2/sample releases from full scale in 32768 samples (~335.54 ms).
        // A short onset stays responsive; the longer tail adds a gentle sustain.
        // No extra sample buffer or audio effect is introduced.
        reg [15:0] level;
        reg [2:0] state;
        assign organ_envelope_level=level;
        assign organ_envelope_state=state;
        assign organ_active=(state!=0);
        always @(posedge clk) begin
            if(rst) begin
                level<=0;
                state<=0;
            end else if(trigger) begin
                level<=0;
                state<=1;
            end else if(sample_tick) begin
                if(gate) begin
                    if(level>=16'd65467) begin
                        level<=16'hffff;
                        state<=3;
                    end else begin
                        level<=level+16'd68;
                        state<=1;
                    end
                end else if(level>16'd2) begin
                    level<=level-16'd2;
                    state<=4;
                end else begin
                    level<=0;
                    state<=0;
                end
            end
        end
    end else begin: no_organ_envelope
        assign organ_envelope_level=0;
        assign organ_envelope_state=0;
        assign organ_active=0;
    end 
    end endgenerate
    assign envelope_level=(TIMBRE_ENABLE!=0 && frame_timbre==0) ? piano_envelope_level :
        frame_timbre==2'd3 ? pluck_envelope_level :
        frame_timbre==2'd2 ? organ_envelope_level : normal_envelope_level;
    assign envelope_state=(TIMBRE_ENABLE!=0 && frame_timbre==0) ? piano_envelope_state :
        frame_timbre==2'd3 ? pluck_envelope_state :
        frame_timbre==2'd2 ? organ_envelope_state : normal_envelope_state;
    assign active=(TIMBRE_ENABLE!=0 && frame_timbre==0) ? piano_active :
        (TIMBRE_ENABLE!=0 && frame_timbre==2'd3) ? pluck_active :
        (TIMBRE_ENABLE!=0 && frame_timbre==2'd2) ? organ_active : normal_active;

    always @(posedge clk) begin
        if(rst) begin
            mod_product<=0; mod_count<=0; mod_negative<=0;
            render_stage<=IDLE;
            oscillator_index<=0; bit_index<=0; factor<=0;
            frame_step<=0; operand<=0; phase_work<=0; phase_base<=0; operand_overflow<=0;
            phase_reset_pending<=1; frame_reset<=1; frame_zero<=1;
            frame_timbre<=0;
            noise_lfsr<=NOISE_SEED; previous_noise_byte<=0;
            render_envelope<=0; rom_address<=0; accumulator<=0; oscillator_audible<=0;
            band_boost<=0; high_cut<=0; fundamental_body<=0;
            low_body<=0; low_harmonic_cut<=0;
            low_tail_stage<=0; low_release_samples<=0;
            high_clarinet_octave<=0; frame_octave<=0;
            sample<=0; sample_valid<=0;
        end else begin
            sample_valid<=0;
            // Shared frame levels are complete well before the final multiplier.
            // NCO phase work proceeds concurrently with context updates.
            if(SHARED_ENVELOPES!=0 && shared_envelopes_ready && render_stage!=IDLE)
                render_envelope<=envelope_level;
            if(trigger) phase_reset_pending<=1;
            if(sample_tick) begin
                if(TIMBRE_ENABLE!=0 && timbre_select==2'd1 &&
                    octave==4'd3 && normal_envelope_state==3'd4) begin
                    if(low_release_samples<14'd16276)
                        low_release_samples<=low_release_samples+1'b1;
                end else low_release_samples<=0;
                noise_lfsr<={noise_lfsr[14:0],
                    noise_lfsr[15]^noise_lfsr[13]^noise_lfsr[12]^noise_lfsr[10]};
                previous_noise_byte<=noise_lfsr[15:8];
                frame_timbre<=(TIMBRE_ENABLE!=0) ? timbre_select : 2'd0;
                high_clarinet_octave<=(TIMBRE_ENABLE!=0) && timbre_select==2'd1 && octave==4'd5;
                frame_octave<=octave;
                frame_step<=selected_step;
                frame_reset<=phase_reset_pending || trigger;
                frame_zero<=trigger;
                phase_reset_pending<=0;
                oscillator_index<=0;
                accumulator<=0;
                mod_product<={32'd0,mod_magnitude[13:0]};
                mod_negative<=vibrato_q16[15]; mod_count<=0;
                render_stage<=VIBRATO_ENABLE ? MOD_SCALE : READ_LOW;
            end else begin
                case(render_stage)
                    MOD_SCALE: begin
                        if(mod_count==0 && SHARED_ENVELOPES==0) render_envelope<=envelope_level;
                        mod_product<=mod_next;
                        if(mod_count==13) begin
                            frame_step<=mod_negative ? frame_step-mod_delta : frame_step+mod_delta;
                            render_stage<=READ_LOW;
                        end else mod_count<=mod_count+1'b1;
                    end
                    READ_LOW: begin
                        // 首路锁存sample_tick之后的ADSR，整帧使用同一包络快照。
                        if(oscillator_index==0 && !VIBRATO_ENABLE && SHARED_ENVELOPES==0) render_envelope<=envelope_level;
                        render_stage<=READ_HIGH;
                    end
                    READ_HIGH: begin
                        phase_base[15:0]<=frame_reset ? 16'd0 : phase_read;
                        render_stage<=LOAD;
                    end
                    LOAD: begin
                        phase_base[31:16]<=frame_reset ? 16'd0 : phase_read;
                        operand<=frame_step;
                        factor<=(TIMBRE_ENABLE!=0 && frame_timbre==0 && oscillator_index==31) ? 1 : harmonic(oscillator_index);
                        phase_work<=0; operand_overflow<=0; oscillator_audible<=1;
                        bit_index<=0;
                        render_stage<=SCALE;
                    end
                    SCALE: begin
                        // 移位加法逐bit计算phase+step*harmonic，全部32路复用此33位加法器。
                        if(factor[0]) begin
                            phase_work<=phase_sum[31:0];
                            if(operand_overflow || |phase_sum[32:31]) oscillator_audible<=0;
                        end
                        operand_overflow<=operand_overflow || operand[31];
                        operand<=operand<<1;
                        factor<=factor>>1;
                        if(bit_index==((TIMBRE_ENABLE!=0 && frame_timbre==0)?PIANO_FACTOR_BITS-1:FACTOR_BITS-1))
                            render_stage<=(TIMBRE_ENABLE!=0 && frame_timbre==0 && oscillator_index==31) ?
                                DETUNE_FOURTH :
                                (TIMBRE_ENABLE!=0 && frame_timbre==0 && oscillator_index!=0) ?
                                PIANO_STRETCH :
                                (TIMBRE_ENABLE!=0 && frame_timbre==2'd3 && oscillator_index==5'd3) ?
                                DETUNE_FOURTH : APPLY_PHASE;
                        else bit_index<=bit_index+1'b1;
                    end
                    // Music-box fourth mode; piano slot32 is a weak unison at f0*(255/256).
                    // Reuse the phase accumulator; one extra cycle only for this partial.
                    DETUNE_FOURTH: begin
                        phase_work<=phase_work-((frame_timbre==0) ? (frame_step>>8) : (frame_step>>6));
                        render_stage<=APPLY_PHASE;
                    end
                    PIANO_STRETCH: begin
                        // Reuse the same phase adder for a second small offset.
                        operand<=phase_work>>piano_extra_shift;
                        phase_work<=phase_sum[31:0];
                        if(|phase_sum[32:31]) oscillator_audible<=0;
                        render_stage<=piano_extra_stretch?PIANO_STRETCH_SECOND:APPLY_PHASE;
                    end
                    PIANO_STRETCH_SECOND: begin
                        phase_work<=phase_sum[31:0];
                        if(|phase_sum[32:31]) oscillator_audible<=0;
                        render_stage<=APPLY_PHASE;
                    end
                    APPLY_PHASE: begin
                        // SCALE has already computed this partial's frequency as phase_work.
                        // Latch before adding the old phase; vibrato/glide are included.
                        band_boost<=(TIMBRE_ENABLE!=0 && frame_timbre==2'd1 &&
                            !operand_overflow && phase_work>=BAND_LOW && phase_work<BAND_HIGH);
                        // Piano uses a register/age-dependent spectrum instead of
                        // the old bass fundamental boost and 10-kHz-only trim.
                        high_cut<=!operand_overflow && high_clarinet_octave &&
                            phase_work>=HIGH_CUT_LOW && phase_work<HIGH_CUT_HIGH;
                        fundamental_body<=high_clarinet_octave && oscillator_index==0;
                        // Lift the five lowest C3..E3 fundamentals without retuning.
                        low_body<=(TIMBRE_ENABLE!=0 && frame_timbre==2'd1 &&
                            frame_octave==4'd3 && VOICE_INDEX<5 && oscillator_index==0);
                        // Keep the fundamental; trim only 160..500 Hz upper partials.
                        low_harmonic_cut<=low_harmonic_selected;
                        // Only C3..D3 fundamentals fall below 150 Hz here.
                        if((TIMBRE_ENABLE!=0 && frame_timbre==2'd1 &&
                            frame_octave==4'd3 && !operand_overflow &&
                            phase_work<LOW_BAND_150 && normal_envelope_state==3'd4)) begin
                            if(low_release_samples>=14'd16276) low_tail_stage<=3'd4;
                            else if(low_release_samples>=14'd14920) low_tail_stage<=3'd3;
                            else if(low_release_samples>=14'd13563) low_tail_stage<=3'd2;
                            else if(low_release_samples>=14'd12207) low_tail_stage<=3'd1;
                            else low_tail_stage<=3'd0;
                        end else if(low_harmonic_selected && normal_envelope_state==3'd4) begin
                            // 160..500 Hz partials fade from 100 to 150 ms, 100 ms
                            // earlier than the clarinet's original 250 ms release.
                            if(low_release_samples>=14'd14648) low_tail_stage<=3'd4;
                            else if(low_release_samples>=14'd13021) low_tail_stage<=3'd3;
                            else if(low_release_samples>=14'd11393) low_tail_stage<=3'd2;
                            else if(low_release_samples>=14'd9766) low_tail_stage<=3'd1;
                            else low_tail_stage<=3'd0;
                        end else low_tail_stage<=3'd0;
                        phase_work<=phase_sum[31:0];
                        render_stage<=STORE_LOW;
                    end
                    STORE_LOW: render_stage<=STORE_HIGH;
                    STORE_HIGH: begin
                        rom_address<=phase_result[31:24];
                        render_stage<=SUM;
                    end
                    SUM: if(SHARED_ROM==0 || shared_wave_grant) begin
                        accumulator<=accumulator+(oscillator_audible ? weighted_wave : {ACC_WIDTH{1'b0}})
                            + ((TIMBRE_ENABLE!=0 && oscillator_index==OSCILLATORS-1) ?
                                ((frame_timbre==2'd1)?breath_noise:
                                 (frame_timbre==0)?hammer_noise:{ACC_WIDTH{1'b0}}) : {ACC_WIDTH{1'b0}});
                        if(oscillator_index==OSCILLATORS-1) render_stage<=OUTPUT_SAMPLE;
                        else begin oscillator_index<=oscillator_index+1'b1; render_stage<=READ_LOW; end
                    end
                    OUTPUT_SAMPLE: begin
                        sample<=limited;
                        sample_valid<=1;
                        render_stage<=IDLE;
                    end
                    default: render_stage<=IDLE;
                endcase
            end
        end
    end
    // synthesis translate_off
    always @(posedge clk) if(!rst && sample_tick && render_stage!=IDLE)
        $fatal(1,"sample_tick overlaps a pending oscillator frame");
    always @(posedge clk) if(!rst && SHARED_ENVELOPES!=0 &&
        render_stage==OUTPUT_SAMPLE && !shared_envelopes_ready)
        $fatal(1,"envelope bank missed NCO output deadline");
    integer check_index;
    initial begin
        if(GAIN_SHIFT_1<0 || GAIN_SHIFT_1>23) $fatal(1,"GAIN_SHIFT_1 must be 0..23");
        if(GAIN_SHIFT_2<0 || GAIN_SHIFT_2>23) $fatal(1,"GAIN_SHIFT_2 must be 0..23");
        if(GAIN_SHIFT_3<0 || GAIN_SHIFT_3>23) $fatal(1,"GAIN_SHIFT_3 must be 0..23");
        if(GAIN_SHIFT_4<0 || GAIN_SHIFT_4>23) $fatal(1,"GAIN_SHIFT_4 must be 0..23");
        if(GAIN_SHIFT_5<0 || GAIN_SHIFT_5>23) $fatal(1,"GAIN_SHIFT_5 must be 0..23");
        if(GAIN_SHIFT_6<0 || GAIN_SHIFT_6>23) $fatal(1,"GAIN_SHIFT_6 must be 0..23");
        if(GAIN_SHIFT_7<0 || GAIN_SHIFT_7>23) $fatal(1,"GAIN_SHIFT_7 must be 0..23");
        if(GAIN_SHIFT_8<0 || GAIN_SHIFT_8>23) $fatal(1,"GAIN_SHIFT_8 must be 0..23");
        if(GAIN_SHIFT_9<0 || GAIN_SHIFT_9>23) $fatal(1,"GAIN_SHIFT_9 must be 0..23");
        if(GAIN_SHIFT_10<0 || GAIN_SHIFT_10>23) $fatal(1,"GAIN_SHIFT_10 must be 0..23");
        if(GAIN_SHIFT_11<0 || GAIN_SHIFT_11>23) $fatal(1,"GAIN_SHIFT_11 must be 0..23");
        if(GAIN_SHIFT_12<0 || GAIN_SHIFT_12>23) $fatal(1,"GAIN_SHIFT_12 must be 0..23");
        if(GAIN_SHIFT_13<0 || GAIN_SHIFT_13>23) $fatal(1,"GAIN_SHIFT_13 must be 0..23");
        if(GAIN_SHIFT_14<0 || GAIN_SHIFT_14>23) $fatal(1,"GAIN_SHIFT_14 must be 0..23");
        if(GAIN_SHIFT_15<0 || GAIN_SHIFT_15>23) $fatal(1,"GAIN_SHIFT_15 must be 0..23");
        if(GAIN_SHIFT_16<0 || GAIN_SHIFT_16>23) $fatal(1,"GAIN_SHIFT_16 must be 0..23");
        if(GAIN_SHIFT_17<0 || GAIN_SHIFT_17>23) $fatal(1,"GAIN_SHIFT_17 must be 0..23");
        if(GAIN_SHIFT_18<0 || GAIN_SHIFT_18>23) $fatal(1,"GAIN_SHIFT_18 must be 0..23");
        if(GAIN_SHIFT_19<0 || GAIN_SHIFT_19>23) $fatal(1,"GAIN_SHIFT_19 must be 0..23");
        if(GAIN_SHIFT_20<0 || GAIN_SHIFT_20>23) $fatal(1,"GAIN_SHIFT_20 must be 0..23");
        if(GAIN_SHIFT_21<0 || GAIN_SHIFT_21>23) $fatal(1,"GAIN_SHIFT_21 must be 0..23");
        if(GAIN_SHIFT_22<0 || GAIN_SHIFT_22>23) $fatal(1,"GAIN_SHIFT_22 must be 0..23");
        if(GAIN_SHIFT_23<0 || GAIN_SHIFT_23>23) $fatal(1,"GAIN_SHIFT_23 must be 0..23");
        if(GAIN_SHIFT_24<0 || GAIN_SHIFT_24>23) $fatal(1,"GAIN_SHIFT_24 must be 0..23");
        if(GAIN_SHIFT_25<0 || GAIN_SHIFT_25>23) $fatal(1,"GAIN_SHIFT_25 must be 0..23");
        if(GAIN_SHIFT_26<0 || GAIN_SHIFT_26>23) $fatal(1,"GAIN_SHIFT_26 must be 0..23");
        if(GAIN_SHIFT_27<0 || GAIN_SHIFT_27>23) $fatal(1,"GAIN_SHIFT_27 must be 0..23");
        if(GAIN_SHIFT_28<0 || GAIN_SHIFT_28>23) $fatal(1,"GAIN_SHIFT_28 must be 0..23");
        if(GAIN_SHIFT_29<0 || GAIN_SHIFT_29>23) $fatal(1,"GAIN_SHIFT_29 must be 0..23");
        if(GAIN_SHIFT_30<0 || GAIN_SHIFT_30>23) $fatal(1,"GAIN_SHIFT_30 must be 0..23");
        if(GAIN_SHIFT_31<0 || GAIN_SHIFT_31>23) $fatal(1,"GAIN_SHIFT_31 must be 0..23");
        if(GAIN_SHIFT_32<0 || GAIN_SHIFT_32>23) $fatal(1,"GAIN_SHIFT_32 must be 0..23");
        for(check_index=0;check_index<OSCILLATORS;check_index=check_index+1) begin
            if(harmonic(check_index)<1) $fatal(1,"HARMONIC must be positive");

        end
    end
    // synthesis translate_on
endmodule
