`timescale 1ns/1ps
// Run against A37's real SPI master, packet decoder, note latch and voice map.
module tb_b42_a37_spi;
    reg clk=0,rst=1;
    always #10 clk=~clk;
    reg clear_cmd=0,append_cmd=0,play_cmd=0;
    reg [11:0] append_mask=0;
    reg [1:0] append_octave_code=0;
    wire [9:0] score_count;
    wire playing,note_gate;
    wire [11:0] score_key,remote_keys;
    wire [1:0] score_octave_code;
    wire score_octave_enable;
    db_score_player #(.CLK_HZ(50000000)) player(
        .clk(clk),.rst(rst),.clock_present(1'b1),
        .clear_cmd(clear_cmd),.append_cmd(append_cmd),.play_cmd(play_cmd),.stop_cmd(1'b0),
        .append_note(4'd0),.append_mask(append_mask),.append_is_mask(1'b1),
        .append_duration(10'd1),
        .append_octave_enable(1'b1),.append_octave_code(append_octave_code),
        .append_timbre_enable(1'b0),.append_timbre_code(2'd0),
        .append_effect_enable(1'b0),.append_effect_code(2'd0),
        .score_count(score_count),.playing(playing),.current_note(),
        .current_keys(score_key),.current_octave_enable(score_octave_enable),
        .current_octave_code(score_octave_code),
        .current_timbre_enable(),.current_timbre_code(),
        .current_effect_enable(),.current_effect_code(),.note_gate(note_gate));
    function [7:0] checksum(input [111:0] payload);
        integer i;
        begin checksum=0;for(i=0;i<14;i=i+1)checksum=checksum^payload[i*8+:8];end
    endfunction
    wire [111:0] b_payload={{8'hb6,8'h32,48'd0},score_key,
        playing,score_octave_code,(playing && score_octave_enable),
        2'd0,1'b0,29'd0};
    wire [127:0] b_status={b_payload,checksum(b_payload),8'h5a};
    wire cs_n,sclk,mosi,miso;
    wire [127:0] a_status,a_received;
    wire a_valid;
    db_spi_master #(.HALF_CYCLES(25),.POLL_CYCLES(50000)) a_spi(
        .clk(clk),.rst(rst),.tx_packet(a_status),.miso(miso),
        .cs_n(cs_n),.sclk(sclk),.mosi(mosi),.rx_packet(a_received),.rx_valid(a_valid));
    db_spi_slave b_spi(.clk(clk),.rst(rst),.cs_n(cs_n),.sclk(sclk),.mosi(mosi),
        .tx_packet(b_status),.miso(miso),.rx_packet(),.rx_valid(),.framing_error());
    wire remote_octave_enable,remote_timbre_enable,link_good,vibrato_enable;
    wire [3:0] remote_octave;
    wire [1:0] remote_timbre;
    wire [15:0] performed_keys={4'd0,remote_keys};
    wire [3:0] selected_octave=remote_octave_enable ? remote_octave : 4'd4;
    db_master_controls #(.TIMEOUT_CYCLES(500000)) a_controls(
        .clk(clk),.rst(rst),.keys(performed_keys),.octave(selected_octave),
        .timbre(2'd0),.any_active(|remote_keys),.active_voices(remote_keys),
        .encoder_delta(8'd0),.encoder_valid(1'b0),
        .rx_packet(a_received),.rx_valid(a_valid),.tx_packet(a_status),
        .vibrato_enable(vibrato_enable),.link_good(link_good),
        .remote_keys(remote_keys),.remote_octave_enable(remote_octave_enable),
        .remote_octave(remote_octave),.remote_timbre_enable(remote_timbre_enable),
        .remote_timbre(remote_timbre));
    reg [11:0] previous_remote_keys=0;
    always @(posedge clk)if(rst)previous_remote_keys<=0;
                         else previous_remote_keys<=remote_keys;
    wire [11:0] note_gate_a,note_press_a,voice_gate,voice_trigger;
    integer c_triggers=0,b_triggers=0,e_triggers=0;
    reg second_phase=0;
    time second_c_at=0,second_e_at=0,second_b_at=0;
    always @(posedge clk)if(!rst)begin
        if(voice_trigger[0])c_triggers=c_triggers+1;
        if(voice_trigger[11])b_triggers=b_triggers+1;
        if(voice_trigger[4])e_triggers=e_triggers+1;
        if(second_phase)begin
            if(voice_trigger[0] && second_c_at==0)second_c_at=$time;
            if(voice_trigger[4] && second_e_at==0)second_e_at=$time;
            if(voice_trigger[11] && second_b_at==0)second_b_at=$time;
        end
    end
    wire [47:0] note_octaves,voice_octaves;
    wire control_valid;
    touch_note_control a_note(.clk(clk),.rst(rst),.key_mask(performed_keys),
        .key_valid(remote_keys!=previous_remote_keys),
        .selected_octave(selected_octave),.control_valid(control_valid),
        .note_gate(note_gate_a),.note_press(note_press_a),
        .note_octaves(note_octaves),.octave(),.hold_enabled());
    voice_mapper_12 a_voice(.clk(clk),.rst(rst),.control_valid(control_valid),
        .sample_tick(1'b0),.glide_samples(15'd0),
        .note_gate(note_gate_a),.note_press(note_press_a),
        .note_octaves(note_octaves),.voice_gate(voice_gate),
        .voice_trigger(voice_trigger),.voice_steps(),.voice_octaves(voice_octaves));
    task add(input [11:0] mask,input [1:0] octave);
        begin
            @(negedge clk);append_mask=mask;append_octave_code=octave;append_cmd=1;
            @(negedge clk);append_cmd=0;
        end
    endtask
    task reached(input [11:0] mask);
        begin
            wait(voice_gate==mask);
            @(negedge clk);
        end
    endtask
    initial begin
        repeat(20)@(negedge clk);rst=0;
        add(12'h001,2'd1); // C4
        add(12'h801,2'd2); // C4+B5
        add(12'h800,2'd2); // B5
        add(12'h810,2'd1); // B5+E4
        add(12'h000,2'd1);
        @(negedge clk);play_cmd=1;
        @(negedge clk);play_cmd=0;
        reached(12'h001);
        if(voice_octaves[3:0]!=4 || !link_good)$fatal(1,"C4 did not start correctly");
        wait(player.index==1 && player.state==3);
        wait(remote_octave_enable && remote_octave==5);
        if(voice_gate!==12'h001 || score_key!==12'h001 ||
           voice_octaves[3:0]!=4)$fatal(1,"C4 changed during B5 preload");
        reached(12'h801);
        if(voice_octaves[3:0]!=4 || voice_octaves[47:44]!=5)
            $fatal(1,"C4+B5 latched wrong octaves");
        reached(12'h800);
        if(voice_octaves[47:44]!=5)$fatal(1,"B5 changed when C4 was released");
        wait(player.index==3 && player.state==3);
        wait(remote_octave==4);
        if(voice_gate!==12'h800 || score_key!==12'h800 ||
           voice_octaves[47:44]!=5)$fatal(1,"B5 changed during E4 preload");
        reached(12'h810);
        if(voice_octaves[47:44]!=5 || voice_octaves[19:16]!=4)
            $fatal(1,"B5+E4 latched wrong octaves");
        reached(12'h000);
        if(c_triggers!=1 || b_triggers!=1 || e_triggers!=1)
            $fatal(1,"unexpected retrigger C/B/E = %0d/%0d/%0d",
                c_triggers,b_triggers,e_triggers);
        wait(!playing);
        @(negedge clk);clear_cmd=1;
        @(negedge clk);clear_cmd=0;
        add(12'h011,2'd1); // C4+E4 starts at nominal same instant as B5
        add(12'h811,2'd2); // add B5 in next minimum 10 ms event
        second_phase=1;
        @(negedge clk);play_cmd=1;
        @(negedge clk);play_cmd=0;
        wait(second_c_at!=0 && second_e_at!=0 && second_b_at!=0);
        if((second_b_at-second_c_at)<9000000 ||
           (second_b_at-second_c_at)>12000000 ||
           (second_b_at-second_e_at)<9000000 ||
           (second_b_at-second_e_at)>12000000)
            $fatal(1,"same-beat stagger outside 9-12 ms: C=%0d E=%0d B=%0d",
                second_c_at,second_e_at,second_b_at);
        $display("Same-beat split onset skew B-C=%0d ns, B-E=%0d ns",
            second_b_at-second_c_at,second_b_at-second_e_at);
        $display("PASS: real A37 SPI decode and per-key octave latch keep C4/B5 while adding B5/E4");
        $finish;
    end
    initial begin #100000000;$fatal(1,"timeout at index=%0d, keys=%h/%h, link=%b",player.index,score_key,voice_gate,link_good);end
endmodule
