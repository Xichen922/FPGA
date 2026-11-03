`timescale 1ns/1ps
module db_slave_controls(input wire clk,rst,audio_link_alive,input wire gesture_on,
 input wire [127:0] rx_packet,input wire rx_valid,
 input wire command_valid,input wire [7:0] opcode,value,
 output wire [127:0] tx_packet,output reg [11:0] keys,output reg [3:0] octave,
 output reg [1:0] timbre,output reg voice_active,vibrato_active,
 output reg [1:0] effect_mode,output reg effect_on,
 output reg [7:0] echo_depth,reverse_depth,output reg link_good,output reg packet_error);
 function [7:0] checksum(input [111:0] p);integer i;begin checksum=0;for(i=0;i<14;i=i+1)checksum=checksum^p[i*8+:8];end endfunction
 function [7:0] clamp_depth(input signed [19:0] p);begin clamp_depth=p<0?0:p>128?128:p[7:0];end endfunction
 reg [15:0] previous_encoder;reg encoder_seen,previous_gesture,command_pending,command_target;
 reg [7:0] command_seq,remote_ack;reg [22:0] watchdog;
 wire [7:0] current_depth=effect_mode==2?reverse_depth:echo_depth;
 wire signed [15:0] detents=rx_packet[79:64]-previous_encoder;
 wire signed [19:0] proposed_depth=$signed({12'd0,current_depth})+($signed({{4{detents[15]}},detents})<<<2);
 wire [111:0] payload={8'hb6,8'h32,command_seq,7'd0,command_target,7'd0,command_pending,6'd0,effect_mode,7'd0,effect_on,current_depth,48'd0};
 assign tx_packet={payload,checksum(payload),8'h5a};
 wire good=rx_packet[127:112]==16'ha531 && rx_packet[7:0]==8'h5a && rx_packet[15:8]==checksum(rx_packet[127:16]);
 always @(posedge clk)begin
  if(rst)begin keys<=0;octave<=4;timbre<=0;voice_active<=0;vibrato_active<=0;effect_mode<=1;effect_on<=0;
   echo_depth<=88;reverse_depth<=96;previous_encoder<=0;encoder_seen<=0;previous_gesture<=0;
   command_seq<=0;command_pending<=0;command_target<=0;remote_ack<=0;watchdog<=0;link_good<=0;packet_error<=0;end
  else begin
   previous_gesture<=gesture_on;
   // The gesture detector changes level once per full hand wave. Every edge
   // The sequence is natural -> echo -> reverse -> natural.
   if(previous_gesture!=gesture_on)begin
    if(!effect_on)begin effect_on<=1;effect_mode<=1;end
    else if(effect_mode==1)effect_mode<=2;
    else begin effect_on<=0;effect_mode<=1;end
   end
   if(!audio_link_alive)encoder_seen<=0;
   if(watchdog<23'd5000000)watchdog<=watchdog+1'b1;else begin link_good<=0;encoder_seen<=0;end
   if(rx_valid)begin
    if(good)begin
     watchdog<=0;link_good<=1;keys<=rx_packet[99:88];octave<=rx_packet[83:80];timbre<=rx_packet[85:84];voice_active<=rx_packet[86];vibrato_active<=rx_packet[87];
     remote_ack<=rx_packet[47:40];
     if(command_pending && rx_packet[32] && rx_packet[47:40]==command_seq)command_pending<=0;
     previous_encoder<=rx_packet[79:64];
     if(audio_link_alive)begin
      encoder_seen<=1;
      if(encoder_seen && detents!=0)case(effect_mode)
       1:echo_depth<=clamp_depth(proposed_depth);2:reverse_depth<=clamp_depth(proposed_depth);
      endcase
     end
    end else if(link_good)packet_error<=1;
   end
   if(command_valid)case(opcode)
    1:if(value<=1)begin command_target<=value[0];command_seq<=command_pending?command_seq+1'b1:remote_ack+1'b1;command_pending<=1;end
    2:if(value>=1 && value<=2)effect_mode<=value[1:0];
    3:if(value<=1)effect_on<=value[0];
    4:if(value<=128)case(effect_mode)1:echo_depth<=value;2:reverse_depth<=value;endcase
   endcase
  end
 end
endmodule
