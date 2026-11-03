`timescale 1ns/1ps
// Four-ms front-loaded strike, register-specific settle/tail/release.
// Q16 energy; one loadable context engine for twelve independent notes.
module latb_piano_context #(
    parameter integer ATTACK_LOW=391,ATTACK_MID=391,ATTACK_HIGH=391
)(input wire clk,rst,sample_tick,trigger,gate,
    input wire [3:0] octave,input wire context_load,
    input wire [45:0] context_in,output wire [45:0] context_out,
    output wire [15:0] level,output wire active,output reg [2:0] state);
    localparam [31:0] PEAK=32'hffff0000;
    localparam [31:0] EARLY_PEAK=(PEAK>>2)*3;
    localparam integer EL=(ATTACK_LOW/8<1)?1:ATTACK_LOW/8;
    localparam integer EM=(ATTACK_MID/8<1)?1:ATTACK_MID/8;
    localparam integer EH=(ATTACK_HIGH/8<1)?1:ATTACK_HIGH/8;
    localparam integer LL=(ATTACK_LOW>EL)?ATTACK_LOW-EL:1;
    localparam integer LM=(ATTACK_MID>EM)?ATTACK_MID-EM:1;
    localparam integer LH=(ATTACK_HIGH>EH)?ATTACK_HIGH-EH:1;
    reg [31:0] energy;
    reg [8:0] attack_count;
    reg [1:0] register_index;
    wire [8:0] attack_length=(register_index==0)?ATTACK_LOW:(register_index==1)?ATTACK_MID:ATTACK_HIGH;
    wire [8:0] early_length=(register_index==0)?EL:(register_index==1)?EM:EH;
    wire early_attack=(attack_count<early_length);
    wire [31:0] attack_step=early_attack ?
        ((register_index==0)?EARLY_PEAK/EL:(register_index==1)?EARLY_PEAK/EM:EARLY_PEAK/EH) :
        ((register_index==0)?(PEAK-EARLY_PEAK)/LL:(register_index==1)?(PEAK-EARLY_PEAK)/LM:(PEAK-EARLY_PEAK)/LH);
    wire [31:0] settle_target=(register_index==0)?32'd1932705792:
        (register_index==1)?32'd1288470528:32'd773082316;
    wire [31:0] initial_loss=(register_index==0)?(energy>>14):
        (register_index==1)?(energy>>13):(energy>>12);
    wire [31:0] held_loss_raw=(register_index==0)?((energy>>17)+(energy>>19)):
        (register_index==1)?(energy>>16):(energy>>15);
    wire [31:0] release_loss=(register_index==0)?((energy>>15)+(energy>>16)):
        (register_index==1)?((energy>>14)+(energy>>16)):(energy>>13);
    // Reduce loss to 3/4: about 33% longer decay, with unchanged settle levels.
    wire [31:0] raw_decay=(state==2)?initial_loss:(state==4)?release_loss:held_loss_raw;
    wire [31:0] slowed_decay=raw_decay-(raw_decay>>2);
    wire [31:0] loss=(state==1)?-attack_step:(slowed_decay!=0)?slowed_decay:32'd1;
    wire [31:0] next_energy=energy-loss;
    assign context_out={register_index,attack_count,state,energy};
    assign level=energy[31:16];
    assign active=(state!=0);
    always @(posedge clk)begin
        if(context_load){register_index,attack_count,state,energy}<=context_in;
        else if(rst)begin register_index<=0;attack_count<=0;state<=0;energy<=0;end
        else if(trigger)begin
            register_index<=octave<=3?2'd0:octave==4?2'd1:2'd2;
            attack_count<=0;state<=1;energy<=0;
        end else if(sample_tick)begin
            if(state==0)energy<=0;
            else if(!gate && state!=4)state<=4;
            else begin
                energy<=next_energy;
                if(state==1)begin
                    attack_count<=attack_count+1'b1;
                    if(early_attack && attack_count==early_length-1'b1)energy<=EARLY_PEAK;
                    if(attack_count==attack_length-1'b1)begin energy<=PEAK;state<=2;end
                end else if(state==2 && next_energy<=settle_target)begin
                    energy<=settle_target;state<=3;
                end else if(energy<=32'h00008000)begin energy<=0;state<=0;end
            end
        end
    end
    // synthesis translate_off
    initial if(ATTACK_LOW<1 || ATTACK_MID<1 || ATTACK_HIGH<1 ||
        ATTACK_LOW>511 || ATTACK_MID>511 || ATTACK_HIGH>511)$fatal(1,"invalid piano attack length");
    // synthesis translate_on
endmodule
