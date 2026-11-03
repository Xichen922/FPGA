`timescale 1ns/1ps
module tb53_envelope_storage;
 reg clk=0,rst=1,tick=0;always #10 clk=~clk;
 reg [11:0] trigger=0,gate=0;reg [47:0] octaves={12{4'd4}};reg [1:0] timbre=1;
 wire [191:0] n0,o0,n1,o1;wire [35:0] ns0,os0,ns1,os1;
 wire [11:0] na0,oa0,na1,oa1;wire r0,r1;
 envelope_bank #(.LEGACY_PERCUSSION_ENABLE(0)) a(.clk(clk),.rst(rst),.sample_tick(tick),.trigger(trigger),.gate(gate),.octaves(octaves),.timbre(timbre),
 .normal_levels(n0),.organ_levels(o0),.normal_states(ns0),.organ_states(os0),.normal_active(na0),.organ_active(oa0),.ready(r0));
 ref51_envelope_bank #(.LEGACY_PERCUSSION_ENABLE(0)) b(.clk(clk),.rst(rst),.sample_tick(tick),.trigger(trigger),.gate(gate),.octaves(octaves),.timbre(timbre),
 .normal_levels(n1),.organ_levels(o1),.normal_states(ns1),.organ_states(os1),.normal_active(na1),.organ_active(oa1),.ready(r1));
 integer f,c,k;reg [31:0] random_value;
 always @(negedge clk)if(!rst)begin
  if({n0,o0,ns0,os0,na0,oa0,r0}!=={n1,o1,ns1,os1,na1,oa1,r1})
   $fatal(1,"compact envelope context differs at frame%0d clock%0d",f,c);
 end
 initial begin
  repeat(5)@(negedge clk);rst=0;
  for(f=0;f<3000;f=f+1)begin
   if(f%97==0)begin
    random_value=$random;gate=random_value[11:0];trigger=gate;timbre=(f/97)%4;
    for(k=0;k<12;k=k+1)octaves[k*4+:4]=3+(f+k)%3;
   end
   if(f%97==60)gate=0;
   tick=1;@(negedge clk);tick=0;trigger=0;
   for(c=1;c<512;c=c+1)begin
    if(c==150 && f%113==0)begin trigger=12'h001;gate=gate|1;end
    if(c==151)trigger=0;
    @(negedge clk);
   end
  end
  $display("PASS compact envelope RAM/FF storage:3000 frames,cycle-exact vs51,12 contexts,random chords,all timbres/octaves,release,restrike and late triggers");$finish;
 end
endmodule
