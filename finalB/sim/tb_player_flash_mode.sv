`timescale 1ns/1ps
module tb_player_flash_mode;
  reg clk=0,rst=1,append_cmd=0,play_cmd=0,guide_cmd=0,
      simple_guide_cmd=0,stop_cmd=0;
  reg [11:0] append_mask=0;
  wire [9:0] score_count,flash_read_addr;
  reg [9:0] flash_copy_addr=0;
  wire [31:0] flash_copy_data;
  wire flash_read_req,playing,guiding,simple_guiding;
  wire [11:0] current_keys,guide_keys;
  reg [31:0] flash_read_data=0;
  reg flash_read_valid=0;
  reg [3:0] delay_count=0;
  reg armed=1;
  always #10 clk=~clk;
  db_score_player #(.CLK_HZ(100000),.USE_FLASH(1)) dut(
    .clk(clk),.rst(rst),.clock_present(1'b1),
    .clear_cmd(1'b0),.append_cmd(append_cmd),.play_cmd(play_cmd),
    .stop_cmd(stop_cmd),.guide_cmd(guide_cmd),
    .simple_guide_cmd(simple_guide_cmd),
    .physical_keys(12'd0),.physical_octave(4'd4),
    .append_note(4'd0),.append_mask(append_mask),.append_is_mask(1'b1),
    .append_duration(10'd1),.append_octave_enable(1'b0),.append_octave_code(2'd0),
    .append_timbre_enable(1'b0),.append_timbre_code(2'd0),
    .append_effect_enable(1'b0),.append_effect_code(2'd0),
    .flash_copy_addr(flash_copy_addr),.flash_copy_data(flash_copy_data),
    .flash_read_req(flash_read_req),.flash_read_addr(flash_read_addr),
    .flash_read_data(flash_read_data),.flash_read_valid(flash_read_valid),
    .score_count(score_count),.playing(playing),.guiding(guiding),
    .simple_guiding(simple_guiding),
    .guide_keys(guide_keys),.current_keys(current_keys));
  // Model flash responses deliberately differ from the uploaded RAM entries.
  always @(posedge clk) begin
    flash_read_valid<=0;
    if(rst)begin delay_count<=0;armed<=1;end
    else if(!flash_read_req)armed<=1;
    else if(flash_read_req && armed && delay_count==0)begin
      delay_count<=4;armed<=0;
      flash_read_data<=flash_read_addr==0 ?
        {1'b1,12'h004,10'd1,9'd0}:{1'b1,12'h008,10'd1,9'd0};
    end
    if(delay_count!=0)begin
      delay_count<=delay_count-1'b1;
      if(delay_count==1)flash_read_valid<=1;
    end
  end
  initial begin
    repeat(10)@(negedge clk);rst=0;
    @(negedge clk);append_mask=12'h001;append_cmd=1;
    @(negedge clk);append_mask=12'h002;
    @(negedge clk);append_cmd=0;
    if(score_count!=2)$fatal(1,"upload RAM count");
    repeat(2)@(negedge clk);
    if(flash_copy_data!=={1'b1,12'h001,10'd1,9'd0})
      $fatal(1,"copy port entry 0 incorrect: %h",flash_copy_data);
    flash_copy_addr=1;
    repeat(2)@(negedge clk);
    if(flash_copy_data!=={1'b1,12'h002,10'd1,9'd0})
      $fatal(1,"copy port entry 1 incorrect: %h",flash_copy_data);
    @(negedge clk);play_cmd=1;
    @(negedge clk);play_cmd=0;
    wait(current_keys==12'h004);
    wait(current_keys==12'h008);
    wait(!playing);
    @(negedge clk);guide_cmd=1;
    @(negedge clk);guide_cmd=0;
    wait(guiding && guide_keys==12'h001);
    @(negedge clk);stop_cmd=1;
    @(negedge clk);stop_cmd=0;
    @(negedge clk);simple_guide_cmd=1;
    @(negedge clk);simple_guide_cmd=0;
    wait(guiding && simple_guiding && guide_keys==12'h001);
    $display("PASS: playback uses flash, practice guide uses B44 RAM path");
    $finish;
  end
  initial begin #1000000;$fatal(1,"timeout");end
endmodule
