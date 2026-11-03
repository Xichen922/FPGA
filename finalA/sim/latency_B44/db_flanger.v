`timescale 1ns/1ps
// Mono modulated short delay is mixed into the independent stereo dry signal.
// 512 x 16-bit RAM covers 0.65..4.1 ms at the project's 97.656 kHz rate.
module latb_db_flanger (
    input wire clk,rst,enable,
    input wire [7:0] depth,
    input wire signed [23:0] in_left,in_right,
    input wire in_valid,output wire in_ready,
    output reg signed [23:0] out_left,out_right,
    output reg out_valid,input wire out_ready
);
    (* syn_ramstyle="block_ram" *) reg signed [15:0] delay_ram[0:511];
    reg [8:0] write_addr;
    reg [9:0] filled;
    reg signed [15:0] delayed;
    reg signed [23:0] held_left,held_right;
    reg signed [16:0] held_mono;
    reg [7:0] held_gain,mix_gain;
    reg held_valid,stage;
    reg [7:0] sweep_div;
    reg [8:0] sweep_pos;
    reg sweep_up;
    wire [8:0] delay_frames=9'd64+sweep_pos;
    wire [8:0] read_addr=write_addr-delay_frames;
    wire accept=in_valid && in_ready;
    assign in_ready=!stage && !out_valid;
    wire signed [16:0] mono_sum=$signed({in_left[23],in_left[23:8]})+
                                 $signed({in_right[23],in_right[23:8]});
    wire signed [16:0] mono_input=mono_sum>>>1;
    wire signed [17:0] feedback_input=$signed({held_mono[16],held_mono})+
                                      (held_valid ? ($signed({{2{delayed[15]}},delayed})>>>2) : 18'sd0);
    function signed [15:0] clip16(input signed [17:0] x);
        begin
            if(x>18'sd32767)clip16=16'sh7fff;
            else if(x< -18'sd32768)clip16=16'sh8000;
            else clip16=x[15:0];
        end
    endfunction
    function signed [23:0] clip24(input signed [32:0] x);
        begin
            if(x>33'sd8388607)clip24=24'sh7fffff;
            else if(x< -33'sd8388608)clip24=24'sh800000;
            else clip24=x[23:0];
        end
    endfunction
    // Maximum wet level is 0.5. The 25% feedback makes the moving comb
    // filtering easy to hear without the self-oscillation of a high-gain jet effect.
    wire signed [32:0] wet_product=$signed(delayed)*$signed({1'b0,held_gain});
    // 16-bit history is scaled back to the 24-bit DAC domain: at gain 128,
    // delayed * 128 is half of (delayed << 8).
    wire signed [32:0] wet_pcm=wet_product;
    wire signed [32:0] mixed_left=$signed({{9{held_left[23]}},held_left})+wet_pcm;
    wire signed [32:0] mixed_right=$signed({{9{held_right[23]}},held_right})+wet_pcm;
    always @(posedge clk)begin
        if(!rst && stage)delay_ram[write_addr]<=clip16(feedback_input);
        else if(!rst && accept)delayed<=delay_ram[read_addr];
    end
    always @(posedge clk)begin
        if(rst)begin
            write_addr<=0;filled<=0;held_left<=0;held_right<=0;held_mono<=0;
            held_gain<=0;held_valid<=0;stage<=0;out_left<=0;out_right<=0;out_valid<=0;
            mix_gain<=0;sweep_div<=0;sweep_pos<=0;sweep_up<=1;
        end else begin
            if(out_valid && out_ready)out_valid<=0;
            if(accept)begin
                held_left<=in_left;held_right<=in_right;
                held_mono<=mono_input;
                held_gain<=mix_gain;
                held_valid<=filled>=delay_frames;
                stage<=1;
                if(mix_gain<(enable ? ((depth>8'd128) ? 8'd128 : depth) : 8'd0))mix_gain<=mix_gain+1'b1;
                else if(mix_gain>(enable ? ((depth>8'd128) ? 8'd128 : depth) : 8'd0))mix_gain<=mix_gain-1'b1;
                if(sweep_div==8'd255)begin
                    sweep_div<=0;
                    if(sweep_up)begin
                        if(sweep_pos==9'd336)sweep_up<=0;
                        else sweep_pos<=sweep_pos+1'b1;
                    end else begin
                        if(sweep_pos==0)sweep_up<=1;
                        else sweep_pos<=sweep_pos-1'b1;
                    end
                end else sweep_div<=sweep_div+1'b1;
            end else if(stage)begin
                write_addr<=write_addr+1'b1;
                if(filled<10'd512)filled<=filled+1'b1;
                if(held_valid && held_gain!=0)begin
                    out_left<=clip24(mixed_left);
                    out_right<=clip24(mixed_right);
                end else begin
                    out_left<=held_left;out_right<=held_right;
                end
                out_valid<=1;stage<=0;
            end
        end
    end
endmodule
