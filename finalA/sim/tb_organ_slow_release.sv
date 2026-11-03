`timescale 1ns/1ps
module tb_organ_slow_release;
 reg clk=0,rst=1,tick=0,trig=0,gate=1;always #10 clk=~clk;
 envelope_bank #(.LEGACY_PERCUSSION_ENABLE(0)) dut(.clk(clk),.rst(rst),.sample_tick(1'b0),
  .trigger(12'd0),.gate(12'd0),.octaves({12{4'd4}}),.timbre(2'd2));
 task step;begin @(negedge clk);tick=1;@(negedge clk);tick=0;repeat(6)@(negedge clk);end endtask
 integer n,expected;
 initial begin
  // Exercise the actual organ envelope engine; frame scheduling is separately
  // covered by the complete A-top/I2S regression.
  force dut.context_load=1'b0;force dut.engine_trigger=trig;force dut.engine_tick=tick;force dut.engine_gate=gate;
  repeat(5)@(negedge clk);rst=0;trig=1;@(negedge clk);trig=0;
  repeat(1000)step();if(dut.organ_level!=65535)$fatal(1,"organ never sustained");
  repeat(100)step();if(dut.organ_level!=65535)$fatal(1,"held organ decayed");
  gate=0;expected=65535;n=0;
  while(expected>0)begin
   if(n%16==15)expected=expected-(expected>>12)-1;
   step();if(dut.organ_level!==expected)$fatal(1,"organ slow release mismatch");n=n+1;
  end
  if(dut.organ_state!=0)$fatal(1,"organ stuck active");
  $display("PASS organ held sustain and exact slow release to zero in%0d samples",n);$finish;
 end
endmodule
