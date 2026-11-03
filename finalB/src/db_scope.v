`timescale 1ns/1ps
// Capture the actual PCM sent to the DAC, then hold one coherent 128-point
// frame until the independent HMI UART has consumed it. No audio backpressure.
module db_scope(
    input wire clk, rst, sample_valid,
    input wire signed [23:0] sample,
    input wire [3:0] octave,
    input wire [11:0] keys,
    input wire [6:0] address,
    output wire [7:0] data,
    output reg ready,
    input wire acknowledge
);
    reg signed [23:0] points[0:127];
    reg signed [23:0] previous_sample;
    reg [23:0] peak;
    reg [6:0] write_address;
    reg [2:0] skip_count, skip_reload;
    reg [9:0] sample_period, phase_acc;
    reg [12:0] trigger_wait;
    reg capturing;
    // 128 points span about 10.5/5.2/2.6 ms at 97.656 kHz for low/mid/high.
    wire [2:0] requested_skip=(octave<=4'd3) ? 3'd7 :
                              (octave>=4'd5) ? 3'd1 : 3'd3;
    // With exactly one key held, spread 128 points over one period of its
    // fundamental. C4..B4 periods are in 97.65625 kHz PCM samples.
    wire single_key=(keys!=12'd0) && ((keys & (keys-12'd1))==12'd0);
    reg [8:0] middle_period;
    integer note_index;
    always @* begin
        middle_period=9'd373;
        for(note_index=0;note_index<12;note_index=note_index+1)
            if(keys[note_index]) begin
                case(note_index)
                    0:middle_period=9'd373; 1:middle_period=9'd352;
                    2:middle_period=9'd333; 3:middle_period=9'd314;
                    4:middle_period=9'd296; 5:middle_period=9'd280;
                    6:middle_period=9'd264; 7:middle_period=9'd249;
                    8:middle_period=9'd235; 9:middle_period=9'd222;
                    10:middle_period=9'd209;11:middle_period=9'd198;
                endcase
            end
    end
    wire [9:0] octave_period=(octave<=4'd3) ? {middle_period,1'b0} :
                              (octave>=4'd5) ? {1'b0,middle_period[8:1]} :
                                               {1'b0,middle_period};
    // High notes can have fewer than 128 PCM samples per cycle. Use each
    // available sample once, giving a little over one cycle in that case.
    wire [9:0] requested_period=(octave_period<10'd128) ? 10'd128 : octave_period;
    wire [10:0] phase_difference=next_phase-{1'b0,sample_period};
    wire [10:0] next_phase={1'b0,phase_acc}+11'd128;
    wire [23:0] magnitude=sample[23] ? (~sample+24'd1) : sample;
    wire rising_zero=previous_sample[23] && !sample[23];

    // One gain for the whole frozen frame keeps its shape stable. Pick a
    // power-of-two visual gain from the captured peak; this never changes PCM.
    reg [4:0] visual_shift;
    always @* begin
        if(peak[23]) visual_shift=17;
        else if(peak[22]) visual_shift=16;
        else if(peak[21]) visual_shift=15;
        else if(peak[20]) visual_shift=14;
        else if(peak[19]) visual_shift=13;
        else if(peak[18]) visual_shift=12;
        else if(peak[17]) visual_shift=11;
        else if(peak[16]) visual_shift=10;
        else if(peak[15]) visual_shift=9;
        else if(peak[14]) visual_shift=8;
        else if(peak[13]) visual_shift=7;
        else if(peak[12]) visual_shift=6;
        else if(peak[11]) visual_shift=5;
        else if(peak[10]) visual_shift=4;
        else if(peak[9]) visual_shift=3;
        else if(peak[8]) visual_shift=2;
        else if(peak[7]) visual_shift=1;
        else visual_shift=0;
    end
    // Registered display read separates the snapshot RAM from gain/clipping.
    // UART gives the read one settling clock after each address change.
    reg signed [23:0] display_point;
    always @(posedge clk) display_point<=points[address];
    wire signed [24:0] normalized=$signed({display_point[23],display_point}) >>> visual_shift;
    // The s0 widget in 嵌赛3.HMI is 200 pixels high, not 256. Keep the
    // peak below 100 pixels so zero=100 is centered without flat-top clipping.
    wire signed [24:0] scaled=normalized-(normalized >>> 2);
    wire signed [25:0] plotted=$signed({scaled[24],scaled})+26'sd100;
    assign data=(plotted<26'sd5) ? 8'd5 :
                (plotted>26'sd195) ? 8'd195 : plotted[7:0];

    always @(posedge clk) begin
        if(rst) begin
            ready<=0;
            capturing<=0;
            previous_sample<=0;
            peak<=0;
            write_address<=0;
            skip_count<=0;
            skip_reload<=0;
            sample_period<=0;
            phase_acc<=0;
            trigger_wait<=0;
        end else if(acknowledge) begin
            ready<=0;
            capturing<=0;
            write_address<=0;
            skip_count<=0;
            phase_acc<=0;
            trigger_wait<=0;
        end else if(sample_valid && !ready) begin
            previous_sample<=sample;
            if(!capturing) begin
                // Rising zero crossing aligns single notes. Silence and
                // nonperiodic sounds still refresh after about 42 ms.
                if(rising_zero || trigger_wait==13'd4095) begin
                    points[0]<=sample;
                    peak<=magnitude;
                    write_address<=7'd1;
                    skip_reload<=requested_skip;
                    skip_count<=requested_skip;
                    sample_period<=single_key ? requested_period : 10'd0;
                    phase_acc<=0;
                    capturing<=1;
                    trigger_wait<=0;
                end else trigger_wait<=trigger_wait+1'b1;
            end else if(sample_period!=0 && next_phase<{1'b0,sample_period})
                phase_acc<=next_phase[9:0];
            else if(sample_period==0 && skip_count!=0)
                skip_count<=skip_count-1'b1;
            else begin
                points[write_address]<=sample;
                if(magnitude>peak) peak<=magnitude;
                skip_count<=skip_reload;
                if(sample_period!=0) phase_acc<=phase_difference[9:0];
                if(write_address==7'd127) begin
                    capturing<=0;
                    ready<=1;
                end else write_address<=write_address+1'b1;
            end
        end
    end
endmodule
