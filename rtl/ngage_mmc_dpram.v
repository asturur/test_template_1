// SPDX-License-Identifier: GPL-2.0-or-later
// Backing-cache helper, not a physical phone chip.
// Verilog-2001 port of ngage2 rtl/board/tdp_ram.sv.
// Donor SHA256: e235b8c071c5b2faa97bc263d51f1e79e7ad52786be4edb7bf2667c4e91fe344
// True dual-port block RAM, one clock: each port reads and writes, and a
// write returns the new data on its own port. This is Quartus's template for
// an M10K in true dual-port mode.
module ngage_mmc_dpram #(
    parameter integer AW = 9,
    parameter integer DW = 16
) (
    input wire clk,

    input  wire          we_a,
    input  wire [AW-1:0] addr_a,
    input  wire [DW-1:0] wdata_a,
    output reg  [DW-1:0] q_a,

    input  wire          we_b,
    input  wire [AW-1:0] addr_b,
    input  wire [DW-1:0] wdata_b,
    output reg  [DW-1:0] q_b
);

    reg [DW-1:0] mem[0:(1 << AW) - 1];

    always @(posedge clk) begin
        if (we_a) begin
            mem[addr_a] <= wdata_a;
            q_a         <= wdata_a;
        end else begin
            q_a <= mem[addr_a];
        end
    end

    always @(posedge clk) begin
        if (we_b) begin
            mem[addr_b] <= wdata_b;
            q_b         <= wdata_b;
        end else begin
            q_b <= mem[addr_b];
        end
    end

endmodule
