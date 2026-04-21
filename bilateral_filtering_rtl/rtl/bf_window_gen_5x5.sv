`timescale 1ns / 1ps
//本模块使用的fifo为预读模式

//数据核in_de再clk下降沿输入？
//对外显示，相对于矩阵，
//matrix_de提前拉高了一拍，out_active提前了一拍，坐标center_x提前了一拍，is_core提前用一拍，但相对对齐
//对的，数据从0开始
//冲刷区衔接没问题

//！在p33输出最后一个值的clk内，matrix_de已经拉低了


module bf_window_gen_5x5 #(
    parameter IMG_WIDTH  = 12'd1920,
    parameter IMG_HEIGHT = 12'd1080
)(
    input  wire        clk,
    input  wire        rst_n,

    // DVP 视频流输入 (Y通道)
    input  wire        vsync_in,    // 场同步信号 (高电平表示一帧开始的消隐区)
    input  wire        de_in,       // 数据有效信号
    input  wire [7:0]  y_in,        // Y分量输入

    // 5x5 矩阵输出 (pXY: X代表行 1~5，Y代表列 1~5)
    output reg  [7:0]  matrix_p11, matrix_p12, matrix_p13, matrix_p14, matrix_p15,
    output reg  [7:0]  matrix_p21, matrix_p22, matrix_p23, matrix_p24, matrix_p25,
    output reg  [7:0]  matrix_p31, matrix_p32, matrix_p33, matrix_p34, matrix_p35,
    output reg  [7:0]  matrix_p41, matrix_p42, matrix_p43, matrix_p44, matrix_p45,
    output reg  [7:0]  matrix_p51, matrix_p52, matrix_p53, matrix_p54, matrix_p55,

    // 同步信号与坐标输出 (严格对齐中心像素 p33)
    output wire        matrix_de,   //开始输出矩阵：窗口中心开始扫描第一个像素时拉高
    output wire        matrix_vsync,
   
    output wire [11:0] center_x,    // 当前中心像素所在的列坐标 (0 ~ IMG_WIDTH-1)
    output wire [11:0] center_y,    // 当前中心像素所在的行坐标 (0 ~ IMG_HEIGHT-1)
    output wire        is_core      //该中心像素可以滤波时拉高
); 

    wire is_flushing;
    wire internal_de;
    wire [7:0] internal_y;

    //======================================================================
    // 1. VSYNC 边沿检测与 FIFO 同步清零逻辑
    //======================================================================
    reg vsync_d1, vsync_d2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            vsync_d1 <= 1'b0;
            vsync_d2 <= 1'b0;
        end else begin
            vsync_d1 <= vsync_in;
            vsync_d2 <= vsync_d1;
        end
    end
    
    // 提取 VSYNC 上升沿作为清零信号 (包含一帧结束，新一帧开始的准备期)
    wire vsync_pos = vsync_d1 & ~vsync_d2; 

    //======================================================================
    // 2. 行列计数器 (追踪当前输入像素 y_in 的坐标)
    //======================================================================
    reg [11:0] col_cnt;
    reg [11:0] row_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            col_cnt <= 12'd0;
            row_cnt <= 12'd0;
        end else if (vsync_pos) begin
            col_cnt <= 12'd0;
            row_cnt <= 12'd0;
        end else if (internal_de) begin
            if (col_cnt == IMG_WIDTH - 1'b1) begin
                col_cnt <= 12'd0;
                row_cnt <= row_cnt + 1'b1;
            end else begin
                col_cnt <= col_cnt + 1'b1;
            end
        end
    end

    //======================================================================
    // 末尾数据冲刷逻辑 
    //======================================================================
    //在每帧结束后，继续强制产生 (2*IMG_WIDTH + 2) 个时钟的移位使能，使卡在行缓存最后面的两行数据会被强行“挤”到窗口中心位p33
    reg [12:0] flush_cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            flush_cnt <= 13'd0;
        end else if (vsync_pos) begin
            flush_cnt <= 13'd0;
        end else if (de_in && (row_cnt == IMG_HEIGHT - 1'b1) && (col_cnt == IMG_WIDTH - 1'b1)) begin
            // 帧输入结束的瞬间，触发冲刷计数器 (2行 + 2个像素)
            flush_cnt <= (IMG_WIDTH * 2) + 3;
        end else if (flush_cnt > 0) begin
            flush_cnt <= flush_cnt - 1'b1;
        end
    end

    assign is_flushing = (flush_cnt > 0);
    assign internal_de = (de_in | is_flushing);  // 两段使能整合
    assign internal_y = de_in ? y_in : 8'd0;   // 两段输入整合


    //======================================================================
    // 3. 例化 4 个 FWFT FIFO 构建 Line Buffer
    //======================================================================
    wire [7:0] row4_data, row3_data, row2_data, row1_data; //row后的序号表示窗口中的row
    
    // 读写使能控制：当行数 >= N 时，对应的 FIFO 才开始吐出历史数据
    wire wr_en1 = internal_de ;
    wire rd_en1 = internal_de && (row_cnt >= 12'd1); // 第2行开始读取第1行
    wire rd_en2 = internal_de && (row_cnt >= 12'd2); // 第3行开始读取第2行
    wire rd_en3 = internal_de && (row_cnt >= 12'd3); // 第4行开始读取第3行
    wire rd_en4 = internal_de && (row_cnt >= 12'd4); // 第5行开始读取第4行

    // 提示：请确保中科亿海微 FIFO IP 例化名和端口名与下方一致
    fifo_filter u_line_buf1 (
        .clock (clk),         // 映射系统时钟
        .sclr  (vsync_pos),   // 同步清零 (帧起始脉冲)
        .data  (internal_y),  // 输入数据
        .wrreq (wr_en1),      // 写请求 (Write Request)
        .rdreq (rd_en1),      // 读请求 (Read Request)
        .q     (row4_data)    // 输出数据
    );

    fifo_filter u_line_buf2 (
        .clock (clk),
        .sclr  (vsync_pos),
        .data  (row4_data),
        .wrreq (rd_en1),      // FWFT模式下，本级读就是下级写
        .rdreq (rd_en2),
        .q     (row3_data)
    );

    fifo_filter u_line_buf3 (
        .clock (clk),
        .sclr  (vsync_pos),
        .data  (row3_data),
        .wrreq (rd_en2),
        .rdreq (rd_en3),
        .q     (row2_data)
    );

    fifo_filter u_line_buf4 (
        .clock (clk),
        .sclr  (vsync_pos),
        .data  (row2_data),
        .wrreq (rd_en3),
        .rdreq (rd_en4),
        .q     (row1_data)
    );

    //======================================================================
    // 4. 5x5 移位寄存器矩阵生成
    //======================================================================
    // 中心像素位于第3行，第3列。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // 矩阵清零 (省略部分代码以保持整洁，实际综合工具会自动处理)
            {matrix_p11, matrix_p12, matrix_p13, matrix_p14, matrix_p15} <= 40'd0;
            {matrix_p21, matrix_p22, matrix_p23, matrix_p24, matrix_p25} <= 40'd0;
            {matrix_p31, matrix_p32, matrix_p33, matrix_p34, matrix_p35} <= 40'd0;
            {matrix_p41, matrix_p42, matrix_p43, matrix_p44, matrix_p45} <= 40'd0;
            {matrix_p51, matrix_p52, matrix_p53, matrix_p54, matrix_p55} <= 40'd0;
        end else if (internal_de) begin
            // 第1行移位
            matrix_p11 <= matrix_p12; matrix_p12 <= matrix_p13; 
            matrix_p13 <= matrix_p14; matrix_p14 <= matrix_p15; matrix_p15 <= row1_data;
            // 第2行移位
            matrix_p21 <= matrix_p22; matrix_p22 <= matrix_p23; 
            matrix_p23 <= matrix_p24; matrix_p24 <= matrix_p25; matrix_p25 <= row2_data;
            // 第3行移位 (中心行)
            matrix_p31 <= matrix_p32; matrix_p32 <= matrix_p33; 
            matrix_p33 <= matrix_p34; matrix_p34 <= matrix_p35; matrix_p35 <= row3_data;
            // 第4行移位
            matrix_p41 <= matrix_p42; matrix_p42 <= matrix_p43; 
            matrix_p43 <= matrix_p44; matrix_p44 <= matrix_p45; matrix_p45 <= row4_data;
            // 第5行移位 (最新行)
            matrix_p51 <= matrix_p52; matrix_p52 <= matrix_p53; 
            matrix_p53 <= matrix_p54; matrix_p54 <= matrix_p55; matrix_p55 <= internal_y;
        end
    end

    //======================================================================
    // 5. 输出坐标系与使能生成
    //======================================================================

    reg [11:0] out_x;
    reg [11:0] out_y;
    reg        out_active;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_x      <= 12'd0;
            out_y      <= 12'd0;
            out_active <= 1'b0;
        end else if (vsync_pos) begin
            out_x      <= 12'd0;
            out_y      <= 12'd0;
            out_active <= 1'b0;
        end else if (internal_de) begin
            // 当内部坐标达到 (2,2) 时，p33正好装入图像像素(0,0)，启动输出！
            if (row_cnt == 12'd2 && col_cnt == 12'd2) begin
                out_active <= 1'b1;
                out_x      <= 12'd0;
                out_y      <= 12'd0;
            end 
            // 维持输出矩阵使能，并严格产生 1920x1080 个坐标
            else if (out_active) begin
                if (out_x == IMG_WIDTH - 1'b1) begin
                    out_x <= 12'd0;
                    if (out_y == IMG_HEIGHT - 1'b1) begin
                        out_active <= 1'b0; // 一帧完整的 1920x1080 输出完毕
                    end else begin
                        out_y <= out_y + 1'b1;
                    end
                end else begin
                    out_x <= out_x + 1'b1;
                end
            end
        end
    end

    // 核心判定区极其直观：仅仅基于输出坐标切除边缘两圈即可
    wire is_core_area = (out_x >= 12'd2) && (out_x <= IMG_WIDTH - 12'd3) && 
                   (out_y >= 12'd2) && (out_y <= IMG_HEIGHT - 12'd3);

    //======================================================================
    // 最终输出端口赋值
    //======================================================================
    assign matrix_de    = (internal_de && out_active); 
    assign matrix_vsync = vsync_pos;

    assign center_x     = out_x;       // 给下游的坐标绝对纯净 (0~1919)
    assign center_y     = out_y;       // 给下游的坐标绝对纯净 (0~1079)
    assign is_core      = is_core_area;    //判定是否为需要滤波的像素 

endmodule