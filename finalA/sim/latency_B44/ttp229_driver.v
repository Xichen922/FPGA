// 【TTP229接口】将两线触摸板的数据读成16位并行按键状态。
// 低有效配置下，SDO为0代表按下；译码后的key_mask为1代表按下。
// key_mask[0]对应面板键1，key_mask[15]对应键16；必须支持实物多键模式。
// key_valid仅在完整16位读完时高一拍，下游据此处理完整快照。
// key_press/key_release是一帧之间的变化事件；raw_mask保留未反相的原始位。
// 本次仅增加中文解释，原驱动功能和协议时序均保留。
`timescale 1ns/1ps
// TTP229-BSF Verilog driver library v1.0.0
// Reusable entry point: latb_ttp229_driver. No UART, PLL or pin assignment required.
// 原reader功能逻辑保留，下方已增加中文阅读注释。
// key_mask[0] = panel key 1; key_mask[15] = panel key 16. 1 means touched.
// Consume key_mask/key_press/key_release on key_valid, in the clk domain.
// rst_n must be asserted at startup and released synchronously to clk.
// Hardware must already select 16 keys and all-multi-key operation.
module latb_ttp229_driver #(
    parameter integer CLK_HZ = 50000000,
    parameter integer SCL_HZ = 100000,
    parameter integer STARTUP_CYCLES = (CLK_HZ / 1000) * 600,
    parameter integer GAP_CYCLES = (CLK_HZ / 1000) * 3,
    parameter integer ACTIVE_LOW = 1
) (
    input wire clk,
    input wire rst_n,
    input wire touch_sdo,
    output wire touch_scl,
    output wire [15:0] key_mask,
    output wire key_valid,
    output wire [15:0] key_press,
    output wire [15:0] key_release,
    output wire [15:0] raw_mask,
    output wire ready
);
    // 此模块是对reader的参数/端口封装。真正的串行状态机在下面的ttp229_reader。
    latb_ttp229_reader #(
        .CLK_HZ(CLK_HZ),
        .SCL_HZ(SCL_HZ),
        .STARTUP_CYCLES(STARTUP_CYCLES),
        .GAP_CYCLES(GAP_CYCLES),
        .ACTIVE_LOW(ACTIVE_LOW)
    ) u_reader (
        .clk(clk), .rst_n(rst_n),
        .touch_sdo(touch_sdo), .touch_scl(touch_scl),
        .key_mask(key_mask), .key_valid(key_valid),
        .key_press(key_press), .key_release(key_release),
        .raw_mask(raw_mask), .ready(ready)
    );
endmodule

// 原ttp229_reader功能逻辑区域：本次仅补充注释。
`timescale 1ns/1ps
// TTP229-BSF two-wire serial reader. This is NOT I2C.
// Default TP1 open: SCL idle high, falling edge requests D0..D15,
// SDO low means touched. All logic runs on clk, never on touch_scl.
module latb_ttp229_reader #(
    parameter integer CLK_HZ = 50000000,
    parameter integer SCL_HZ = 100000,
    parameter integer STARTUP_CYCLES = (CLK_HZ / 1000) * 600,
    parameter integer GAP_CYCLES = (CLK_HZ / 1000) * 3,
    parameter integer ACTIVE_LOW = 1
) (
    input wire clk,
    input wire rst_n,
    input wire touch_sdo,
    output reg touch_scl,
    output reg [15:0] raw_mask,
    output reg [15:0] key_mask,
    output reg [15:0] key_press,
    output reg [15:0] key_release,
    output reg key_valid,
    output reg ready
);
    // 默认100kHz读键时钟，半周期是250个50MHz时钟（5us）。
    localparam integer HALF_CYCLES = CLK_HZ / (2 * SCL_HZ);
    localparam IDLE_LEVEL = (ACTIVE_LOW != 0);
    // 状态机：上电等待 -> 扫描间隔 -> SCL有效半周期 -> 无效半周期 -> 完整帧发布。
    localparam [2:0] STARTUP = 0, GAP = 1, ACTIVE = 2, INACTIVE = 3, COMMIT = 4;
    reg [2:0] state;
    reg [31:0] timer;
    // 4位索引0..15逐一接收各键。shift_raw只在帧读完后整体发布。
    reg [3:0] bit_index;
    reg [15:0] shift_raw;
    // SDO来自外部异步器件，用两级寄存器同步到clk域；只对同步后的值采样。
    (* syn_preserve = 1 *) reg sdo_meta;
    (* syn_preserve = 1 *) reg sdo_sync;
    // 低有效协议下逐位取反，把“0表示触摸”统一变成下游的“1表示触摸”。
    wire [15:0] decoded = ACTIVE_LOW ? ~shift_raw : shift_raw;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sdo_meta <= IDLE_LEVEL;
            sdo_sync <= IDLE_LEVEL;
        end else begin
            sdo_meta <= touch_sdo;
            sdo_sync <= sdo_meta;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= STARTUP;
            timer <= 0;
            bit_index <= 0;
            shift_raw <= 0;
            touch_scl <= IDLE_LEVEL;
            raw_mask <= ACTIVE_LOW ? 16'hFFFF : 16'h0000;
            key_mask <= 0;
            key_press <= 0;
            key_release <= 0;
            key_valid <= 0;
            ready <= 0;
        end else begin
            // 默认撤销事件脉冲；key_mask保留上一份快照，不会在扫描期间清空。
            key_valid <= 0;
            key_press <= 0;
            key_release <= 0;
            case (state)
                // 等待触摸板完成上电校准，默认600ms；ready仅表示本等待已经结束。
                STARTUP: begin
                    touch_scl <= IDLE_LEVEL;
                    if (timer == STARTUP_CYCLES - 1) begin
                        timer <= 0;
                        ready <= 1;
                        state <= GAP;
                    end else timer <= timer + 1'b1;
                end
                // 两次16位读取之间留出间隔，默认3ms；SCL保持空闲高电平。
                GAP: begin
                    touch_scl <= IDLE_LEVEL;
                    if (timer == GAP_CYCLES - 1) begin
                        timer <= 0;
                        bit_index <= 0;
                        touch_scl <= ~IDLE_LEVEL;
                        state <= ACTIVE;
                    end else timer <= timer + 1'b1;
                end
                // 当前键的数据有一个完整低半周期稳定时间，末尾采样SDO，再把SCL拉高。
                ACTIVE: begin
                    // Sample after a full 5 us settling interval at 100 kHz.
                    // The two-register synchronizer has already settled.
                    if (timer == HALF_CYCLES - 1) begin
                        timer <= 0;
                        shift_raw[bit_index] <= sdo_sync;
                        touch_scl <= IDLE_LEVEL;
                        state <= INACTIVE;
                    end else timer <= timer + 1'b1;
                end
                // 高半周期结束后，继续下一键；第16键结束时转入完整帧提交。
                INACTIVE: begin
                    if (timer == HALF_CYCLES - 1) begin
                        timer <= 0;
                        if (bit_index == 15) state <= COMMIT;
                        else begin
                            bit_index <= bit_index + 1'b1;
                            touch_scl <= ~IDLE_LEVEL;
                            state <= ACTIVE;
                        end
                    end else timer <= timer + 1'b1;
                end
                // 新按下=current & ~previous；新松开=previous & ~current。
                // key_mask<=decoded是非阻塞赋值，因此下面的变化比较仍使用旧key_mask。
                COMMIT: begin
                    // Publish only a complete frame; no priority encoder.
                    raw_mask <= shift_raw;
                    key_press <= decoded & ~key_mask;
                    key_release <= key_mask & ~decoded;
                    key_mask <= decoded;
                    key_valid <= 1;
                    timer <= 0;
                    state <= GAP;
                end
                default: begin
                    state <= STARTUP;
                    timer <= 0;
                    touch_scl <= IDLE_LEVEL;
                    ready <= 0;
                end
            endcase
        end
    end
endmodule
