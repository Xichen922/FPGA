`timescale 1ns/1ps
module tb_poly_score;
    reg clk=0,rst=1,rx=1;
    always #10 clk=~clk;
    wire tx,clear_cmd,append_cmd,play_cmd,stop_cmd,playing,gate;
    wire [3:0] append_note,current_note;
    wire [11:0] append_mask,current_keys;
    wire append_is_mask;
    wire [9:0] append_duration,count;
    wire ae,te,ee,cae,cte,cee;
    wire [1:0] ao,at,af,co,ct,cf;
    db_score_serial #(.BAUD(500000)) serial(
        .clk(clk),.rst(rst),.rx(rx),.tx(tx),.score_count(count),.playing(playing),
        .clear_cmd(clear_cmd),.append_cmd(append_cmd),.play_cmd(play_cmd),.stop_cmd(stop_cmd),
        .append_note(append_note),.append_mask(append_mask),.append_is_mask(append_is_mask),
        .append_duration(append_duration),.append_octave_enable(ae),.append_octave_code(ao),
        .append_timbre_enable(te),.append_timbre_code(at),
        .append_effect_enable(ee),.append_effect_code(af));
    db_score_player #(.CLK_HZ(100000)) player(
        .clk(clk),.rst(rst),.clock_present(1'b1),
        .clear_cmd(clear_cmd),.append_cmd(append_cmd),.play_cmd(play_cmd),.stop_cmd(stop_cmd),
        .append_note(append_note),.append_mask(append_mask),.append_is_mask(append_is_mask),
        .append_duration(append_duration),.append_octave_enable(ae),.append_octave_code(ao),
        .append_timbre_enable(te),.append_timbre_code(at),
        .append_effect_enable(ee),.append_effect_code(af),
        .score_count(count),.playing(playing),.current_note(current_note),
        .current_keys(current_keys),.current_octave_enable(cae),.current_octave_code(co),
        .current_timbre_enable(cte),.current_timbre_code(ct),
        .current_effect_enable(cee),.current_effect_code(cf),.note_gate(gate));
    task send_byte(input [7:0] b);
        integer i;
        begin
            @(negedge clk);rx=0;repeat(100)@(negedge clk);
            for(i=0;i<8;i=i+1)begin rx=b[i];repeat(100)@(negedge clk);end
            rx=1;repeat(100)@(negedge clk);
        end
    endtask
    task send_line(input string s);
        integer i;
        begin for(i=0;i<s.len();i=i+1)send_byte(s[i]);send_byte(8'h0a);end
    endtask
    task expect_keys(input [11:0] wanted);
        begin
            if(current_keys!==wanted)$fatal(1,"keys=%h expected=%h at index %0d",current_keys,wanted,player.index);
        end
    endtask
    initial begin
        repeat(20)@(negedge clk);rst=0;
        send_line("C");
        // Key 1=C, key 5=E, key 8=G; then add key 12, release E.
        send_line("M091,010,-,-,-");
        send_line("M891,010,-,-,-");
        send_line("M881,010,-,-,-");
        send_line("M000,010,-,-,-");
        repeat(10)@(negedge clk);
        if(count!=4)$fatal(1,"expected 4 mask events, got %0d",count);
        send_line("P");
        wait(player.index==0 && player.state==4);expect_keys(12'h091);
        wait(player.index==1 && player.state==4);expect_keys(12'h891);
        wait(player.index==2 && player.state==4);expect_keys(12'h881);
        wait(player.index==3 && player.state==4);expect_keys(12'h000);
        wait(!playing);expect_keys(12'h000);
        send_line("C");send_line("M00f,001");
        repeat(10)@(negedge clk);
        if(count!=1 || append_mask!=12'h00f || !append_is_mask)
            $fatal(1,"lowercase hex or short mask format failed");
        $display("PASS: four-voice mask, overlapping note release, rest, lowercase hex");
        $finish;
    end
    initial begin #100000000;$fatal(1,"timeout");end
endmodule
