/*  Simple dual-port 32-bit RAM with byte enables and a registered read,
    written as four independent 8-bit lanes so Quartus infers block RAM
    (M10K) rather than registers. Read data appears one clock after the
    address; contents power up as zero (FPGA init / Verilator x-initial 0).
*/

module ngage_bram_be #(
    parameter AW = 10
)(
    input  wire          clk,
    input  wire [AW-1:0] raddr,
    output wire [31:0]   rdata,
    input  wire [AW-1:0] waddr,
    input  wire [ 3:0]   we,
    input  wire [31:0]   wdata
);

genvar g;
generate
    for (g = 0; g < 4; g = g + 1) begin : lane
        (* ramstyle = "no_rw_check" *)
        reg [7:0] mem [0:(1<<AW)-1];
        reg [7:0] q;

        always @(posedge clk) begin
            if (we[g]) mem[waddr] <= wdata[g*8 +: 8];
            q <= mem[raddr];
        end

        assign rdata[g*8 +: 8] = q;
    end
endgenerate

endmodule
