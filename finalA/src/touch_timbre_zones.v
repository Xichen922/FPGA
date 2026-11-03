`timescale 1ns/1ps
// Physical 4x4 pad: each 2x2 region selects one timbre. No note events.
// Ambiguous cross-region contacts keep the last requested timbre unchanged.
module touch_timbre_zones (
    input wire clk, rst, key_valid,
    input wire [15:0] key_mask,
    output reg select_valid,
    output reg [1:0] timbre
);
    wire [3:0] regions = {|(key_mask & 16'hcc00), |(key_mask & 16'h3300),
                          |(key_mask & 16'h00cc), |(key_mask & 16'h0033)};
    wire [2:0] decoded=(regions==4'b0001)?3'd0:
                       (regions==4'b0010)?3'd1:
                       (regions==4'b0100)?3'd2:
                       (regions==4'b1000)?3'd3:3'd4;
    reg [2:0] previous_region;
    always @(posedge clk) begin
        if (rst) begin select_valid<=0; timbre<=0; previous_region<=4; end
        else begin
            select_valid<=0;
            if (key_valid) begin
                previous_region<=decoded;
                if (decoded<4 && decoded!=previous_region) begin
                    timbre<=decoded[1:0];
                    select_valid<=1;
                end
            end
        end
    end
endmodule
