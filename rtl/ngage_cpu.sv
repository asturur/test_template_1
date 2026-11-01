// SPDX-License-Identifier: GPL-3.0-or-later
// N-Gage CPU integration boundary. This is a ZAP-based ARMv4T/ARM920T
// compatibility configuration; board clocks, SDRAM and peripherals belong
// outside this module. Use the pinned source plus patches/zap/ fixes.
module ngage_cpu (
    input  logic        clk,
    input  logic        reset,
    input  logic        irq,
    input  logic        fiq,
    output logic        wb_cyc,
    output logic        wb_stb,
    output logic [31:0] wb_address,
    output logic        wb_write,
    output logic [31:0] wb_write_data,
    output logic [3:0]  wb_byte_enable,
    output logic [2:0]  wb_cycle_type,
    output logic [1:0]  wb_burst_type,
    input  logic        wb_ack,
    input  logic        wb_error,
    input  logic [31:0] wb_read_data
);
    zap_top #(
        .CP15_L4_DEFAULT(1'b1),
        .ONLY_CORE(1'b0),
        .BP_ENTRIES(32'd64),      // BTB entries (was 512; Cyclone V limit)
        .RESET_VECTOR(32'h00000000),
        .DATA_CACHE_SIZE(1024),   // 1KB (was 16KB; Cyclone V limit)
        .CODE_CACHE_SIZE(1024),   // 1KB (was 16KB)
        .DATA_CACHE_LINE(32),
        .CODE_CACHE_LINE(32)
    ) u_zap (
        .i_clk(clk), .i_reset(reset),
        .i_irq(irq), .i_fiq(fiq),
        .o_wb_cyc(wb_cyc), .o_wb_stb(wb_stb),
        .o_wb_adr(wb_address), .o_wb_we(wb_write),
        .o_wb_dat(wb_write_data), .o_wb_sel(wb_byte_enable),
        .o_wb_cti(wb_cycle_type), .o_wb_bte(wb_burst_type),
        .i_wb_ack(wb_ack), .i_wb_dat(wb_read_data), .i_wb_err(wb_error)
    );
endmodule
