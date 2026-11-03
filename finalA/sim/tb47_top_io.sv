`timescale 1ns/1ps
module tb47_top_io;
 reg clk=0,reset_n=0,sdo=1;always #10 clk=~clk;
 reg [15:0] pad=0,serial_frame=0,held=0;
 reg [9:0] sensor=0;wire scl,led;wire [3:0] rows;
 wire [3:0] cols=(rows[0]?held[3:0]:4'd0)|(rows[1]?held[7:4]:4'd0)|
                  (rows[2]?held[11:8]:4'd0)|(rows[3]?held[15:12]:4'd0);
 finalA_top #(.KEYBOARD_ROW_CYCLES(16),.TOUCH_STARTUP_CYCLES(16),
 .TOUCH_GAP_CYCLES(500),.TOUCH_SCL_HZ(500000),
 .LIGHT_DARK_CONFIRM(3),.LIGHT_BRIGHT_CONFIRM(4),.LIGHT_MIN_HOLD(2)) a(
 .clk(clk),.reset_n(reset_n),.touch_sdo(sdo),.touch_scl(scl),.led_fill_en(led),
 .kb_row(rows),.kb_col({cols[0],cols[1],cols[2],cols[3]}),
 .mcp_miso(1'b0),.encoder_s1(1'b1),.encoder_s2(1'b1),.link_miso(1'b0));
 integer bit_index=0,serial_reads=0;time last_edge=0;
 // External active-low TTP229-BSF serial model. Start-of-frame is detected
 // from the inter-frame SCL idle gap, never by reading driver internals.
 always @(negedge scl) if(reset_n)begin
  if($time-last_edge>4000)begin bit_index=0;serial_frame=pad;serial_reads=serial_reads+1;end
  else bit_index=bit_index+1;
  if(bit_index>15)$fatal(1,"too many TTP clocks");
  sdo<=~serial_frame[bit_index];last_edge=$time;
 end
 integer frames=0;
 always @(posedge clk)if(!a.rst)begin
  if(a.frame_tick)frames=frames+1;
  if(a.underrun)$fatal(1,"I2S underrun with new controls");
  if(a.u_instrument.note_gate!=0 || a.u_instrument.note_press!=0)$fatal(1,"TTP timbre pad triggered musical note");
 end
 task settle(input [1:0] target);integer n;begin
  n=0;while(a.current_timbre!=target || a.u_instrument.u_timbre.gain!=256)begin
   @(negedge clk);n=n+1;if(n>300000)$fatal(1,"actual top timbre timeout target=%0d actual=%0d",target,a.current_timbre);
  end
 end endtask
 task read_pad(input [15:0] mask);integer read_start;begin
  @(negedge clk);pad=mask;read_start=serial_reads;
  wait(serial_reads>=read_start+2);repeat(1700)@(negedge clk);
 end endtask
 initial begin
  force a.por_count=16'h8000;
  force a.adc_ch0=10'd512;force a.adc_ch1=10'd512;
  force a.adc_ch4=sensor;force a.adc_valid=a.frame_tick;
  #300;reset_n=1;repeat(100)@(negedge clk);
  read_pad(16'h00cc);settle(1);
  if(led)$fatal(1,"bright sensor lit lamp");
  sensor=1023;repeat(3000)@(negedge clk);if(!led)$fatal(1,"top DO not connected to output");
  if(a.current_timbre!=1)$fatal(1,"light still switches timbre");
  read_pad(16'h0101);if(a.current_timbre!=1)$fatal(1,"cross-zone ambiguity changed sound");
  read_pad(16'h3300);settle(2);
  // Existing MX key13 remains usable while the TTP region is held.
  held=16'h1000;repeat(1000)@(negedge clk);held=0;settle(0);
  repeat(4000)@(negedge clk);if(a.current_timbre!=0)$fatal(1,"held TTP repeatedly overrode mechanical key");
  force a.remote_timbre_enable=1'b1;force a.remote_timbre=2'd3;settle(3);
  read_pad(0);read_pad(16'h0033);
  if(a.current_timbre!=3)$fatal(1,"TTP stole score override");
  force a.remote_timbre_enable=1'b0;settle(0);
  sensor=0;repeat(5000)@(negedge clk);if(led)$fatal(1,"top lamp did not turn off");
  $display("PASS actual47 top: external serial TTP229 -> four-zone events -> manual/score fade/restore; existing matrix13 still works; no false notes; CH4->lamp only; %0d actual I2S frames without underrun (accelerated sensor/touch timing)",frames);$finish;
 end
 initial begin #50000000;$fatal(1,"top IO timeout");end
endmodule
