`timescale 1ns / 1ps

//乘法计算优化？

module bf_weight_calc_mac (
    input  logic        clk,
    input  logic        rst_n,

    // 来自前级 bf_window_gen_5x5 的输入
    input  logic [7:0]  matrix_p11, matrix_p12, matrix_p13, matrix_p14, matrix_p15,
    input  logic [7:0]  matrix_p21, matrix_p22, matrix_p23, matrix_p24, matrix_p25,
    input  logic [7:0]  matrix_p31, matrix_p32, matrix_p33, matrix_p34, matrix_p35,
    input  logic [7:0]  matrix_p41, matrix_p42, matrix_p43, matrix_p44, matrix_p45,
    input  logic [7:0]  matrix_p51, matrix_p52, matrix_p53, matrix_p54, matrix_p55,
    
    input  logic        matrix_de,
    input  logic        is_core_area, // 矩阵中心的像素是否能滤波（透传）

    // 输出给除法器的结果
    output logic [17:0] sum_weight,       // 权重总和 (除数)
    output logic [25:0] sum_pixel_weight, // 像素加权总和 (被除数)
    // 输出给mux的结果
    output logic        mac_de,           // 乘加结果有效信号
    output logic        mac_is_core,      // 计算的矩阵的中心是否属于核心区
    output logic [7:0]  center_pixel_out  // 伴随输出的中心像素(备用，可用于边缘透传)   
);

    //======================================================================
    // 0. 空间权重定义 (Spatial Weight Parameter) - 类似高斯分布
    // 中心权重最大(64)，越往边缘越小。为了省资源，设为 2 的次幂或简单整数
    //======================================================================
    logic [7:0] SPATIAL_W [0:4][0:4];
    assign SPATIAL_W[0][0]=8'd4;  assign SPATIAL_W[0][1]=8'd8;  assign SPATIAL_W[0][2]=8'd16; assign SPATIAL_W[0][3]=8'd8;  assign SPATIAL_W[0][4]=8'd4;
    assign SPATIAL_W[1][0]=8'd8;  assign SPATIAL_W[1][1]=8'd16; assign SPATIAL_W[1][2]=8'd32; assign SPATIAL_W[1][3]=8'd16; assign SPATIAL_W[1][4]=8'd8;
    assign SPATIAL_W[2][0]=8'd16; assign SPATIAL_W[2][1]=8'd32; assign SPATIAL_W[2][2]=8'd64; assign SPATIAL_W[2][3]=8'd32; assign SPATIAL_W[2][4]=8'd16;
    assign SPATIAL_W[3][0]=8'd8;  assign SPATIAL_W[3][1]=8'd16; assign SPATIAL_W[3][2]=8'd32; assign SPATIAL_W[3][3]=8'd16; assign SPATIAL_W[3][4]=8'd8;
    assign SPATIAL_W[4][0]=8'd4;  assign SPATIAL_W[4][1]=8'd8;  assign SPATIAL_W[4][2]=8'd16; assign SPATIAL_W[4][3]=8'd8;  assign SPATIAL_W[4][4]=8'd4;

    //======================================================================
    // 分布式 ROM 定义 (Range Weight LUT)
    // 采用纯 RTL 声明，综合工具会将其映射为 LUT RAM，支持并发多路读取！
    //======================================================================
    logic [7:0] range_weight_rom [0:255];
    
    initial begin
        // 这里加载你用 Python 提前算好的 256 个权重值文件
        // 如果文件不存在，仿真时会有警告，但综合时可以填入默认值
        $readmemh("D:/AAA_Code/bilateral_filtering_rtl/prepare/test_range_weight.txt", range_weight_rom);
    end

    //======================================================================
    // 接口映射：将离散端口映射为 2D 数组 (下标 [row][col])
    //======================================================================
    logic [7:0] p_in [0:4][0:4];
    assign p_in[0][0]=matrix_p11; assign p_in[0][1]=matrix_p12; assign p_in[0][2]=matrix_p13; assign p_in[0][3]=matrix_p14; assign p_in[0][4]=matrix_p15;
    assign p_in[1][0]=matrix_p21; assign p_in[1][1]=matrix_p22; assign p_in[1][2]=matrix_p23; assign p_in[1][3]=matrix_p24; assign p_in[1][4]=matrix_p25;
    assign p_in[2][0]=matrix_p31; assign p_in[2][1]=matrix_p32; assign p_in[2][2]=matrix_p33; assign p_in[2][3]=matrix_p34; assign p_in[2][4]=matrix_p35;
    assign p_in[3][0]=matrix_p41; assign p_in[3][1]=matrix_p42; assign p_in[3][2]=matrix_p43; assign p_in[3][3]=matrix_p44; assign p_in[3][4]=matrix_p45;
    assign p_in[4][0]=matrix_p51; assign p_in[4][1]=matrix_p52; assign p_in[4][2]=matrix_p53; assign p_in[4][3]=matrix_p54; assign p_in[4][4]=matrix_p55;

    // 控制信号延迟移位寄存器 (总共延迟 6 拍)
    logic [5:0] de_shift;
    logic [5:0] is_core_shift;
    logic [7:0] center_p_shift [0:5];//？

    //======================================================================
    // 流水线核心逻辑
    //======================================================================
    // Stage 声明：每一拍的计算结果
    logic [7:0]  st1_diff    [0:4][0:4]; //与中心的绝对差值
    logic [7:0]  st2_rw      [0:4][0:4]; //查值域权重
    logic [15:0] st3_w_total [0:4][0:4]; // 联合权重 = range * spatial
    logic [23:0] st4_wp      [0:4][0:4]; // 加权像素 = 联合权重 * 像素值
    
    // 因为像素值要和第4级的权重相乘，所以像素值本身也需要打 3 拍对齐
    logic [7:0]  p_dly1 [0:4][0:4];
    logic [7:0]  p_dly2 [0:4][0:4];
    logic [7:0]  p_dly3 [0:4][0:4];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            de_shift      <= 6'd0;
            is_core_shift <= 6'd0;
            sum_weight    <= 16'd0;
            sum_pixel_weight <= 24'd0;
        end else begin
            // 控制信号与中心像素打拍跟随
            de_shift      <= {de_shift[4:0], matrix_de};
            is_core_shift <= {is_core_shift[4:0], is_core_area};
            
            center_p_shift[0] <= p_in[2][2];
            for(int i=1; i<6; i++) center_p_shift[i] <= center_p_shift[i-1];

            // 我们只在 matrix_de 有效时进行流水线移位计算，节省动态功耗
            if (matrix_de || de_shift > 0) begin
                
                // -------------------------------------------------------------
                // Stage 1: 绝对差值计算 与 像素本身打拍
                // -------------------------------------------------------------
                for(int r=0; r<5; r++) begin
                    for(int c=0; c<5; c++) begin
                        // 计算绝对差值
                        st1_diff[r][c] <= (p_in[2][2] > p_in[r][c]) ? (p_in[2][2] - p_in[r][c]) : (p_in[r][c] - p_in[2][2]);
                        p_dly1[r][c]   <= p_in[r][c]; // 像素打第 1 拍
                    end
                end

                // -------------------------------------------------------------
                // Stage 2: ROM 查表 (值域权重)
                // -------------------------------------------------------------
                for(int r=0; r<5; r++) begin
                    for(int c=0; c<5; c++) begin
                        st2_rw[r][c] <= range_weight_rom[ st1_diff[r][c] ];
                        p_dly2[r][c] <= p_dly1[r][c]; // 像素打第 2 拍
                    end
                end

                // -------------------------------------------------------------
                // Stage 3: 计算联合权重 (Spatial * Range)
                // -------------------------------------------------------------
                for(int r=0; r<5; r++) begin
                    for(int c=0; c<5; c++) begin
                        // 8bit * 8bit = 16bit 联合权重
                        st3_w_total[r][c] <= st2_rw[r][c] * SPATIAL_W[r][c];
                        p_dly3[r][c]      <= p_dly2[r][c]; // 像素打第 3 拍
                    end
                end

                // -------------------------------------------------------------
                // Stage 4: 计算加权像素 (联合权重 * 像素)
                // -------------------------------------------------------------
                for(int r=0; r<5; r++) begin
                    for(int c=0; c<5; c++) begin
                        // 16bit * 8bit = 24bit 加权像素
                        st4_wp[r][c] <= st3_w_total[r][c] * p_dly3[r][c];
                    end
                end
            end
        end
    end

    // -------------------------------------------------------------
    // Stage 5 & 6: 累加树 (Adder Tree)
    // 为了防止时序违例，我们分两步累加：先按行累加(Row Sum)，再总体累加
    // -------------------------------------------------------------
    logic [17:0] row_sum_w  [0:4];
    logic [25:0] row_sum_wp [0:4];

    always_ff @(posedge clk) begin
        // Stage 5: 按行求和 (5个加法器并行)
        for(int r=0; r<5; r++) begin
            row_sum_w[r]  <= st3_w_total[r][0] + st3_w_total[r][1] + st3_w_total[r][2] + st3_w_total[r][3] + st3_w_total[r][4];
            row_sum_wp[r] <= st4_wp[r][0]      + st4_wp[r][1]      + st4_wp[r][2]      + st4_wp[r][3]      + st4_wp[r][4];
        end

        // Stage 6: 总体求和 (最终输出)
        sum_weight       <= row_sum_w[0]  + row_sum_w[1]  + row_sum_w[2]  + row_sum_w[3]  + row_sum_w[4];
        sum_pixel_weight <= row_sum_wp[0] + row_sum_wp[1] + row_sum_wp[2] + row_sum_wp[3] + row_sum_wp[4];
    end

    //======================================================================
    // 最终端口赋值
    //======================================================================
    assign mac_de           = de_shift[5];       // 延迟了6拍的 de
    assign mac_is_core      = is_core_shift[5];  // 延迟了6拍的核心区标志
    assign center_pixel_out = center_p_shift[5]; // 同步延迟的中心像素（用于极端边缘透传）

endmodule