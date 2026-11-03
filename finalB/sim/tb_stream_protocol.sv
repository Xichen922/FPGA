`timescale 1ns/1ps
module tb_stream_protocol;
  reg clk=0,rst=1,rx=1,ready=1,initialized=0;
  reg clear_done=0,append_done=0,storage_error=0;
  reg [13:0] count=0;
  wire tx,clear_cmd,append_cmd,play_cmd,stop_cmd,guide_cmd,simple_guide_cmd;
  wire [11:0] mask;
  wire [9:0] duration;
  wire [7:0] tx_byte;
  wire tx_byte_valid,tx_error;
  integer response_n=0;
  integer clear_n=0,append_n=0;
  reg [7:0] responses[0:63];
  always #10 clk=~clk;
  db_score_serial #(.CLK_HZ(1000000),.BAUD(100000)) dut(
    .clk(clk),.rst(rst),.rx(rx),.tx(tx),.score_count(count),.playing(1'b0),
    .storage_ready(ready),.storage_initialized(initialized),
    .clear_done(clear_done),.append_done(append_done),.storage_error(storage_error),
    .clear_cmd(clear_cmd),.append_cmd(append_cmd),.play_cmd(play_cmd),
    .stop_cmd(stop_cmd),.guide_cmd(guide_cmd),.simple_guide_cmd(simple_guide_cmd),
    .append_note(),.append_mask(mask),.append_is_mask(),.append_duration(duration),
    .append_octave_enable(),.append_octave_code(),.append_timbre_enable(),
    .append_timbre_code(),.append_effect_enable(),.append_effect_code());
  db_uart_rx #(.CLK_HZ(1000000),.BAUD(100000)) monitor(
    .clk(clk),.rst(rst),.rx(tx),.data(tx_byte),.valid(tx_byte_valid),
    .framing_error(tx_error));
  always @(posedge clk)if(tx_byte_valid)begin
    responses[response_n]=tx_byte;response_n=response_n+1;
  end
  always @(posedge clk)begin
    if(clear_cmd)clear_n=clear_n+1;
    if(append_cmd)append_n=append_n+1;
  end
  task send_byte(input [7:0] b);
    integer j;
    begin
      rx=0;repeat(10)@(negedge clk);
      for(j=0;j<8;j=j+1)begin rx=b[j];repeat(10)@(negedge clk);end
      rx=1;repeat(10)@(negedge clk);
    end
  endtask
  task send_line(input [8*20-1:0] s,input integer n);
    integer j;
    begin for(j=n-1;j>=0;j=j-1)send_byte(s[j*8+:8]);send_byte(8'h0a);end
  endtask
  task wait_response(input integer n);
    begin wait(response_n>=n);repeat(5)@(negedge clk);end
  endtask
  initial begin
    repeat(5)@(negedge clk);rst=0;
    send_line("C",1);
    if(clear_n!=1)$fatal(1,"no C pulse");
    repeat(100)@(negedge clk);
    if(response_n!=0)$fatal(1,"C replied before erase");
    initialized=1;clear_done=1;
    @(negedge clk);clear_done=0;
    wait_response(2);
    if(responses[0]!="K" || responses[1]!=8'h0a)$fatal(1,"C ack");
    send_line("M001,100",8);
    if(append_n!=1 || mask!=12'h001 || duration!=100)$fatal(1,"event decode");
    repeat(100)@(negedge clk);
    if(response_n!=2)$fatal(1,"event replied before verification");
    count=14'd513;append_done=1;
    @(negedge clk);append_done=0;
    wait_response(4);
    if(responses[2]!="K")$fatal(1,"commit ack");
    send_line("?",1);
    wait_response(11);
    if(responses[4]!="N" || responses[5]!="=" ||
       responses[6]!="0" || responses[7]!="5" ||
       responses[8]!="1" || responses[9]!="3" ||
       responses[10]!=8'h0a)$fatal(1,"N=0513 format");
    send_line("V",1);
    wait_response(17);
    if(responses[11]!="V" || responses[12]!="=" ||
       responses[13]!="0" || responses[14]!="4" ||
       responses[15]!="8")$fatal(1,"V=048 format");
    $display("PASS: delayed K, N=0513, V=048");
    $finish;
  end
  initial begin #10000000;$fatal(1,"timeout");end
endmodule
