`timescale 1ns/1ps
module tb_stream_flash;
  reg clk=0,rst=1,clear_req=0,append_req=0,read_req=0;
  reg [31:0] append_data=0;
  reg [13:0] read_addr=0;
  wire [13:0] entry_count;
  wire ready,initialized,clear_done,append_done,op_error,read_valid;
  wire [31:0] read_data;
  wire cs_n,sclk,mosi;
  reg miso=1;
  always #10 clk=~clk;
  db_flash_score dut(.clk(clk),.rst(rst),.clear_req(clear_req),
    .append_req(append_req),.append_data(append_data),
    .entry_count(entry_count),.ready(ready),.initialized(initialized),
    .clear_done(clear_done),.append_done(append_done),.op_error(op_error),
    .read_req(read_req),.read_addr(read_addr),.read_data(read_data),
    .read_valid(read_valid),.flash_cs_n(cs_n),.flash_sclk(sclk),
    .flash_mosi(mosi),.flash_miso(miso));
  reg [7:0] mem[0:32767];
  reg [7:0] shift=0,cmd=0;
  reg [23:0] address=0;
  integer bit_no=0,byte_no=0,i;
  reg write_enable=0;
  always @(negedge cs_n) begin bit_no=0;byte_no=0;shift=0;cmd=0;address=0;end
  always @(posedge sclk) if(!cs_n) begin
    shift={shift[6:0],mosi};
    if(bit_no==7)begin
      if(byte_no==0)begin cmd=shift;if(shift==8'h06)write_enable=1;end
      if(byte_no==1)address[23:16]=shift;
      if(byte_no==2)address[15:8]=shift;
      if(byte_no==3)begin
        address[7:0]=shift;
        if(cmd==8'hd8 && write_enable)begin
          for(i=0;i<32768;i=i+1)mem[i]=8'hff;
          write_enable=0;
        end
      end
      if(cmd==8'h02 && byte_no>=4 && byte_no<8 && write_enable)
        mem[address[14:0]+byte_no-4]=shift;
      bit_no=0;byte_no=byte_no+1;shift=0;
    end else bit_no=bit_no+1;
  end
  always @(posedge cs_n) if(cmd==8'h02)write_enable=0;
  always @(negedge sclk) if(!cs_n)begin
    if(cmd==8'h9f && byte_no>=1 && byte_no<=3)
      case(byte_no)
        1:miso=(8'hef>>(7-bit_no))&1;
        2:miso=(8'h40>>(7-bit_no))&1;
        3:miso=(8'h17>>(7-bit_no))&1;
      endcase
    else if(cmd==8'h05 && byte_no==1)miso=0;
    else if(cmd==8'h03 && byte_no>=4 && byte_no<8)
      miso=(mem[address[14:0]+byte_no-4]>>(7-bit_no))&1;
    else miso=1;
  end
  task append_check(input [31:0] word,input [13:0] count);
    begin
      @(negedge clk);append_data=word;append_req=1;
      @(negedge clk);append_req=0;
      wait(append_done || op_error);
      if(op_error || entry_count!==count)$fatal(1,"append failed count %0d",entry_count);
      @(negedge clk);
    end
  endtask
  task read_check(input [13:0] index,input [31:0] word);
    begin
      @(negedge clk);read_addr=index;read_req=1;
      wait(read_valid || op_error);
      if(op_error || read_data!==word)$fatal(1,"read %0d got %h want %h",index,read_data,word);
      @(negedge clk);read_req=0;
      repeat(3)@(negedge clk);
    end
  endtask
  initial begin
    for(i=0;i<32768;i=i+1)mem[i]=8'h00;
    #200 rst=0;
    wait(ready);
    @(negedge clk);clear_req=1;
    @(negedge clk);clear_req=0;
    wait(clear_done || op_error);
    if(op_error || !initialized || entry_count!=0)$fatal(1,"erase failed");
    append_check(32'h81234567,14'd1);
    append_check(32'h76543210,14'd2);
    read_check(0,32'h81234567);
    read_check(1,32'h76543210);
    // Boundary proof: the next committed event is beyond the old 512 limit.
    @(negedge clk);dut.entry_count=14'd512;
    append_check(32'hff00aa55,14'd513);
    read_check(512,32'hff00aa55);
    @(negedge clk);dut.entry_count=14'd8191;
    append_check(32'h00ab12cd,14'd8192);
    read_check(8191,32'h00ab12cd);
    @(negedge clk);append_data=32'h11111111;append_req=1;
    @(negedge clk);append_req=0;
    wait(op_error);
    if(entry_count!=8192)$fatal(1,"full store changed count");
    $display("PASS: erase, commit, verify, read events 513 and 8192; full rejected");
    $finish;
  end
  initial begin #200000000;$fatal(1,"timeout");end
endmodule
