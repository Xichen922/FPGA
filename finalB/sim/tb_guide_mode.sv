`timescale 1ns/1ps
module tb_guide_mode;
    reg clk=0,rst=1,rx=1;
    always #10 clk=~clk;
    reg [11:0] keys=0;
    reg [3:0] octave=4;
    wire clear_cmd,append_cmd,play_cmd,stop_cmd,guide_cmd,simple_guide_cmd;
    wire playing,guiding,simple_guiding;
    wire [11:0] append_mask,current_keys,guide_keys;
    wire [3:0] append_note;
    wire [9:0] append_duration,count;
    wire append_is_mask,ae,te,ee;
    wire [1:0] ao,at,af;
    db_score_serial #(.BAUD(500000)) serial(
        .clk(clk),.rst(rst),.rx(rx),.tx(),.score_count(count),
        .playing(playing || guiding),.clear_cmd(clear_cmd),
        .append_cmd(append_cmd),.play_cmd(play_cmd),
        .stop_cmd(stop_cmd),.guide_cmd(guide_cmd),.simple_guide_cmd(simple_guide_cmd),
        .append_note(append_note),.append_mask(append_mask),
        .append_is_mask(append_is_mask),.append_duration(append_duration),
        .append_octave_enable(ae),.append_octave_code(ao),
        .append_timbre_enable(te),.append_timbre_code(at),
        .append_effect_enable(ee),.append_effect_code(af));
    db_score_player #(.CLK_HZ(100000)) player(
        .clk(clk),.rst(rst),.clock_present(1'b1),
        .physical_keys(keys),.physical_octave(octave),
        .clear_cmd(clear_cmd),.append_cmd(append_cmd),
        .play_cmd(play_cmd),.stop_cmd(stop_cmd),.guide_cmd(guide_cmd),
        .simple_guide_cmd(simple_guide_cmd),
        .append_note(append_note),.append_mask(append_mask),
        .append_is_mask(append_is_mask),.append_duration(append_duration),
        .append_octave_enable(ae),.append_octave_code(ao),
        .append_timbre_enable(te),.append_timbre_code(at),
        .append_effect_enable(ee),.append_effect_code(af),
        .score_count(count),.playing(playing),.guiding(guiding),
        .simple_guiding(simple_guiding),.guide_allowed_keys(),
        .guide_keys(guide_keys),.current_note(),.current_keys(current_keys),
        .current_octave_enable(),.current_octave_code(),
        .current_timbre_enable(),.current_timbre_code(),
        .current_effect_enable(),.current_effect_code(),.note_gate());
    task send_byte(input [7:0] b);
        integer j;
        begin
            @(negedge clk);rx=0;repeat(100)@(negedge clk);
            for(j=0;j<8;j=j+1)begin rx=b[j];repeat(100)@(negedge clk);end
            rx=1;repeat(100)@(negedge clk);
        end
    endtask
    task send_line(input string s);
        integer j;
        begin for(j=0;j<s.len();j=j+1)send_byte(s[j]);send_byte(8'h0a);end
    endtask
    initial begin
        repeat(20)@(negedge clk);rst=0;
        send_line("M001,010,4,-,-");
        send_line("M000,010,4,-,-");
        send_line("M002,010,5,-,-");
        if(count!=3)$fatal(1,"upload failed");
        send_line("G");
        wait(guiding && guide_keys==12'h001);
        if(playing || current_keys!=0)$fatal(1,"guide caused remote playback");
        keys=12'h002;repeat(6000)@(negedge clk);
        if(guide_keys!=12'h001)$fatal(1,"wrong key advanced guide");
        keys=12'h001;repeat(6000)@(negedge clk);
        wait(guide_keys==0);
        if(current_keys!=0)$fatal(1,"guide sent remote key");
        keys=0;repeat(6000)@(negedge clk);
        wait(guide_keys==12'h002);
        keys=12'h002;repeat(6000)@(negedge clk);
        if(!guiding)$fatal(1,"wrong octave advanced guide");
        octave=5;repeat(6000)@(negedge clk);
        if(guiding)$fatal(1,"guide did not finish");
        send_line("P");wait(playing);
        if(guiding)$fatal(1,"auto playback did not exit guide");
        send_line("S");repeat(30)@(negedge clk);
        if(playing || guiding)$fatal(1,"stop failed");
        // Simple mode: old C can remain down while D is pressed. A key
        // already down when it becomes the target needs release and re-press.
        send_line("C");
        send_line("M001,010,4,-,-");
        send_line("M002,010,4,-,-");
        send_line("M002,010,4,-,-");
        octave=4;keys=0;
        send_line("H");wait(guiding && simple_guiding && guide_keys==12'h001);
        keys=12'h001;repeat(6000)@(negedge clk);
        wait(guide_keys==12'h002);
        if(!guiding || playing)$fatal(1,"H did not enter simple guide");
        keys=12'h003;repeat(6000)@(negedge clk);
        wait(guide_keys==12'h002 && player.index==2);
        repeat(6000)@(negedge clk);
        if(!guiding)$fatal(1,"repeated D advanced without fresh press");
        if(!player.guide_allowed_keys[0])$fatal(1,"old held C incorrectly marked wrong on third step");
        keys=12'h001;repeat(200)@(negedge clk);
        keys=12'h003;repeat(6000)@(negedge clk);
        if(guiding)$fatal(1,"simple guide did not finish after re-press");
        send_line("G");wait(guiding && !simple_guiding);
        send_line("S");repeat(30)@(negedge clk);
        if(guiding)$fatal(1,"stop did not exit simple/normal mode");
        $display("PASS: G normal, H simple with held old key and repeated-note re-press, P and S");
        $finish;
    end
    initial begin #100000000;$fatal(1,"timeout");end
endmodule
