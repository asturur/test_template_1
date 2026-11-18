// SPDX-License-Identifier: GPL-3.0-or-later
// N-Gage CPU integration boundary. Board clocks, SDRAM and peripherals
// belong outside this module. The reference build uses patched ZAP ARM920T.
module ngage_cpu #(
    parameter LINE_REFILL = 0
) (

    output wire        line_req,
    output wire [31:0] line_addr,
    input  wire        line_ready,
    input  wire        line_reject,
    input  wire        line_valid,
    input  wire [63:0] line_data,
    input  wire        line_wide,
    input  wire        line_last,
    input  wire        line_error,

    input  logic        clk,
    input  logic        reset,
    input  logic        irq,
    input  logic        fiq,
    output logic        wb_cyc,
    output logic        wb_lock,
    output wire         wb_code,
    output logic        wb_stb,
    output logic [31:0] wb_address,
    output logic        wb_write,
    output logic [31:0] wb_write_data,
    output logic [ 3:0] wb_byte_enable,
    output logic [ 2:0] wb_cycle_type,
    output logic [ 1:0] wb_burst_type,
    input  logic        wb_ack,
    input  logic        wb_error,
    input  logic [31:0] wb_read_data,
    output wire  [31:0] debug_pc,
    output wire  [31:0] debug_cpsr,
    output wire  [31:0] debug_instruction,
    output wire         debug_fetch
);
`ifdef NGAGE_ARM9V2
    wire [31:0] donor_pc, donor_cpsr, donor_instruction;
    wire donor_fetch;

    // A donor refill is a wrapped sequence of four owned 32-bit beats.
    // Use the board's normal word path so every beat can return its own error.
    // The separate 32-byte line channel has different alignment and framing.
    assign line_req  = 1'b0;
    assign line_addr = 32'b0;
    assign wb_stb    = wb_cyc;

`ifndef NGAGE_NO_CPU_DEBUG
    assign debug_pc          = donor_pc;
    assign debug_cpsr        = donor_cpsr;
    assign debug_instruction = donor_instruction;
    assign debug_fetch       = donor_fetch;
`endif

    ngage2_arm925t u_arm925t (
        .clk              (clk),
        .reset            (reset),
        .irq              (irq),
        .fiq              (fiq),
        .bus_req          (wb_cyc),
        .bus_lock         (wb_lock),
        .bus_code         (wb_code),
        .bus_addr         (wb_address),
        .bus_we           (wb_write),
        .bus_wdata        (wb_write_data),
        .bus_be           (wb_byte_enable),
        .bus_cti          (wb_cycle_type),
        .bus_bte          (wb_burst_type),
        .bus_burst        (),
        .bus_ack          (wb_ack),
        .bus_err          (wb_error),
        .bus_rdata        (wb_read_data),
        .bus_no_late_error(1'b0),
        .dbg_pc           (donor_pc),
        .dbg_wb_cpsr      (donor_cpsr),
        .dbg_instruction  (donor_instruction),
        .dbg_fetch_valid  (donor_fetch)
    );
`else
    zap_top #(
        .LINE_REFILL    (LINE_REFILL),
        .CP15_L4_DEFAULT(1'b1),
        .ONLY_CORE      (1'b0),
        .RESET_VECTOR   (32'h00000000),
        .DATA_CACHE_SIZE(16384),
        .CODE_CACHE_SIZE(16384),
        .DATA_CACHE_LINE(32),
        .CODE_CACHE_LINE(32)
    ) u_zap (
        .line_req   (line_req),
        .line_addr  (line_addr),
        .line_ready (line_ready),
        .line_reject(line_reject),
        .line_valid (line_valid),
        .line_data  (line_data),
        .line_wide  (line_wide),
        .line_last  (line_last),
        .line_error (line_error),

`ifndef NGAGE_NO_CPU_DEBUG
        .o_debug_pc         (debug_pc),
        .o_debug_cpsr       (debug_cpsr),
        .o_debug_instruction(debug_instruction),
        .o_debug_fetch      (debug_fetch),
`endif
        .i_clk              (clk),
        .i_reset            (reset),
        .i_irq              (irq),
        .i_fiq              (fiq),
        .o_wb_lock          (wb_lock),
        .o_wb_code          (wb_code),
        .o_wb_cyc           (wb_cyc),
        .o_wb_stb           (wb_stb),
        .o_wb_adr           (wb_address),
        .o_wb_we            (wb_write),
        .o_wb_dat           (wb_write_data),
        .o_wb_sel           (wb_byte_enable),
        .o_wb_cti           (wb_cycle_type),
        .o_wb_bte           (wb_burst_type),
        .i_wb_ack           (wb_ack),
        .i_wb_dat           (wb_read_data),
        .i_wb_err           (wb_error)
    );
`endif
`ifdef NGAGE_NO_CPU_DEBUG
    assign debug_pc          = 0;
    assign debug_cpsr        = 0;
    assign debug_instruction = 0;
    assign debug_fetch       = 0;
`endif
endmodule
