`timescale 1ns/1ps
module ref51_db_master_controls #(parameter integer TIMEOUT_CYCLES=5000000)(input wire clk,rst,input wire [15:0] keys,input wire [3:0] octave,
 input wire [1:0] timbre,input wire any_active,input wire [11:0] active_voices,
 input wire signed [7:0] encoder_delta,input wire encoder_valid,
 input wire [127:0] rx_packet,input wire rx_valid,output wire [127:0] tx_packet,
 output reg vibrato_enable,output reg link_good,output reg [11:0] remote_keys,
 output reg remote_octave_enable,output reg [3:0] remote_octave,
 output reg remote_timbre_enable,output reg [1:0] remote_timbre);
 function [7:0] checksum(input [111:0] p);integer i;begin checksum=0;for(i=0;i<14;i=i+1)checksum=checksum^p[i*8+:8];end endfunction
 reg [15:0] encoder_total;reg [7:0] seq,last_command;reg command_seen;localparam integer WATCHDOG_BITS=(TIMEOUT_CYCLES<2) ? 1 : $clog2(TIMEOUT_CYCLES+1);
 reg [WATCHDOG_BITS-1:0] watchdog;
 // A41 -> B44 status layout stays backward-compatible: [99:88] note keys,
 // [83:80] effective octave, [85:84] current timbre, [86] voice activity.
 // Guide target and 50 ms matching belong to B44, not this transmitter.
 wire [111:0] payload={8'ha5,8'h31,seq,keys,{vibrato_enable,any_active,timbre,octave},encoder_total,{4'd0,active_voices},last_command,7'd0,command_seen,16'd0};
 assign tx_packet={payload,checksum(payload),8'h5a};
 wire good=rx_packet[127:112]==16'hb632 && rx_packet[7:0]==8'h5a && rx_packet[15:8]==checksum(rx_packet[127:16]);
 always @(posedge clk)begin
  if(rst)begin encoder_total<=0;seq<=0;last_command<=0;command_seen<=0;vibrato_enable<=0;watchdog<=0;link_good<=0;remote_keys<=0;remote_octave_enable<=0;remote_octave<=4;remote_timbre_enable<=0;remote_timbre<=0;end
  else begin
   if(encoder_valid)encoder_total<=encoder_total+{{8{encoder_delta[7]}},encoder_delta};
   if(watchdog<TIMEOUT_CYCLES)watchdog<=watchdog+1'b1;
   else begin link_good<=0;remote_keys<=0;remote_octave_enable<=0;remote_octave<=4;remote_timbre_enable<=0;remote_timbre<=0;end
   if(rx_valid)begin
    seq<=seq+1'b1;
    if(good)begin watchdog<=0;link_good<=1;remote_keys<=rx_packet[63:52];
     // Controls are snapshots, independent of the existing command-sequence ACK.
     // Keep keys even when score_mode=0 for compatibility with the original B38.
     remote_octave_enable<=rx_packet[51] && rx_packet[48] && rx_packet[50:49]!=2'd3;
     case(rx_packet[50:49])
      0:remote_octave<=4'd3;1:remote_octave<=4'd4;
      2:remote_octave<=4'd5;default:remote_octave<=4'd4;
     endcase
     remote_timbre_enable<=rx_packet[51] && rx_packet[45];
     remote_timbre<=rx_packet[47:46];
     if(rx_packet[88] && (!command_seen || rx_packet[111:104]!=last_command))begin
      vibrato_enable<=rx_packet[96];last_command<=rx_packet[111:104];command_seen<=1;
     end
    end
   end
  end
 end
endmodule
