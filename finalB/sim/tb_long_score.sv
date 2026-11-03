`timescale 1ns/1ps
module tb_long_score;
    reg clk=0,rst=1,rx=1;
    always #10 clk=~clk;
    wire tx,clear_cmd,append_cmd,play_cmd,stop_cmd,playing,gate;
    wire [3:0] append_note,current_note;
    wire [11:0] append_mask,current_keys;
    wire append_is_mask;
    wire [9:0] append_duration,count;
    wire ae,te,ee,cae,cte,cee;
    wire [1:0] ao,at,af,co,ct,cf;
    wire [7:0] answer;
    wire answer_valid,answer_error;
    integer ack_count=0,ack_lines=0,query_count=0;
    reg capture_query=0;
    reg [7:0] query_bytes [0:5];

    db_score_serial #(.BAUD(500000)) serial(
        .clk(clk),.rst(rst),.rx(rx),.tx(tx),.score_count(count),.playing(playing),
        .clear_cmd(clear_cmd),.append_cmd(append_cmd),.play_cmd(play_cmd),.stop_cmd(stop_cmd),
        .append_note(append_note),.append_mask(append_mask),.append_is_mask(append_is_mask),.append_duration(append_duration),
        .append_octave_enable(ae),.append_octave_code(ao),
        .append_timbre_enable(te),.append_timbre_code(at),
        .append_effect_enable(ee),.append_effect_code(af));
    db_score_player #(.CLK_HZ(100000)) player(
        .clk(clk),.rst(rst),.clock_present(1'b1),
        .clear_cmd(clear_cmd),.append_cmd(append_cmd),.play_cmd(play_cmd),.stop_cmd(stop_cmd),
        .append_note(append_note),.append_mask(append_mask),.append_is_mask(append_is_mask),.append_duration(append_duration),
        .append_octave_enable(ae),.append_octave_code(ao),
        .append_timbre_enable(te),.append_timbre_code(at),
        .append_effect_enable(ee),.append_effect_code(af),
        .score_count(count),.playing(playing),.current_note(current_note),.current_keys(current_keys),
        .current_octave_enable(cae),.current_octave_code(co),
        .current_timbre_enable(cte),.current_timbre_code(ct),
        .current_effect_enable(cee),.current_effect_code(cf),.note_gate(gate));
    db_uart_rx #(.BAUD(500000)) reply_rx(
        .clk(clk),.rst(rst),.rx(tx),.data(answer),.valid(answer_valid),
        .framing_error(answer_error));
    always @(posedge clk) if(answer_valid) begin
        if(answer_error)$fatal(1,"UART reply framing error");
        if(capture_query) begin
            if(query_count<6)query_bytes[query_count]<=answer;
            query_count<=query_count+1;
        end else if(answer=="K")ack_count<=ack_count+1;
        else if(answer==8'h0a)ack_lines<=ack_lines+1;
        else $fatal(1,"unexpected upload reply: %h",answer);
    end
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
    integer n;
    initial begin
        repeat(20)@(negedge clk);rst=0;
        send_line("C");
        for(n=0;n<415;n=n+1)send_line("01,001,5,-,-");
        wait(ack_count==416 && ack_lines==416);
        if(count!=415)$fatal(1,"stored %0d rather than 415 entries",count);
        capture_query=1;
        send_line("?");
        wait(query_count==6);
        if(query_bytes[0]!="N" || query_bytes[1]!="=" ||
           query_bytes[2]!="4" || query_bytes[3]!="1" ||
           query_bytes[4]!="5" || query_bytes[5]!=8'h0a)
            $fatal(1,"incorrect three-digit count reply: %h %h %h %h %h %h",
                query_bytes[0],query_bytes[1],query_bytes[2],
                query_bytes[3],query_bytes[4],query_bytes[5]);
        query_count=0;
        send_line("V");
        wait(query_count==6);
        if(query_bytes[0]!="V" || query_bytes[1]!="=" ||
           query_bytes[2]!="0" || query_bytes[3]!="4" ||
           query_bytes[4]!="2" || query_bytes[5]!=8'h0a)
            $fatal(1,"incorrect firmware version reply");
        capture_query=0;
        send_line("P");
        wait(playing);
        wait(player.index==10'd414 && player.state==3'd4);
        if(count!=415 || current_note!=1)$fatal(1,"last note not reached");
        wait(!playing);
        if(gate || player.index!=10'd414)$fatal(1,"playback did not finish cleanly");
        $display("PASS: 415 UART uploads, N=415 reply, uninterrupted playback through final event");
        $finish;
    end
    initial begin #250000000;$fatal(1,"timeout: stored=%0d ack=%0d query=%0d playing=%0d index=%0d",count,ack_count,query_count,playing,player.index);end
endmodule
