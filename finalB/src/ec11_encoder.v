`timescale 1ns/1ps
// S1/S2 are two mechanical contacts. Pull both high; their common pin is GND.
// One complete quadrature cycle (four valid edges) emits one signed detent.
module ec11_encoder #(
    parameter integer DEBOUNCE_CYCLES=100000 // 2 ms at 50 MHz
) (
    input wire clk, rst, s1, s2,
    output reg signed [7:0] step_delta,
    output reg step_valid
);
    (* syn_preserve=1 *) reg [1:0] ab_meta, ab_sync;
    reg [1:0] candidate, stable_ab;
    reg [31:0] stable_count;
    reg signed [2:0] edge_balance;
    wire [3:0] transition={stable_ab,candidate};
    always @(posedge clk) begin
        if(rst) begin
            ab_meta<=2'b11; ab_sync<=2'b11;
            candidate<=2'b11; stable_ab<=2'b11;
            stable_count<=0; edge_balance<=0;
            step_delta<=0; step_valid<=0;
        end else begin
            ab_meta<={s1,s2};
            ab_sync<=ab_meta;
            step_valid<=0;
            step_delta<=0;
            if(ab_sync!=candidate) begin
                candidate<=ab_sync;
                stable_count<=0;
            end else if(candidate!=stable_ab) begin
                if(stable_count==DEBOUNCE_CYCLES-1) begin
                    stable_count<=0;
                    stable_ab<=candidate;
                    case(transition)
                        4'b1110,4'b1000,4'b0001,4'b0111: begin
                            if(edge_balance==3) begin
                                edge_balance<=0; step_delta<=8'sd1; step_valid<=1;
                            end else edge_balance<=edge_balance+3'sd1;
                        end
                        4'b1101,4'b0100,4'b0010,4'b1011: begin
                            if(edge_balance==-3) begin
                                edge_balance<=0; step_delta<=-8'sd1; step_valid<=1;
                            end else edge_balance<=edge_balance-3'sd1;
                        end
                        default: edge_balance<=0; // missed an edge; never invent a step
                    endcase
                end else stable_count<=stable_count+1'b1;
            end else stable_count<=0;
        end
    end
endmodule
