`timescale 1ns/1ps
// HC-SR04 gesture: one valid near reading (<20 cm) toggles immediately.
// The gesture stays latched until eight consecutive clear readings (>=30 cm
// or no echo). This catches a brief wave without toggling twice while the
// hand slowly enters/leaves the sensing area. The sample period stays 40 ms.
// Thresholds compare Echo pulse width directly, avoiding a divider.
module latb_ultrasonic_effect_toggle #(
    parameter integer TRIG_CLOCKS=500,
    parameter integer CYCLE_CLOCKS=2000000,
    parameter integer TIMEOUT_CLOCKS=1250000,
    parameter integer MIN_NEAR_CLOCKS=5800,
    parameter integer NEAR_CLOCKS=58300,
    parameter integer FAR_CLOCKS=87500,
    parameter integer CLEAR_READINGS=8
) (
    input wire clk, rst_n, echo_async,
    output reg trig,
    output reg effect_on
);
    localparam [2:0] START=0,PULSE=1,WAIT_RISE=2,MEASURE=3,WAIT_NEXT=4;
    reg [2:0] state;
    reg [20:0] cycle_count, echo_count;
    (* syn_preserve=1 *) reg echo_meta,echo_sync,echo_prev;
    reg armed;
    reg [3:0] clear_count;
    wire rise=echo_sync && !echo_prev;
    wire fall_edge=!echo_sync && echo_prev;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin echo_meta<=0;echo_sync<=0;echo_prev<=0;end
        else begin echo_meta<=echo_async;echo_sync<=echo_meta;echo_prev<=echo_sync;end
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=START;cycle_count<=0;echo_count<=0;trig<=0;effect_on<=0;
            armed<=1;clear_count<=0;
        end else begin
            if(cycle_count<CYCLE_CLOCKS-1) cycle_count<=cycle_count+1'b1;
            case(state)
                START:begin
                    cycle_count<=0;echo_count<=0;trig<=1;state<=PULSE;
                end
                PULSE:if(cycle_count>=TRIG_CLOCKS-1) begin trig<=0;state<=WAIT_RISE;end
                WAIT_RISE:begin
                    if(rise) begin echo_count<=0;state<=MEASURE;end
                    else if(cycle_count>=TIMEOUT_CLOCKS) begin
                        if(!armed) begin
                            if(clear_count>=CLEAR_READINGS-1) begin armed<=1;clear_count<=0;end
                            else clear_count<=clear_count+1'b1;
                        end
                        state<=WAIT_NEXT;
                    end
                end
                MEASURE:begin
                    if(fall_edge || echo_count>=TIMEOUT_CLOCKS) begin
                        if(fall_edge && echo_count>=MIN_NEAR_CLOCKS && echo_count<NEAR_CLOCKS) begin
                            clear_count<=0;
                            if(armed) begin effect_on<=~effect_on;armed<=0;end
                        end else if(!fall_edge || echo_count>=FAR_CLOCKS) begin
                            if(!armed) begin
                                if(clear_count>=CLEAR_READINGS-1) begin armed<=1;clear_count<=0;end
                                else clear_count<=clear_count+1'b1;
                            end
                        end else clear_count<=0; // transition band or invalid short pulse
                        state<=WAIT_NEXT;
                    end else echo_count<=echo_count+1'b1;
                end
                WAIT_NEXT:if(cycle_count>=CYCLE_CLOCKS-1 && !echo_sync) state<=START;
                default:state<=START;
            endcase
        end
    end
endmodule
