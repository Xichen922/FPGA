`timescale 1ns/1ps
module tb_score_automation;
    reg clk=0,rst=1,rx=1;
    always #10 clk=~clk;
    wire clear_cmd,append_cmd,play_cmd,stop_cmd,playing,gate;
    wire [3:0] append_note,current_note;
    wire [11:0] append_mask,current_keys;
    wire append_is_mask;
    wire [9:0] append_duration;
    wire ae,te,ee,cae,cte,cee;
    wire [1:0] ao,at,af,co,ct,cf;
    wire [9:0] count;
    db_score_serial #(.BAUD(500000)) serial(
       .clk(clk),.rst(rst),.rx(rx),.tx(),.score_count(count),.playing(playing),
       .clear_cmd(clear_cmd),.append_cmd(append_cmd),
       .play_cmd(play_cmd),.stop_cmd(stop_cmd),
       .append_note(append_note),.append_mask(append_mask),.append_is_mask(append_is_mask),.append_duration(append_duration),
       .append_octave_enable(ae),.append_octave_code(ao),
       .append_timbre_enable(te),.append_timbre_code(at),
       .append_effect_enable(ee),.append_effect_code(af));
    db_score_player #(.CLK_HZ(100000)) player(
       .clk(clk),.rst(rst),.clock_present(1'b1),
       .clear_cmd(clear_cmd),.append_cmd(append_cmd),
       .play_cmd(play_cmd),.stop_cmd(stop_cmd),
       .append_note(append_note),.append_mask(append_mask),.append_is_mask(append_is_mask),.append_duration(append_duration),
       .append_octave_enable(ae),.append_octave_code(ao),
       .append_timbre_enable(te),.append_timbre_code(at),
       .append_effect_enable(ee),.append_effect_code(af),
       .score_count(count),.playing(playing),.current_note(current_note),.current_keys(current_keys),
       .current_octave_enable(cae),.current_octave_code(co),
       .current_timbre_enable(cte),.current_timbre_code(ct),
       .current_effect_enable(cee),.current_effect_code(cf),
       .note_gate(gate));
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
    initial begin
       repeat(20)@(negedge clk);rst=0;
       send_line("C");
       send_line("01,005,5,2,1");
       repeat(10)@(negedge clk);
       if(count!=1 || !ae || ao!=2 || !te || at!=2 || !ee || af!=1)
          $fatal(1,"extended parse failed");
       send_line("P");
       wait(playing && current_note==1);
       if(gate || !cae || co!=2 || !cte || ct!=2 || !cee || cf!=1)
          $fatal(1,"automatic controls were not sent before first note");
       repeat(900)@(negedge clk);
       if(gate)$fatal(1,"timbre pre-roll shorter than 9 ms");
       repeat(150)@(negedge clk);
       if(!gate)$fatal(1,"note did not start after timbre pre-roll");
       send_line("S");repeat(10)@(negedge clk);
       if(playing || gate)$fatal(1,"stop did not release notes");
       send_line("C");send_line("03,005");
       repeat(10)@(negedge clk);
       if(count!=1 || ae || te || ee)$fatal(1,"legacy line is not manual");
       send_line("01,005,6,0,1");repeat(10)@(negedge clk);
       if(count!=1)$fatal(1,"invalid octave was accepted");
       send_line("P");wait(playing && current_note==3);
       if(!gate || cae || cte || cee)$fatal(1,"legacy note did not play immediately");
       $display("PASS: extended and legacy score parsing; 10ms timbre pre-roll; stop and invalid input");
       $finish;
    end
    initial begin #100000000;$fatal(1,"timeout");end
endmodule
