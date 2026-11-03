`timescale 1ns/1ps
// B-side scheduling check. The A37 SPI/voice check needs the actual A37 source.
module tb_cross_octave;
    reg clk=0,rst=1;
    always #10 clk=~clk;
    reg clear_cmd=0,append_cmd=0,play_cmd=0,stop_cmd=0;
    reg [11:0] append_mask=0;
    reg [1:0] append_octave_code=0;
    reg append_octave_enable=1;
    wire [9:0] score_count;
    wire playing,note_gate;
    wire [11:0] current_keys;
    wire [1:0] current_octave_code;
    wire current_octave_enable;
    time started_at;
    db_score_player #(.CLK_HZ(100000)) player(
        .clk(clk),.rst(rst),.clock_present(1'b1),
        .clear_cmd(clear_cmd),.append_cmd(append_cmd),
        .play_cmd(play_cmd),.stop_cmd(stop_cmd),
        .append_note(4'd0),.append_mask(append_mask),.append_is_mask(1'b1),
        .append_duration(10'd50),
        .append_octave_enable(append_octave_enable),.append_octave_code(append_octave_code),
        .append_timbre_enable(1'b0),.append_timbre_code(2'd0),
        .append_effect_enable(1'b0),.append_effect_code(2'd0),
        .score_count(score_count),.playing(playing),.current_note(),
        .current_keys(current_keys),.current_octave_enable(current_octave_enable),
        .current_octave_code(current_octave_code),
        .current_timbre_enable(),.current_timbre_code(),
        .current_effect_enable(),.current_effect_code(),.note_gate(note_gate));
    task add(input [11:0] mask,input [1:0] octave);
        begin
            @(negedge clk);append_mask=mask;append_octave_code=octave;append_cmd=1;
            @(negedge clk);append_cmd=0;
        end
    endtask
    task check(input [9:0] target_index,input [2:0] target_state,
               input [11:0] expected_keys,input [1:0] expected_octave);
        begin
            wait(player.index==target_index && player.state==target_state);
            @(negedge clk);
            if(current_keys!==expected_keys || current_octave_code!==expected_octave)
                $fatal(1,"index=%0d state=%0d keys=%h octave=%0d expected=%h/%0d",
                    player.index,player.state,current_keys,current_octave_code,
                    expected_keys,expected_octave);
        end
    endtask
    initial begin
        repeat(20)@(negedge clk);rst=0;
        add(12'h001,2'd1); // C4
        add(12'h801,2'd2); // C4 + B5
        add(12'h800,2'd2); // release C, hold B5
        add(12'h810,2'd1); // B5 + E4
        add(12'h000,2'd1); // release all
        if(score_count!=5)$fatal(1,"wrong score length");
        @(negedge clk);started_at=$time;play_cmd=1;
        @(negedge clk);play_cmd=0;
        check(0,3,12'h000,2'd1);
        check(0,4,12'h001,2'd1);
        check(1,3,12'h001,2'd2);
        check(1,4,12'h801,2'd2);
        check(2,4,12'h800,2'd2);
        check(3,3,12'h800,2'd1);
        check(3,4,12'h810,2'd1);
        check(4,4,12'h000,2'd1);
        wait(!playing);
        if(current_keys!=0)$fatal(1,"keys not released at end");
        if(($time-started_at)<4990000 || ($time-started_at)>5010000)
            $fatal(1,"octave preload stretched song: %0d ns",$time-started_at);
        @(negedge clk);play_cmd=1;
        @(negedge clk);play_cmd=0;
        check(0,3,12'h000,2'd1);
        check(0,4,12'h001,2'd1);
        @(negedge clk);stop_cmd=1;
        @(negedge clk);stop_cmd=0;
        if(playing || current_keys!=0)$fatal(1,"stop after replay did not release keys");
        @(negedge clk);clear_cmd=1;
        @(negedge clk);clear_cmd=0;
        add(12'h001,2'd2);
        append_octave_enable=0;
        add(12'h011,2'd0);
        @(negedge clk);play_cmd=1;
        @(negedge clk);play_cmd=0;
        check(0,3,12'h000,2'd2);
        check(0,4,12'h001,2'd2);
        wait(player.index==1 && player.state==3);
        @(negedge clk);
        if(current_keys!=12'h001 || current_octave_enable)
            $fatal(1,"auto-to-manual octave did not preserve held key");
        check(1,4,12'h011,2'd0);
        $display("PASS: kept C4 during B5 octave preload, kept B5 during E4 preload");
        $finish;
    end
    initial begin #100000000;$fatal(1,"timeout");end
endmodule
