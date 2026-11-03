`timescale 1ns/1ps
module tb_piano_i2s;
 reg clk=0,reset_n=0;always #10 clk=~clk;
 reg [15:0] held=0;reg [9:0] y=100;wire [3:0] rows;
 wire [3:0] cols=(rows[0]?held[3:0]:4'd0)|(rows[1]?held[7:4]:4'd0)|
                  (rows[2]?held[11:8]:4'd0)|(rows[3]?held[15:12]:4'd0);
 finalA_top #(.KEYBOARD_ROW_CYCLES(16),.FILL_LIGHT_ENABLE(0)) a(
  .clk(clk),.reset_n(reset_n),.touch_sdo(1'b1),.kb_row(rows),.kb_col({cols[0],cols[1],cols[2],cols[3]}),
  .mcp_miso(1'b0),.encoder_s1(1'b1),.encoder_s2(1'b1),.link_miso(1'b0));
 integer frames=0,nonzero=0;
 always @(posedge clk)if(!a.rst)begin
  if(a.frame_tick)frames=frames+1;
  if(a.underrun)$fatal(1,"actual I2S underrun");
  if(a.pcm_ready)begin
   if(!a.pcm_valid)$fatal(1,"PCM missed actual I2S capture edge");
   if(a.pcm_left!=0)nonzero=nonzero+1;
  end
 end
 initial begin
  force a.por_count=16'h8000;
  force a.adc_ch0=10'd512;force a.adc_ch1=y;force a.adc_valid=1'b1;
  #300;reset_n=1;wait(frames==5);held=16'hfff;
  wait(frames==70);y=900;wait(frames==100);held=0;
  wait(frames==130);held=16'h555;wait(frames==160);held=0;
  wait(frames==170);held=16'hfff;wait(frames==240);
  if(nonzero<180)$fatal(1,"actual piano path silent");
  $display("PASS actual A top + C4321 matrix + PCM/I2S at50MHz: %0d frames, %0d nonzero captured frames, no underrun; held-note octave change, release/restrike,12-note chords",frames,nonzero);
  $finish;
 end
 initial begin #10000000;$fatal(1,"timeout");end
endmodule
