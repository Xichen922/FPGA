`timescale 1ns/1ps
module tb_tjc_mode_uart;
    reg clk=0,rst_n=0;
    always #5 clk=~clk;
    reg [1:0] play_mode=0;
    wire tx;
    wire [6:0] wave_address;
    wire wave_ack;
    tjc_display_uart #(.CLK_HZ(1000000),.BAUD(100000),
        .STARTUP_CYCLES(10),.STATUS_REFRESH_CYCLES(10000000),
        .WAVE_CYCLES(10000000)) dut(
        .clk(clk),.rst_n(rst_n),.keys(12'd0),.guide_active(1'b0),
        .guide_keys(12'd0),.guide_allowed_keys(12'd0),
        .play_mode(play_mode),.timbre(2'd0),.effect_mode(2'd0),
        .effect_depth(8'd0),.octave(4'd4),.sound_active(1'b0),
        .wave_ready(1'b0),.wave_data(8'd0),.wave_address(wave_address),
        .wave_ack(wave_ack),.tx(tx));
    integer bit_index,ff_count=0,widget_count=0,ref_count=0;
    reg [7:0] received;
    string command_text="";
    reg manual_seen=0,auto_seen=0,guide_seen=0;
    always @(negedge tx) if(rst_n) begin
        repeat(5) @(posedge clk); #1;
        if(tx!==0) $fatal(1,"UART start bit");
        for(bit_index=0;bit_index<8;bit_index=bit_index+1) begin
            repeat(10) @(posedge clk); #1; received[bit_index]=tx;
        end
        repeat(10) @(posedge clk); #1;
        if(tx!==1) $fatal(1,"UART stop bit");
        if(received==8'hff) begin
            ff_count=ff_count+1;
            if(ff_count==3) begin
                if(command_text=="ref t15") ref_count=ref_count+1;
                if(command_text=={"t15.txt=\"",8'hca,8'hd6,8'hb6,8'haf,8'h22} ||
                   command_text=={"t15.txt=\"",8'hd7,8'hd4,8'hb6,8'haf,8'h22} ||
                   command_text=={"t15.txt=\"",8'hb8,8'ha8,8'hd6,8'hfa,8'h22})
                    widget_count=widget_count+1;
                if(command_text=={"t15.txt=\"",8'hca,8'hd6,8'hb6,8'haf,8'h22}) manual_seen=1;
                if(command_text=={"t15.txt=\"",8'hd7,8'hd4,8'hb6,8'haf,8'h22}) auto_seen=1;
                if(command_text=={"t15.txt=\"",8'hb8,8'ha8,8'hd6,8'hfa,8'h22}) guide_seen=1;
                command_text="";ff_count=0;
            end
        end else begin
            if(ff_count!=0) $fatal(1,"Unexpected FF inside command");
            command_text={command_text,received};
        end
    end
    initial begin
        repeat(4) @(negedge clk); rst_n=1;
        wait(manual_seen); play_mode=1;
        wait(auto_seen); play_mode=2;
        wait(guide_seen); play_mode=0;
        // Manual must be sent again when playback/practice ends.
        wait(widget_count>=4 && dut.sent_mode==0 && dut.force_mode==0);
        if(widget_count!=4 || ref_count!=4)
            $fatal(1,"Mode command counts: text=%0d ref=%0d",widget_count,ref_count);
        $display("PASS mode display: manual, automatic, assist, manual; commands=%0d",widget_count);
        $finish;
    end
    initial begin #3000000; $fatal(1,"Mode UART timeout"); end
endmodule
