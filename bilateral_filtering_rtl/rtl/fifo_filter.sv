`timescale 1ns/1ps

module fifo_filter (
    input  wire       clock,
    input  wire [7:0] data,
    input  wire       rdreq,
    input  wire       wrreq,
    input  wire       sclr,
    output wire [7:0] q
);

    // 深度 2048 的 RAM
    reg [7:0] mem [0:2047];
    reg [11:0] wr_ptr;
    reg [11:0] rd_ptr;

    always @(posedge clock) begin
        if (sclr) begin
            wr_ptr <= 12'd0;
            rd_ptr <= 12'd0;
        end else begin
            if (wrreq) begin
                mem[wr_ptr] <= data;
                wr_ptr <= (wr_ptr == 12'd2047) ? 12'd0 : wr_ptr + 1'b1;
            end
            if (rdreq) begin
                rd_ptr <= (rd_ptr == 12'd2047) ? 12'd0 : rd_ptr + 1'b1;
            end
        end
    end

    // FWFT 模式核心：只要 rd_ptr 指向哪里，数据直接透传到输出 q
    assign q = mem[rd_ptr];

endmodule