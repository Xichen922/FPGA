// 保留256点、24位接口；利用象限对称性只保存65个20位正幅值。
// 正弦查找表，峰值529285。
`timescale 1ns/1ps
module sine_rom_256(input wire [7:0] address, output wire signed [23:0] sample);
    wire [6:0] index = address[6] ? 7'd64 - {1'b0,address[5:0]}
                                    : {1'b0,address[5:0]};
    reg [19:0] magnitude;
    wire signed [23:0] positive = $signed({4'b0000,magnitude});
    assign sample = address[7] ? -positive : positive;
    always @* begin
        case(index)
            7'd0: magnitude = 20'd0;
            7'd1: magnitude = 20'd12989;
            7'd2: magnitude = 20'd25971;
            7'd3: magnitude = 20'd38937;
            7'd4: magnitude = 20'd51879;
            7'd5: magnitude = 20'd64790;
            7'd6: magnitude = 20'd77662;
            7'd7: magnitude = 20'd90488;
            7'd8: magnitude = 20'd103258;
            7'd9: magnitude = 20'd115967;
            7'd10: magnitude = 20'd128606;
            7'd11: magnitude = 20'd141167;
            7'd12: magnitude = 20'd153643;
            7'd13: magnitude = 20'd166027;
            7'd14: magnitude = 20'd178311;
            7'd15: magnitude = 20'd190487;
            7'd16: magnitude = 20'd202549;
            7'd17: magnitude = 20'd214488;
            7'd18: magnitude = 20'd226298;
            7'd19: magnitude = 20'd237973;
            7'd20: magnitude = 20'd249503;
            7'd21: magnitude = 20'd260884;
            7'd22: magnitude = 20'd272107;
            7'd23: magnitude = 20'd283166;
            7'd24: magnitude = 20'd294055;
            7'd25: magnitude = 20'd304767;
            7'd26: magnitude = 20'd315295;
            7'd27: magnitude = 20'd325633;
            7'd28: magnitude = 20'd335775;
            7'd29: magnitude = 20'd345715;
            7'd30: magnitude = 20'd355446;
            7'd31: magnitude = 20'd364963;
            7'd32: magnitude = 20'd374261;
            7'd33: magnitude = 20'd383333;
            7'd34: magnitude = 20'd392174;
            7'd35: magnitude = 20'd400779;
            7'd36: magnitude = 20'd409143;
            7'd37: magnitude = 20'd417260;
            7'd38: magnitude = 20'd425126;
            7'd39: magnitude = 20'd432735;
            7'd40: magnitude = 20'd440084;
            7'd41: magnitude = 20'd447168;
            7'd42: magnitude = 20'd453983;
            7'd43: magnitude = 20'd460524;
            7'd44: magnitude = 20'd466788;
            7'd45: magnitude = 20'd472770;
            7'd46: magnitude = 20'd478468;
            7'd47: magnitude = 20'd483878;
            7'd48: magnitude = 20'd488996;
            7'd49: magnitude = 20'd493819;
            7'd50: magnitude = 20'd498345;
            7'd51: magnitude = 20'd502571;
            7'd52: magnitude = 20'd506494;
            7'd53: magnitude = 20'd510112;
            7'd54: magnitude = 20'd513423;
            7'd55: magnitude = 20'd516425;
            7'd56: magnitude = 20'd519115;
            7'd57: magnitude = 20'd521493;
            7'd58: magnitude = 20'd523556;
            7'd59: magnitude = 20'd525305;
            7'd60: magnitude = 20'd526736;
            7'd61: magnitude = 20'd527851;
            7'd62: magnitude = 20'd528647;
            7'd63: magnitude = 20'd529126;
            7'd64: magnitude = 20'd529285;
            default: magnitude = 0;
        endcase
    end
endmodule
