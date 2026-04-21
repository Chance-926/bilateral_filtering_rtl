`timescale 1ns / 1ps

module bf_delay_buf #(
    parameter DELAY_CYCLES = 3876,  // 默认延迟拍数：滑窗(3843) + MAC(6) + 同步除法(27) = 3876
    
    parameter RAM_DEPTH    = 4096,   // RAM 深度必须是 2 的次幂，且大于延迟拍数。4096 最合适。
    parameter ADDR_WIDTH   = 12      // 2^12 = 4096
)(
    input  logic       clk,
    input  logic       rst_n,

    // 1. 上游输入 (此时的 Y 数据刚要进入滑窗模块，三个通道在同一起跑线)
    input  logic       vsync_in,
    input  logic       hsync_in,     // 通常场同步也伴随行同步，一起打包最安全
    input  logic       de_in,
    input  logic [7:0] cb_in,
    input  logic [7:0] cr_in,

    // 2. 下游输出 (经历 3876 拍后，恰好与处理完毕的 Y_out 完美相遇)
    output logic       vsync_out,
    output logic       hsync_out,
    output logic       de_out,
    output logic [7:0] cb_out,
    output logic [7:0] cr_out
);

    //======================================================================
    // 信号打包 (1 + 1 + 1 + 8 + 8 = 19 bits)
    //======================================================================
    localparam DATA_WIDTH = 19;
    
    wire  [DATA_WIDTH-1:0] pack_in = {vsync_in, hsync_in, de_in, cb_in, cr_in};
    logic [DATA_WIDTH-1:0] pack_out;

    //======================================================================
    // 核心存储阵列声明
    // (* ram_style = "block" *) 指导综合工具强制使用块 RAM (BRAM/M4K)
    //======================================================================
    (* ram_style = "block" *) logic [DATA_WIDTH-1:0] ring_ram [0 : RAM_DEPTH-1];

    //======================================================================
    // 读写指针控制区 (带异步复位)
    //======================================================================
    logic [ADDR_WIDTH-1:0] wr_ptr;
    logic [ADDR_WIDTH-1:0] rd_ptr;

    // 因为 BRAM 读出自身需要 1 拍，所以地址偏移量必须减 1  ？？？
    // 例如要求延迟 3876 拍，指针差值应为 3875。
    localparam PTR_OFFSET = DELAY_CYCLES - 1;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= '0;
            // 利用无符号数补码特性，0 - 3875 会自动变成 4096-3875=221
            // 天然形成完美的追逃环形跑道
            rd_ptr <= -PTR_OFFSET; 
        end else begin
            // 计数器达到 4095 后自动溢出回 0
            wr_ptr <= wr_ptr + 1'b1;
            rd_ptr <= rd_ptr + 1'b1;
        end
    end

    //======================================================================
    // RAM 读写执行区 (无异步复位，确保生成最纯正的 BRAM)
    //======================================================================
    always_ff @(posedge clk) begin
        // 永远在当前写指针位置写入最新数据
        ring_ram[wr_ptr] <= pack_in;
        // 永远在当前读指针位置读出历史数据 (下一拍出现在 pack_out 上)
        pack_out         <= ring_ram[rd_ptr];
    end

    //======================================================================
    // 信号解包
    //======================================================================
    assign {vsync_out, hsync_out, de_out, cb_out, cr_out} = pack_out;

endmodule