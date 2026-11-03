`timescale 1ns/1ps
// Dry signal is always unity. The encoder controls only the added wet component.
// Mono wet effects are sent to both channels; the two dry channels stay independent.
module latb_db_effects #(parameter integer DIAGNOSTIC_ECHO_ONLY=0)(input wire clk,rst,input wire in_valid,output wire in_ready,
 input wire signed [23:0] in_left,in_right,input wire effect_on,input wire [1:0] effect_mode,
 input wire [7:0] echo_depth,reverb_depth,chorus_depth,
 output reg signed [23:0] out_left,out_right,output reg out_valid,input wire out_ready,
 output reg clipped,output wire [7:0] applied_depth,output wire [1:0] applied_mode);
 // Production: 4883 frames (~50 ms). Echo-only diagnostic: 19532 (~200 ms),
 // long enough to separate a short played note from its delayed copy.
 localparam integer ECHO_FRAMES=(DIAGNOSTIC_ECHO_ONLY!=0) ? 19532 : 4883;
 (* syn_ramstyle="block_ram" *) reg signed [15:0] er[0:ECHO_FRAMES-1],r0[0:1422],r1[0:1666],r2[0:1876],r3[0:2136],cr[0:2047];
 reg [14:0] ea,filled;reg [10:0] a0,a1,a2,ca;reg [11:0] a3;
 reg signed [15:0] et,t0,t1,t2,t3,c0,c1,echo_previous;
 reg [10:0] craddr;reg [13:0] fraction;reg [23:0] lfo;
 reg [2:0] stage;reg signed [23:0] hl,hr,wet_sample;
 reg [1:0] active_mode,frame_mode;reg [7:0] mix_gain,frame_gain;
 reg ef,f0,f1,f2,f3,cf;
 wire accept=in_valid && in_ready;
 assign in_ready=stage==0 && !out_valid;
 assign applied_depth=mix_gain;assign applied_mode=active_mode;
 wire [1:0] requested_mode=effect_on ? effect_mode : 0;
 wire [7:0] requested_depth=active_mode==1?echo_depth:active_mode==2?reverb_depth:active_mode==3?chorus_depth:0;
 wire [22:0] triangle=lfo[23]?~lfo[22:0]:lfo[22:0];
 wire [10:0] next_craddr=ca-(11'd1000+{2'd0,triangle[22:14]});
 function [15:0] clip16(input signed [20:0] x);begin clip16=x>32767?16'h7fff:x< -32768?16'h8000:x[15:0];end endfunction
 function [23:0] clip24(input signed [33:0] x);begin clip24=x>8388607?24'h7fffff:x< -8388608?24'h800000:x[23:0];end endfunction
 wire signed [20:0] x16={{5{hl[23]}},hl[23:8]};
 wire signed [20:0] ewide=ef ? {{5{et[15]}},et}:21'sd0;
 wire signed [20:0] eprev={{5{echo_previous[15]}},echo_previous};
 wire signed [20:0] efiltered=(ewide+(ewide<<<1)+eprev)>>>2;
 wire signed [20:0] efeedback=((efiltered<<<4)+(efiltered<<<2)+(efiltered<<<1)+efiltered)>>>7;
 wire signed [20:0] v0=f0?{{5{t0[15]}},t0}:21'sd0;
 wire signed [20:0] v1=f1?{{5{t1[15]}},t1}:21'sd0;
 wire signed [20:0] v2=f2?{{5{t2[15]}},t2}:21'sd0;
 wire signed [20:0] v3=f3?{{5{t3[15]}},t3}:21'sd0;
 wire signed [20:0] reverb_average=(v0+v1+v2+v3)>>>2;
 wire signed [16:0] difference=$signed({c1[15],c1})-$signed({c0[15],c0});
 wire signed [31:0] interp_product=difference*$signed({1'b0,fraction});
 wire signed [31:0] interpolated=$signed({{16{c0[15]}},c0})+(interp_product>>>14);
 wire signed [23:0] echo_wet=efiltered<<<8;
 wire signed [23:0] reverb_wet=reverb_average<<<8;
 wire signed [23:0] chorus_wet=cf ? (interpolated<<<8):24'sd0;
 wire signed [32:0] wet_product=wet_sample*$signed({1'b0,frame_gain});
 wire signed [33:0] wet_scaled=$signed(wet_product)>>>8;
 // Separate diagnostic build: when echo is selected, remove the dry sound and
 // send only one unity-level delayed copy. This tests the real FPGA->DAC wet path
 // without depending on the EC11 depth or on a subtle dry/wet comparison.
 wire diagnostic_wet_only=(DIAGNOSTIC_ECHO_ONLY!=0) && frame_mode==2'd1;
 wire signed [33:0] wet_unity=$signed({{10{wet_sample[23]}},wet_sample});
 wire signed [33:0] mix_left=diagnostic_wet_only ? wet_unity : $signed({{10{hl[23]}},hl})+wet_scaled;
 wire signed [33:0] mix_right=diagnostic_wet_only ? wet_unity : $signed({{10{hr[23]}},hr})+wet_scaled;
 // RAM ports are synchronous and never reset. filled masks unwritten locations.
 always @(posedge clk)begin
  if(!rst)begin
   if(accept)begin et<=er[ea];t0<=r0[a0];t1<=r1[a1];t2<=r2[a2];t3<=r3[a3];c0<=cr[next_craddr];end
   else if(stage==1)c1<=cr[craddr-11'd1];
   else if(stage==2)begin
    er[ea]<=clip16(x16+efeedback);
    r0[a0]<=clip16(x16+((v0+(v0<<<2))>>>3));r1[a1]<=clip16(x16+((v1+(v1<<<2))>>>3));
    r2[a2]<=clip16(x16+((v2+(v2<<<2))>>>3));r3[a3]<=clip16(x16+((v3+(v3<<<2))>>>3));
    cr[ca]<=hl[23:8];
   end
  end
 end
 always @(posedge clk)begin
  if(rst)begin ea<=0;a0<=0;a1<=0;a2<=0;a3<=0;ca<=0;filled<=0;craddr<=0;fraction<=0;lfo<=0;stage<=0;
   hl<=0;hr<=0;wet_sample<=0;active_mode<=0;frame_mode<=0;mix_gain<=0;frame_gain<=0;echo_previous<=0;
   ef<=0;f0<=0;f1<=0;f2<=0;f3<=0;cf<=0;out_left<=0;out_right<=0;out_valid<=0;clipped<=0;end
  else begin
   if(out_valid && out_ready)out_valid<=0;
   if(accept)begin
    hl<=in_left;hr<=in_right;frame_mode<=active_mode;frame_gain<=mix_gain;stage<=1;
    craddr<=next_craddr;fraction<=triangle[13:0];lfo<=lfo+24'd103;
    ef<=filled>=ECHO_FRAMES;f0<=filled>=1423;f1<=filled>=1667;f2<=filled>=1877;f3<=filled>=2137;cf<=filled>=1536;
    if(requested_mode!=active_mode)begin if(mix_gain!=0)mix_gain<=mix_gain-1'b1;else active_mode<=requested_mode;end
    else if(mix_gain<requested_depth)mix_gain<=mix_gain+1'b1;
    else if(mix_gain>requested_depth)mix_gain<=mix_gain-1'b1;
   end else if(stage==1)stage<=2;
   else if(stage==2)begin
    wet_sample<=frame_mode==1?echo_wet:frame_mode==2?reverb_wet:frame_mode==3?chorus_wet:24'sd0;
    echo_previous<=efiltered[15:0];
    ea<=ea==ECHO_FRAMES-1?0:ea+1'b1;a0<=a0==1422?0:a0+1'b1;a1<=a1==1666?0:a1+1'b1;
    a2<=a2==1876?0:a2+1'b1;a3<=a3==2136?0:a3+1'b1;ca<=ca+1'b1;
    if(filled<ECHO_FRAMES)filled<=filled+1'b1;
    stage<=3;
   end else if(stage==3)begin
    out_left<=clip24(mix_left);out_right<=clip24(mix_right);out_valid<=1;stage<=0;
    if(mix_left>8388607 || mix_left< -8388608 || mix_right>8388607 || mix_right< -8388608)clipped<=1;
   end
  end
 end
endmodule
