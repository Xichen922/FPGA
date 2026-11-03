`timescale 1ns/1ps
module tb53_end_latency;
 reg clk=0,reset_n=0;always #10 clk=~clk;
 reg [15:0] held=0;wire [3:0] rows;
 wire [3:0] cols=(rows[0]?held[3:0]:4'd0)|(rows[1]?held[7:4]:4'd0)|(rows[2]?held[11:8]:4'd0)|(rows[3]?held[15:12]:4'd0);
 wire bc,ws,sd,bws,bsd;
 finalA_top a(.clk(clk),.reset_n(reset_n),.kb_row(rows),.kb_col({cols[0],cols[1],cols[2],cols[3]}),.touch_sdo(1'b1),
 .mcp_miso(1'b0),.encoder_s1(1'b1),.encoder_s2(1'b1),.link_miso(1'b0),.i2s_bclk(bc),.i2s_lrck(ws),.i2s_dout(sd));
 latb_example42_top #(.DAC_STARTUP_FRAMES(16)) b(.clk(clk),.reset_n(reset_n),.audio_bclk(bc),.audio_lrck(ws),.audio_din(sd),
 .link_cs_n(1'b1),.link_sclk(1'b0),.link_mosi(1'b0),.uart_rx(1'b1),.ultrasonic_echo(1'b0),.bt_rx(1'b1),.i2s_lrck(bws),.i2s_dout(bsd));
 wire [47:0] captured;wire captured_valid;
 latb_db_i2s_rx monitor(.bclk(bc),.rst(b.audio_rst),.ws(bws),.sd(bsd),.data(captured),.valid(captured_valid),.framing_error());
 time start_at=0,mask_at=0,trigger_at=0,pcm_at=0,rx_at=0,post_at=0,out_at=0;
 always @(posedge clk)begin #1;
  if(start_at && !mask_at && a.touch_keys!=0)mask_at=$time;
  if(start_at && !trigger_at && a.u_instrument.voice_trigger!=0)trigger_at=$time;
  if(start_at && !pcm_at && a.pcm_valid && a.pcm_left!=0)pcm_at=$time;
  if(start_at && !post_at && b.post_valid && b.post_left!=0)post_at=$time;
 end
 always @(posedge bc)begin #1;
  if(start_at && !rx_at && b.received_valid && b.received_pair!=0)rx_at=$time;
  if(start_at && !out_at && captured_valid && captured!=0)out_at=$time;
 end
 initial begin
  force a.por_count=16'h8000;force b.por_count=16'h8000;
  force a.adc_ch0=10'd512;force a.adc_ch1=10'd512;force a.adc_valid=1'b1;
  #300;reset_n=1;wait(b.dac_xsmt);repeat(100)@(posedge a.frame_tick);
  @(negedge rows[0]);#100;held=16'h0001;start_at=$time;
  wait(out_at!=0);
  if(out_at-start_at>3500000)$fatal(1,"digital onset exceeds3.5ms");
  $display("PASS steady-state actual A53+B44 RTL path (ns): contact_to_mask=%0d mask_to_trigger=%0d trigger_to_first_nonzero_PCM=%0d PCM_to_B_rx_pair=%0d B_rx_to_post=%0d post_to_DAC_I2S_pair=%0d contact_to_DAC_I2S_pair=%0d",mask_at-start_at,trigger_at-mask_at,pcm_at-trigger_at,rx_at-pcm_at,post_at-rx_at,out_at-post_at,out_at-start_at);
  $finish;
 end
 initial begin #15000000;$fatal(1,"latency timeout");end
endmodule


