/*  Simple dual-port 32-bit RAM with byte enables and a registered read,
    implemented with explicit M10K and four native byte enables. Read data
    appears one clock after the address; contents power up as zero.
*/

module ngage_bram_be #(
    parameter AW = 10
) (
    input  wire          clk,
    input  wire [AW-1:0] raddr,
    output wire [  31:0] rdata,
    input  wire [AW-1:0] waddr,
    input  wire [   3:0] we,
    input  wire [  31:0] wdata
);

    ngage_bram #(
        .AW         (AW),
        .DW         (32),
        .BYTE_WIDTH (8),
        .READ_ONLY_B(1)
    ) ram (
        .clk   (clk),
        .addr_a(waddr),
        .data_a(wdata),
        .we_a  (we),
        .q_a   (),
        .addr_b(raddr),
        .data_b(32'b0),
        .we_b  (4'b0),
        .q_b   (rdata)
    );
endmodule
