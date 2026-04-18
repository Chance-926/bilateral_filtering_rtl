`timescale 1ns / 1ps

module bf_final_sync_mux #(
    parameter DIV_LATENCY = 26  // 除法器 IP 的延迟拍数
)(
    input  logic       clk,
    input  logic       rst_n,

    // 1. 来自除法器 IP 的数据输入 (相对延迟：26拍)
    input  logic [7:0] divide_quotient,  // 除法器算出的滤波结果 (商的低 8 位)

    // 2. 来自乘加引擎(MAC)的控制与原图数据输入 (相对延迟：0拍)
    input  logic       mac_de,           // 乘加模块输出的使能信号
    input  logic       mac_is_core,      // 乘加模块输出的核心区标志
    input  logic [7:0] center_pixel_out, // 乘加模块透传过来的中心原图像素
    
    // (可选) 帧同步信号，这里假设从滑窗模块一路打拍送过来，为了方便也跟着延迟
    input  logic       mac_vsync,    //?    

    // 3. 终极输出给下一级 (HDMI/VGA 显示端或色彩空间转换端)
    output logic [7:0] y_out,            // 最终的 Y 通道输出
    output logic       de_out,           // 最终的数据有效信号
    output logic       vsync_out         // 最终的场同步信号
);

    //======================================================================
    // 移位寄存器链：延迟控制信号，等待除法器完成计算
    //======================================================================
    // SystemVerilog 支持直接定义二维数组来做深度打拍，非常优雅
    logic [DIV_LATENCY-1:0] de_shift_chain;
    logic [DIV_LATENCY-1:0] is_core_shift_chain;
    logic [DIV_LATENCY-1:0] vsync_shift_chain;
    logic [7:0]             pixel_shift_chain [0 : DIV_LATENCY-1];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            de_shift_chain      <= '0; 
            is_core_shift_chain <= '0;
            vsync_shift_chain   <= '0;
            for(int i=0; i<DIV_LATENCY; i++) begin
                pixel_shift_chain[i] <= 8'd0;
            end
        end else begin
            // 数据移位入列 (链首)
            de_shift_chain      <= {de_shift_chain[DIV_LATENCY-2 : 0], mac_de};
            is_core_shift_chain <= {is_core_shift_chain[DIV_LATENCY-2 : 0], mac_is_core};
            vsync_shift_chain   <= {vsync_shift_chain[DIV_LATENCY-2 : 0], mac_vsync};
            
            pixel_shift_chain[0] <= center_pixel_out;
            for(int i=1; i<DIV_LATENCY; i++) begin
                pixel_shift_chain[i] <= pixel_shift_chain[i-1];
            end
        end
    end

    //======================================================================
    // 提取链尾信号 (刚好延迟了 DIV_LATENCY 拍，与除法器商绝对对齐)
    //======================================================================
    wire aligned_de       = de_shift_chain[DIV_LATENCY-1];
    wire aligned_is_core  = is_core_shift_chain[DIV_LATENCY-1];
    wire aligned_vsync    = vsync_shift_chain[DIV_LATENCY-1];
    wire [7:0] aligned_px = pixel_shift_chain[DIV_LATENCY-1];

    //======================================================================
    // 终极输出多路选择器 (MUX)
    //======================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            y_out     <= 8'd0;
            de_out    <= 1'b0;
            vsync_out <= 1'b0;
        end else begin
            // 同步信号直接输出
            de_out    <= aligned_de;
            vsync_out <= aligned_vsync;
            
            // 业务逻辑判断：
            if (aligned_de) begin//
                if (aligned_is_core) begin
                    // 核心区：输出除法器算出来的双边滤波结果
                    y_out <= divide_quotient;
                end else begin
                    // 边缘区：直接输出纯黑，裁剪掉边缘
                    // (如果以后你又想透传了，只需要把 8'd0 改成 aligned_px 即可！)
                    y_out <= 8'd0; 
                end
            end else begin
                y_out <= 8'd0; // 非有效显示区域保持纯黑
            end
        end
    end

endmodule