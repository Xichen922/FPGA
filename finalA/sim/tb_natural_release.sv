`timescale 1ns/1ps
module tb_natural_release;
 reg clk=0,rst=1,tick=0,trig=0,gate=1;always #10 clk=~clk;
 wire [15:0] level;wire [2:0] state;wire active;
 // A deliberately short old time limit proves release is no longer capped.
 adsr_context #(.ATTACK_SAMPLES(4),.DECAY_SAMPLES(4),.SUSTAIN_LEVEL(60000),
  .CLARINET_RELEASE_SAMPLES(64)) dut(.clk(clk),.rst(rst),.sample_tick(tick),
  .trigger(trig),.gate(gate),.keyboard_mode(1'b0),.clarinet_mode(1'b1),
  .high_clarinet_mode(1'b0),.low_keyboard_mode(1'b0),.context_load(1'b0),
  .context_in(192'd0),.context_out(),.level(level),.state(state),.active(active));
 task step;begin @(negedge clk);tick=1;@(negedge clk);tick=0;repeat(6)@(negedge clk);end endtask
 task strike;begin @(negedge clk);trig=1;gate=1;@(negedge clk);trig=0;end endtask
 integer n,expected;
 initial begin
  repeat(5)@(negedge clk);rst=0;strike();repeat(8)step();
  if(level!=60000)$fatal(1,"test setup");
  gate=0;step();expected=60000;n=0;
  while(expected>0)begin
   if(n%16==15)expected=expected-(expected>>12)-1;step();
   if(level!==expected)$fatal(1,"release cut or wrong slope at tick%0d got%0d want%0d",n,level,expected);
   if(n==64 && (!active || level==0))$fatal(1,"old timeout still active");n=n+1;
  end
  if(active || state!=0)$fatal(1,"release never returns idle");
  strike();step();gate=0;step();repeat(20)step();
  if(level==0)$fatal(1,"early key-up abruptly muted");
  strike();if(state!=1 || level!=0)$fatal(1,"retrigger failed");
  $display("PASS natural clarinet release: %0d samples follow exact monotone decay to zero beyond old timeout; early release and restrike",n);$finish;
 end
endmodule
