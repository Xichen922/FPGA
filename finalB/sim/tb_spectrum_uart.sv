`timescale 1ns/1ps
module tb_spectrum_uart;
    reg clk=0,rst_n=0;
    always #5 clk=~clk;
    reg [11:0] keys=0;
    reg [1:0] timbre=0;
    reg [3:0] octave=4;
    wire tx;
    wire [6:0] wave_address;
    wire wave_ack;
    integer bit_index,ff_count=0,fill_count=0,add_count=0,black_count=0;
    integer c4_draw_count=0;
    reg [7:0] received;
    string command_text="";
    reg saw_hide=0,saw_background=0,saw_c4_erase=0,saw_c4_bar=0;
    tjc_display_uart #(.CLK_HZ(1000000),.BAUD(100000),
        .STARTUP_CYCLES(10),.STATUS_REFRESH_CYCLES(10000000),
        .WAVE_CYCLES(500)) dut (
        .clk(clk),.rst_n(rst_n),.keys(keys),.guide_active(1'b0),.guide_keys(12'd0),
        .guide_allowed_keys(12'd0),.play_mode(2'd0),.timbre(timbre),
        .effect_mode(2'd0),.effect_depth(8'd0),.octave(octave),
        .sound_active(1'b1),.wave_ready(1'b1),.wave_data(8'd0),
        .wave_address(wave_address),.wave_ack(wave_ack),.tx(tx));
    always @(negedge tx) if(rst_n) begin
        repeat(5) @(posedge clk); #1;
        if(tx!==0) $fatal(1,"UART start bit");
        for(bit_index=0;bit_index<8;bit_index=bit_index+1) begin
            repeat(10) @(posedge clk); #1;
            received[bit_index]=tx;
        end
        repeat(10) @(posedge clk); #1;
        if(tx!==1) $fatal(1,"UART stop bit");
        if(received==8'hff) begin
            ff_count=ff_count+1;
            if(ff_count==3) begin
                if(command_text=="vis s0,0") saw_hide=1;
                if(command_text=="fill 025,235,220,200,6471") saw_background=1;
                if(command_text=="fill 079,340,010,090,6471") saw_c4_erase=1;
                if(command_text=="fill 079,350,010,080,2047") begin
                    saw_c4_bar=1;c4_draw_count=c4_draw_count+1;
                end
                if(command_text.len()>=4 &&
                   command_text.substr(command_text.len()-4,command_text.len()-1)=="0000")
                    black_count=black_count+1;
                if(command_text.len()>=4 && command_text.substr(0,3)=="fill")
                    fill_count=fill_count+1;
                if(command_text.len()>=3 && command_text.substr(0,2)=="add")
                    add_count=add_count+1;
                command_text="";ff_count=0;
            end
        end else begin
            ff_count=0;
            command_text={command_text,received};
        end
    end
    initial begin
        repeat(4) @(negedge clk);rst_n=1;
        repeat(100000) @(negedge clk);
        keys=12'h001; // C4: fundamental band 4, second harmonic band 8.
        repeat(120000) @(negedge clk);
        if(!saw_hide || !saw_background) $fatal(1,"spectrum startup commands missing");
        if(dut.shown_height[4]!=80 || dut.shown_height[8]!=60)
            $fatal(1,"C4 spectrum bins: fundamental=%0d octave=%0d",
                dut.shown_height[4],dut.shown_height[8]);
        if(!saw_c4_bar) $fatal(1,"full-height C4 bar not sent");
        if(c4_draw_count<2) $fatal(1,"unchanged bar was not restored periodically");
        if(black_count!=0) $fatal(1,"pure-black fill causes video artifact");
        if(add_count!=0) $fatal(1,"legacy waveform add commands still active");
        if(fill_count>45) $fatal(1,"display command flood: %0d fills",fill_count);
        timbre=1; // Clarinet: odd harmonics dominate.
        repeat(120000) @(negedge clk);
        if(dut.shown_height[4]!=90 || dut.shown_height[8]!=2 ||
           dut.shown_height[10]!=52)
            $fatal(1,"clarinet profile: %0d %0d %0d",
                dut.shown_height[4],dut.shown_height[8],dut.shown_height[10]);
        octave=5; // C5 moves up four three-semitone bands.
        repeat(120000) @(negedge clk);
        if(dut.shown_height[4]!=0 || dut.shown_height[8]!=90)
            $fatal(1,"octave shift: old=%0d new=%0d",
                dut.shown_height[4],dut.shown_height[8]);
        if(!saw_c4_erase) $fatal(1,"released band was not erased in native background color");
        $display("PASS spectrum: C4 harmonics, clarinet profile, octave move, incremental fill; fills=%0d",fill_count);
        $finish;
    end
    initial begin #5000000;$fatal(1,"spectrum test timeout");end
endmodule

