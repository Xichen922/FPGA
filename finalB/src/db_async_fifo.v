`timescale 1ns/1ps
// Complete audio words cross domains; Gray pointers alone pass through 2FF synchronizers.
module db_async_fifo #(parameter WIDTH=48,ADDR_BITS=3)(
 input wire wr_clk,wr_rst,wr_en,input wire [WIDTH-1:0] wr_data,output reg full,
 input wire rd_clk,rd_rst,rd_en,output reg [WIDTH-1:0] rd_data,output reg rd_valid,output reg empty);
 localparam [ADDR_BITS:0] FULL_MASK=(1<<ADDR_BITS)|(1<<(ADDR_BITS-1));
 (* syn_ramstyle="block_ram" *) reg [WIDTH-1:0] mem[0:(1<<ADDR_BITS)-1];
 reg [ADDR_BITS:0] wb,wg,rb,rg;
 (* syn_preserve=1, async_reg="true" *) reg [ADDR_BITS:0] rmeta,rsync,wmeta,wsync;
 wire push=wr_en && !full,pop=rd_en && !empty;
 wire [ADDR_BITS:0] wn=wb+push,rn=rb+pop;
 wire [ADDR_BITS:0] wgn=(wn>>1)^wn,rgn=(rn>>1)^rn;
 always @(posedge wr_clk)if(push)mem[wb[ADDR_BITS-1:0]]<=wr_data;
 always @(posedge rd_clk)if(pop)rd_data<=mem[rb[ADDR_BITS-1:0]];
 always @(posedge wr_clk or posedge wr_rst)begin
  if(wr_rst)begin wb<=0;wg<=0;full<=0;rmeta<=0;rsync<=0;end
  else begin rmeta<=rg;rsync<=rmeta;wb<=wn;wg<=wgn;full<=(wgn==(rsync^FULL_MASK));end
 end
 always @(posedge rd_clk or posedge rd_rst)begin
  if(rd_rst)begin rb<=0;rg<=0;empty<=1;wmeta<=0;wsync<=0;rd_valid<=0;end
  else begin wmeta<=wg;wsync<=wmeta;rb<=rn;rg<=rgn;empty<=(rgn==wsync);rd_valid<=pop;end
 end
endmodule
