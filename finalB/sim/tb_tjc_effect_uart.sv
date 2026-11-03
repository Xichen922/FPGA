`timescale 1ns/1ps
module tb_tjc_effect_uart;
    reg clk=0,rst_n=0;
    always #5 clk=~clk;
    reg [11:0] keys=0;
    reg guide_active=0;
    reg [11:0] guide_keys=0;
    reg [1:0] effect_mode=0,timbre=0;
    reg [7:0] effect_depth=0;
    reg [3:0] octave=4;
    wire tx;
    wire [6:0] wave_address;
    wire wave_ack;
    wire [7:0] wave_data=8'd40+{1'b0,wave_address};
    integer output_file,bit_index,byte_count=0;
    reg [7:0] received;
    reg [8*16-1:0] recent_bytes=0;
    reg press_0=0,press_11=0,release_0=0,release_11=0;
    reg label_timbre=0,label_octave=0,label_effect=0,page_selected=0;
    reg echo_label=0,reverse_label=0;
    reg mode_text=0,depth_bar=0;
    reg hint_0=0,wrong_1=0,correct_0=0;
    tjc_display_uart #(.CLK_HZ(1000000),.BAUD(100000),.STARTUP_CYCLES(10),
        .STATUS_REFRESH_CYCLES(100000),.WAVE_CYCLES(10000000)) dut(
        .clk(clk),.rst_n(rst_n),.keys(keys),.guide_active(guide_active),.guide_keys(guide_keys),.guide_allowed_keys(guide_keys),.play_mode(2'd0),.timbre(timbre),.effect_mode(effect_mode),
        .effect_depth(effect_depth),
        .octave(octave),.sound_active(1'b0),
        .wave_ready(1'b1),.wave_data(wave_data),.wave_address(wave_address),
        .wave_ack(wave_ack),.tx(tx));
    // Independent 8N1 receiver samples the physical TX pin, not the internal byte interface.
    always @(negedge tx)if(rst_n)begin
        repeat(5)@(posedge clk);#1;
        if(tx!==0)$fatal(1,"UART start bit");
        for(bit_index=0;bit_index<8;bit_index=bit_index+1)begin
            repeat(10)@(posedge clk);#1;received[bit_index]=tx;
        end
        repeat(10)@(posedge clk);#1;
        if(tx!==1)$fatal(1,"UART stop bit");
        $fwrite(output_file,"%02x ",received);byte_count=byte_count+1;
        recent_bytes={recent_bytes[8*15-1:0],received};
        if(recent_bytes[8*6-1:0]=="page 0") page_selected=1;
        if(recent_bytes[8*11-1:0]=="t0.bco=9942") press_0=1;
        if(recent_bytes[8*12-1:0]=="t0.bco=65504") hint_0=1;
        if(recent_bytes[8*12-1:0]=="t1.bco=63488") wrong_1=1;
        if(hint_0 && recent_bytes[8*11-1:0]=="t0.bco=9942") correct_0=1;
        if(recent_bytes[8*12-1:0]=="t11.bco=9942") press_11=1;
        if(recent_bytes[8*11-1:0]=="t0.bco=6471") release_0=1;
        if(recent_bytes[8*12-1:0]=="t11.bco=6471") release_11=1;
        if(recent_bytes[8*8-1:0]=="t12.txt=") label_timbre=1;
        if(recent_bytes[8*8-1:0]=="t13.txt=") label_octave=1;
        if(recent_bytes[8*8-1:0]=="t14.txt=") label_effect=1;
        if(recent_bytes[8*8-1:0]=="t15.txt=") mode_text=1;
        if(recent_bytes[8*10-1:0]=="j0.val=075") depth_bar=1;
        if(recent_bytes[8*14-1:0]=={8'h74,8'h31,8'h34,8'h2e,8'h74,8'h78,8'h74,8'h3d,8'h22,8'hbb,8'hd8,8'hc9,8'hf9,8'h22}) echo_label=1;
        if(recent_bytes[8*16-1:0]=={8'h31,8'h34,8'h2e,8'h74,8'h78,8'h74,8'h3d,8'h22,8'hb5,8'hb9,8'hb7,8'hc5,8'hce,8'hb2,8'hd2,8'hf4}) reverse_label=1;
    end
    initial begin
        output_file=$fopen("sim/results/effect_uart_bytes.txt","w");
        if(!output_file)$fatal(1,"UART capture open");
        repeat(4)@(negedge clk);rst_n=1;
        repeat(65000)@(negedge clk);
        effect_mode=1;effect_depth=96;timbre=1;octave=5;keys=12'h801;
        repeat(14000)@(negedge clk);
        effect_mode=2;
        repeat(10000)@(negedge clk);
        effect_mode=0;keys=0;
        repeat(150000)@(negedge clk); // unchanged labels must recover after a screen-only restart.
        effect_mode=1;repeat(600)@(negedge clk);effect_mode=2;
        repeat(15000)@(negedge clk);
        wait(dut.state==0 && dut.tx_ready);repeat(20)@(negedge clk);
        if(byte_count<700)$fatal(1,"Insufficient UART capture");
        if(!press_0 || !press_11 || !release_0 || !release_11)
            $fatal(1,"HMI key background commands missing: press=%b%b release=%b%b",
                press_0,press_11,release_0,release_11);
        if(!page_selected)$fatal(1,"HMI page0 selection missing");
        if(!label_timbre || !label_octave || !label_effect)
            $fatal(1,"HMI status widget mapping wrong: t12/t13/t14=%b%b%b",
                label_timbre,label_octave,label_effect);
        if(!echo_label)$fatal(1,"HMI did not transmit GB2312 echo label");
        if(!reverse_label)$fatal(1,"HMI did not transmit GB2312 reverse-tail label");
        if(!mode_text || !depth_bar)$fatal(1,"HMI mode/depth widgets missing: t15=%b j0=%b",mode_text,depth_bar);
        guide_active=1;guide_keys=12'h001;keys=0;
        wait(hint_0);repeat(100)@(negedge clk);
        keys=12'h002;wait(wrong_1);repeat(100)@(negedge clk);
        keys=12'h001;wait(correct_0);repeat(100)@(negedge clk);
        guide_active=0;guide_keys=0;keys=0;
        $fclose(output_file);
        $display("PASS physical UART capture: natural/echo/reverse-tail, periodic refresh, keys, timbre and octave; %0d bytes",byte_count);
        $finish;
    end
    initial begin #5000000;$fatal(1,"UART effect timeout");end
endmodule


