`timescale 1ns/1ps
// Real A41 matrix/status/SPI and B44 UART/decoder/player modules.
// B player's millisecond divider is accelerated 500x; its 50-tick match
// requirement is unchanged. This is a control-path test, not audio simulation.
module tb_a41_b44_guide;
 reg clk=0,rst=1,bt_rx=1;always #10 clk=~clk;
 reg [15:0] held=0;reg [9:0] joystick_y=512;
 wire [3:0] row,logical_col;
 assign logical_col=(row[0]?held[3:0]:4'd0)|(row[1]?held[7:4]:4'd0)|
                    (row[2]?held[11:8]:4'd0)|(row[3]?held[15:12]:4'd0);
 wire [15:0] local_keys;wire local_valid;
 keyboard_matrix_scan #(.ROW_CYCLES(16)) matrix(.clk(clk),.rst_n(!rst),
  .kb_row(row),.kb_col({logical_col[0],logical_col[1],logical_col[2],logical_col[3]}),
  .key_mask(local_keys),.key_valid(local_valid),.raw_mask());
 wire [3:0] manual_octave,selected_octave,remote_octave;
 joystick_octave joy(.clk(clk),.rst(rst),.adc_value(joystick_y),
  .snapshot_valid(1'b1),.octave(manual_octave));
 wire [11:0] remote_keys;wire remote_octave_enable,remote_timbre_enable,link_good;
 wire [1:0] remote_timbre;
 reg [11:0] previous_remote=0;
 always @(posedge clk)if(rst)previous_remote<=0;else previous_remote<=remote_keys;
 wire [15:0] performed={local_keys[15:12],local_keys[11:0]|remote_keys};
 assign selected_octave=remote_octave_enable?remote_octave:manual_octave;
 wire [11:0] notes,presses;wire [47:0] octaves;
 touch_note_control note_ctrl(.clk(clk),.rst(rst),.key_mask(performed),
  .key_valid(local_valid|(previous_remote!=remote_keys)),.selected_octave(selected_octave),
  .note_gate(notes),.note_press(presses),.note_octaves(octaves),
  .control_valid(),.octave(),.hold_enabled());
 wire [127:0] a_tx,a_rx,b_tx,b_rx,base_status;wire a_valid,b_valid;
 wire cs,sck,mosi,miso;
 db_master_controls a_status(.clk(clk),.rst(rst),.keys(performed),.octave(selected_octave),
  .timbre(2'd0),.any_active(|notes),.active_voices(notes),
  .encoder_delta(8'd0),.encoder_valid(1'b0),.rx_packet(a_rx),.rx_valid(a_valid),
  .tx_packet(a_tx),.vibrato_enable(),.link_good(link_good),.remote_keys(remote_keys),
  .remote_octave_enable(remote_octave_enable),.remote_octave(remote_octave),
  .remote_timbre_enable(remote_timbre_enable),.remote_timbre(remote_timbre));
 db_spi_master #(.HALF_CYCLES(8),.POLL_CYCLES(5000)) a_spi(.clk(clk),.rst(rst),
  .tx_packet(a_tx),.miso(miso),.cs_n(cs),.sclk(sck),.mosi(mosi),.rx_packet(a_rx),.rx_valid(a_valid));
 db_spi_slave b_spi(.clk(clk),.rst(rst),.cs_n(cs),.sclk(sck),.mosi(mosi),
  .tx_packet(b_tx),.miso(miso),.rx_packet(b_rx),.rx_valid(b_valid),.framing_error());
 wire [11:0] b_keys;wire [3:0] b_octave;
 db_slave_controls b_status(.clk(clk),.rst(rst),.audio_link_alive(1'b1),.gesture_on(1'b0),
  .rx_packet(b_rx),.rx_valid(b_valid),.command_valid(1'b0),.opcode(8'd0),.value(8'd0),
  .tx_packet(base_status),.keys(b_keys),.octave(b_octave),.timbre(),.voice_active(),
  .vibrato_active(),.effect_mode(),.effect_on(),.echo_depth(),.reverse_depth(),
  .link_good(),.packet_error());
 wire clear_cmd,append_cmd,play_cmd,stop_cmd,guide_cmd,playing,guiding;
 wire [9:0] count,duration;wire [11:0] append_mask,score_keys,guide_keys;
 wire [3:0] append_note;wire is_mask,ao_en,at_en,ae_en,score_oe,score_te;
 wire [1:0] ao,at,ae,score_o,score_t;
 db_score_serial #(.BAUD(500000)) serial(.clk(clk),.rst(rst),.rx(bt_rx),.tx(),
  .score_count(count),.playing(playing|guiding),.clear_cmd(clear_cmd),.append_cmd(append_cmd),
  .play_cmd(play_cmd),.stop_cmd(stop_cmd),.guide_cmd(guide_cmd),.append_note(append_note),
  .append_mask(append_mask),.append_is_mask(is_mask),.append_duration(duration),
  .append_octave_enable(ao_en),.append_octave_code(ao),.append_timbre_enable(at_en),
  .append_timbre_code(at),.append_effect_enable(ae_en),.append_effect_code(ae));
 db_score_player #(.CLK_HZ(100000)) player(.clk(clk),.rst(rst),.clock_present(1'b1),
  .physical_keys(b_keys),.physical_octave(b_octave),.clear_cmd(clear_cmd),.append_cmd(append_cmd),
  .play_cmd(play_cmd),.stop_cmd(stop_cmd),.guide_cmd(guide_cmd),.append_note(append_note),
  .append_mask(append_mask),.append_is_mask(is_mask),.append_duration(duration),
  .append_octave_enable(ao_en),.append_octave_code(ao),.append_timbre_enable(at_en),
  .append_timbre_code(at),.append_effect_enable(ae_en),.append_effect_code(ae),
  .score_count(count),.playing(playing),.guiding(guiding),.guide_keys(guide_keys),
  .current_note(),.current_keys(score_keys),.current_octave_enable(score_oe),
  .current_octave_code(score_o),.current_timbre_enable(score_te),.current_timbre_code(score_t),
  .current_effect_enable(),.current_effect_code(),.note_gate());
 function [7:0] checksum(input [111:0] p);integer i;
  begin checksum=0;for(i=0;i<14;i=i+1)checksum=checksum^p[i*8+:8];end
 endfunction
 wire [111:0] payload={base_status[127:64],score_keys,playing,score_o,
                      (playing&&score_oe),score_t,(playing&&score_te),29'd0};
 assign b_tx={payload,checksum(payload),8'h5a};
 task byte_send(input [7:0] data);integer i;begin
  @(negedge clk);bt_rx=0;repeat(100)@(negedge clk);
  for(i=0;i<8;i=i+1)begin bt_rx=data[i];repeat(100)@(negedge clk);end
  bt_rx=1;repeat(100)@(negedge clk);
 end endtask
 task line_send(input string text);integer i;begin
  for(i=0;i<text.len();i=i+1)byte_send(text[i]);byte_send(10);
 end endtask
 always @(posedge clk)if(!rst && guiding)begin
  if(score_keys!==0 || playing || remote_octave_enable || remote_timbre_enable)
   $fatal(1,"guide injected auto keys or overrides");
 end
 initial begin
  repeat(20)@(negedge clk);rst=0;wait(link_good);$display("STAGE link good");
  line_send("C");line_send("M001,999,4,-,-");line_send("M000,999,4,-,-");
  line_send("M004,999,5,-,-");if(count!=3)$fatal(1,"upload failed");
  line_send("G");wait(guiding && guide_keys==1);$display("STAGE guide entered");#50000;
  if(notes!=0 || remote_keys!=0)$fatal(1,"guide made sound without physical key");
  held=3;#300000;if(guide_keys!=1)$fatal(1,"extra wrong key advanced guide");
  held=1;wait(guide_keys==0);$display("STAGE release target");#200000;
  if(player.index!=1)$fatal(1,"rest advanced while key held");
  held=0;wait(guide_keys==4);$display("STAGE last target");held=4;#300000;
  if(!guiding || b_octave!=4)$fatal(1,"wrong octave advanced guide");
  joystick_y=900;wait(!guiding);$display("STAGE guide finished");
  if(b_octave!=5 || b_keys!=4)$fatal(1,"physical octave/key feedback mismatch");
  held=0;#50000;joystick_y=512;
  // Go back to guide; S cancels. P must then send normal automatic notes.
  line_send("G");wait(guiding);line_send("S");#50000;
  if(guiding || playing)$fatal(1,"stop failed");
  line_send("P");wait(remote_keys==1);wait(notes==1);
  if(!playing || guiding || !remote_octave_enable)$fatal(1,"normal playback regressed");
  line_send("S");wait(remote_keys==0);#50000;if(notes!=0)$fatal(1,"stop stuck note");
  $display("PASS A41+B44 real control chain: reversed matrix -> SPI -> physical key/octave feedback -> guide, extra-key rejection, release entry, wrong octave, no auto sound/overrides, G/S/P transitions, original automatic playback");
  $finish;
 end
 initial begin #20000000;$fatal(1,"timeout keys=%h target=%h state=%d",b_keys,guide_keys,player.state);end
endmodule
