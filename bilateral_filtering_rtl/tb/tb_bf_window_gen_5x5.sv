`timescale 1ns / 1ps

module tb_bf_window_gen_5x5;

    //======================================================================
    // 1. 参数覆盖：降维打击，将图像设为 10x10
    //======================================================================
    parameter W = 12'd10;
    parameter H = 12'd10;

    //======================================================================
    // 2. 信号声明
    //======================================================================
    logic        clk;
    logic        rst_n;

    // 输入激励信号
    logic        vsync_in;
    logic        de_in;
    logic [7:0]  y_in;

    // 输出矩阵信号
    logic [7:0]  p11, p12, p13, p14, p15;
    logic [7:0]  p21, p22, p23, p24, p25;
    logic [7:0]  p31, p32, p33, p34, p35;
    logic [7:0]  p41, p42, p43, p44, p45;
    logic [7:0]  p51, p52, p53, p54, p55;

    // 输出控制信号
    logic        matrix_de;
    logic        matrix_vsync;
    logic [11:0] center_x;
    logic [11:0] center_y;
    logic        is_core;

    //======================================================================
    // 3. 例化待测模块 (DUT)
    //======================================================================
    bf_window_gen_5x5 #(
        .IMG_WIDTH (W),
        .IMG_HEIGHT(H)
    ) u_dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .vsync_in     (vsync_in),
        .de_in        (de_in),
        .y_in         (y_in),

        .matrix_p11   (p11), .matrix_p12(p12), .matrix_p13(p13), .matrix_p14(p14), .matrix_p15(p15),
        .matrix_p21   (p21), .matrix_p22(p22), .matrix_p23(p23), .matrix_p24(p24), .matrix_p25(p25),
        .matrix_p31   (p31), .matrix_p32(p32), .matrix_p33(p33), .matrix_p34(p34), .matrix_p35(p35),
        .matrix_p41   (p41), .matrix_p42(p42), .matrix_p43(p43), .matrix_p44(p44), .matrix_p45(p45),
        .matrix_p51   (p51), .matrix_p52(p52), .matrix_p53(p53), .matrix_p54(p54), .matrix_p55(p55),

        .matrix_de    (matrix_de),
        .matrix_vsync (matrix_vsync),
        .center_x     (center_x),
        .center_y     (center_y),
        .is_core      (is_core)
    );

    //======================================================================
    // 4. 时钟生成 (模拟 100MHz 像素时钟)
    //======================================================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk; 
    end

    //======================================================================
    // 5. 模拟 OV5640 摄像头时序 (激励生成状态机)
    //======================================================================
    int pixel_val; // 用一个 int 变量来生成 0~99 的自增像素

    initial begin
        // --- A. 系统复位初始化 ---
        rst_n     = 0;
        vsync_in  = 0;
        de_in     = 0;
        y_in      = 0;
        pixel_val = 0;
        #30 rst_n = 1;
        #30;

        // --- B. 模拟消隐区，发送一帧起始的 VSYNC 脉冲 ---
        $display("[%0t] Sending VSYNC pulse...", $time);
        vsync_in = 1;
        #50;
        vsync_in = 0;
        #50; // VSYNC 下降沿后，等待一段时间准备发第一行数据

        // --- C. 开始发送 10x10 的一帧图像 ---
        $display("[%0t] Starting Video Frame (10x10)...", $time);
        
        for (int r = 0; r < H; r++) begin
            
            // 1. 行前消隐期 (H-Blanking: 模拟真实视频行与行之间的停顿)
            de_in = 0;
            #30; 

            // 2. 发送一行有效数据 (10 个像素)
            for (int c = 0; c < W; c++) begin
                de_in = 1;
                y_in  = pixel_val[7:0]; // 像素值为 0, 1, 2 ... 99
                pixel_val++;
                #10; // 等待一个时钟周期
            end

            // 3. 行后消隐期
            de_in = 0;
            #20;
        end
        $display("[%0t] Video Frame Input Finished.", $time);

        // --- D. 观察末尾冲刷逻辑 (Flush) ---
        // 摄像头输入已经停止 (de_in = 0)。
        // 按照我们的逻辑，flush_cnt 会自动接管，再“挤”出 (2*10+2) = 22 个有效像素。
        // 我们给足时间让它冲刷完
        #1000;

        $display("[%0t] Simulation Done!", $time);
        $stop; // 暂停仿真
    end

endmodule