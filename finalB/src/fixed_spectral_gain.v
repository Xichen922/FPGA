`timescale 1ns/1ps
// One shared copy of the four production spectral tables.
// Piano static weights combine with the register/age-dependent spectral ROM.
// Other profiles retain their calibrated coefficients.
module fixed_spectral_gain(
    input wire [1:0] timbre,
    input wire [4:0] oscillator_index,
    output wire [4:0] shift
);
    function [4:0] clarinet_shift;
        input integer index;
        begin
            if(index[0]) clarinet_shift=14;
            else if(index==0) clarinet_shift=1;
            else if(index==2) clarinet_shift=2;
            else if(index==4) clarinet_shift=4;
            else if(index==6) clarinet_shift=5;
            else if(index<=14) clarinet_shift=6;
            else clarinet_shift=10;
        end
    endfunction
    function [4:0] keyboard_shift;
        input integer index;
        begin
            if(index==0) keyboard_shift=2;
            else if(index==1) keyboard_shift=3;
            else if(index==2) keyboard_shift=4;
            else if(index<=4) keyboard_shift=5;
            else if(index<=6) keyboard_shift=6;
            else if(index==7) keyboard_shift=7;
            else if(index<=11) keyboard_shift=8;
            else if(index<=15) keyboard_shift=10;
            else if(index<=23) keyboard_shift=12;
            else if(index==31) keyboard_shift=6; // weak unison/body string
            else keyboard_shift=14;
        end
    endfunction
    function [4:0] organ_shift;
        input integer index;
        begin
            case(index)
                0: organ_shift=1;
                1: organ_shift=2;
                3: organ_shift=3;
                7: organ_shift=4;
                15: organ_shift=6;
                5,11: organ_shift=8;
                2,4: organ_shift=9;
                default: organ_shift=14;
            endcase
        end
    endfunction
    function [4:0] pluck_shift;
        input integer index;
        begin
            case(index)
                0: pluck_shift=2;
                1: pluck_shift=5;
                2: pluck_shift=7;
                3: pluck_shift=4;
                4: pluck_shift=9;
                5: pluck_shift=10;
                6: pluck_shift=11;
                7: pluck_shift=7;
                15: pluck_shift=10;
                default: pluck_shift=18;
            endcase
        end
    endfunction
    assign shift=(timbre==2'd1) ? clarinet_shift(oscillator_index) :
        (timbre==2'd2) ? organ_shift(oscillator_index) :
        (timbre==2'd3) ? pluck_shift(oscillator_index) : keyboard_shift(oscillator_index);
endmodule
