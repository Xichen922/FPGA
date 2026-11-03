`timescale 1ns/1ps
// Slave B: A supplies the only sample cadence. Local50MHz is processing/control only.
module latb_example42_top #(
 parameter integer UART_BAUD=115200,BLUETOOTH_BAUD=9600,HMI_STARTUP_CYCLES=50000000,HMI_EXTENSIONS_ENABLE=0,
 parameter integer CLOCK_TIMEOUT_CYCLES=1024,DAC_STARTUP_FRAMES=4096,
 parameter integer ECHO_DIAGNOSTIC=0
)(input wire clk,reset_n,audio_bclk,audio_lrck,audio_din,
 input wire link_cs_n,link_sclk,link_mosi,uart_rx,ultrasonic_echo,bt_rx,
 output wire link_miso,latb_uart_tx,ultrasonic_trig,i2s_bclk,i2s_lrck,i2s_dout,bt_tx,output reg dac_xsmt);
 (* syn_preserve=1 *)reg [1:0] reset_pipe=0;
 always @(posedge clk or negedge reset_n)if(!reset_n)reset_pipe<=0;else reset_pipe<={reset_pipe[0],1'b1};
 reg [15:0] por_count=0;always @(posedge clk)if(!por_count[15])por_count<=por_count+1'b1;
 wire rst=!(por_count[15] && reset_pipe[1]);
 (* syn_preserve=1,async_reg="true" *)reg clock_meta,clock_sync;
 reg previous_clock;reg [15:0] loss_count;reg [4:0] edge_count;
 wire audio_alive=edge_count>=16 && loss_count<CLOCK_TIMEOUT_CYCLES;
 always @(posedge clk)begin
  if(rst)begin clock_meta<=0;clock_sync<=0;previous_clock<=0;loss_count<=CLOCK_TIMEOUT_CYCLES;edge_count<=0;end
  else begin
   clock_meta<=audio_bclk;clock_sync<=clock_meta;previous_clock<=clock_sync;
   if(clock_sync!=previous_clock)begin loss_count<=0;if(edge_count<31)edge_count<=edge_count+1'b1;end
   else if(loss_count<CLOCK_TIMEOUT_CYCLES)loss_count<=loss_count+1'b1;
   else edge_count<=0;
  end
 end
 wire link_arst=rst || !audio_alive;wire audio_rst,proc_rst;
 latb_db_reset_sync u_audio_reset(.clk(audio_bclk),.arst(link_arst),.rst(audio_rst));
 latb_db_reset_sync u_proc_reset(.clk(clk),.arst(link_arst),.rst(proc_rst));
 wire [47:0] received_pair,rx_fifo_data,tx_fifo_data;
 wire received_valid,rx_full,rx_empty,rx_fifo_valid,rx_fifo_read,framing_error;
 reg rx_overflow;
 latb_db_i2s_rx u_rx(.bclk(audio_bclk),.rst(audio_rst),.ws(audio_lrck),.sd(audio_din),.data(received_pair),.valid(received_valid),.framing_error(framing_error));
 always @(posedge audio_bclk or posedge audio_rst)if(audio_rst)rx_overflow<=0;else if(received_valid && rx_full)rx_overflow<=1;
 latb_db_async_fifo #(.WIDTH(48),.ADDR_BITS(4)) u_rx_fifo(
  .wr_clk(audio_bclk),.wr_rst(audio_rst),.wr_en(received_valid),.wr_data(received_pair),.full(rx_full),
  .rd_clk(clk),.rd_rst(proc_rst),.rd_en(rx_fifo_read),.rd_data(rx_fifo_data),.rd_valid(rx_fifo_valid),.empty(rx_empty));
 wire manual_effect_on,effect_on;
 wire [1:0] manual_effect_mode,effect_mode;
 wire [7:0] echo_depth,reverse_depth;
 wire [11:0] keys;wire [3:0] octave;wire [1:0] timbre;
 wire voice_active,vibrato_active,control_link_good,packet_error;
 wire fx_ready;
 // HC-06 has its own 9600 baud UART. It never shares the 115200 baud HMI link.
 wire score_clear,score_append,score_play,score_stop,score_guide;
 wire score_playing,guide_active,score_gate;
 wire [11:0] guide_keys;
 wire [3:0] score_append_note,score_note;
 wire [11:0] score_append_mask,score_key;
 wire score_append_is_mask;
 wire [9:0] score_append_duration;
 wire score_append_octave_enable,score_append_timbre_enable,score_append_effect_enable;
 wire [1:0] score_append_octave_code,score_append_timbre_code,score_append_effect_code;
 wire score_octave_enable,score_timbre_enable,score_effect_enable;
 wire [1:0] score_octave_code,score_timbre_code,score_effect_code;
 wire [9:0] score_count;
 latb_db_score_serial #(.BAUD(BLUETOOTH_BAUD)) u_bluetooth(.clk(clk),.rst(rst),.rx(bt_rx),.tx(bt_tx),
  .score_count(score_count),.playing(score_playing || guide_active),
  .clear_cmd(score_clear),.append_cmd(score_append),.play_cmd(score_play),
  .stop_cmd(score_stop),.guide_cmd(score_guide),
  .append_note(score_append_note),.append_mask(score_append_mask),
  .append_is_mask(score_append_is_mask),.append_duration(score_append_duration),
  .append_octave_enable(score_append_octave_enable),.append_octave_code(score_append_octave_code),
  .append_timbre_enable(score_append_timbre_enable),.append_timbre_code(score_append_timbre_code),
  .append_effect_enable(score_append_effect_enable),.append_effect_code(score_append_effect_code));
 latb_db_score_player u_score(.clk(clk),.rst(rst),.clock_present(audio_alive),
  .physical_keys(keys),.physical_octave(octave),
  .clear_cmd(score_clear),.append_cmd(score_append),.play_cmd(score_play),
  .stop_cmd(score_stop),.guide_cmd(score_guide),
  .append_note(score_append_note),.append_mask(score_append_mask),
  .append_is_mask(score_append_is_mask),.append_duration(score_append_duration),
  .append_octave_enable(score_append_octave_enable),.append_octave_code(score_append_octave_code),
  .append_timbre_enable(score_append_timbre_enable),.append_timbre_code(score_append_timbre_code),
  .append_effect_enable(score_append_effect_enable),.append_effect_code(score_append_effect_code),
  .score_count(score_count),.playing(score_playing),.guiding(guide_active),
  .guide_keys(guide_keys),.current_note(score_note),
  .current_keys(score_key),
  .current_octave_enable(score_octave_enable),.current_octave_code(score_octave_code),
  .current_timbre_enable(score_timbre_enable),.current_timbre_code(score_timbre_code),
  .current_effect_enable(score_effect_enable),.current_effect_code(score_effect_code),
  .note_gate(score_gate));
 wire [11:0] all_keys=keys | score_key;
 wire all_voice_active=voice_active | score_gate;
 // A song's effect selection temporarily overrides the ultrasonic selection.
 // The manual effect state keeps updating and returns when playback stops.
 wire auto_effect_active=score_playing && score_effect_enable;
 assign effect_on=auto_effect_active ? (score_effect_code!=2'd0) : manual_effect_on;
 assign effect_mode=(auto_effect_active && score_effect_code!=2'd0) ?
    score_effect_code : manual_effect_mode;
 wire signed [23:0] fx_left,fx_right;wire fx_valid,fx_input_ready,fx_clipped;
 wire signed [23:0] post_left,post_right;wire post_valid,post_ready;
 wire [7:0] applied_depth;wire [1:0] applied_mode;
 wire tx_full,tx_empty,tx_fifo_valid,tx_fifo_read,tx_primed,tx_underrun;
 reg read_pending;
 assign rx_fifo_read=!proc_rst && !rx_empty && !read_pending && fx_input_ready && !tx_full;
 always @(posedge clk)if(proc_rst)read_pending<=0;else begin if(rx_fifo_read)read_pending<=1;if(rx_fifo_valid)read_pending<=0;end
 // Echo/reverse reuse one long recording.
 // Keep the old wet-effect RAMs only in the separate echo diagnostic build.
 generate if(ECHO_DIAGNOSTIC==0)begin: post_repeat
  assign fx_left=rx_fifo_data[47:24];assign fx_right=rx_fifo_data[23:0];
  assign fx_valid=rx_fifo_valid;assign fx_input_ready=fx_ready;
  assign fx_clipped=1'b0;assign applied_depth=8'd0;assign applied_mode=2'd0;
  latb_db_post_note_repeat u_repeat(.clk(clk),.rst(proc_rst),
   .enable(effect_on && (effect_mode==2'd1 || effect_mode==2'd2)),
   .reverse_mode(effect_mode==2'd2),
   .depth(effect_mode==2'd2 ? reverse_depth : echo_depth),
   .keys(all_keys),.voice_active(all_voice_active),
   .in_left(fx_left),.in_right(fx_right),.in_valid(fx_valid),.in_ready(fx_ready),
   .out_left(post_left),.out_right(post_right),.out_valid(post_valid),.out_ready(post_ready));
 end else begin: diagnostic_bypass
  latb_db_effects #(.DIAGNOSTIC_ECHO_ONLY(1)) u_effects(.clk(clk),.rst(proc_rst),
   .in_valid(rx_fifo_valid),.in_ready(fx_input_ready),
   .in_left(rx_fifo_data[47:24]),.in_right(rx_fifo_data[23:0]),
   .effect_on(effect_on),.effect_mode(effect_mode),
   .echo_depth(echo_depth),.reverb_depth(reverse_depth),.chorus_depth(8'd0),
   .out_left(fx_left),.out_right(fx_right),.out_valid(fx_valid),.out_ready(fx_ready),
   .clipped(fx_clipped),.applied_depth(applied_depth),.applied_mode(applied_mode));
  assign post_left=fx_left;assign post_right=fx_right;
  assign post_valid=fx_valid;assign fx_ready=post_ready;
 end endgenerate
 assign post_ready=!tx_full;
 latb_db_async_fifo #(.WIDTH(48),.ADDR_BITS(4)) u_tx_fifo(
  .wr_clk(clk),.wr_rst(proc_rst),.wr_en(post_valid && post_ready),.wr_data({post_left,post_right}),.full(tx_full),
  .rd_clk(audio_bclk),.rd_rst(audio_rst),.rd_en(tx_fifo_read),.rd_data(tx_fifo_data),.rd_valid(tx_fifo_valid),.empty(tx_empty));
 latb_db_i2s_tx u_tx(.bclk(audio_bclk),.rst(audio_rst),.ws(audio_lrck),.fifo_data(tx_fifo_data),.fifo_valid(tx_fifo_valid),.fifo_empty(tx_empty),
  .fifo_read(tx_fifo_read),.out_ws(i2s_lrck),.out_sd(i2s_dout),.primed(tx_primed),.underrun(tx_underrun));
 assign i2s_bclk=audio_bclk;
 (* syn_preserve=1,async_reg="true" *)reg primed_meta,primed_sync;
 reg [12:0] startup_frames;
 always @(posedge clk)begin
  if(proc_rst)begin primed_meta<=0;primed_sync<=0;startup_frames<=0;dac_xsmt<=0;end
  else begin
   primed_meta<=tx_primed;primed_sync<=primed_meta;
   if(fx_valid && fx_ready && startup_frames<DAC_STARTUP_FRAMES)startup_frames<=startup_frames+1'b1;
   dac_xsmt<=audio_alive && primed_sync && startup_frames>=DAC_STARTUP_FRAMES;
  end
 end
 wire gesture_on;
 latb_ultrasonic_effect_toggle u_gesture(.clk(clk),.rst_n(!rst),.echo_async(ultrasonic_echo),.trig(ultrasonic_trig),.effect_on(gesture_on));
 wire [127:0] outgoing_status,base_status,incoming_status;wire status_valid,spi_error;
 // Keep the old B->A command bytes. Add score mode, octave and timbre in
 // previously unused bits below the 12-bit remote key mask.
 function [7:0] score_checksum;
  input [111:0] payload;
  integer k;
  begin score_checksum=0;for(k=0;k<14;k=k+1)score_checksum=score_checksum^payload[k*8+:8];end
 endfunction
 wire [111:0] score_payload={base_status[127:64],score_key,
    score_playing,score_octave_code,(score_playing && score_octave_enable),
    score_timbre_code,(score_playing && score_timbre_enable),29'd0};
 assign outgoing_status={score_payload,score_checksum(score_payload),8'h5a};
 latb_db_spi_slave u_link(.clk(clk),.rst(rst),.cs_n(link_cs_n),.sclk(link_sclk),.mosi(link_mosi),.tx_packet(outgoing_status),
  .miso(link_miso),.rx_packet(incoming_status),.rx_valid(status_valid),.framing_error(spi_error));
 // Current bitstream uses the original display protocol only. New HMI RX remains opt-in.
 wire [7:0] command_opcode,command_value;wire command_valid;
 generate if(HMI_EXTENSIONS_ENABLE!=0)begin: future_hmi_rx
  wire [7:0] uart_byte;wire uart_valid,uart_error,command_error;
  latb_db_uart_rx #(.BAUD(UART_BAUD)) u_hmi_rx(.clk(clk),.rst(rst),.rx(uart_rx),.data(uart_byte),.valid(uart_valid),.framing_error(uart_error));
  latb_db_hmi_commands u_commands(.clk(clk),.rst(rst),.byte_valid(uart_valid),.byte_data(uart_byte),.valid(command_valid),.opcode(command_opcode),.value(command_value),.checksum_error(command_error));
 end else begin: current_hmi_rx
  assign command_valid=1'b0;assign command_opcode=8'd0;assign command_value=8'd0;
 end endgenerate
 latb_db_slave_controls u_controls(.clk(clk),.rst(rst),.audio_link_alive(audio_alive),.gesture_on(gesture_on),
  .rx_packet(incoming_status),.rx_valid(status_valid),.command_valid(command_valid),.opcode(command_opcode),.value(command_value),
  .tx_packet(base_status),.keys(keys),.octave(octave),.timbre(timbre),.voice_active(voice_active),.vibrato_active(vibrato_active),
  .effect_mode(manual_effect_mode),.effect_on(manual_effect_on),.echo_depth(echo_depth),.reverse_depth(reverse_depth),.link_good(control_link_good),.packet_error(packet_error));
 // Contest 3 HMI uses 115200 baud and reports the current effect depth.
 localparam [17:0] DISPLAY_TAIL_FRAMES=(ECHO_DIAGNOSTIC!=0) ? 18'd78129 : 18'd235000;
 reg [17:0] display_tail_frames;
 always @(posedge clk)begin
  if(proc_rst)display_tail_frames<=0;
  else if(rx_fifo_valid)begin
   if(all_voice_active && effect_on && (effect_mode==2'd1 || effect_mode==2'd2))display_tail_frames<=DISPLAY_TAIL_FRAMES;
   else if(display_tail_frames!=0)display_tail_frames<=display_tail_frames-1'b1;
  end
 end
 wire display_active=all_voice_active || (effect_on && (effect_mode==2'd1 || effect_mode==2'd2) && display_tail_frames!=0);
 wire [7:0] display_depth=effect_on ?
    ((effect_mode==2'd2) ? reverse_depth : echo_depth) : 8'd0;
 // During practice, t13 shows the score's required octave when specified.
 wire [3:0] guide_display_octave=(guide_active && score_octave_enable) ?
    ({2'b00,score_octave_code}+4'd3) : octave;
 // Observe only samples actually accepted for the DAC. The scope never
 // drives post_ready, so a slow screen cannot delay the audio path.
 wire scope_ready,scope_ack;wire [6:0] scope_address;wire [7:0] scope_data;
 latb_db_scope u_scope(.clk(clk),.rst(proc_rst),.sample_valid(post_valid && post_ready),
  .sample(post_left),.octave(octave),.keys(all_keys),.address(scope_address),.data(scope_data),
  .ready(scope_ready),.acknowledge(scope_ack));
 generate if(HMI_EXTENSIONS_ENABLE==0)begin: current_display
  latb_tjc_display_uart #(.BAUD(UART_BAUD),.STARTUP_CYCLES(HMI_STARTUP_CYCLES)) u_display(
   .clk(clk),.rst_n(!rst),.keys(all_keys),.guide_active(guide_active),
   .guide_keys(guide_keys),.timbre(timbre),.effect_mode(effect_on?effect_mode:2'd0),
   .effect_depth(display_depth),.octave(guide_display_octave),.sound_active(display_active),
   .wave_ready(scope_ready),.wave_data(scope_data),.wave_address(scope_address),
   .wave_ack(scope_ack),.tx(latb_uart_tx));
 end else begin: future_display
  wire [7:0] selected_depth=effect_mode==2?reverse_depth:echo_depth;
  latb_db_hmi_tx #(.BAUD(UART_BAUD),.STARTUP_CYCLES(HMI_STARTUP_CYCLES)) u_display(
   .clk(clk),.rst_n(!rst),.keys(all_keys),.timbre(timbre),.effect_mode(effect_on?effect_mode:2'd0),.octave(octave),.sound_active(all_voice_active),
   .vibrato_active(vibrato_active),.effect_depth(selected_depth),.wave_ready(scope_ready),.wave_data(scope_data),.wave_address(scope_address),.wave_ack(scope_ack),.tx(latb_uart_tx));
 end endgenerate
endmodule



