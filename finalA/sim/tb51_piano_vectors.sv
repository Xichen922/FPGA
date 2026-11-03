`timescale 1ns/1ps
module tb51_piano_vectors;
 reg clk=0,rst=1,tick=0;always #10 clk=~clk;
 reg [11:0] trigger=0,gate=0;reg [47:0] octaves={12{4'd4}};reg signed [15:0] vib=0;
 wire [287:0] samples;wire [11:0] valid,active;wire ready;
 shared_modal_core dut(.clk(clk),.rst(rst),.frame_tick(tick),.trigger(trigger),.gate(gate),
  .octaves(octaves),.vibrato_q16(vib),.timbre(2'd0),.phase_steps(384'd0),.normal_levels(192'd0),.organ_levels(192'd0),.envelopes_ready(1'b1),.samples(samples),.valid(valid),.active(active),.ready(ready));
 reg [387:0] vectors[0:999];reg [11:0] seen;integer f,c,k,max_cycle=0;
 initial begin
  $readmemh("analysis/shared32_piano_vectors.hex",vectors);
  repeat(5)@(negedge clk);rst=0;
  for(f=0;f<1000;f=f+1)begin
   @(negedge clk);tick=1;trigger=vectors[f][387:376];gate=vectors[f][375:364];
   octaves=vectors[f][363:316];vib=vectors[f][315:300];seen=0;
   @(negedge clk);tick=0;trigger=0;
   for(c=1;c<511;c=c+1)begin
    @(negedge clk);
    for(k=0;k<12;k=k+1)if(valid[k])begin
     if(seen[k])$fatal(1,"duplicate sample voice %0d",k);seen[k]=1;
     if(samples[k*24+:24]!==vectors[f][k*24+:24])
      $fatal(1,"PCM f=%0d voice=%0d got=%0d expected=%0d",f,k,$signed(samples[k*24+:24]),$signed(vectors[f][k*24+:24]));
     if(active[k]!==vectors[f][288+k])$fatal(1,"active mismatch f=%0d voice=%0d",f,k);
     if(c>max_cycle)max_cycle=c;
    end
   end
   if(seen!=12'hfff || !ready)$fatal(1,"missing voices/frame overrun");
  end
  $display("PASS piano 1000 frames /12000 voice samples bit-exact: all36 notes, 12-way polyphony, release, rapid retrigger, mixed octaves, signed vibrato; shared32 last voice cycle=%0d/512",max_cycle);
  $finish;
 end
 initial begin #20000000;$fatal(1,"timeout");end
endmodule
