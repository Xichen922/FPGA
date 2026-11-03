`timescale 1ns/1ps
// Passive diode matrix: anodes on rows, cathodes on columns.
// Rows drive one-hot HIGH; all columns require physical/internal pull-downs.
// Bit 4*r+c is R(r+1)C(c+1). All logic stays in the system clock domain.
module ref51_keyboard_matrix_scan #(
    parameter integer CLK_HZ=50000000,
    parameter integer ROW_CYCLES=CLK_HZ/4000,
    parameter integer DEBOUNCE_FRAMES=5
)(
    input wire clk, rst_n,
    input wire [3:0] kb_col,
    output wire [3:0] kb_row,
    output reg [15:0] key_mask,
    output reg key_valid,
    output reg [15:0] raw_mask
);
    localparam integer TIMER_BITS=(ROW_CYCLES>1) ? $clog2(ROW_CYCLES) : 1;
    localparam integer COUNT_BITS=(DEBOUNCE_FRAMES>1) ? $clog2(DEBOUNCE_FRAMES) : 1;
    reg [TIMER_BITS-1:0] timer;
    reg [1:0] row_index;
    reg [15:0] scan_mask;
    (* syn_preserve=1, async_reg="true" *) reg [3:0] col_meta, col_sync;
    reg [COUNT_BITS-1:0] count [0:15];
    // External wires are now C4,C3,C2,C1 on kb_col[0], [1], [2], [3].
    // Restore logical C1..C4 before packing each row; note/timbre bits stay fixed.
    wire [3:0] logical_columns={col_sync[0],col_sync[1],col_sync[2],col_sync[3]};
    // At row 4 completion, its current sample must be included immediately.
    wire [15:0] completed_frame={logical_columns,scan_mask[11:0]};
    assign kb_row=rst_n ? (4'b0001 << row_index) : 4'b0000;
    integer k;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin col_meta<=0;col_sync<=0;end
        else begin col_meta<=kb_col;col_sync<=col_meta;end
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            timer<=0;row_index<=0;scan_mask<=0;
            key_mask<=0;key_valid<=0;raw_mask<=0;
            for(k=0;k<16;k=k+1) count[k]<=0;
        end else begin
            key_valid<=0;
            if(timer==ROW_CYCLES-1) begin
                timer<=0;
                scan_mask[row_index*4 +: 4]<=logical_columns;
                row_index<=row_index+1'b1;
                if(row_index==3) begin
                    raw_mask<=completed_frame;
                    // Independent counters: a bouncing key never stalls another.
                    // Press and release both require consecutive opposite samples.
                    for(k=0;k<16;k=k+1) begin
                        if(completed_frame[k]==key_mask[k]) count[k]<=0;
                        else if(count[k]==DEBOUNCE_FRAMES-1) begin
                            key_mask[k]<=completed_frame[k];count[k]<=0;
                        end else count[k]<=count[k]+1'b1;
                    end
                    // The downstream consumer sees this pulse alongside the new
                    // registered mask on its next clk; never publish a partial row.
                    key_valid<=1;
                end
            end else timer<=timer+1'b1;
        end
    end
endmodule
