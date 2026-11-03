`timescale 1ns/1ps
// Four sensor DO outputs on MCP3008 CH4..7. A newly confirmed active level selects.
// A held light never overrides a later manual selection. A dark->light cycle re-arms it.
// Default DO active=LOW. ADC<=256 confirms LOW, ADC>=640 confirms HIGH.
// The digital comparator in each sensor sets the optical switching point.
// Intermediate ADC values do not assert or release; ACTIVE_LOW=0 supports active-high DO.
// CONFIRM_SNAPSHOTS is 1..255. Default: two 1 kHz snapshots (~1..2 ms).
// Per-channel voltage thresholds remain configurable for input-level compatibility.
module ref51_light_timbre_select #(
    parameter integer ACTIVE_LOW=1,
    parameter integer HIGH_THRESHOLD=640, LOW_THRESHOLD=256,
    parameter integer HIGH_THRESHOLD_1=HIGH_THRESHOLD, LOW_THRESHOLD_1=LOW_THRESHOLD,
    parameter integer HIGH_THRESHOLD_2=HIGH_THRESHOLD, LOW_THRESHOLD_2=LOW_THRESHOLD,
    parameter integer HIGH_THRESHOLD_3=HIGH_THRESHOLD, LOW_THRESHOLD_3=LOW_THRESHOLD,
    parameter integer HIGH_THRESHOLD_4=HIGH_THRESHOLD, LOW_THRESHOLD_4=LOW_THRESHOLD,
    parameter integer CONFIRM_SNAPSHOTS=2
) (
    input wire clk, rst, snapshot_valid,
    input wire [9:0] light_1, light_2, light_3, light_4,
    output reg select_valid,
    output reg [1:0] timbre
);
    wire [9:0] values [0:3];
    assign values[0]=light_1;
    assign values[1]=light_2;
    assign values[2]=light_3;
    assign values[3]=light_4;
    wire [9:0] high_thresholds [0:3];
    wire [9:0] low_thresholds [0:3];
    assign high_thresholds[0]=HIGH_THRESHOLD_1;
    assign low_thresholds[0]=LOW_THRESHOLD_1;
    assign high_thresholds[1]=HIGH_THRESHOLD_2;
    assign low_thresholds[1]=LOW_THRESHOLD_2;
    assign high_thresholds[2]=HIGH_THRESHOLD_3;
    assign low_thresholds[2]=LOW_THRESHOLD_3;
    assign high_thresholds[3]=HIGH_THRESHOLD_4;
    assign low_thresholds[3]=LOW_THRESHOLD_4;
    reg [3:0] lit, rising;
    reg [7:0] confirm_count [0:3];
    integer i;
    always @(posedge clk) begin
        if(rst) begin
            lit<=0; rising<=0; select_valid<=0; timbre<=0;
            for(i=0;i<4;i=i+1) confirm_count[i]<=0;
        end else begin
            rising<=0;
            select_valid<=0;
            if(snapshot_valid) begin
                for(i=0;i<4;i=i+1) begin
                    if((!lit[i] && ((ACTIVE_LOW!=0) ? values[i]<=low_thresholds[i] : values[i]>=high_thresholds[i])) ||
                       ( lit[i] && ((ACTIVE_LOW!=0) ? values[i]>=high_thresholds[i] : values[i]<=low_thresholds[i]))) begin
                        if(confirm_count[i]==CONFIRM_SNAPSHOTS-1) begin
                            lit[i]<=!lit[i];
                            rising[i]<=!lit[i];
                            confirm_count[i]<=0;
                        end else confirm_count[i]<=confirm_count[i]+1'b1;
                    end else confirm_count[i]<=0;
                end
            end
            // If several lights qualify on the same scan: CH4 > CH5 > CH6 > CH7.
            if(rising[0]) begin select_valid<=1; timbre<=0; end
            else if(rising[1]) begin select_valid<=1; timbre<=1; end
            else if(rising[2]) begin select_valid<=1; timbre<=2; end
            else if(rising[3]) begin select_valid<=1; timbre<=3; end
        end
    end
endmodule
