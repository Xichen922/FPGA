`timescale 1ns/1ps
// Four physical lanes, three voices/lane, 32 independent phase/energy slots.
// All four timbres use the SAME lane multiplier, accumulator and context RAM.
module ref51_shared32_core(input wire clk,rst,frame_tick,input wire [1:0] timbre,
 input wire [11:0] trigger,gate,input wire [47:0] octaves,
 input wire [383:0] phase_steps,input wire signed [15:0] vibrato_q16,
 input wire [191:0] normal_levels,organ_levels,input wire envelopes_ready,
 output wire [287:0] samples,output wire [11:0] valid,active,output wire ready);
 wire [3:0] ready_lanes;genvar g;
 generate for(g=0;g<4;g=g+1)begin: lanes
  ref51_shared32_lane #(.LANE(g)) lane(.clk(clk),.rst(rst),.frame_tick(frame_tick),.timbre(timbre),
   .trigger(trigger[g*3+:3]),.gate(gate[g*3+:3]),.octaves(octaves[g*12+:12]),
   .phase_steps(phase_steps[g*96+:96]),.vibrato_q16(vibrato_q16),
   .normal_levels(normal_levels[g*48+:48]),.organ_levels(organ_levels[g*48+:48]),
   .envelopes_ready(envelopes_ready),.samples(samples[g*72+:72]),
   .valid(valid[g*3+:3]),.active(active[g*3+:3]),.ready(ready_lanes[g]));
 end endgenerate
 assign ready=&ready_lanes;
endmodule

module ref51_shared32_lane #(parameter integer LANE=0)(
 input wire clk,rst,frame_tick,input wire [1:0] timbre,
 input wire [2:0] trigger,gate,input wire [11:0] octaves,
 input wire [95:0] phase_steps,input wire signed [15:0] vibrato_q16,
 input wire [47:0] normal_levels,organ_levels,input wire envelopes_ready,
 output reg [71:0] samples,output reg [2:0] valid,active,output wire ready);
 localparam IDLE=0,BEGIN_VOICE=1,PREP=2,RD=3,CALC=4,WAVE=5,SUM=6,
  DRAIN=7,POST=8,OUTPUT_SAMPLE=9,WIND_SHAPE=10;
 reg [3:0] state;reg [1:0] voice,last_timbre;
 (* syn_preserve=1 *) reg [1:0] frame_timbre;
 reg [4:0] mode,work_mode;
 reg [2:0] initialized,pending,frame_trigger,frame_gate,frame_zero;
 reg [11:0] frame_octaves;reg [95:0] frame_steps;reg signed [15:0] frame_vibrato;
 reg [9:0] ages[0:2];reg [9:0] age;
 reg [18:0] noise_levels[0:2];reg [15:0] noise_states[0:2];reg [7:0] noise_previous[0:2];
 reg [15:0] wind_states[0:2];reg [7:0] wind_previous[0:2];
 reg [55:0] contexts[0:127] /* synthesis syn_ramstyle="block_ram" */;
 reg [55:0] context_read;
 wire [6:0] context_address={voice,mode};
 wire [3:0] octave=frame_octaves[voice*4+:4];
 wire [3:0] note_bank=((octave<=3)?4'd0:(octave==4)?4'd3:4'd6)+voice;
 wire [8:0] parameter_address={note_bank,5'd0}+{4'd0,mode};
 wire [63:0] pp_raw;wire [35:0] bp;
 wire [63:0] pp=pp_raw;
 ref51_shared32_parameters #(.LANE(LANE)) parameters(.clk(clk),.address(parameter_address),
  .box_attack(state==DRAIN || state==POST),.high_octave(octave>=5),
  .attack_index(age[9:3]),.piano(pp_raw),.musicbox(bp));
 wire piano=(frame_timbre==0),box=(frame_timbre==3),wind=!piano&&!box;
 wire restart=frame_trigger[voice] || (!initialized[voice]&&frame_gate[voice]);
 wire [31:0] base_step=frame_steps[voice*32+:32];
 wire [1:0] header_voice=(state==OUTPUT_SAMPLE && voice<2)?voice+2'd1:voice;
 wire [31:0] header_step=frame_steps[header_voice*32+:32];
 reg [31:0] voice_step,phase_before,work_phase,work_frequency;
 reg [23:0] work_energy;reg work_audible,voice_active;
 reg signed [23:0] accumulator;
 reg signed [32:0] mul_a;reg signed [18:0] mul_b;
 reg signed [44:0] product_narrow;
 wire signed [51:0] product={{7{product_narrow[44]}},product_narrow};
 wire [36:0] decay_product=product[36:0];
 wire [23:0] fetched_energy=restart ? (frame_gate[voice] ? (piano?{pp[45:32],10'd0}:box?bp[23:0]:24'h800000):24'd0):
  initialized[voice]?context_read[23:0]:24'd0;
 wire [12:0] fetched_decay=piano?{1'b0,pp[57:46]}:box?{1'b0,bp[35:24]}:
  (mode==0?13'd0:{10'd0,mode[4:2]}+13'd1);
 wire [36:0] decay_loss=(decay_product>>(piano?20:24))+37'd1;
 wire [23:0] intrinsic_energy=(work_energy<=(piano?24'd1024:24'd256) || decay_loss>={13'd0,work_energy})?24'd0:
   work_energy-decay_loss[23:0];
 wire [23:0] next_energy=!work_audible?24'd0:wind?(frame_gate[voice]?24'h800000:intrinsic_energy):(box&&restart)?work_energy:intrinsic_energy;
 wire [31:0] frequency=piano ? pp[31:0]+product[39:8]:box ? product[35:4]:product[31:0];
 wire [31:0] phase_next=(wind&&frame_zero[voice])?32'd0:phase_before+frequency;
 wire signed [15:0] piano_wave,box_wave;wire signed [23:0] wind_wave;
 assign piano_wave=box_wave;
 ref51_musicbox_sine_rom box_table(.clk(clk),.address(piano?{phase_next[31:22],1'b0}:phase_next[31:21]),.value(box_wave));
 wire signed [23:0] wind_combinational;
 ref51_sine_rom_256 wind_table(.address(phase_next[31:24]),.sample(wind_combinational));
 reg signed [23:0] wind_registered /* synthesis syn_romstyle="logic" */;
 always @(posedge clk)wind_registered<=wind_combinational;
 assign wind_wave=wind_registered;
 wire signed [51:0] rounded=product+52'sd16384;
 wire signed [15:0] piano_component=product[30:15];
 wire signed [23:0] box_component=rounded[38:15];
 reg signed [20:0] wind_component;
 reg signed [19:0] wind_shaped;
 reg [13:0] wind_gain;
 reg [23:0] wind_energy_next;
 wire [23:0] energy_to_store=wind?wind_energy_next:next_energy;
 wire signed [20:0] wind_component_scaled=product[33:13];
 wire signed [23:0] contribution=piano?{{8{piano_component[15]}},piano_component}:box?box_component:
  {{3{wind_component_scaled[20]}},wind_component_scaled};
 wire signed [23:0] sum_next=accumulator+contribution;
 wire signed [19:0] piano_sum=sum_next[19:0];
 wire signed [20:0] wind_sum=sum_next[20:0];
 function [4:0] wind_shift(input [1:0] t,input [4:0] m);begin
 if(t==1)begin
  if(m[0])wind_shift=14;else if(m==0)wind_shift=1;else if(m==2)wind_shift=2;
  else if(m==4)wind_shift=4;else if(m==6)wind_shift=5;else if(m<=14)wind_shift=6;else wind_shift=10;
 end else begin case(m)
  0:wind_shift=1;1:wind_shift=2;3:wind_shift=3;7:wind_shift=4;
  15:wind_shift=6;5,11:wind_shift=8;2,4:wind_shift=9;default:wind_shift=14;
 endcase end
 end endfunction
 wire [4:0] spectral_shift=wind_shift(frame_timbre,work_mode);
 wire signed [20:0] wind_source=wind_wave[20:0];
 wire signed [20:0] shifted=wind_source>>>spectral_shift;
 wire signed [19:0] spectral_base=shifted[19:0];
 wire low_harmonic=(frame_timbre==1 && octave==3 && work_mode!=0 && work_frequency>=32'd7036874 && work_frequency<32'd21990233);
 wire band_boost=(frame_timbre==1 && work_frequency>=32'd87960930 && work_frequency<32'd131941395);
 wire high_cut=(frame_timbre==1 && octave==5 && work_frequency>=32'd263882791 && work_frequency<32'd351843721);
 wire low_body=(frame_timbre==1 && octave==3 && LANE*3+voice<5 && work_mode==0);
 wire treble=(frame_timbre==1 && ((LANE*3+voice>=9 && work_mode>=4 && !work_mode[0]) || (octave==5 && work_mode==0)));
 wire signed [19:0] spectral_shape=low_harmonic ? spectral_base-(spectral_base>>>3)-(spectral_base>>>4)-(spectral_base>>>6):
  spectral_base+(band_boost?(spectral_base>>>2):high_cut?-(spectral_base>>>2):20'sd0);
 wire signed [19:0] shaped=spectral_shape+(low_body?((spectral_shape>>>1)+(spectral_shape>>>4)+(spectral_shape>>>6)):
  treble?(spectral_shape>>>3):20'sd0);
 wire signed [8:0] piano_noise=$signed({1'b0,noise_states[voice][15:8]})-$signed({1'b0,noise_previous[voice]});
 wire signed [9:0] wind_noise=$signed({2'd0,wind_states[voice][15:8]})-$signed({2'd0,wind_previous[voice]});
 wire signed [23:0] breath_value=$signed({{14{wind_noise[9]}},wind_noise})<<<3;
 wire signed [20:0] wind_total=wind_sum+((frame_timbre==1)?breath_value[20:0]:21'd0);
 reg signed [17:0] noise_product;
 wire signed [51:0] piano_output=((product>>>6)+($signed(noise_product)>>>8))<<<4;
 wire signed [23:0] box_output={rounded[34:15],4'd0};
 wire signed [51:0] wind_output=product>>>16;
 wire signed [23:0] final_output=piano?piano_output[23:0]:box?box_output:
  wind_output>8388607?24'sh7fffff:wind_output< -8388608?24'sh800000:wind_output[23:0];
 function [15:0] next_noise(input [15:0] n);begin next_noise={n[14:0],n[15]^n[13]^n[12]^n[10]};end endfunction
 function [31:0] seed(input [4:0] m);begin case(m)
  1:seed=32'h0f133d70;2:seed=32'h1e267ae0;3:seed=32'h2d39b850;
  4:seed=32'h3c4cf5c0;5:seed=32'h4b603330;6:seed=32'h24ab572c;default:seed=(32'h9e3779b9*{27'd0,m});
 endcase end endfunction
 function [17:0] ratio(input [4:0] m);begin case(m)
  5'd0:ratio=18'd4096;
  5'd1:ratio=18'd8192;
  5'd2:ratio=18'd12288;
  5'd3:ratio=18'd25670;
  5'd4:ratio=18'd50176;
  5'd5:ratio=18'd71885;
  5'd6:ratio=18'd25716;
  5'd7:ratio=18'd5612;
  5'd8:ratio=18'd7496;
  5'd9:ratio=18'd9708;
  5'd10:ratio=18'd11428;
  5'd11:ratio=18'd13967;
  5'd12:ratio=18'd16097;
  5'd13:ratio=18'd18391;
  5'd14:ratio=18'd20193;
  5'd15:ratio=18'd22569;
  5'd16:ratio=18'd24289;
  5'd17:ratio=18'd27976;
  5'd18:ratio=18'd30351;
  5'd19:ratio=18'd32645;
  5'd20:ratio=18'd34939;
  5'd21:ratio=18'd37642;
  5'd22:ratio=18'd40264;
  5'd23:ratio=18'd42885;
  5'd24:ratio=18'd45507;
  5'd25:ratio=18'd48046;
  5'd26:ratio=18'd51978;
  5'd27:ratio=18'd54764;
  5'd28:ratio=18'd58040;
  5'd29:ratio=18'd61972;
  5'd30:ratio=18'd66068;
  5'd31:ratio=18'd75244;
  default:ratio=0;
 endcase end endfunction
 wire [15:0] vib_magnitude=frame_vibrato[15]?-frame_vibrato:frame_vibrato;
 wire [31:0] wind_delta=product[47:16];
 always @*begin
  mul_a=0;mul_b=0;
  if(state==BEGIN_VOICE || state==OUTPUT_SAMPLE)begin
   mul_a=box?$signed({10'd0,header_step[30:8]}):$signed({1'b0,header_step});
   mul_b=box?{{3{frame_vibrato[15]}},frame_vibrato}:$signed({5'd0,vib_magnitude[13:0]});
  end else if(state==CALC)begin
   mul_a=piano?$signed({10'd0,pp[30:8]}):box?$signed({10'd0,voice_step[30:8]}):$signed({1'b0,voice_step});
   mul_b=piano?{{3{frame_vibrato[15]}},frame_vibrato}:box?$signed({1'b0,ratio(mode)}):$signed({13'd0,1'b0,mode}+19'd1);
  end else if(state==WAVE)begin
   mul_a=$signed({9'd0,work_energy});mul_b=$signed({6'd0,fetched_decay});
  end else if(state==SUM)begin
   mul_a=piano?$signed({19'd0,work_energy[23:10]}):box?$signed({17'd0,next_energy[23:8]}):
    $signed({{13{wind_shaped[19]}},wind_shaped});
   mul_b=piano?{{3{piano_wave[15]}},piano_wave}:box?{{3{box_wave[15]}},box_wave}:$signed({5'd0,wind_gain});
  end else if(state==POST)begin
   mul_a={{9{accumulator[23]}},accumulator};
   mul_b=piano?$signed({9'd0,age}):box?$signed({3'd0,bp[15:0]}):
    $signed({3'd0,(frame_timbre==2?organ_levels[voice*16+:16]:normal_levels[voice*16+:16])});
  end
 end
 integer i;
 always @(posedge clk)begin
  product_narrow<=$signed(mul_a[26:0])*$signed(mul_b[17:0]);
  noise_product<=piano_noise*$signed({1'b0,noise_levels[voice][18:10]});
  if(state==RD || state==PREP)context_read<=contexts[context_address];
  if(!rst && state==SUM)contexts[context_address]<={work_phase,energy_to_store};
  if(rst)begin
   state<=IDLE;voice<=0;mode<=0;work_mode<=0;frame_timbre<=0;last_timbre<=0;
   initialized<=0;pending<=0;frame_trigger<=0;frame_gate<=0;frame_zero<=0;
   frame_octaves<=12'h444;frame_steps<=0;frame_vibrato<=0;
   age<=0;voice_step<=0;phase_before<=0;work_phase<=0;work_frequency<=0;
   work_energy<=0;work_audible<=0;voice_active<=0;accumulator<=0;
   samples<=0;valid<=0;active<=0;noise_product<=0;wind_component<=0;
   wind_shaped<=0;wind_gain<=0;wind_energy_next<=0;
   for(i=0;i<3;i=i+1)begin
    ages[i]<=0;noise_levels[i]<=0;noise_states[i]<=16'hace1^((LANE*3+i)*16'h0f35);noise_previous[i]<=0;
    wind_states[i]<=16'hace1^((LANE*3+i)*16'h0f35);wind_previous[i]<=0;
   end
  end else begin
   valid<=0;pending<=pending|trigger;
   if(frame_tick)begin
    frame_timbre<=timbre;last_timbre<=timbre;frame_trigger<=pending|trigger|{3{timbre!=last_timbre}};
    frame_zero<=trigger|{3{timbre!=last_timbre}};pending<=0;frame_gate<=gate;
    frame_octaves<=octaves;frame_steps<=phase_steps;frame_vibrato<=vibrato_q16;
    voice<=0;mode<=0;state<=BEGIN_VOICE;
    for(i=0;i<3;i=i+1)begin wind_states[i]<=next_noise(wind_states[i]);wind_previous[i]<=wind_states[i][15:8];end
   end else case(state)
    BEGIN_VOICE:begin
     accumulator<=0;voice_active<=0;
     age<=restart?10'd0:(ages[voice]>=(piano?10'd64:10'd1023))?(piano?10'd64:10'd1023):ages[voice]+10'd1;
     state<=PREP;
    end
    PREP:begin
     voice_step<=box?base_step+product[39:8]:frame_vibrato[15]?base_step-wind_delta:base_step+wind_delta;
     state<=CALC;
    end
    RD:begin
     if(mode!=0)accumulator<=piano?{{4{piano_sum[19]}},piano_sum}:wind?{{3{wind_sum[20]}},wind_sum}:sum_next;
     state<=CALC;
    end
    CALC:begin
     phase_before<=restart?(piano?{pp[63:58],26'd0}:box?seed(mode):32'd0):initialized[voice]?context_read[55:24]:32'd0;
     work_energy<=fetched_energy;work_mode<=mode;
     if(piano && restart && mode==0)begin
      noise_levels[voice]<=frame_gate[voice]?{pp[45:32],5'd0}:19'd0;
      noise_states[voice]<=16'hace1^((LANE*3+voice)*16'h0f35);noise_previous[voice]<=0;
     end
     state<=WAVE;
    end
    WAVE:begin
     work_phase<=phase_next;work_frequency<=frequency;
     work_audible<=piano?!pp[31]:box?!(|product[51:35]):!(|product[51:31]);
     state<=wind?WIND_SHAPE:SUM;
    end
    WIND_SHAPE:begin
     wind_shaped<=work_audible?shaped:20'sd0;
     wind_gain<=next_energy[23:10];wind_energy_next<=next_energy;
     state<=SUM;
    end
    SUM:begin
     wind_component<=work_audible?{shaped[19],shaped}:21'sd0;
     voice_active<=voice_active||(energy_to_store!=0);
     if(mode==31)state<=DRAIN;else begin mode<=mode+5'd1;state<=RD;end
    end
    DRAIN:begin
     accumulator<=piano?{{4{piano_sum[19]}},piano_sum}:wind?{{3{wind_total[20]}},wind_total}:sum_next;
     state<=POST;
    end
    POST:if(piano||box||envelopes_ready)state<=OUTPUT_SAMPLE;
    OUTPUT_SAMPLE:begin
     samples[voice*24+:24]<=final_output;valid[voice]<=1;active[voice]<=voice_active;
     initialized[voice]<=1;ages[voice]<=age;
     if(piano)begin
      noise_levels[voice]<=noise_levels[voice]<=1024?19'd0:noise_levels[voice]-(noise_levels[voice]>>8)-19'd1;
      noise_states[voice]<=next_noise(noise_states[voice]);noise_previous[voice]<=noise_states[voice][15:8];
     end
     if(voice==2)state<=IDLE;else begin
      voice<=voice+2'd1;mode<=0;state<=PREP;accumulator<=0;voice_active<=0;
      age<=(frame_trigger[voice+1]||(!initialized[voice+1]&&frame_gate[voice+1]))?10'd0:
       (ages[voice+1]>=(piano?10'd64:10'd1023))?(piano?10'd64:10'd1023):ages[voice+1]+10'd1;
     end
    end
    default:state<=IDLE;
   endcase
  end
 end
 assign ready=(state==IDLE);
 // synthesis translate_off
 reg signed [23:0] debug_acc[0:2];
 always @(posedge clk)if(state==POST)debug_acc[voice]<=accumulator;
 always @(posedge clk)if(!rst && frame_tick && !ready)$fatal(1,"shared32 exceeded512 clocks");
 always @(posedge clk)if(!rst && state!=IDLE)begin
  if(mul_a[32:27]!={6{mul_a[26]}} || mul_b[18]!=mul_b[17])$fatal(1,"shared32 multiplier operand out of production range");
 end
 // synthesis translate_on
endmodule
