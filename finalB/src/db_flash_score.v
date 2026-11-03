`timescale 1ns/1ps
// Streaming W25Q64 store: each event is programmed and read back before K.
// The final 64 KiB sector holds up to 8192 score events in this version.
module db_flash_score #(
    parameter integer MAX_NOTES=8192
)(
    input wire clk,rst,clear_req,append_req,
    input wire [31:0] append_data,
    output reg [13:0] entry_count,
    output wire ready,output reg initialized,
    input wire read_req,
    input wire [13:0] read_addr,
    output reg [31:0] read_data,
    output reg read_valid,clear_done,append_done,op_error,
    output reg flash_cs_n,
    output wire flash_sclk,flash_mosi,
    input wire flash_miso
);
    localparam [3:0] OP_ID=0,OP_WREN_ERASE=1,OP_ERASE=2,OP_POLL_ERASE=3,
                     OP_WREN_WORD=4,OP_WRITE_WORD=5,OP_POLL_WORD=6,OP_READ=7,OP_VERIFY=8;
    localparam [3:0] POWER=0,BEGIN_OP=1,SEND_BYTE=2,WAIT_BYTE=3,GAP=4,
                     IDLE=5;
    reg [3:0] state,op;
    reg [3:0] byte_index;
    reg [15:0] gap_count,poll_count;
    reg [13:0] active_index;
    reg [31:0] write_word;
    reg [23:0] jedec_id;
    reg [7:0] status_byte;
    reg id_ok,read_armed;
    reg spi_start;
    reg [7:0] spi_tx;
    wire spi_busy,spi_done;
    wire [7:0] spi_rx;
    wire [23:0] addr=24'h7F0000+{8'd0,active_index,2'b00};
    assign ready=state==IDLE;
    w25q64_spi_byte #(.HALF_CYCLES(25)) u_spi(
        .clk(clk),.rst_n(!rst),.start(spi_start),.tx_data(spi_tx),
        .miso(flash_miso),.sclk(flash_sclk),.mosi(flash_mosi),
        .busy(spi_busy),.done(spi_done),.rx_data(spi_rx));
    function [3:0] last_byte;
        input [3:0] operation;
        begin case(operation)
            OP_ID,OP_ERASE:last_byte=3;
            OP_WREN_ERASE,OP_WREN_WORD:last_byte=0;
            OP_POLL_ERASE,OP_POLL_WORD:last_byte=1;
            OP_WRITE_WORD,OP_READ,OP_VERIFY:last_byte=7;
            default:last_byte=0;
        endcase end
    endfunction
    function [7:0] tx_byte;
        input [3:0] operation,index;
        input [23:0] address;
        input [31:0] word;
        begin
            tx_byte=0;
            case(operation)
                OP_ID:if(index==0)tx_byte=8'h9F;
                OP_WREN_ERASE,OP_WREN_WORD:tx_byte=8'h06;
                OP_ERASE,OP_WRITE_WORD,OP_READ,OP_VERIFY:case(index)
                    0:tx_byte=operation==OP_ERASE?8'hD8:
                              operation==OP_WRITE_WORD?8'h02:8'h03;
                    1:tx_byte=address[23:16];
                    2:tx_byte=address[15:8];
                    3:tx_byte=address[7:0];
                    4:if(operation==OP_WRITE_WORD)tx_byte=word[31:24];
                    5:if(operation==OP_WRITE_WORD)tx_byte=word[23:16];
                    6:if(operation==OP_WRITE_WORD)tx_byte=word[15:8];
                    7:if(operation==OP_WRITE_WORD)tx_byte=word[7:0];
                endcase
                OP_POLL_ERASE,OP_POLL_WORD:if(index==0)tx_byte=8'h05;
            endcase
        end
    endfunction
    always @(posedge clk) begin
        if(rst)begin
            state<=POWER;op<=OP_ID;byte_index<=0;gap_count<=0;
            poll_count<=0;active_index<=0;entry_count<=0;
            write_word<=0;jedec_id<=0;status_byte<=0;id_ok<=0;initialized<=0;
            read_armed<=1;read_data<=0;read_valid<=0;
            clear_done<=0;append_done<=0;op_error<=0;
            flash_cs_n<=1;spi_start<=0;spi_tx<=0;
        end else begin
            spi_start<=0;read_valid<=0;clear_done<=0;append_done<=0;op_error<=0;
            if(!read_req)read_armed<=1;
            case(state)
                POWER:if(gap_count==16'd49999)begin
                    gap_count<=0;op<=OP_ID;state<=BEGIN_OP;
                end else gap_count<=gap_count+1'b1;
                BEGIN_OP:begin
                    flash_cs_n<=0;byte_index<=0;state<=SEND_BYTE;
                end
                SEND_BYTE:if(!spi_busy)begin
                    spi_tx<=tx_byte(op,byte_index,addr,write_word);
                    spi_start<=1;state<=WAIT_BYTE;
                end
                WAIT_BYTE:if(spi_done)begin
                    if(op==OP_ID)case(byte_index)
                        1:jedec_id[23:16]<=spi_rx;
                        2:jedec_id[15:8]<=spi_rx;
                        3:jedec_id[7:0]<=spi_rx;
                    endcase
                    if((op==OP_POLL_ERASE || op==OP_POLL_WORD)&&byte_index==1)
                        status_byte<=spi_rx;
                    if(op==OP_READ || op==OP_VERIFY)case(byte_index)
                        4:read_data[31:24]<=spi_rx;
                        5:read_data[23:16]<=spi_rx;
                        6:read_data[15:8]<=spi_rx;
                        7:read_data[7:0]<=spi_rx;
                    endcase
                    if(byte_index==last_byte(op))begin
                        flash_cs_n<=1;gap_count<=0;state<=GAP;
                    end else begin
                        byte_index<=byte_index+1'b1;state<=SEND_BYTE;
                    end
                end
                GAP:if(gap_count==16'd4999)begin
                    gap_count<=0;
                    case(op)
                        OP_ID:begin id_ok<=jedec_id==24'hEF4017;state<=IDLE;end
                        OP_WREN_ERASE:begin op<=OP_ERASE;state<=BEGIN_OP;end
                        OP_ERASE:begin op<=OP_POLL_ERASE;poll_count<=0;state<=BEGIN_OP;end
                        OP_POLL_ERASE:if(status_byte[0])begin
                            if(poll_count==16'd50000)begin
                                op_error<=1;state<=IDLE;
                            end else begin
                                poll_count<=poll_count+1'b1;state<=BEGIN_OP;
                            end
                        end else begin
                            entry_count<=0;initialized<=1;clear_done<=1;state<=IDLE;
                        end
                        OP_WREN_WORD:begin op<=OP_WRITE_WORD;state<=BEGIN_OP;end
                        OP_WRITE_WORD:begin
                            op<=OP_POLL_WORD;poll_count<=0;state<=BEGIN_OP;
                        end
                        OP_POLL_WORD:if(status_byte[0])begin
                            if(poll_count==16'd50000)begin
                                op_error<=1;state<=IDLE;
                            end else begin
                                poll_count<=poll_count+1'b1;state<=BEGIN_OP;
                            end
                        end else begin op<=OP_VERIFY;state<=BEGIN_OP;end
                        OP_VERIFY:begin
                            if(read_data==write_word)begin
                                entry_count<=entry_count+1'b1;append_done<=1;
                            end else op_error<=1;
                            state<=IDLE;
                        end
                        OP_READ:begin read_valid<=1;state<=IDLE;end
                        default:state<=IDLE;
                    endcase
                end else gap_count<=gap_count+1'b1;
                IDLE:if(clear_req)begin
                    if(!id_ok)op_error<=1;
                    else begin initialized<=0;op<=OP_WREN_ERASE;state<=BEGIN_OP;end
                end else if(append_req)begin
                    if(!id_ok || !initialized || entry_count>=MAX_NOTES)op_error<=1;
                    else begin
                        active_index<=entry_count;write_word<=append_data;
                        op<=OP_WREN_WORD;state<=BEGIN_OP;
                    end
                end else if(read_req && read_armed && !spi_busy)begin
                    if(!id_ok || !initialized || read_addr>=entry_count)op_error<=1;
                    else begin
                        active_index<=read_addr;read_armed<=0;
                        op<=OP_READ;state<=BEGIN_OP;
                    end
                end
                default:state<=POWER;
            endcase
        end
    end
endmodule
