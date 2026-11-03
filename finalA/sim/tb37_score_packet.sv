`timescale 1ns/1ps
module tb37_score_packet;
 reg clk=0,rst=1,valid=0;always #10 clk=~clk;
 reg [127:0] rx=0;wire [127:0] tx;wire link,vib,oe,te;wire [11:0] keys;wire [3:0] octave;wire [1:0] timbre;
 db_master_controls #(.TIMEOUT_CYCLES(40)) dut(.clk(clk),.rst(rst),.keys(16'd0),.octave(4'd4),.timbre(2'd0),
 .any_active(1'b0),.active_voices(12'd0),.encoder_delta(8'd0),.encoder_valid(1'b0),
 .rx_packet(rx),.rx_valid(valid),.tx_packet(tx),.vibrato_enable(vib),.link_good(link),.remote_keys(keys),
 .remote_octave_enable(oe),.remote_octave(octave),.remote_timbre_enable(te),.remote_timbre(timbre));
 function [127:0] packet(input [11:0] k,input mode,input [1:0] o,input en_o,input [1:0] t,input en_t);
 reg [127:0] p;reg [7:0] x;integer i;begin
 p=0;p[127:112]=16'hb632;p[111:104]=8'd7;p[96]=1;p[88]=1;
 p[63:52]=k;p[51]=mode;p[50:49]=o;p[48]=en_o;p[47:46]=t;p[45]=en_t;p[7:0]=8'h5a;
 x=0;for(i=2;i<16;i=i+1)x=x^p[i*8+:8];p[15:8]=x;packet=p;end endfunction
 task send(input [127:0] p);begin @(negedge clk);rx=p;valid=1;@(negedge clk);valid=0;end endtask
 integer o,t,i;reg [127:0] p;reg [19:0] snapshot;
 initial begin
 repeat(3)@(negedge clk);rst=0;
 if({keys,oe,te}!==0)$fatal(1,"reset");
 for(o=0;o<3;o=o+1)for(t=0;t<4;t=t+1)begin
 send(packet(12'h841,1,o,1,t,1));
 if(!link || !oe || !te || octave!==o+3 || timbre!==t || keys!==12'h841)$fatal(1,"control mapping %d %d",o,t);
 end
 if(!vib)$fatal(1,"existing vibrato command lost");
 snapshot={keys,oe,octave,te,timbre};
 for(i=0;i<3;i=i+1)begin
 p=packet(12'h123,1,0,1,0,1);
 case(i)0:p[127]=~p[127];1:p[0]=~p[0];2:p[8]=~p[8];endcase
 send(p);if({keys,oe,octave,te,timbre}!==snapshot)$fatal(1,"bad packet partially updated fields");
 end
 send(packet(12'h123,1,3,1,2,1));if(oe || !te || timbre!=2)$fatal(1,"reserved octave must disable only octave");
 send(packet(12'h111,1,0,0,1,0));if(oe || te)$fatal(1,"disabled overrides");
 send(packet(12'h222,0,2,1,3,1));if(oe || te || keys!=12'h222)$fatal(1,"legacy mode0 note compatibility");
 send(packet(0,0,0,0,0,0));if(keys || oe || te)$fatal(1,"stop");
 send(packet(12'hfff,1,2,1,3,1));
 repeat(25)send(0);
 if(link || keys || oe || te)$fatal(1,"timeout must revoke controls under invalid traffic");
 send(packet(1,1,1,1,0,1));if(!link || !oe || !te || octave!=4)$fatal(1,"recovery");
 @(negedge clk);rst=1;@(negedge clk);if(keys || oe || te)$fatal(1,"reset held automation");
 $display("PASS score packet:12 octave/timbre combos,atomic header/footer/XOR,legacy keys,reserved octave,override masks,stop,timeout,recovery,existing command");$finish;
 end
endmodule

