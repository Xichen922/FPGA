`timescale 1ns/1ps
module tb37_timbre_restore;
 reg clk=0,rst=1,tick=0,kv=0,ls=0,re=0;
 reg [15:0] keys=0;reg [1:0] light=0,remote=0;
 wire [1:0] requested,active;wire [8:0] gain;
 always #10 clk=~clk;
 timbre_control #(.REMOTE_CONTROL_ENABLE(1)) dut(.clk(clk),.rst(rst),.sample_tick(tick),.key_valid(kv),.key_mask(keys),
 .light_select(ls),.light_timbre(light),.remote_timbre_enable(re),.remote_timbre(remote),
 .requested_timbre(requested),.active_timbre(active),.gain(gain));
 reg [1:0] prev_active=0;reg [8:0] prev_gain=0;integer changes=0;
 always @(posedge clk)if(!rst)begin
 #1;if(active!=prev_active)begin if(gain!=0 || prev_gain!=0)$fatal(1,"timbre changed before zero");changes=changes+1;end
 if(gain>256)$fatal(1,"gain range");
 prev_active=active;prev_gain=gain;end
 task key(input [3:0] k);begin @(negedge clk);keys={k,12'd0};kv=1;@(negedge clk);kv=0;end endtask
 task settle(input [1:0] t);integer n;begin
 n=0;while(active!=t || gain!=256)begin @(negedge clk);n=n+1;if(n>530)$fatal(1,"transition timeout");end end endtask
 integer t;
 initial begin
 repeat(3)@(negedge clk);rst=0;tick=1;
 key(4'b0100);key(0);settle(2);
 re=1;remote=3;settle(3);
 key(4'b0010);key(0);
 if(dut.manual_requested_timbre!=1 || requested!=3)$fatal(1,"manual key must update behind remote");
 @(negedge clk);ls=1;light=0;@(negedge clk);ls=0;
 if(dut.manual_requested_timbre!=0 || requested!=3)$fatal(1,"light must update behind remote");
 // New local key keeps its former priority over a simultaneous light event.
 @(negedge clk);ls=1;light=1;keys=16'h4000;kv=1;
 @(negedge clk);ls=0;kv=0;key(0);
 if(dut.manual_requested_timbre!=2 || requested!=3)$fatal(1,"local/light priority");
 for(t=0;t<4;t=t+1)begin @(negedge clk);remote=t;settle(t);end
 @(negedge clk);re=0;settle(2);
 // Reverse the requested transition while fading; use the same zero-crossing rule.
 @(negedge clk);re=1;remote=0;repeat(40)@(negedge clk);
 remote=1;settle(1);@(negedge clk);re=0;settle(2);
 $display("PASS timbre restore:all4 remote targets,background keys/light,manual priority,stop restore,reversed transition,%0d switches only at zero gain",changes);$finish;
 end
endmodule

