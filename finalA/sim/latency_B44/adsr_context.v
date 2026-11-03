// 【每个声部自己的音量曲线】ADSR决定声音怎样起音、保持以及松键后消失。
// IDLE静音 -> ATTACK由0升至65535 -> DECAY降至持续值 -> SUSTAIN保持。
// gate变0后，从当前音量进入RELEASE，逐渐降到0，再回到IDLE。
// trigger是新按键的一拍脉冲，优先级高于采样更新，会立即重新从ATTACK起音。
// level是16位无符号幅度，声音实际乘以level/65536；45875约等于70%。
// ATTACK/DECAY/RELEASE参数是“采样次数”，不是50MHz系统时钟次数。
// Fs=97656.25Hz，每次采样10.24us；489/7813/11719次约为5/80/120ms。
// 段长度必须大于0，SUSTAIN_LEVEL取0..65535。
`timescale 1ns/1ps
// Linear ADSR for default timbres; keyboard and clarinet have curved releases.
// Fs=97656.25Hz: ceil(5ms)=489, ceil(80ms)=7813, ceil(120ms)=11719.
// Gate release works during any segment and starts from the current level.
module latb_adsr_context #(
    parameter integer ATTACK_SAMPLES=489,
    parameter integer KEYBOARD_ATTACK_SAMPLES=293,
    parameter integer LOW_KEYBOARD_ATTACK_SAMPLES=391,
    parameter integer HIGH_CLARINET_ATTACK_SAMPLES=684,
    parameter integer DECAY_SAMPLES=7813,
    parameter integer SUSTAIN_LEVEL=45875,
    parameter integer PIANO_SUSTAIN_LEVEL=16384,
    parameter integer RELEASE_SAMPLES=11719,
    parameter integer KEYBOARD_RELEASE_SHIFT=12,
    parameter integer KEYBOARD_RELEASE_SAMPLES=29300,
    parameter integer LOW_KEYBOARD_RELEASE_SAMPLES=14648,
    parameter integer CLARINET_RELEASE_SAMPLES=24414
) (
    input wire clk, rst, sample_tick, trigger, gate, keyboard_mode, clarinet_mode,
    input wire context_load,
    input wire [191:0] context_in,
    output wire [191:0] context_out,
    input wire high_clarinet_mode,
    input wire low_keyboard_mode,
    output reg [15:0] level,
    output wire active,
    output reg [2:0] state
);
    localparam [2:0] IDLE=0, ATTACK=1, DECAY=2, SUSTAIN=3, RELEASE=4;
    // “商+余数”分配整数步长，避免四舍五入后包络过早到顶。
    // Attack示例：65535/489=134余9；每次至少加134，并按余数累计偶尔多加1。
    localparam integer A_BASE=65535/ATTACK_SAMPLES, A_REM=65535%ATTACK_SAMPLES;
    localparam integer KA_BASE=65535/KEYBOARD_ATTACK_SAMPLES;
    localparam integer KA_REM=65535%KEYBOARD_ATTACK_SAMPLES;
    localparam integer LKA_BASE=65535/LOW_KEYBOARD_ATTACK_SAMPLES;
    localparam integer LKA_REM=65535%LOW_KEYBOARD_ATTACK_SAMPLES;
    localparam integer HCA_BASE=65535/HIGH_CLARINET_ATTACK_SAMPLES;
    localparam integer HCA_REM=65535%HIGH_CLARINET_ATTACK_SAMPLES;
    localparam integer D_BASE=(65535-SUSTAIN_LEVEL)/DECAY_SAMPLES;
    localparam integer D_REM=(65535-SUSTAIN_LEVEL)%DECAY_SAMPLES;
    localparam integer PD_BASE=(65535-PIANO_SUSTAIN_LEVEL)/DECAY_SAMPLES;
    localparam integer PD_REM=(65535-PIANO_SUSTAIN_LEVEL)%DECAY_SAMPLES;
    // count统计当前段已经推进的采样次数；error_acc累积不足1个幅值单位的余数。
    function integer bits_for;
        input integer value;
        integer v;
        begin
            v = value;
            bits_for = 0;
            while(v > 0) begin bits_for = bits_for + 1; v = v >> 1; end
            if(bits_for == 0) bits_for = 1;
        end
    endfunction
    localparam integer NORMAL_ATTACK_MAX=(ATTACK_SAMPLES>KEYBOARD_ATTACK_SAMPLES) ?
        ATTACK_SAMPLES : KEYBOARD_ATTACK_SAMPLES;
    localparam integer ATTACK_MAX=(NORMAL_ATTACK_MAX>HIGH_CLARINET_ATTACK_SAMPLES) ?
        NORMAL_ATTACK_MAX : HIGH_CLARINET_ATTACK_SAMPLES;
    localparam integer AD_MAX = (ATTACK_MAX > DECAY_SAMPLES) ? ATTACK_MAX : DECAY_SAMPLES;
    localparam integer CURVED_RELEASE_MAX=(KEYBOARD_RELEASE_SAMPLES>CLARINET_RELEASE_SAMPLES) ?
        KEYBOARD_RELEASE_SAMPLES : CLARINET_RELEASE_SAMPLES;
    localparam integer RELEASE_MAX=(RELEASE_SAMPLES>CURVED_RELEASE_MAX) ?
        RELEASE_SAMPLES : CURVED_RELEASE_MAX;
    localparam integer SEGMENT_MAX = (AD_MAX > RELEASE_MAX) ? AD_MAX : RELEASE_MAX;
    localparam integer TIMER_WIDTH = bits_for(SEGMENT_MAX-1);
    // 段长可能是2的整数次幂，比段内计数多一位；明确宽度避免隐式截断。
    localparam [TIMER_WIDTH:0] A_LENGTH=ATTACK_SAMPLES;
    localparam [TIMER_WIDTH:0] KA_LENGTH=KEYBOARD_ATTACK_SAMPLES;
    localparam [TIMER_WIDTH:0] LKA_LENGTH=LOW_KEYBOARD_ATTACK_SAMPLES;
    localparam [TIMER_WIDTH:0] HCA_LENGTH=HIGH_CLARINET_ATTACK_SAMPLES;
    localparam [TIMER_WIDTH:0] D_LENGTH=DECAY_SAMPLES;
    localparam [TIMER_WIDTH:0] R_LENGTH=RELEASE_SAMPLES;
    localparam [TIMER_WIDTH-1:0] A_REMAINDER=A_REM, KA_REMAINDER=KA_REM,
        LKA_REMAINDER=LKA_REM,
        HCA_REMAINDER=HCA_REM,
        D_REMAINDER=D_REM, PD_REMAINDER=PD_REM;
    // Counter width follows the longest selected envelope segment.
    reg [TIMER_WIDTH-1:0] count, error_acc;
    reg fast_attack, slow_clarinet_attack, exponential_release, clarinet_release;
    // Release从松键瞬间的level计算步长，因此提前松键也能从当前音量平滑下降。
    reg [15:0] release_base;
    reg [TIMER_WIDTH-1:0] release_rem;
    // sum_error/delta是本拍计算用的中间量：用阻塞赋值=先算，供后面的语句使用。
    // level/state/count/error_acc用非阻塞赋值<=，在本次时钟边沿结束时统一更新。
    wire [TIMER_WIDTH-1:0] ramp_remainder=(state==ATTACK) ?
        (fast_attack ? (slow_clarinet_attack ? LKA_REMAINDER : KA_REMAINDER) :
            slow_clarinet_attack ? HCA_REMAINDER : A_REMAINDER) :
        (state==DECAY) ? (fast_attack ? PD_REMAINDER : D_REMAINDER) : release_rem;
    wire [TIMER_WIDTH:0] ramp_length=(state==ATTACK) ?
        (fast_attack ? (slow_clarinet_attack ? LKA_LENGTH : KA_LENGTH) :
            slow_clarinet_attack ? HCA_LENGTH : A_LENGTH) :
        (state==DECAY) ? D_LENGTH : R_LENGTH;
    wire [15:0] ramp_base=(state==ATTACK) ?
        (fast_attack ? (slow_clarinet_attack ? LKA_BASE : KA_BASE) :
            slow_clarinet_attack ? HCA_BASE : A_BASE) :
        (state==DECAY) ? (fast_attack ? PD_BASE : D_BASE) :
        (state==SUSTAIN) ? 16'd1 : release_base;
    wire [TIMER_WIDTH:0] ramp_sum={1'b0,error_acc}+{1'b0,ramp_remainder};
    wire ramp_carry=(ramp_sum>=ramp_length);
    wire [TIMER_WIDTH:0] ramp_error=ramp_carry ? ramp_sum-ramp_length : ramp_sum;
    wire [15:0] ramp_delta=ramp_base+ramp_carry;
    // 16位level的最大商为65535/R；默认R=11719只需3次迭代。
    // 常量移位均不超过65535，避免32位整数 / 和 % 推导出宽除法网络。
    localparam integer RELEASE_QUOTIENT_BITS=bits_for(65535/RELEASE_SAMPLES);
    localparam [15:0] RELEASE_DIVISOR=RELEASE_SAMPLES;
    localparam integer DIV_COUNT_WIDTH=bits_for(RELEASE_QUOTIENT_BITS-1);
    reg division_busy;
    reg [DIV_COUNT_WIDTH-1:0] division_bit;
    reg [15:0] division_remainder;
    reg [RELEASE_QUOTIENT_BITS-1:0] division_quotient;
    wire [15:0] division_threshold=RELEASE_DIVISOR << division_bit;
    wire [16:0] division_difference={1'b0,division_remainder}-{1'b0,division_threshold};
    wire division_accept=!division_difference[16];
    wire [15:0] division_next_remainder=division_accept ? division_difference[15:0] : division_remainder;
    wire [RELEASE_QUOTIENT_BITS-1:0] division_next_quotient=(division_quotient<<1) | division_accept;
    wire [TIMER_WIDTH-1:0] division_final_remainder;
    generate if(TIMER_WIDTH<=16) begin: narrow_remainder
        assign division_final_remainder=division_next_remainder[TIMER_WIDTH-1:0];
    end else begin: extend_remainder
        assign division_final_remainder={{(TIMER_WIDTH-16){1'b0}},division_next_remainder};
    end endgenerate
    assign context_out={state,level,count,error_acc,fast_attack,slow_clarinet_attack,exponential_release,clarinet_release,division_busy,division_bit,division_remainder,division_quotient,release_base,release_rem};
    // Release开始后复用一个17位减法器，默认3clk内求出精确商/余数。
    // 不改变任何采样边沿的level/state；下一采样至少间隔Q_BITS+1clk。
    always @(posedge clk) begin
        if(context_load) begin
            {division_busy,division_bit,division_remainder,division_quotient,release_base,release_rem}<=context_in[0 +: (1+DIV_COUNT_WIDTH+16+RELEASE_QUOTIENT_BITS+16+TIMER_WIDTH)];
        end else if(rst || trigger) begin
            division_busy<=0; division_bit<=0; division_remainder<=0; division_quotient<=0;
            release_base<=0; release_rem<=0;
        end else if(sample_tick && !gate && state!=IDLE && state!=RELEASE) begin
            division_remainder<=level; division_quotient<=0;
            division_bit<=RELEASE_QUOTIENT_BITS-1;
            if(RELEASE_SAMPLES<=65535) division_busy<=1;
            else begin
                division_busy<=0; release_base<=0; release_rem<=level;
            end
        end else if(division_busy) begin
            division_remainder<=division_next_remainder;
            division_quotient<=division_next_quotient;
            if(division_bit==0) begin
                division_busy<=0;
                release_base<=division_next_quotient;
                release_rem<=division_final_remainder;
            end else division_bit<=division_bit-1'b1;
        end
    end
    // synthesis translate_off
    always @(posedge clk) if(!rst && !trigger && sample_tick && state==RELEASE && division_busy)
        $fatal(1,"sample_tick interval too short for exact Release division");
    // synthesis translate_on
    // Release期间仍然active=1；顶层据此等待尾音结束才静音DAC。
    assign active = state != IDLE;
    always @(posedge clk) begin
        if(context_load) begin
            {state,level,count,error_acc,fast_attack,slow_clarinet_attack,exponential_release,clarinet_release}<=context_in >> (1+DIV_COUNT_WIDTH+16+RELEASE_QUOTIENT_BITS+16+TIMER_WIDTH);
        end else if (rst) begin
            state <= IDLE;
            level <= 0;
            count <= 0;
            error_acc <= 0;
            fast_attack<=0;
            slow_clarinet_attack<=0;
            exponential_release<=0;
            clarinet_release<=0;
        // 新按键优先级最高；同一个键再按一次，会重新起音，不创建额外声部。
        end else if (trigger) begin
            state <= ATTACK;
            level <= 0;
            count <= 0;
            error_acc <= 0;
            fast_attack<=keyboard_mode;
            // Reuse the existing flag: with fast_attack it marks low piano;
            // without fast_attack it marks high clarinet.
            slow_clarinet_attack<=high_clarinet_mode || low_keyboard_mode;
        // 平时保持包络；只有音频采样使能到来时推进，不能按50MHz频率直接增减。
        end else if (sample_tick) begin
            // 松键在下一次采样被处理：先锁定Release步长，后续采样再逐步下降。
            // 不把level直接归零，也不跳到Sustain，避免切掉音尾。
            if (!gate && state != IDLE && state != RELEASE) begin
                state <= RELEASE;
                count <= 0;
                error_acc <= 0;
                exponential_release<=keyboard_mode || clarinet_mode;
                clarinet_release<=clarinet_mode;
            end else begin
                case (state)
                    IDLE: level <= 0;
                    // A：音量向上爬升，最后一次采样精确设为65535并切到Decay。
                    ATTACK: begin
                        error_acc <= ramp_error[TIMER_WIDTH-1:0];
                        level <= level + ramp_delta;
                        count <= count + 1'b1;
                        // count从0开始，所以比较长度-1。最后一次对level赋值覆盖前面的累加。
                        if (count == (fast_attack ?
                            (slow_clarinet_attack ? LOW_KEYBOARD_ATTACK_SAMPLES-1 : KEYBOARD_ATTACK_SAMPLES-1) :
                            slow_clarinet_attack ? HIGH_CLARINET_ATTACK_SAMPLES-1 :
                            ATTACK_SAMPLES-1)) begin
                            level <= 65535;
                            state <= DECAY;
                            count <= 0;
                            error_acc <= 0;
                        end
                    end
                    // D：从峰值下降到SUSTAIN_LEVEL，使用同样的商/余数方法精确计时。
                    DECAY: begin
                        error_acc <= ramp_error[TIMER_WIDTH-1:0];
                        level <= level - ramp_delta;
                        count <= count + 1'b1;
                        if (count == DECAY_SAMPLES-1) begin
                            level <= fast_attack ? PIANO_SUSTAIN_LEVEL : SUSTAIN_LEVEL;
                            state <= SUSTAIN;
                            count <= 0;
                            error_acc <= 0;
                        end
                    end
                    // Piano reuses the existing envelope registers: after the
                    // initial decay, the held string keeps losing energy.
                    // Other timbres retain their original flat sustain.
                    SUSTAIN: begin
                        if(fast_attack) begin
                            count[1:0]<=count[1:0]+1'b1;
                            if(count[1:0]==2'd3 && level!=0) level<=level-ramp_delta;
                            if(level==0) state<=IDLE;
                        end else level<=SUSTAIN_LEVEL;
                    end
                    // R：从当前音量自然衰减；单簧管参数保持不变。
                    RELEASE: begin
                        if(exponential_release) begin
                            level <= (level>16'd8) ? level-((level>>KEYBOARD_RELEASE_SHIFT)+16'd1) : 16'd0;
                        end else begin
                            error_acc <= ramp_error[TIMER_WIDTH-1:0];
                            level <= (level > ramp_delta) ? level-ramp_delta : 16'd0;
                        end
                        count <= count + 1'b1;
                        if (count == (exponential_release ?
                            (clarinet_release ? CLARINET_RELEASE_SAMPLES-1 :
                             (fast_attack && slow_clarinet_attack) ? LOW_KEYBOARD_RELEASE_SAMPLES-1 :
                             KEYBOARD_RELEASE_SAMPLES-1) :
                            RELEASE_SAMPLES-1) ||
                            (exponential_release && level<=16'd8)) begin
                            level <= 0;
                            state <= IDLE;
                            count <= 0;
                        end
                    end
                    default: begin state <= IDLE; level <= 0; end
                endcase
            end
        end
    end
    // synthesis translate_off
    initial if(KEYBOARD_ATTACK_SAMPLES<1 || LOW_KEYBOARD_ATTACK_SAMPLES<1 ||
        HIGH_CLARINET_ATTACK_SAMPLES<1 || KEYBOARD_RELEASE_SAMPLES<1 ||
        LOW_KEYBOARD_RELEASE_SAMPLES<1 ||
        CLARINET_RELEASE_SAMPLES<1 ||
        KEYBOARD_RELEASE_SHIFT<1 || KEYBOARD_RELEASE_SHIFT>15)
        $fatal(1,"invalid keyboard envelope parameters");
    // synthesis translate_on
endmodule
