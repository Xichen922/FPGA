`timescale 1ns/1ps
module tb_flash_score;
  reg clk=0,rst=1,copy_start=0,read_req=0;
  reg [9:0] read_addr=0;
  wire [9:0] source_addr;
  reg [31:0] source_data;
  reg [31:0] source[0:2];
  wire [31:0] read_data;
  wire read_valid,copy_done,copy_error,copy_busy,cs_n,sclk,mosi;
  reg miso=1;
  always #10 clk=~clk;
  always @(posedge clk) source_data<=source[source_addr];
  db_flash_score dut(.clk(clk),.rst(rst),.copy_start(copy_start),
    .entry_count(10'd3),.source_addr(source_addr),.source_data(source_data),
    .read_req(read_req),.read_addr(read_addr),.read_data(read_data),
    .read_valid(read_valid),.copy_done(copy_done),.copy_error(copy_error),
    .copy_busy(copy_busy),.flash_cs_n(cs_n),.flash_sclk(sclk),
    .flash_mosi(mosi),.flash_miso(miso));
  reg [7:0] mem[0:2047];
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
        if(cmd==8'h20 && write_enable)begin
          for(i=0;i<2048;i=i+1)mem[i]=8'hff;
          write_enable=0;
        end
      end
      if(cmd==8'h02 && byte_no>=4 && byte_no<8 && write_enable)
        mem[address[10:0]+byte_no-4]=shift;
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
      miso=(mem[address[10:0]+byte_no-4]>>(7-bit_no))&1;
    else miso=1;
  end
  task read_check(input [9:0] index,input [31:0] expected);
    begin
      @(negedge clk);read_addr=index;read_req=1;
      wait(read_valid);
      if(read_data!==expected)$fatal(1,"index %0d got %h want %h",index,read_data,expected);
      @(negedge clk);read_req=0;
      repeat(4)@(negedge clk);
    end
  endtask
  initial begin
    source[0]=32'h81234567;source[1]=32'h76543210;source[2]=32'hff00aa55;
    #200 rst=0;
    #1500000;
    @(negedge clk);copy_start=1;
    @(negedge clk);copy_start=0;
    wait(copy_done || copy_error);
    if(copy_error)$fatal(1,"copy error");
    read_check(0,source[0]);
    read_check(1,source[1]);
    read_check(2,source[2]);
    $display("PASS: three 32-bit score events copied and read from flash");
    $finish;
  end
  initial begin #100000000;$fatal(1,"timeout");end
endmodule
