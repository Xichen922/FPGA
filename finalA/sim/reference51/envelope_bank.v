`timescale 1ns/1ps
// Exact context switching of the original ADSR, organ and music-box envelopes.
// All 48 envelopes (legacy ADSR, organ, music box, piano) retain independent state.
// The bank runs while NCOs render, so no extra audio-frame latency is added.
module ref51_envelope_bank #(
    parameter integer LEGACY_PERCUSSION_ENABLE=1,
    parameter integer ATTACK_SAMPLES=489,DECAY_SAMPLES=7813,
    parameter integer SUSTAIN_LEVEL=45875,RELEASE_SAMPLES=11719
)(input wire clk,rst,sample_tick,
    input wire [11:0] trigger,gate,
    input wire [47:0] octaves,input wire [1:0] timbre,
    output reg [191:0] normal_levels,organ_levels,pluck_levels,piano_levels,
    output reg [35:0] normal_states,organ_states,pluck_states,piano_states,
    output reg [11:0] normal_active,organ_active,pluck_active,piano_active,
    output wire ready);
    function integer bits_for;
        input integer value;
        integer v;
        begin v=value;bits_for=0;
            while(v>0) begin bits_for=bits_for+1;v=v>>1;end
            if(bits_for==0)bits_for=1;
        end
    endfunction
    localparam integer KA=(ATTACK_SAMPLES<49)?ATTACK_SAMPLES:49;
    localparam integer LKA=(ATTACK_SAMPLES<98)?ATTACK_SAMPLES:98;
    localparam integer KR=(RELEASE_SAMPLES<11719)?RELEASE_SAMPLES:17578;
    localparam integer LKR=(RELEASE_SAMPLES<11719)?RELEASE_SAMPLES:13183;
    localparam integer CR=(RELEASE_SAMPLES<11719)?RELEASE_SAMPLES:24414;
    // Match adsr_envelope's original context widths exactly.
    localparam integer NA_MAX=(ATTACK_SAMPLES>KA)?ATTACK_SAMPLES:KA;
    localparam integer A_MAX=(NA_MAX>684)?NA_MAX:684;
    localparam integer AD_MAX=(A_MAX>DECAY_SAMPLES)?A_MAX:DECAY_SAMPLES;
    localparam integer CURVED_MAX=(KR>CR)?KR:CR;
    localparam integer R_MAX=(RELEASE_SAMPLES>CURVED_MAX)?RELEASE_SAMPLES:CURVED_MAX;
    localparam integer SEG_MAX=(AD_MAX>R_MAX)?AD_MAX:R_MAX;
    localparam integer W=bits_for(SEG_MAX-1);
    localparam integer Q=bits_for(65535/RELEASE_SAMPLES),QB=bits_for(Q-1);
    localparam integer ENV_BITS=56+3*W+Q+QB;
    localparam integer CONTEXT_BITS=ENV_BITS+36+23+46;
    localparam [2:0] IDLE=0,READ=1,LOAD=2,STRIKE=3,TICK=4,DIVIDE=5,SAVE=6;
    reg [CONTEXT_BITS-1:0] memory[0:15] /* synthesis syn_ramstyle="block_ram" */;
    reg [CONTEXT_BITS-1:0] read_context;
    reg [2:0] stage;
    reg [3:0] index;
    reg [4:0] divide_count;
    reg [11:0] initialized,pending,pending_gate;
    reg [23:0] pending_timbres;
    reg [47:0] pending_octaves;
    reg [11:0] frame_trigger,frame_coincident,frame_gate,frame_trigger_gate;
    reg [23:0] frame_trigger_timbres;
    reg [47:0] frame_trigger_octaves,frame_octaves;
    reg [1:0] frame_timbre;
    wire context_load=(stage==LOAD);
    wire engine_trigger=(stage==STRIKE);
    wire engine_tick=(stage==TICK);
    wire engine_gate=engine_trigger ? frame_trigger_gate[index] : frame_gate[index];
    wire [1:0] engine_timbre=engine_trigger ? frame_trigger_timbres[index*2 +: 2] : frame_timbre;
    wire [3:0] engine_octave=engine_trigger ? frame_trigger_octaves[index*4 +: 4] : frame_octaves[index*4 +: 4];
    wire [CONTEXT_BITS-1:0] load_context=initialized[index] ? read_context : {CONTEXT_BITS{1'b0}};
    wire [191:0] env_context_out;
    wire [191:0] env_context_in={{(192-ENV_BITS){1'b0}},load_context[ENV_BITS-1:0]};
    wire [35:0] pluck_context_out;
    wire [15:0] normal_level,pluck_level;
    wire [2:0] normal_state,pluck_state;
    wire normal_running,pluck_running;
    ref51_adsr_context #(.ATTACK_SAMPLES(ATTACK_SAMPLES),
        .KEYBOARD_ATTACK_SAMPLES(KA),.LOW_KEYBOARD_ATTACK_SAMPLES(LKA),
        .DECAY_SAMPLES(DECAY_SAMPLES),.SUSTAIN_LEVEL(SUSTAIN_LEVEL),
        .RELEASE_SAMPLES(RELEASE_SAMPLES),.KEYBOARD_RELEASE_SAMPLES(KR),
        .LOW_KEYBOARD_RELEASE_SAMPLES(LKR),.CLARINET_RELEASE_SAMPLES(CR)) u_adsr(
        .clk(clk),.rst(rst),.sample_tick(engine_tick),.trigger(engine_trigger),.gate(engine_gate),
        .keyboard_mode(engine_timbre==0),.clarinet_mode(engine_timbre==1),
        .high_clarinet_mode(engine_timbre==1 && engine_octave==5),
        .low_keyboard_mode(engine_timbre==0 && engine_octave==3),
        .context_load(context_load),.context_in(env_context_in),.context_out(env_context_out),
        .level(normal_level),.state(normal_state),.active(normal_running));
    generate if(LEGACY_PERCUSSION_ENABLE!=0)begin: legacy_pluck
    plucked_context u_pluck(.clk(clk),.rst(rst),.sample_tick(engine_tick),
        .trigger(engine_trigger),.gate(engine_gate),.octave(engine_octave),.context_load(context_load),
        .context_in(load_context[ENV_BITS +: 36]),.context_out(pluck_context_out),
        .level(pluck_level),.state(pluck_state),.active(pluck_running));
    end else begin: no_legacy_pluck
        assign pluck_context_out=36'd0;assign pluck_level=0;
        assign pluck_state=0;assign pluck_running=0;
    end endgenerate
    reg [15:0] organ_level;
    reg [3:0] organ_release_div;
    reg [2:0] organ_state;
    always @(posedge clk) begin
        if(context_load) {organ_release_div,organ_state,organ_level}<=load_context[ENV_BITS+36 +: 23];
        else if(rst) begin organ_level<=0;organ_state<=0;organ_release_div<=0;end
        else if(engine_trigger) begin organ_level<=0;organ_state<=1;organ_release_div<=0;end
        else if(engine_tick) begin
            if(engine_gate) begin
                organ_release_div<=0;
                if(organ_level>=16'd65467) begin organ_level<=16'hffff;organ_state<=3;end
                else begin organ_level<=organ_level+16'd68;organ_state<=1;end
            end else if(organ_level!=0) begin
                organ_release_div<=organ_release_div+1'b1;organ_state<=4;
                if(organ_release_div==15)begin
                    organ_level<=organ_level-(organ_level>>12)-1'b1;
                    if(organ_level<=1)organ_state<=0;
                end
            end
            else begin organ_level<=0;organ_state<=0;organ_release_div<=0;end
        end
    end
    wire [45:0] piano_context_out;
    wire [15:0] piano_level;
    wire [2:0] piano_state;
    wire piano_running;
    generate if(LEGACY_PERCUSSION_ENABLE!=0)begin: legacy_piano
    piano_context #(.ATTACK_LOW(ATTACK_SAMPLES<391?ATTACK_SAMPLES:391),
        .ATTACK_MID(ATTACK_SAMPLES<391?ATTACK_SAMPLES:391),
        .ATTACK_HIGH(ATTACK_SAMPLES<391?ATTACK_SAMPLES:391)) u_piano(
        .clk(clk),.rst(rst),.sample_tick(engine_tick),.trigger(engine_trigger),.gate(engine_gate),
        .octave(engine_octave),.context_load(context_load),
        .context_in(load_context[ENV_BITS+59 +: 46]),.context_out(piano_context_out),
        .level(piano_level),.state(piano_state),.active(piano_running));
    end else begin: no_legacy_piano
        assign piano_context_out=46'd0;assign piano_level=0;
        assign piano_state=0;assign piano_running=0;
    end endgenerate
    assign ready=(stage==IDLE);
    always @(posedge clk) begin
        if(!rst && stage==READ) read_context<=memory[index];
        if(!rst && stage==SAVE) memory[index]<={piano_context_out,organ_release_div,organ_state,organ_level,pluck_context_out,env_context_out[ENV_BITS-1:0]};
    end
    integer i;
    always @(posedge clk) begin
        if(rst) begin
            stage<=IDLE;index<=0;divide_count<=0;initialized<=0;pending<=0;
            pending_gate<=0;pending_timbres<=0;pending_octaves<=0;
            frame_trigger<=0;frame_coincident<=0;frame_gate<=0;frame_trigger_gate<=0;
            frame_trigger_timbres<=0;frame_trigger_octaves<=0;frame_octaves<=0;frame_timbre<=0;
            normal_levels<=0;normal_states<=0;normal_active<=0;
            piano_levels<=0;piano_states<=0;piano_active<=0;
            organ_levels<=0;organ_states<=0;organ_active<=0;
            pluck_levels<=0;pluck_states<=0;pluck_active<=0;
        end else begin
            pending<=pending|trigger;
            for(i=0;i<12;i=i+1) begin
                if(trigger[i]) begin
                    pending_gate[i]<=gate[i];pending_timbres[i*2 +: 2]<=timbre;
                    pending_octaves[i*4 +: 4]<=octaves[i*4 +: 4];
                    // Preserve immediate active/state response to asynchronous strikes.
                    normal_active[i]<=1;normal_states[i*3 +: 3]<=1;
                    piano_active[i]<=1;piano_states[i*3 +: 3]<=1;
                    organ_active[i]<=1;organ_states[i*3 +: 3]<=1;
                    pluck_active[i]<=gate[i];pluck_states[i*3 +: 3]<=gate[i] ? 1 : 0;
                end
            end
            if(sample_tick) begin
                frame_trigger<=pending|trigger;frame_coincident<=trigger;frame_gate<=gate;
                frame_timbre<=timbre;frame_octaves<=octaves;
                for(i=0;i<12;i=i+1) begin
                    frame_trigger_gate[i]<=trigger[i] ? gate[i] : pending_gate[i];
                    frame_trigger_timbres[i*2 +: 2]<=trigger[i] ? timbre : pending_timbres[i*2 +: 2];
                    frame_trigger_octaves[i*4 +: 4]<=trigger[i] ? octaves[i*4 +: 4] : pending_octaves[i*4 +: 4];
                end
                pending<=0;index<=0;stage<=READ;
            end else case(stage)
                READ:stage<=LOAD;
                LOAD:stage<=frame_trigger[index] ? STRIKE : TICK;
                STRIKE:stage<=frame_coincident[index] ? SAVE : TICK;
                TICK:begin stage<=DIVIDE;divide_count<=Q-1;end
                DIVIDE:if(divide_count==0)stage<=SAVE;else divide_count<=divide_count-1'b1;
                SAVE:begin
                    normal_levels[index*16 +: 16]<=normal_level;
                    piano_levels[index*16 +: 16]<=piano_level;
                    organ_levels[index*16 +: 16]<=organ_level;
                    pluck_levels[index*16 +: 16]<=pluck_level;
                    // A strike after frame_tick belongs to the next frame. Keep
                    // its immediate status instead of overwriting it with old work.
                    if(!pending[index] && !trigger[index]) begin
                        normal_states[index*3 +: 3]<=normal_state;normal_active[index]<=normal_running;
                        piano_states[index*3 +: 3]<=piano_state;piano_active[index]<=piano_running;
                        organ_states[index*3 +: 3]<=organ_state;organ_active[index]<=(organ_state!=0);
                        pluck_states[index*3 +: 3]<=pluck_state;pluck_active[index]<=pluck_running;
                    end
                    initialized[index]<=1;
                    if(index==11)stage<=IDLE;else begin index<=index+1'b1;stage<=READ;end
                end
                default:stage<=IDLE;
            endcase
        end
    end
    // synthesis translate_off
    initial if(ENV_BITS>192)$fatal(1,"ADSR context width exceeds storage");
    always @(posedge clk) if(!rst && sample_tick && !ready)
        $fatal(1,"envelope bank overlaps sample frame");
    // synthesis translate_on
endmodule
