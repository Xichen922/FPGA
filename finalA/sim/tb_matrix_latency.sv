`timescale 1ns/1ps
module tb_matrix_latency;
 reg clk=0,rst_n=0;always #10 clk=~clk;
 reg [15:0] held=0;wire [3:0] rows;
 wire [3:0] cols=(rows[0]?held[3:0]:4'd0)|(rows[1]?held[7:4]:4'd0)|
                  (rows[2]?held[11:8]:4'd0)|(rows[3]?held[15:12]:4'd0);
 wire [15:0] keys;wire valid;
 keyboard_matrix_scan #(.RELEASE_FRAMES(21)) dut(.clk(clk),.rst_n(rst_n),.kb_row(rows),.kb_col({cols[0],cols[1],cols[2],cols[3]}),
  .key_mask(keys),.key_valid(valid),.raw_mask());
 time last_frame=0,started,press_ns,release_ns;
 always @(posedge valid)begin
  if(last_frame && $time-last_frame!=250000)$fatal(1,"default frame is not 0.25ms");
  last_frame=$time;
 end
 initial begin
  #100;rst_n=1;repeat(2)@(posedge valid);
  // Change just after R1 has been sampled: near the worst row/frame phase.
  @(negedge rows[0]);#100;held=16'hffff;started=$time;
  wait(keys==16'hffff);press_ns=$time-started;
  if(press_ns>3440000 || press_ns<3000000)$fatal(1,"default press latency %0d",press_ns);
  @(negedge rows[0]);#100;held=0;started=$time;
  wait(keys==0);release_ns=$time-started;
  if(release_ns>5440000 || release_ns<5000000)$fatal(1,"default release latency %0d",release_ns);
  $display("PASS default 50MHz/0.25ms frame/press13 release21 snapshots: worst-phase press=%0d ns release=%0d ns (stable ideal contacts, excludes mechanical bounce and downstream audio)",press_ns,release_ns);
  $finish;
 end
 initial begin #20000000;$fatal(1,"timeout");end
endmodule
