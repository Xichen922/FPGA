`timescale 1ns/1ps
module tb47_touch;
 reg clk=0,rst=1,kv=0; always #10 clk=~clk;
 reg [15:0] keys=0; wire event_valid; wire [1:0] choice;
 touch_timbre_zones zones(.clk(clk),.rst(rst),.key_valid(kv),.key_mask(keys),
     .select_valid(event_valid),.timbre(choice));
 reg remote_en=0; reg [1:0] remote=0;
 wire [1:0] requested,active;wire [8:0] gain;
 timbre_control #(.REMOTE_CONTROL_ENABLE(1),.EXTERNAL_CONTROL_ENABLE(1)) controller(
     .clk(clk),.rst(rst),.sample_tick(1'b1),.key_valid(1'b0),.key_mask(16'd0),
     .light_select(1'b0),.light_timbre(2'd0),.external_select(event_valid),
     .external_timbre(choice),.remote_timbre_enable(remote_en),.remote_timbre(remote),
     .requested_timbre(requested),.active_timbre(active),.gain(gain));
 integer value,region,previous=4,events=0,i,count;reg [3:0] groups;
 task frame(input [15:0] mask);begin
  @(negedge clk);keys=mask;kv=1;
  @(negedge clk);kv=0;
 end endtask
 initial begin
  repeat(4)@(negedge clk);rst=0;
  // Exhaust ALL 65536 raw masks, not just one key per quadrant.
  for(value=0;value<65536;value=value+1)begin
   groups={|(value&16'hcc00),|(value&16'h3300),|(value&16'h00cc),|(value&16'h0033)};
   case(groups) 1:region=0;2:region=1;4:region=2;8:region=3;default:region=4;endcase
   frame(value);
   if(event_valid !== (region<4 && region!=previous))$fatal(1,"event mask %h event=%b groups=%b region=%0d previous=%0d actual=%b decoded=%0d prior=%0d",value,event_valid,groups,region,previous,zones.regions,zones.decoded,zones.previous_region);
   if(event_valid && choice!=region)$fatal(1,"wrong zone mask %h",value);
   if(event_valid)events=events+1;
   previous=region;
  end
  frame(0);frame(16'hcc00);repeat(540)@(negedge clk);
  if(active!=3 || gain!=256)$fatal(1,"TTP event not applied to fade controller");
  remote_en=1;remote=1;repeat(540)@(negedge clk);
  frame(0);frame(16'h3300);repeat(4)@(negedge clk);
  if(requested!=1 || controller.manual_requested_timbre!=2)$fatal(1,"remote ownership/manual background");
  remote_en=0;repeat(540)@(negedge clk);
  if(active!=2 || gain!=256)$fatal(1,"restore TTP manual selection after score stop");
  $display("PASS TTP zones: all65536 masks, any/multi within each 2x2 zone, conflicts, release, no held retrigger, remote override/restore, fade selection (%0d events)",events);$finish;
 end
endmodule
