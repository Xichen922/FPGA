`timescale 1ns/1ps
// CH0..CH7 single-ended polling at 1 kHz. Channels are sampled sequentially.
// All eight outputs update together after CH7; snapshot_valid is a one-clock pulse.
// 通道之间CS至少拉高50个clk（1us），芯片要求至少270ns。
module ref51_mcp3008_scan #(
    parameter integer SCAN_CYCLES=50000,
    parameter integer SPI_HALF_CYCLES=25,
    parameter integer CS_GAP_CYCLES=50,
    // 47: keep joystick CH0/1 and one sensor CH4, omit unused conversions.
    // Default retains the original eight-channel scanner for other callers.
    parameter integer SCAN_MODE_014=0
) (
    input wire clk, rst_n, miso,
    output wire cs_n, sclk, mosi,
    output reg [9:0] ch0, ch1, ch2, ch3, ch4, ch5, ch6, ch7,
    output reg snapshot_valid
);
    localparam IDLE=0, ISSUE=1, WAIT_RESULT=2, GAP=3;
    localparam integer LAST_CHANNEL=(SCAN_MODE_014!=0)?4:7;
    reg [1:0] state;
    reg [2:0] channel;
    reg [31:0] scan_timer, gap_timer;
    reg [9:0] pending0, pending1, pending2, pending3, pending4, pending5, pending6;
    wire spi_ready, result_valid;
    wire [9:0] result;
    wire start=(state==ISSUE) && spi_ready;
    ref51_mcp3008_spi #(.HALF_CYCLES(SPI_HALF_CYCLES)) u_spi (
        .clk(clk), .rst_n(rst_n), .start(start), .channel(channel), .miso(miso),
        .ready(spi_ready), .cs_n(cs_n), .sclk(sclk), .mosi(mosi),
        .result(result), .result_valid(result_valid));
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=IDLE; channel<=0; scan_timer<=0; gap_timer<=0;
            pending0<=0; pending1<=0; pending2<=0; pending3<=0; pending4<=0; pending5<=0; pending6<=0;
            ch0<=0; ch1<=0; ch2<=0; ch3<=0; ch4<=0; ch5<=0; ch6<=0; ch7<=0; snapshot_valid<=0;
        end else begin
            snapshot_valid<=0;
            // 固定扫描起点节拍。参数必须保证一轮扫描能在下一节拍前完成。
            if (scan_timer==0) scan_timer<=SCAN_CYCLES-1;
            else scan_timer<=scan_timer-1'b1;
            case (state)
                IDLE: if (scan_timer==0) begin channel<=0; state<=ISSUE; end
                ISSUE: if (spi_ready) state<=WAIT_RESULT;
                WAIT_RESULT: if (result_valid) begin
                    case (channel)
                        0: pending0<=result;
                        1: pending1<=result;
                        2: pending2<=result;
                        3: pending3<=result;
                        4: begin
                            pending4<=result;
                            if (SCAN_MODE_014!=0) begin
                                ch0<=pending0; ch1<=pending1; ch4<=result;
                                snapshot_valid<=1;
                            end
                        end
                        5: pending5<=result;
                        6: pending6<=result;
                        7: begin
                            ch0<=pending0; ch1<=pending1; ch2<=pending2; ch3<=pending3;
                            ch4<=pending4; ch5<=pending5; ch6<=pending6; ch7<=result;
                            snapshot_valid<=1;
                        end
                    endcase
                    if (channel==LAST_CHANNEL) state<=IDLE;
                    else begin
                        channel<=(SCAN_MODE_014!=0 && channel==1)?3'd4:channel+1'b1;
                        gap_timer<=CS_GAP_CYCLES-1; state<=GAP;
                    end
                end
                GAP: if (gap_timer==0) state<=ISSUE;
                     else gap_timer<=gap_timer-1'b1;
                default: state<=IDLE;
            endcase
        end
    end
endmodule
