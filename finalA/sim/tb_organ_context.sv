`timescale 1ns/1ps
module tb_organ_context;
 reg clk=0,rst=1,tick=0;always #10 clk=~clk;
 reg [11:0] trigger=0,gate=0;wire [191:0] levels;wire ready;
 envelope_bank #(.LEGACY_PERCUSSION_ENABLE(0)) dut(.clk(clk),.rst(rst),.sample_tick(tick),
  .trigger(trigger),.gate(gate),.octaves({12{4'd4}}),.timbre(2'd2),.organ_levels(levels),.ready(ready));
 integer expected[0:11],divs[0:11];integer f,k;
 initial begin
  for(k=0;k<12;k=k+1)begin expected[k]=0;divs[k]=0;end
  repeat(5)@(negedge clk);rst=0;
  for(f=0;f<128;f=f+1)begin
   @(negedge clk);tick=1;trigger=0;
   if(f==0)begin trigger=12'hfff;gate=12'hfff;end
   if(f==64)gate=0;
   if(f==96)begin trigger=1;gate=1;end
   if(f==104)gate=0;
   for(k=0;k<12;k=k+1)begin
    if(trigger[k])begin expected[k]=0;divs[k]=0;end
    else if(gate[k])begin expected[k]=expected[k]+68;if(expected[k]>65535)expected[k]=65535;divs[k]=0;end
    else if(expected[k]!=0)begin
     if(divs[k]==15)expected[k]=expected[k]-(expected[k]>>12)-1;
     divs[k]=(divs[k]+1)%16;
    end else divs[k]=0;
   end
   @(negedge clk);tick=0;trigger=0;repeat(510)@(negedge clk);
   if(!ready)$fatal(1,"organ context bank overrun");
   for(k=0;k<12;k=k+1)if(levels[k*16+:16]!==expected[k])
    $fatal(1,"organ context f%0d voice%0d got%0d expected%0d",f,k,levels[k*16+:16],expected[k]);
  end
  $display("PASS real12-voice organ context save/load keeps independent16-sample slow-release dividers across chords and single-key restrike");$finish;
 end
endmodule
