`timescale 1ns/1ps
module tb53_asymmetric_keys;
 reg clk=0,rst_n=0; always #10 clk=~clk;
 reg [15:0] held=0;
 wire [3:0] rows;
 wire [3:0] columns=(rows[0] ? held[3:0] : 4'd0) |
                    (rows[1] ? held[7:4] : 4'd0) |
                    (rows[2] ? held[11:8] : 4'd0) |
                    (rows[3] ? held[15:12] : 4'd0);
 // Model line propagation ahead of the actual two-stage synchronizer.
 wire [3:0] delayed_columns; assign #35 delayed_columns={columns[0],columns[1],columns[2],columns[3]};
 wire [15:0] keys,raw; wire valid;
 keyboard_matrix_scan #(.ROW_CYCLES(16),.DEBOUNCE_FRAMES(13),.RELEASE_FRAMES(21)) dut(
  .clk(clk),.rst_n(rst_n),.kb_col(delayed_columns),.kb_row(rows),
  .key_mask(keys),.key_valid(valid),.raw_mask(raw));
 task frames(input integer n); integer j; begin
  for(j=0;j<n;j=j+1) begin @(posedge valid); @(negedge clk);end
 end endtask
 task check(input [15:0] expected);begin
  if(keys!==expected)$fatal(1,"keys=%h expected=%h",keys,expected);
 end endtask
 task stable(input [15:0] k);begin held=k;frames(22);check(k);end endtask
 reg [15:0] previous_keys=0;reg previous_valid=0;
 integer publications=0;time previous_frame=0;
 always @(negedge clk) begin #1; if(rst_n) begin
  if(rows!=1 && rows!=2 && rows!=4 && rows!=8)$fatal(1,"non-onehot rows");
  if(keys!==previous_keys && !valid)$fatal(1,"partial frame publication");
  if(valid && previous_valid)$fatal(1,"valid longer than one clock");
  if(valid) begin
   if(previous_frame && $time-previous_frame!=1280)$fatal(1,"wrong scan period");
   previous_frame=$time;publications=publications+1;
  end
  previous_keys=keys;previous_valid=valid;
 end else begin previous_keys=0;previous_valid=0;previous_frame=0;end
 end
 integer i;reg [15:0] target;integer seed=32'h376642;
 initial begin
  #55;if(rows!==0 || keys!==0 || valid!==0)$fatal(1,"reset state");
  @(negedge clk);rst_n=1;frames(2);check(0);
  // Every position must map to its own bit, including the four timbre keys.
  for(i=0;i<16;i=i+1)begin stable(16'b1<<i);stable(0);end
  stable(16'hffff);stable(16'ha55a);stable(16'h0fff);stable(0);
  // Contact chatter cannot trigger key 1; stable key 5 must still be accepted.
  repeat(3)begin held=16'h0011;frames(2);held=16'h0010;frames(1);end
  frames(14);check(16'h0010);stable(16'h0011);
  // Release chatter must not cause a release/retrigger of a held key.
  repeat(3)begin held=16'h0010;frames(2);held=16'h0011;frames(1);end
  check(16'h0011);stable(0);
  // Four opposite snapshots are insufficient; the fifth commits exactly once.
  held=16'h8001;frames(12);check(0);frames(1);check(16'h8001);
  held=0;frames(20);check(16'h8001);frames(1);check(0);
  // Reproducible arbitrary chords and key rollovers with both press/release.
  for(i=0;i<128;i=i+1)begin target=$random(seed);stable(target);end
  held=16'hffff;frames(22);rst_n=0;#1;
  if(rows!==0 || keys!==0 || valid!==0)$fatal(1,"reset while held");
  repeat(3)@(negedge clk);rst_n=1;frames(12);check(0);frames(1);check(16'hffff);
  $display("PASS matrix: 16 mappings, full rollover, independent debounce, press/release chatter, exact13/21 asymmetric thresholds, 128 random chords, atomic valid, reset-held recovery (%0d frames)",publications);
  $finish;
 end
 initial begin #15000000;$fatal(1,"timeout");end
endmodule
