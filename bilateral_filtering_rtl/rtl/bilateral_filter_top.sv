`timescale 1ns / 1ps

module bilateral_filter_top #(
    // 默认按照 1080P 视频流配置
    parameter IMG_WIDTH   = 12'd1920,
    parameter IMG_HEIGHT  = 12'd1080,
    parameter DIV_LATENCY = 26,
    
    // 【系统级延迟精准计算】
    // 滑窗延迟: (1920 * 2 + 3) = 3843
    // MAC延迟 : 6
    // 除法及MUX延迟: DIV_LATENCY(26) + MUX打拍(1) = 27
    // 总延迟: 3843 + 6 + 27 = 3876 拍
    parameter TOTAL_DELAY = (IMG_WIDTH * 2 + 3) + 6 + DIV_LATENCY + 1
)(
    input  logic       clk,
    input  logic       rst_n,

    // ==========================================
    // 1. 视频流输入接口 (RGB->YCbCr 模块送来的数据)
    // ==========================================
    input  logic       vsync_in,
    input  logic       hsync_in,
    input  logic       de_in,
    input  logic [7:0] y_in,
    input  logic [7:0] cb_in,
    input  logic [7:0] cr_in,

    // ==========================================
    // 2. 滤波后视频流输出接口 (送往 YCbCr->RGB 模块)
    // ==========================================
    output logic       vsync_out,
    output logic       hsync_out,
    output logic       de_out,
    output logic [7:0] y_out,
    output logic [7:0] cb_out,
    output logic [7:0] cr_out
);

    //======================================================================
    // 内部互连线网声明 (Internal Wires)
    //======================================================================
    // 1. 滑窗 -> MAC
    wire [7:0] w2m_p11, w2m_p12, w2m_p13, w2m_p14, w2m_p15;
    wire [7:0] w2m_p21, w2m_p22, w2m_p23, w2m_p24, w2m_p25;
    wire [7:0] w2m_p31, w2m_p32, w2m_p33, w2m_p34, w2m_p35;
    wire [7:0] w2m_p41, w2m_p42, w2m_p43, w2m_p44, w2m_p45;
    wire [7:0] w2m_p51, w2m_p52, w2m_p53, w2m_p54, w2m_p55;
    wire       w2m_de;
    wire       w2m_is_core;

    // 2. MAC -> 除法器 (算数通道)
    wire [17:0] m2d_sum_weight;        // 分母
    wire [25:0] m2d_sum_pixel_weight;  // 分子

    // 3. MAC -> MUX 同步路由模块 (控制通道)
    wire       m2x_mac_de;
    wire       m2x_mac_is_core;
    wire [7:0] m2x_center_pixel_out;

    // 4. 除法器 -> MUX 同步路由模块
    wire [25:0] div_quotient_full;     // 除法器出来的完整 26位 商
    wire [17:0] div_remain;            // 除法器出来的余数 (悬空不接)
    
    // 5. MUX -> 顶层输出
    wire        mux_y_de_out;          // 算法计算出的独立 DE (用作观测，实际对外输出用 delay_buf 的 de)


    //======================================================================
    // U1: 滑窗与边界生成模块 (处理 Y 通道)
    //======================================================================
    bf_window_gen_5x5 #(
        .IMG_WIDTH (IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT)
    ) u_window_gen (
        .clk         (clk),
        .rst_n       (rst_n),
        .vsync_in    (vsync_in),
        .de_in       (de_in),
        .y_in        (y_in),

        .matrix_p11(w2m_p11), .matrix_p12(w2m_p12), .matrix_p13(w2m_p13), .matrix_p14(w2m_p14), .matrix_p15(w2m_p15),
        .matrix_p21(w2m_p21), .matrix_p22(w2m_p22), .matrix_p23(w2m_p23), .matrix_p24(w2m_p24), .matrix_p25(w2m_p25),
        .matrix_p31(w2m_p31), .matrix_p32(w2m_p32), .matrix_p33(w2m_p33), .matrix_p34(w2m_p34), .matrix_p35(w2m_p35),
        .matrix_p41(w2m_p41), .matrix_p42(w2m_p42), .matrix_p43(w2m_p43), .matrix_p44(w2m_p44), .matrix_p45(w2m_p45),
        .matrix_p51(w2m_p51), .matrix_p52(w2m_p52), .matrix_p53(w2m_p53), .matrix_p54(w2m_p54), .matrix_p55(w2m_p55),

        .matrix_de   (w2m_de),
        .center_x    (), // 悬空 (如果不用于调试可不接)
        .center_y    (), // 悬空
        .is_core     (w2m_is_core)
    );

    //======================================================================
    // U2: 乘加树与权重计算模块
    //======================================================================
    bf_weight_calc_mac u_weight_calc_mac (
        .clk              (clk),
        .rst_n            (rst_n),
        
        .matrix_p11(w2m_p11), .matrix_p12(w2m_p12), .matrix_p13(w2m_p13), .matrix_p14(w2m_p14), .matrix_p15(w2m_p15),
        .matrix_p21(w2m_p21), .matrix_p22(w2m_p22), .matrix_p23(w2m_p23), .matrix_p24(w2m_p24), .matrix_p25(w2m_p25),
        .matrix_p31(w2m_p31), .matrix_p32(w2m_p32), .matrix_p33(w2m_p33), .matrix_p34(w2m_p34), .matrix_p35(w2m_p35),
        .matrix_p41(w2m_p41), .matrix_p42(w2m_p42), .matrix_p43(w2m_p43), .matrix_p44(w2m_p44), .matrix_p45(w2m_p45),
        .matrix_p51(w2m_p51), .matrix_p52(w2m_p52), .matrix_p53(w2m_p53), .matrix_p54(w2m_p54), .matrix_p55(w2m_p55),

        .matrix_de        (w2m_de),
        .is_core_area     (w2m_is_core),

        .sum_weight       (m2d_sum_weight),
        .sum_pixel_weight (m2d_sum_pixel_weight),
        
        .mac_de           (m2x_mac_de),
        .mac_is_core      (m2x_mac_is_core),
        .center_pixel_out (m2x_center_pixel_out)
    );

    //======================================================================
    // U3: 中科亿海微 底层除法器 IP 实例化
    //======================================================================
    divide_bf u_divide_bf (
        .clock    (clk),
        .denom    (m2d_sum_weight),         // 除数 (18bit 权重总和)
        .numer    (m2d_sum_pixel_weight),   // 被除数 (26bit 像素总和)
        .quotient (div_quotient_full),      // 商输出 (26bit)
        .remain   (div_remain)              // 余数 (不接入系统)
    );

    //======================================================================
    // U4: 终极同步路由 MUX (裁决除法器输出与边缘黑边)
    //======================================================================
    bf_final_sync_mux #(
        .DIV_LATENCY(DIV_LATENCY)
    ) u_final_sync_mux (
        .clk              (clk),
        .rst_n            (rst_n),

        // 提取除法器商的低 8 位作为真实亮度值
        .divide_quotient  (div_quotient_full[7:0]), 
        
        .mac_de           (m2x_mac_de),
        .mac_is_core      (m2x_mac_is_core),
        .center_pixel_out (m2x_center_pixel_out),
        
        // 最终的 Y 通道数据
        .y_out            (y_out),
        // 算法内部跑出来的 DE，仅保留作调试线，真实输出用环形缓存的 DE
        .de_out           (mux_y_de_out) 
    );

    //======================================================================
    // U5: 环形缓存模块 (处理 Cb/Cr 及所有同步信号的时空穿梭)
    //======================================================================
    bf_delay_buf #(
        .DELAY_CYCLES(TOTAL_DELAY),  // 3876
        .RAM_DEPTH   (4096),
        .ADDR_WIDTH  (12)
    ) u_delay_buf (
        .clk       (clk),
        .rst_n     (rst_n),
        
        .vsync_in  (vsync_in),
        .hsync_in  (hsync_in),
        .de_in     (de_in),
        .cb_in     (cb_in),
        .cr_in     (cr_in),
        
        // 这里输出的信号，就是 3876 拍前原始视频流最原汁原味的时序！
        // 它们直接连接到顶层的输出端口，给下游的 YCbCr->RGB 模块。
        .vsync_out (vsync_out),
        .hsync_out (hsync_out),
        .de_out    (de_out),
        .cb_out    (cb_out),
        .cr_out    (cr_out)
    );

endmodule