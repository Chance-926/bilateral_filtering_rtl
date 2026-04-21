`timescale 1ns / 1ps

module tb_bf_final_sync_mux;

    //======================================================================
    // 1. 参数设置：黄金延迟 10 拍
    //======================================================================
    parameter LAT_VAL = 10;

    //======================================================================
    // 2. 信号声明 (完全模拟 MAC 模块的全部真实输出端口)
    //======================================================================
    logic        clk;
    logic        rst_n;

    // 模拟 MAC 模块吐出的控制信号 (送给 DUT)
    logic        mac_de;
    logic        mac_is_core;
    logic [7:0]  center_pixel_out;
    logic        mac_vsync;

    // 模拟 MAC 模块吐出的算数信号 (送给假除法器)
    logic [25:0] mock_sum_pixel_weight; // 分子
    logic [17:0] mock_sum_weight;       // 分母

    // DUT 与假除法器之间的连线
    logic [7:0]  divide_quotient;

    // DUT 的最终输出
    logic [7:0]  y_out;
    logic        de_out;
    logic        vsync_out;

    //======================================================================
    // 3. 例化待测模块 (DUT: 终极同步路由)
    //======================================================================
    bf_final_sync_mux #(
        .DIV_LATENCY(LAT_VAL)
    ) u_dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .divide_quotient  (divide_quotient),
        .mac_de           (mac_de),
        .mac_is_core      (mac_is_core),
        .center_pixel_out (center_pixel_out),
        .mac_vsync        (mac_vsync),
        .y_out            (y_out),
        .de_out           (de_out),
        .vsync_out        (vsync_out)
    );

    //======================================================================
    // 4. 时钟生成
    //======================================================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    //======================================================================
    // 5. 核心修正：真实的“假除法器”模型 (Mock Divider)
    // 它现在真正吃的是分子和分母，并执行除法，然后延迟 LAT_VAL 拍！
    //======================================================================
    logic [7:0] mock_div_pipe [0 : LAT_VAL-1];
    
    always_ff @(posedge clk) begin
        // 第一拍：真实执行除法 (防止除以0)
        if (mock_sum_weight != 0) begin
            mock_div_pipe[0] <= mock_sum_pixel_weight / mock_sum_weight;
        end else begin
            mock_div_pipe[0] <= 8'd0;
        end
        
        // 后面拍数：移位延迟
        for (int i=1; i<LAT_VAL; i++) begin
            mock_div_pipe[i] <= mock_div_pipe[i-1];
        end
    end
    
    // 假除法器的链尾吐给 DUT 的数据输入口
    assign divide_quotient = mock_div_pipe[LAT_VAL-1];


    //======================================================================
    // 6. 主激励状态机 (MAC 引擎模拟器)
    //======================================================================
    initial begin
        // --- 初始化 MAC 引擎的所有输出 ---
        rst_n                 = 0;
        mac_de                = 0;
        mac_is_core           = 0;
        center_pixel_out      = 0;
        mac_vsync             = 0;
        mock_sum_pixel_weight = 0;
        mock_sum_weight       = 0;
        
        #30 rst_n = 1;
        #20;

        $display("=== 阶段二：真实链路架构测试 (单发脉冲) ===");
        // 模拟 MAC 在某一刻同时吐出了一套结果：
        // 算出了总权重是 100，加权像素和是 12000。(理论除法结果应为 120)
        mac_de                = 1;
        mac_is_core           = 1;
        center_pixel_out      = 8'd10; // 原图很暗，但滤波后应该变亮(120)
        mac_vsync             = 1; 
        mock_sum_pixel_weight = 26'd12000; // 送给除法器
        mock_sum_weight       = 18'd100;   // 送给除法器
        #10;
        
        // 恢复闲置状态
        mac_de                = 0;
        mac_is_core           = 0;
        center_pixel_out      = 8'd0;
        mac_vsync             = 0;
        mock_sum_pixel_weight = 26'd0;
        mock_sum_weight       = 18'd0;

        #200; // 等待假除法器和 DUT 同步模块跑完

        $display("=== 阶段三：连发与边缘透传裁剪测试 ===");
        // 连续发送 3 个有效数据。
        // 前 2 个在核心区，第 3 个在边缘区。
        
        // 1. 核心区：15000 / 100 = 150
        mac_de = 1; mac_is_core = 1; center_pixel_out = 8'd0; 
        mock_sum_pixel_weight = 15000; mock_sum_weight = 100; #10;
        
        // 2. 核心区：16000 / 100 = 160
        mac_de = 1; mac_is_core = 1; center_pixel_out = 8'd0; 
        mock_sum_pixel_weight = 16000; mock_sum_weight = 100; #10;
        
        // 3. 边缘区：虽然除法器算出来是 17000/100=170，但因为 is_core=0，必须强制输出 0！
        mac_de = 1; mac_is_core = 0; center_pixel_out = 8'd99; // 原图像素 99
        mock_sum_pixel_weight = 17000; mock_sum_weight = 100; #10;

        // 断流
        mac_de = 0; mac_is_core = 0; center_pixel_out = 8'd0; 
        mock_sum_pixel_weight = 0; mock_sum_weight = 0; #10;

        #200; 
        $display("Simulation Finished!");
        $stop;
    end

endmodule