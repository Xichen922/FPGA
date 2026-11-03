`timescale 1ns/1ps
// Before/after complete audio engines, sharing unchanged inputs and ROM modules.
// Baseline source copies are simulation-only and excluded from the GPRJ.
module tb53_equivalence32;
 defparam a.u_shared32.PARTIALS=32;
 reg clk=0,rst=1,tick=0,kv=0;always #10 clk=~clk;
 reg [15:0] keys=0;reg [1:0] timbre=0;
 reg [9:0] x=512,y=100;
 wire signed [23:0] left_new,right_new,left_old,right_old;
 wire valid_new,valid_old;wire [11:0] active_new,active_old;
 wire [3:0] octave_new,octave_old;wire any_new,any_old;
 instrument_core #(.REMOTE_CONTROL_ENABLE(1)) a(
 .clk(clk),.rst(rst),.frame_tick(tick),.touch_valid(kv),.touch_keys(keys),.pcm_ready(1'b1),
 .joystick_x(x),.joystick_y(y),.joystick_valid(1'b1),
 .remote_octave_enable(1'b0),.remote_octave(4'd4),
 .remote_timbre_enable(1'b1),.remote_timbre(timbre),
 .light_valid(1'b0),.light_1(10'd0),.light_2(10'd0),.light_3(10'd0),.light_4(10'd0),
 .ultrasonic_valid(1'b0),.ultrasonic_distance_mm(16'd0),
 .encoder_valid(1'b0),.encoder_delta(8'sd0),.encoder_button_press(1'b0),.vibrato_enable(1'b1),
 .pcm_left(left_new),.pcm_right(right_new),.pcm_valid(valid_new),
 .active_voices(active_new),.any_active(any_new),.octave(octave_new));
 ref51_instrument_core #(.REMOTE_CONTROL_ENABLE(1)) b(
 .clk(clk),.rst(rst),.frame_tick(tick),.touch_valid(kv),.touch_keys(keys),.pcm_ready(1'b1),
 .joystick_x(x),.joystick_y(y),.joystick_valid(1'b1),
 .remote_octave_enable(1'b0),.remote_octave(4'd4),
 .remote_timbre_enable(1'b1),.remote_timbre(timbre),
 .light_valid(1'b0),.light_1(10'd0),.light_2(10'd0),.light_3(10'd0),.light_4(10'd0),
 .ultrasonic_valid(1'b0),.ultrasonic_distance_mm(16'd0),
 .encoder_valid(1'b0),.encoder_delta(8'sd0),.encoder_button_press(1'b0),.vibrato_enable(1'b1),
 .pcm_left(left_old),.pcm_right(right_old),.pcm_valid(valid_old),
 .active_voices(active_old),.any_active(any_old),.octave(octave_old));
 integer f,c,t,received=0,nonzero=0,max_cycle=0,cycles=0;
 real error_energy=0,reference_energy=0,relative_error; integer pairs_file;
 reg [23:0] captured_new,captured_old;reg seen_new=0,seen_old=0;
 always @(posedge clk)begin
  #1;
  if(rst)cycles=0;
  else begin
   if(tick)cycles=0;else cycles=cycles+1;
   if(valid_new)begin captured_new=left_new;seen_new=1;if(cycles>max_cycle)max_cycle=cycles;end
   if(valid_old)begin captured_old=left_old;seen_old=1;end
  end
 end
 initial begin
  pairs_file=$fopen("verification/equivalence32_pairs.csv","w");
  for(t=0;t<4;t=t+1)begin
   error_energy=0;reference_energy=0;
   @(negedge clk);rst=1;tick=0;kv=0;keys=0;timbre=t;x=512;y=100;
   repeat(8)@(negedge clk);
   // Start each instrument at full gain; ordinary fade/restore has its own
   // unchanged-controller regression. Both engines receive identical forces.
   force a.u_timbre.active_timbre=timbre;force b.u_timbre.active_timbre=timbre;
   rst=0;
   for(f=0;f<200;f=f+1)begin
    if(f==8 || f==48 || f==88 || f==140)begin keys=16'h0fff;kv=1;end
    if(f==40)begin keys=0;kv=1;y=512;end
    if(f==80)begin keys=0;kv=1;y=900;end
    if(f==120 || f==143)begin keys=0;kv=1;end
    if(f==25)begin keys=16'h0555;kv=1;end
    if(f==28)begin keys=16'h0fff;kv=1;end
    if(f==16)x=900;if(f==66)x=100;if(f==100)x=512;
    @(negedge clk);kv=0;
    seen_new=0;seen_old=0;tick=1;@(negedge clk);tick=0;
    for(c=1;c<511;c=c+1)@(negedge clk);
    if(!seen_new || !seen_old)$fatal(1,"missing frame t=%0d f=%0d",t,f);
    if(captured_new!==captured_old)$fatal(1,"32-mode optimization not bit exact t=%0d f=%0d",t,f);
    error_energy=error_energy+($itor($signed(captured_new))-$itor($signed(captured_old)))*($itor($signed(captured_new))-$itor($signed(captured_old)));
    reference_energy=reference_energy+$itor($signed(captured_old))*$itor($signed(captured_old));
    $fdisplay(pairs_file,"%0d,%0d,%0d,%0d",t,f,$signed(captured_old),$signed(captured_new));
    received=received+1;if(captured_new!=0)nonzero=nonzero+1;
   end
   // Drain the last frame before reset/finish; its PCM arrives at clock507.
   repeat(12)@(negedge clk);
   release a.u_timbre.active_timbre;release b.u_timbre.active_timbre;
   relative_error=$sqrt(error_energy/reference_energy);
   if(relative_error>0.05)$fatal(1,"waveform error exceeds calibration limit timbre%0d: %f",t,relative_error);
   $display("STAGE shared32 comparison timbre%0d: relative waveform RMS error %f",t,relative_error);
  end
  if(received!=800 || nonzero<600 || max_cycle>511)$fatal(1,"insufficient audio coverage / frame budget %0d %0d %0d",received,nonzero,max_cycle);
  $fclose(pairs_file);$display("PASS shared32 comparison:800 stereo frames,C3..B5,12-note chords,octave locks,release/restrike,vibrato; bounded waveform error, PCM<=%0d/512 clocks",max_cycle);$finish;
 end
 initial begin #20000000;$fatal(1,"equivalence timeout");end
endmodule
