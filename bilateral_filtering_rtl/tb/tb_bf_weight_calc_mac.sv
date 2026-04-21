`timescale 1ns / 1ps

module tb_bf_weight_calc_mac;

    // 信号定义
    logic clk;
    logic rst_n;
    logic [7:0] p [1:5][1:5];
    logic matrix_de;
    logic is_core_area;

    logic [17:0] sum_weight;
    logic [25:0] sum_pixel_weight;
    logic mac_de;
    logic mac_is_core;
    logic [7:0] center_pixel_out;

    // 实例化 DUT
    bf_weight_calc_mac u_dut (
        .clk(clk), .rst_n(rst_n),
        .matrix_p11(p[1][1]), .matrix_p12(p[1][2]), .matrix_p13(p[1][3]), .matrix_p14(p[1][4]), .matrix_p15(p[1][5]),
        .matrix_p21(p[2][1]), .matrix_p22(p[2][2]), .matrix_p23(p[2][3]), .matrix_p24(p[2][4]), .matrix_p25(p[2][5]),
        .matrix_p31(p[3][1]), .matrix_p32(p[3][2]), .matrix_p33(p[3][3]), .matrix_p34(p[3][4]), .matrix_p35(p[3][5]),
        .matrix_p41(p[4][1]), .matrix_p42(p[4][2]), .matrix_p43(p[4][3]), .matrix_p44(p[4][4]), .matrix_p45(p[4][5]),
        .matrix_p51(p[5][1]), .matrix_p52(p[5][2]), .matrix_p53(p[5][3]), .matrix_p54(p[5][4]), .matrix_p55(p[5][5]),
        .matrix_de(matrix_de),
        .is_core_area(is_core_area),
        .sum_weight(sum_weight),
        .sum_pixel_weight(sum_pixel_weight),
        .mac_de(mac_de),
        .mac_is_core(mac_is_core),
        .center_pixel_out(center_pixel_out)
    );

    // 时钟生成
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

   // 激励过程
    initial begin
  

        rst_n = 0;
        matrix_de = 0;
        is_core_area = 0;
        for(int r=1; r<=5; r++) for(int c=1; c<=5; c++) p[r][c] = 8'd0;
        #20 rst_n = 1;

        // =========================================================
        // 测试用例 1：平坦矩阵 (差值全为0)
        // 预期 sum_weight = 102000 (18E78)
        // =========================================================
        #10;
        matrix_de = 1;
        is_core_area = 1;
        for(int r=1; r<=5; r++) for(int c=1; c<=5; c++) p[r][c] = 8'd100;
        
        #100; // 等待流水线稳定输出

        // =========================================================
        // 测试用例 2：靶心矩阵 (中心100，上半区110，下半区90)
        // 验证绝对值计算、非零地址 ROM 查表、空间权重联合乘法
        // 预期 sum_weight = 98640 (18150)
        // 预期 sum_pixel_weight = 9864000 (9681E0)
        // =========================================================
        matrix_de = 0; // 模拟行间消隐断流
        #30; 
        
        matrix_de = 1;
        for(int r=1; r<=5; r++) begin
            for(int c=1; c<=5; c++) begin
                if (r < 3)        p[r][c] = 8'd110; // 上半部分 > 中心
                else if (r > 3)   p[r][c] = 8'd90;  // 下半部分 < 中心
                else if (c < 3)   p[r][c] = 8'd110; // 中心行左侧
                else if (c > 3)   p[r][c] = 8'd90;  // 中心行右侧
                else              p[r][c] = 8'd100; // 中心点 p33
            end
        end

        #20;
        matrix_de = 0; // 输入 2 拍后立刻断流，看流水线里的数据能不能正常跑完

        #200;
        $display("Simulation Finished");
        $stop;
    end

endmodule