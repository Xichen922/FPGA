`timescale 1ns/1ps
module tb_player_stream_mode;
  reg clk=0,rst=1,play_cmd=0,guide_cmd=0,simple_guide_cmd=0,stop_cmd=0;
  wire [13:0] flash_read_addr;
  wire flash_read_req,playing,guiding,simple_guiding;
  wire [11:0] current_keys,guide_keys;
  reg [31:0] flash_read_data=0;
  reg flash_read_valid=0;
  reg [3:0] delay_count=0;
  reg armed=1;
  always #10 clk=~clk;
  db_score_player_flash #(.CLK_HZ(100000)) dut(
    .clk(clk),.rst(rst),.clock_present(1'b1),
    .clear_cmd(1'b0),.play_cmd(play_cmd),.stop_cmd(stop_cmd),
    .guide_cmd(guide_cmd),.simple_guide_cmd(simple_guide_cmd),
    .physical_keys(12'd0),.physical_octave(4'd4),
    .flash_read_req(flash_read_req),.flash_read_addr(flash_read_addr),
    .flash_read_data(flash_read_data),.flash_read_valid(flash_read_valid),
    .score_count(14'd513),.playing(playing),.guiding(guiding),
    .simple_guiding(simple_guiding),.guide_keys(guide_keys),
    .current_keys(current_keys));
  always @(posedge clk) begin
    flash_read_valid<=0;
    if(rst)begin delay_count<=0;armed<=1;end
    else if(!flash_read_req)armed<=1;
    else if(flash_read_req && armed && delay_count==0)begin
      delay_count<=4;armed<=0;
      flash_read_data<={1'b1,12'h004,10'd1,9'd0};
    end
    if(delay_count!=0)begin
      delay_count<=delay_count-1'b1;
      if(delay_count==1)flash_read_valid<=1;
    end
  end
  initial begin
    repeat(10)@(negedge clk);rst=0;
    @(negedge clk);play_cmd=1;
    @(negedge clk);play_cmd=0;
    wait(current_keys==12'h004);
    @(negedge clk);stop_cmd=1;
    @(negedge clk);stop_cmd=0;
    @(negedge clk);guide_cmd=1;
    @(negedge clk);guide_cmd=0;
    wait(guiding && guide_keys==12'h004);
    @(negedge clk);stop_cmd=1;
    @(negedge clk);stop_cmd=0;
    @(negedge clk);simple_guide_cmd=1;
    @(negedge clk);simple_guide_cmd=0;
    wait(guiding && simple_guiding && guide_keys==12'h004);
    $display("PASS: playback and both practice modes read flash");
    $finish;
  end
  initial begin #1000000;$fatal(1,"timeout");end
endmodule
