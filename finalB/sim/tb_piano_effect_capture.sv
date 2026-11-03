`timescale 1ns/1ps
module tb_piano_effect_capture;
 reg clk=0,rst=1,enable=1,reverse_mode=0,decaying_source=1;
 reg [7:0] depth=8'd128;
 reg [11:0] keys=12'd1;
 reg voice_active=1,in_valid=0;
 reg signed [23:0] in_left=0,in_right=0;
 wire in_ready,out_valid;
 wire signed [23:0] out_left,out_right;
 always #5 clk=~clk;
 db_post_note_repeat #(.RECORD_FRAMES(4),.FIRST_GAP_FRAMES(1),.GAP_FRAMES(1)) dut(
  .clk(clk),.rst(rst),.enable(enable),.reverse_mode(reverse_mode),
  .depth(depth),.keys(keys),.voice_active(voice_active),.decaying_source(decaying_source),
  .in_left(in_left),.in_right(in_right),.in_valid(in_valid),.in_ready(in_ready),
  .out_left(out_left),.out_right(out_right),.out_valid(out_valid),.out_ready(1'b1));
 task frame(input integer n);
 begin
  @(negedge clk);
  while(!in_ready) @(negedge clk);
  in_left=n<<<8;in_right=n<<<8;in_valid=1;
  @(negedge clk);in_valid=0;
 end
 endtask
 initial begin
  repeat(2) @(negedge clk);rst=0;
  frame(100);frame(200);frame(300);frame(400);frame(500);frame(600);
  if(dut.recording[0]!==16'sd100 || dut.recording[3]!==16'sd400 ||
     dut.recorded!==4 || dut.write_addr!==0)
    $fatal(1,"piano attack was overwritten");
  keys=0;
  // The long piano envelope remains active, yet playback must begin and
  // overlay the dry sample after key release.
  frame(100);frame(100);frame(100);frame(100);
  if(dut.state==0) $fatal(1,"decaying source still waits for voice_active to clear");
  frame(100);frame(100);frame(100);frame(100);
  if(out_left<=24'sd25600) $fatal(1,"repeat did not overlay the dry signal");
  @(negedge clk);rst=1;decaying_source=0;keys=12'd1;
  repeat(2) @(negedge clk);rst=0;
  frame(100);frame(200);frame(300);frame(400);frame(500);frame(600);
  if(dut.recording[0]!==16'sd500 || dut.recording[1]!==16'sd600 ||
     dut.recorded!==4 || dut.write_addr!==2)
    $fatal(1,"other timbre recording changed");
  $display("PASS: piano keeps attack, other timbres retain rolling capture");
  $finish;
 end
endmodule
