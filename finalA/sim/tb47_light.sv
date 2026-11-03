`timescale 1ns/1ps
module tb47_light;
 reg clk=0,rst=1,valid=0;reg [9:0] adc=0; always #10 clk=~clk;
 wire led,opposite,disabled;
 fill_light_control #(.DARK_CONFIRM(3),.BRIGHT_CONFIRM(4),.MIN_HOLD(2)) high(
 .clk(clk),.rst(rst),.snapshot_valid(valid),.adc_do(adc),.led_enable(led));
 fill_light_control #(.DARK_HIGH(0),.DARK_CONFIRM(3),.BRIGHT_CONFIRM(4),.MIN_HOLD(2)) low(
 .clk(clk),.rst(rst),.snapshot_valid(valid),.adc_do(adc),.led_enable(opposite));
 fill_light_control #(.ENABLE(0)) off(
 .clk(clk),.rst(rst),.snapshot_valid(valid),.adc_do(adc),.led_enable(disabled));
 task snap(input [9:0] v);begin
 @(negedge clk);valid=1;adc=v;@(negedge clk);valid=0;repeat(3)@(negedge clk);
 if(disabled)$fatal(1,"disabled light on");end endtask
 initial begin
 repeat(3)@(negedge clk);rst=0;
 snap(1023);snap(1023);if(led)$fatal(1,"dark glitch lit LED");
 snap(512);snap(1023);snap(1023);if(led)$fatal(1,"ambiguous snapshot did not reset confirmation");
 snap(1023);if(!led)$fatal(1,"stable dark not on");
 // No adc_valid: neither hold timer nor confirmation may advance.
 adc=0;repeat(30)@(negedge clk);if(!led)$fatal(1,"clock-based timer instead of snapshot timer");
 snap(0);snap(0);if(!led)$fatal(1,"minimum on time failed");
 snap(0);snap(0);snap(0);if(!led)$fatal(1,"bright confirmation too short");
 snap(0);if(led || !opposite)$fatal(1,"stable bright / opposite polarity");
 // Confirm thresholds are inclusive, middle-band cannot cause a toggle.
 snap(640);snap(640);snap(640);snap(640);snap(640);if(!led)$fatal(1,"high threshold inclusion");
 snap(256);snap(256);snap(256);snap(256);snap(256);snap(256);if(led)$fatal(1,"low threshold inclusion");
 @(negedge clk);rst=1;@(negedge clk);if(led||opposite)$fatal(1,"reset output not low");
 $display("PASS fill light: both DO polarities, valid-only counters, stable confirmations, midband/glitch rejection, minimum on/off hold, disable/reset safe low");$finish;
 end
endmodule
