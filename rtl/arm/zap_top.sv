//
// (C)2016-2024 Revanth Kamaraj (krevanth) <revanth91kamaraj@gmail.com>
//
//
// This program is free software; you can redistribute it and/or
// modify it under the terms of the GNU General Public License
// as published by the Free Software Foundation; either version 3
// of the License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program; if not, write to the Free Software
// Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
// 02110-1301, USA.
//
//
// This is the top module of the ZAP processor. It contains instances of
// processor core and the memory management units. I and D WB busses
// are provided.
//

module zap_top #(

    // -----------------------------------
    // CP15 L4 bit default.
    // -----------------------------------

    parameter             LINE_REFILL     = 0,
    parameter logic [0:0] CP15_L4_DEFAULT = 1'd0,

    // -----------------------------------
    // Only core. When 1, cache and MMU
    // are not present.
    // -----------------------------------

    parameter logic [0:0] ONLY_CORE = 1'd0,

    // -----------------------------------
    // Set reset vector here
    // -----------------------------------

    parameter logic [31:0] RESET_VECTOR = 32'd0,

    // -----------------------------------
    // Set initial value of CPSR here.
    // -----------------------------------

    parameter logic [31:0] CPSR_INIT = {24'd0, 1'd1, 1'd1, 1'd0, 5'b10011},

    // -----------------------------------
    // Enable BE-32
    // -----------------------------------

    parameter logic [0:0] BE_32_ENABLE = 1'd0,

    // -----------------------------------
    // BP entries, FIFO depths
    // -----------------------------------

    parameter logic [31:0] BP_ENTRIES = 32'd512,  // Predictor depth.
    parameter logic [31:0] FIFO_DEPTH = 32'd16,   // FIFO depth.
    parameter logic [31:0] RAS_DEPTH  = 32'd4,    // Depth of RAS.

    // ----------------------------------
    // Data MMU/Cache configuration.
    // ----------------------------------
    parameter logic [31:0] DATA_CACHE_SIZE = 32'd16384,  // Cache size in bytes.
    parameter logic [31:0] DATA_CACHE_LINE = 32'd64,     // Cache line size in bytes.

    // ----------------------------------
    // Code MMU/Cache configuration.
    // ----------------------------------
    parameter logic [31:0] CODE_CACHE_SIZE = 32'd16384,  // Cache size in bytes.
    parameter logic [31:0] CODE_CACHE_LINE = 32'd64      // Ccahe line size in bytes.

) (
`ifndef SYNTHESIS

    // --------------------------------------
    // Trace. Only for DV. Leave open.
    // --------------------------------------

    output logic [1023:0] o_trace,
    output logic          o_trace_valid,
    output logic          o_trace_uop_last,

`endif

    // --------------------------------------
    // Clock and reset
    // --------------------------------------

    output wire  [31:0] o_debug_pc,
    output wire  [31:0] o_debug_cpsr,
    output wire  [31:0] o_debug_instruction,
    output wire         o_debug_fetch,
    input  logic        i_clk,
    input  logic        i_reset,

    // ---------------------------------------
    // Interrupts.
    // Both of them are active high and level
    // trigerred.
    // ---------------------------------------

    input logic i_irq,
    input logic i_fiq,

    // ---------------------
    // Wishbone interface.
    // ---------------------

    output logic        o_wb_cyc,
    output logic        o_wb_code,
    output logic        o_wb_lock,
    output logic        o_wb_stb,
    output logic [31:0] o_wb_adr,
    output logic        o_wb_we,
    output logic [31:0] o_wb_dat,
    output logic [ 3:0] o_wb_sel,

    output wire line_req,
    output wire [31:0] line_addr,
    input wire line_ready,
    input wire line_reject,
    input wire line_valid,
    input wire [63:0] line_data,
    input wire line_wide,
    input wire line_last,
    input wire line_error,

    output logic [ 2:0] o_wb_cti,
    output logic [ 1:0] o_wb_bte,
    input  logic        i_wb_ack,
    input  logic [31:0] i_wb_dat,
    input  logic        i_wb_err
);

  assign o_wb_bte = 2'b00;  // Linear Burst.

  `include "zap_defines.svh"
  `include "zap_localparams.svh"
  `include "zap_functions.svh"

  // Assertion.

  always@(posedge i_clk) // Assertion.
begin
    if (!i_reset && o_wb_cyc) begin
      assert (|o_wb_cti)
      else $fatal(2, "O_WB_CTI is not EOB.");
    end
  end

  logic wb_cyc, wb_stb, wb_we;
  logic [3:0] wb_sel;
  logic [31:0] wb_dat, wb_idat;
  logic [31:0] wb_adr;
  logic [ 2:0] wb_cti;
  wire c_line_req, d_line_req, c_line_ready, d_line_ready;
  wire [31:0] c_line_addr, d_line_addr;
  wire c_line_valid, d_line_valid, c_line_reject, d_line_reject;
  wire [63:0] cache_line_data;
  wire cache_line_wide, cache_line_last, cache_line_error;
  arm920_line_owner #(
      .ENABLE(LINE_REFILL && !ONLY_CORE)
  ) line_owner (
      .clk(i_clk),
      .reset(s_reset),
      .blocked(o_wb_cyc || !dc_write_buffer_empty || cpu_dc_swp_lock),
      .c_req(c_line_req),
      .c_addr(c_line_addr),
      .c_ready(c_line_ready),
      .c_valid(c_line_valid),
      .c_reject(c_line_reject),
      .d_req(d_line_req),
      .d_addr(d_line_addr),
      .d_ready(d_line_ready),
      .d_valid(d_line_valid),
      .d_reject(d_line_reject),
      .out_data(cache_line_data),
      .out_wide(cache_line_wide),
      .out_last(cache_line_last),
      .out_error(cache_line_error),
      .line_req(line_req),
      .line_addr(line_addr),
      .line_ready(line_ready),
      .line_reject(line_reject),
      .line_valid(line_valid),
      .line_data(line_data),
      .line_wide(line_wide),
      .line_last(line_last),
      .line_error(line_error)
  );

  logic        wb_ack;
  logic        wb_err;
  logic        cpu_mmu_en;
  logic        cpu_alignment_fault;
  logic [31:0] cpu_alignment_far;
  logic [ZAP_CPSR_MODE:0] cpu_cpsr, cpu_data_cpsr;
  logic cpu_mem_translate;
  logic [31:0] cpu_daddr, cpu_daddr_nxt, cpu_daddr_check;
  logic [31:0] cpu_iaddr, cpu_iaddr_nxt, cpu_iaddr_check;
  logic [ 7:0] dc_fsr;
  logic [31:0] dc_far;
  logic cpu_dc_en, cpu_ic_en;
  logic [1:0] cpu_sr;
  logic [31:0] cpu_baddr, cpu_dac_reg;
  logic cpu_dc_inv, cpu_ic_inv;
  logic cpu_dc_clean, cpu_ic_clean;
  logic dc_inv_done, ic_inv_done, dc_clean_done, ic_clean_done;
  logic cpu_dtlb_inv, cpu_itlb_inv;
  logic data_ack, data_request_ack, data_err, instr_ack, instr_err;
  logic [31:0] ic_data, dc_data, cpu_dc_dat;
  logic cpu_instr_stb;
  logic cpu_dc_we, cpu_dc_stb;
  logic [ 1:0] cpu_dc_swp_tag;
  logic        cpu_dc_swp_lock;
  logic [ 3:0] cpu_dc_sel;
  logic        c_wb_stb;
  logic        c_wb_cyc;
  logic        c_wb_wen;
  logic [ 3:0] c_wb_sel;
  logic [31:0] c_wb_dat;
  logic [31:0] c_wb_adr;
  logic [ 2:0] c_wb_cti;
  logic        c_wb_ack;
  logic        c_wb_err;
  logic        d_wb_stb;
  logic        d_wb_cyc;
  logic        d_wb_wen;
  logic [ 3:0] d_wb_sel;
  logic [31:0] d_wb_dat;
  logic [31:0] d_wb_adr;
  logic [ 2:0] d_wb_cti;
  logic        d_wb_ack;
  logic        d_wb_err;
  logic [63:0] dc_rreg_idx, dc_wreg_idx;
  logic [ 5:0] dc_rreg_idx_bin;
  logic [ 5:0] dc_load_info;
  logic [63:0] dc_lock;
  logic [31:0] dc_reg_data;
  logic icache_err2, dcache_err2;
  logic       cpu_cache_rr;
  logic       cpu_dc_lock_write;
  logic [5:0] cpu_dc_lock_base;
  logic       cpu_ic_lock_write;
  logic dc_lock_done, ic_lock_done;
  logic [5:0] cpu_ic_lock_base;
  logic cpu_cache_op_single, cpu_cache_op_by_mva;
  logic cpu_drain_write_buffer, dc_write_buffer_empty;
  logic cpu_icache_prefetch, icache_prefetch_done;
  logic [31:0] cpu_cache_op_address;
  wire cpu_tlb_inv_mva, cpu_dtlb_lock_write, cpu_itlb_lock_write;
  wire [31:0] cpu_tlb_inv_address, cpu_tlb_lock_data, dtlb_lock_read, itlb_lock_read;
  logic cpu_dwe_check, cpu_dre_check;
  logic s_reset, s_fiq, s_irq;
  logic code_stall;
  wire  instr_discard;

  assign s_reset = i_reset;

  zap_dual_rank_synchronizer #(
      .WIDTH(2)
  ) u_sync (
      .i_clk  (i_clk),
      .i_reset(i_reset),
      .i_async({i_fiq, i_irq}),
      .o_sync ({s_fiq, s_irq})
  );

`ifdef SYNTHESIS

  /* verilator lint_off UNUSEDSIGNAL */

  logic [1023:0] o_trace;
  logic          o_trace_valid;
  logic          o_trace_uop_last;

  /* verilator lint_on UNUSEDSIGNAL */

`endif

  zap_core #(
      .CP15_L4_DEFAULT(CP15_L4_DEFAULT),
      .BP_ENTRIES(BP_ENTRIES),
      .FIFO_DEPTH(FIFO_DEPTH),
      .RAS_DEPTH(RAS_DEPTH),
      .BE_32_ENABLE(BE_32_ENABLE),
      .RESET_VECTOR(RESET_VECTOR),
      .CPSR_INIT(CPSR_INIT),
      .DATA_CACHE_SIZE(DATA_CACHE_SIZE),
      .DATA_CACHE_LINE(DATA_CACHE_LINE),
      .CODE_CACHE_SIZE(CODE_CACHE_SIZE),
      .CODE_CACHE_LINE(CODE_CACHE_LINE),
      .CPSR_MODE(ZAP_CPSR_MODE)
  ) u_zap_core (
      // Trace
      .o_trace         (o_trace),
      .o_trace_valid   (o_trace_valid),
      .o_trace_uop_last(o_trace_uop_last),

      // Read-only board diagnostics.
      .o_debug_pc         (o_debug_pc),
      .o_debug_cpsr       (o_debug_cpsr),
      .o_debug_instruction(o_debug_instruction),
      .o_debug_fetch      (o_debug_fetch),
      // Clock and reset.
      .i_clk              (i_clk),
      .i_reset            (s_reset),

      // Code related.
      .o_instr_wb_adr (cpu_iaddr),
      .o_instr_wb_stb (cpu_instr_stb),
      /* verilator lint_off PINCONNECTEMPTY */
      .o_instr_wb_cyc (),
      .o_instr_wb_we  (),
      .o_instr_wb_sel (),
      /* verilator lint_on PINCONNECTEMPTY */
      .o_code_stall   (code_stall),
      .o_instr_discard(instr_discard),

      .i_instr_wb_dat(!ONLY_CORE ? ic_data : i_wb_dat),
      .i_instr_wb_ack(instr_ack),
      .i_instr_wb_err(instr_err),

      // Data related.
      .o_data_wb_we(cpu_dc_we),
      .o_data_wb_adr(cpu_daddr),
      .o_data_alignment_fault(cpu_alignment_fault),
      .o_data_alignment_far(cpu_alignment_far),
      .o_data_wb_sel(cpu_dc_sel),
      .o_data_wb_dat(cpu_dc_dat),
      /* verilator lint_off PINCONNECTEMPTY */
      .o_data_wb_cyc(),
      .o_pid(),
      /* verilator lint_on PINCONNECTEMPTY */
      .o_data_wb_stb(cpu_dc_stb),
      .o_data_swp_tag(cpu_dc_swp_tag),
      .i_data_wb_dat(!ONLY_CORE ? dc_data : BE_32_ENABLE ? be_32(i_wb_dat, o_wb_sel) : i_wb_dat),
      // Swap data into CPU based on current o_wb_sel.

      .i_data_wb_ack(data_request_ack),
      .i_data_wb_err(data_err),

      // Interrupts.
      .i_fiq(s_fiq),
      .i_irq(s_irq),

      // MMU/cache is present.
      .i_fsr(!ONLY_CORE ? {24'd0, dc_fsr} : '0),
      .i_far(!ONLY_CORE ? dc_far : '0),

      .o_mem_translate       (cpu_mem_translate),
      .o_data_cpsr           (cpu_data_cpsr),
      .o_dac                 (cpu_dac_reg),
      .o_baddr               (cpu_baddr),
      .o_mmu_en              (cpu_mmu_en),
      .o_sr                  (cpu_sr),
      .o_dcache_inv          (cpu_dc_inv),
      .o_icache_inv          (cpu_ic_inv),
      .o_dcache_clean        (cpu_dc_clean),
      .o_icache_clean        (cpu_ic_clean),
      .o_dtlb_inv            (cpu_dtlb_inv),
      .o_itlb_inv            (cpu_itlb_inv),
      .o_tlb_inv_mva         (cpu_tlb_inv_mva),
      .o_tlb_inv_address     (cpu_tlb_inv_address),
      .o_dtlb_lock_write     (cpu_dtlb_lock_write),
      .o_itlb_lock_write     (cpu_itlb_lock_write),
      .o_tlb_lock_data       (cpu_tlb_lock_data),
      .i_dtlb_lock_read      (dtlb_lock_read),
      .i_itlb_lock_read      (itlb_lock_read),
      .o_dcache_en           (cpu_dc_en),
      .o_icache_en           (cpu_ic_en),
      .o_cache_rr            (cpu_cache_rr),
      .o_dcache_lock_write   (cpu_dc_lock_write),
      .o_dcache_lock_base    (cpu_dc_lock_base),
      .o_icache_lock_write   (cpu_ic_lock_write),
      .o_icache_lock_base    (cpu_ic_lock_base),
      .o_icache_prefetch     (cpu_icache_prefetch),
      .i_icache_prefetch_done(!ONLY_CORE ? icache_prefetch_done : 1'b1),
      .o_drain_write_buffer  (cpu_drain_write_buffer),
      .i_write_buffer_empty  (!ONLY_CORE ? dc_write_buffer_empty : 1'b1),
      .o_cache_op_single     (cpu_cache_op_single),
      .o_cache_op_by_mva     (cpu_cache_op_by_mva),
      .o_cache_op_address    (cpu_cache_op_address),
      .o_data_wb_adr_nxt     (cpu_daddr_nxt),
      // Data addr nxt. Used to drive address of data tag RAM.
      .o_data_wb_adr_check   (cpu_daddr_check),
      .o_data_wb_we_check    (cpu_dwe_check),
      .o_data_wb_re_check    (cpu_dre_check),
      .o_instr_wb_adr_nxt    (cpu_iaddr_nxt),
      // PC addr nxt. Drives read address of code tag RAM.
      .o_instr_wb_adr_check  (cpu_iaddr_check),
      .o_cpsr                (cpu_cpsr[ZAP_CPSR_MODE:0]),
      .o_dc_reg_idx          (dc_rreg_idx),
      .o_dc_reg_idx_bin      (dc_rreg_idx_bin),
      .o_dc_load_info        (dc_load_info),

      .i_dc_reg_idx       (!ONLY_CORE ? dc_wreg_idx : '0),
      .i_dc_lock          (!ONLY_CORE ? dc_lock : '0),
      .i_dc_reg_dat       (!ONLY_CORE ? dc_reg_data : '0),
      .i_dcache_lock_done (!ONLY_CORE ? dc_lock_done : 1'b1),
      .i_icache_lock_done (!ONLY_CORE ? ic_lock_done : 1'b1),
      .i_dcache_inv_done  (!ONLY_CORE ? dc_inv_done : '0),
      .i_icache_inv_done  (!ONLY_CORE ? ic_inv_done : '0),
      .i_dcache_clean_done(!ONLY_CORE ? dc_clean_done : '0),
      .i_icache_clean_done(!ONLY_CORE ? ic_clean_done : '0),
      .i_icache_err2      (!ONLY_CORE ? icache_err2 : '0),
      .i_dcache_err2      (!ONLY_CORE ? dcache_err2 : '0)
  );

  generate  // Quartus 17 compat: explicit generate
    if (!ONLY_CORE) begin : l_tieoffs_full
      // Normal case - with cache and MMU.
    end : l_tieoffs_full
    else begin : l_tieoffs_only_core
      assign data_request_ack = data_ack;
      assign dc_wreg_idx      = '0;
      assign dc_lock          = '0;
      assign dc_reg_data      = '0;
      assign dc_inv_done      = '0;
      assign ic_inv_done      = '0;
      assign dc_clean_done    = '0;
      assign ic_clean_done    = '0;
      assign icache_err2      = '0;
      assign dcache_err2      = '0;
      assign dc_fsr           = '0;
      assign dc_far           = '0;
      assign dc_data          = '0;
      assign ic_data          = '0;
      assign c_wb_ack         = '0;
      assign c_wb_err         = '0;
      assign d_wb_ack         = '0;
      assign d_wb_err         = '0;
      assign wb_cyc           = '0;
      assign wb_stb           = '0;
      assign wb_we            = '0;
      assign wb_sel           = '0;
      assign wb_idat          = '0;
      assign wb_adr           = '0;
      assign wb_cti           = CTI_EOB;
      assign wb_ack           = '0;
      assign wb_err           = '0;
      assign c_wb_stb         = '0;
      assign c_wb_cyc         = '0;
      assign c_wb_wen         = '0;
      assign c_wb_sel         = '0;
      assign c_wb_dat         = '0;
      assign c_wb_adr         = '0;
      assign c_wb_cti         = CTI_EOB;
      assign d_wb_stb         = '0;
      assign d_wb_cyc         = '0;
      assign d_wb_wen         = '0;
      assign d_wb_sel         = '0;
      assign d_wb_dat         = '0;
      assign d_wb_adr         = '0;
      assign d_wb_cti         = CTI_EOB;
      assign wb_dat           = '0;

      logic unused;

      assign unused =
           (    |dc_wreg_idx       )
         | (    |dc_lock           )
         | (    |dc_reg_data       )
         | (    |dc_inv_done       )
         | (    |ic_inv_done       )
         | (    |dc_clean_done     )
         | (    |ic_clean_done     )
         | (    |icache_err2       )
         | (    |dcache_err2       )
         | (    |dc_fsr            )
         | (    |dc_far            )
         | (    |dc_data           )
         | (    |ic_data           )
         | (    |c_wb_ack          )
         | (    |c_wb_err          )
         | (    |d_wb_ack          )
         | (    |d_wb_err          )
         | (    |wb_cyc            )
         | (    |wb_stb            )
         | (    |wb_we             )
         | (    |wb_sel            )
         | (    |wb_idat           )
         | (    |wb_adr            )
         | (    |wb_cti            )
         | (    |wb_ack            )
         | (    |wb_err            )
         | (    |c_wb_stb          )
         | (    |c_wb_cyc          )
         | (    |c_wb_wen          )
         | (    |c_wb_sel          )
         | (    |c_wb_dat          )
         | (    |c_wb_adr          )
         | (    |c_wb_cti          )
         | (    |d_wb_stb          )
         | (    |d_wb_cyc          )
         | (    |d_wb_wen          )
         | (    |d_wb_sel          )
         | (    |d_wb_dat          )
         | (    |d_wb_adr          )
         | (    |d_wb_cti          )
         | (    |wb_dat            )
         | (    |cpu_mmu_en        )
         | (    |cpu_cpsr          )
         | (    |cpu_mem_translate )
         | (    |cpu_daddr_nxt     )
         | (    |cpu_daddr_check   )
         | (    |cpu_iaddr_nxt     )
         | (    |cpu_iaddr_check   )
         | (    |cpu_dc_en         )
         | (    |cpu_ic_en         )
         | (    |cpu_sr            )
         | (    |cpu_baddr         )
         | (    |cpu_dac_reg       )
         | (    |cpu_dc_inv        )
         | (    |cpu_ic_inv        )
         | (    |cpu_dc_clean      )
         | (    |cpu_ic_clean      )
         | (    |cpu_dtlb_inv      )
         | (    |cpu_itlb_inv      )
         | (    |dc_rreg_idx       )
         | (    |dc_rreg_idx_bin   )
         | (    |cpu_dwe_check     )
         | (    |cpu_dre_check     )
         | (    |code_stall        )
         ;
    end : l_tieoffs_only_core

    if (!ONLY_CORE) begin : l_merger_for_core_with_cache_mmu

      zap_wb_merger #(
          .ONLY_CORE(1'd0)
      ) u_zap_wb_merger (

          .i_clk  (i_clk),
          .i_reset(s_reset),

          .i_c_wb_stb(c_wb_stb),
          .i_c_wb_cyc(c_wb_cyc),
          .i_c_wb_wen(c_wb_wen),
          .i_c_wb_sel(c_wb_sel),
          .i_c_wb_dat(c_wb_dat),
          .i_c_wb_adr(c_wb_adr),
          .i_c_wb_cti(c_wb_cti),
          .o_c_wb_ack(c_wb_ack),
          .o_c_wb_err(c_wb_err),

          .i_d_wb_lock(cpu_dc_swp_lock),
          .o_wb_lock  (o_wb_lock),
          .i_d_wb_stb (d_wb_stb),
          .i_d_wb_cyc (d_wb_cyc),
          .i_d_wb_wen (d_wb_wen),
          .i_d_wb_sel (d_wb_sel),
          .i_d_wb_dat (d_wb_dat),
          .i_d_wb_adr (d_wb_adr),
          .i_d_wb_cti (d_wb_cti),
          .o_d_wb_ack (d_wb_ack),
          .o_d_wb_err (d_wb_err),

          .o_wb_code(o_wb_code),
          .o_wb_cyc (wb_cyc),
          .o_wb_stb (wb_stb),
          .o_wb_wen (wb_we),
          .o_wb_sel (wb_sel),
          .o_wb_dat (wb_idat),
          .o_wb_adr (wb_adr),
          .o_wb_cti (wb_cti),
          .i_wb_ack (wb_ack),
          .i_wb_err (wb_err)

      );
    end : l_merger_for_core_with_cache_mmu
    else  // if ( ONLY_CORE )
    begin : l_merger_for_core_without_cache_mmu
      zap_wb_merger #(
          .ONLY_CORE(1'd1)
      ) u_zap_wb_merger (

          .i_clk  (i_clk),
          .i_reset(s_reset),

          .i_c_wb_stb(cpu_instr_stb),
          .i_c_wb_cyc(cpu_instr_stb),
          .i_c_wb_wen(1'h0),
          .i_c_wb_sel(4'hF),
          .i_c_wb_dat(32'd0),
          .i_c_wb_adr(cpu_iaddr),
          .i_c_wb_cti(3'b111),
          .o_c_wb_ack(instr_ack),
          .o_c_wb_err(instr_err),

          .i_d_wb_lock(1'b0),
          .o_wb_lock  (o_wb_lock),
          .i_d_wb_stb (cpu_dc_stb),
          .i_d_wb_cyc (cpu_dc_stb),
          .i_d_wb_wen (cpu_dc_we),

          // Swap sel from CPU if BE_32_ENABLE = 1.
          .i_d_wb_sel(BE_32_ENABLE ? be_sel_32(cpu_dc_sel) : cpu_dc_sel),

          .i_d_wb_dat(cpu_dc_dat),
          .i_d_wb_adr(cpu_daddr),
          .i_d_wb_cti(3'b111),
          .o_d_wb_ack(data_ack),
          .o_d_wb_err(data_err),

          .o_wb_code(o_wb_code),
          .o_wb_cyc (o_wb_cyc),
          .o_wb_stb (o_wb_stb),
          .o_wb_wen (o_wb_we),
          .o_wb_sel (o_wb_sel),
          .o_wb_dat (o_wb_dat),
          .o_wb_adr (o_wb_adr),
          .o_wb_cti (o_wb_cti),
          .i_wb_ack (i_wb_ack),
          .i_wb_err (i_wb_err)

      );
    end : l_merger_for_core_without_cache_mmu


    ///////////////////////////////////////////////////////////////////////////////
    // Put cache and MMU only if ONLY_CORE == 0
    ///////////////////////////////////////////////////////////////////////////////

    if (!ONLY_CORE) begin : l_generate_with_cache_mmu

      zap_dcache #(
          .LINE_REFILL (LINE_REFILL),
          .CACHE_SIZE  (DATA_CACHE_SIZE),
          .CACHE_LINE  (CODE_CACHE_LINE),
          .BE_32_ENABLE(BE_32_ENABLE)
      ) u_data_cache (
          .line_req(d_line_req),
          .line_addr(d_line_addr),
          .line_ready(d_line_ready),
          .line_reject(d_line_reject),
          .line_valid(d_line_valid),
          .line_data(cache_line_data),
          .line_wide(cache_line_wide),
          .line_last(cache_line_last),
          .line_error(cache_line_error),

          .i_clk            (i_clk),
          .i_stall          (1'd0),                      // For timing.
          .i_reset          (s_reset),
          .i_address        (cpu_daddr),
          .i_alignment_fault(cpu_alignment_fault),
          .i_alignment_far  (cpu_alignment_far),
          .i_address_nxt    (cpu_daddr_nxt),
          .i_address_check  (cpu_daddr_check),
          .i_wr_check       (cpu_dwe_check),
          .i_rd_check       (cpu_dre_check),
          .i_swp_tag        (cpu_dc_swp_tag),
          .o_swp_bus_lock   (cpu_dc_swp_lock),
          .i_rd             (!cpu_dc_we && cpu_dc_stb),
          .i_wr             (cpu_dc_we && cpu_dc_stb),
          .i_ben            (cpu_dc_sel),
          .i_dat            (cpu_dc_dat),
          .i_reg_idx        (dc_rreg_idx),
          .i_reg_idx_bin    (dc_rreg_idx_bin),
          .i_load_info      (dc_load_info),

          .o_dat             (dc_data),
          .o_ack             (data_ack),
          .o_request_ack     (data_request_ack),
          .o_err             (data_err),
          .o_lock            (dc_lock),
          .o_reg_dat         (dc_reg_data),
          .o_reg_idx         (dc_wreg_idx),
          .o_fsr             (dc_fsr),
          .o_far             (dc_far),
          .o_cache_inv_done  (dc_inv_done),
          .o_cache_clean_done(dc_clean_done),

          .i_mmu_en            (cpu_mmu_en),
          .i_cache_en          (cpu_dc_en),
          .i_cache_rr          (cpu_cache_rr),
          .o_write_buffer_empty(dc_write_buffer_empty),
          .i_cache_lock_write  (cpu_dc_lock_write),
          .i_cache_lock_base   (cpu_dc_lock_base),
          .o_cache_lock_done   (dc_lock_done),
          .i_cache_op_single   (cpu_cache_op_single),
          .i_cache_op_by_mva   (cpu_cache_op_by_mva),
          .i_cache_op_address  (cpu_cache_op_address),
          .i_cache_inv_req     (cpu_dc_inv),
          .i_cache_clean_req   (cpu_dc_clean),
          .i_cpsr              (cpu_mem_translate ? USR : cpu_data_cpsr),
          .i_sr                (cpu_sr),
          .i_baddr             (cpu_baddr),
          .i_dac_reg           (cpu_dac_reg),
          .i_tlb_inv           (cpu_dtlb_inv),
          .i_tlb_inv_mva       (cpu_tlb_inv_mva),
          .i_tlb_inv_address   (cpu_tlb_inv_address),
          .i_tlb_lock_write    (cpu_dtlb_lock_write),
          .i_tlb_lock_data     (cpu_tlb_lock_data),
          .o_tlb_lock_read     (dtlb_lock_read),

          .o_err2(dcache_err2),

          /* verilator lint_off PINCONNECTEMPTY */
          .o_wb_stb(),
          .o_wb_cyc(),
          .o_wb_wen(),
          .o_wb_sel(),
          .o_wb_dat(),
          .o_wb_adr(),
          .o_wb_cti(),
          /* verilator lint_on PINCONNECTEMPTY */

          .i_wb_dat(wb_dat),
          .i_wb_ack(d_wb_ack),
          .i_wb_err(d_wb_err),

          .o_wb_stb_nxt(d_wb_stb),
          .o_wb_cyc_nxt(d_wb_cyc),
          .o_wb_wen_nxt(d_wb_wen),
          .o_wb_sel_nxt(d_wb_sel),
          .o_wb_dat_nxt(d_wb_dat),
          .o_wb_adr_nxt(d_wb_adr),
          .o_wb_cti_nxt(d_wb_cti)
      );

      zap_cache #(
          .LINE_REFILL(LINE_REFILL),
          .CACHE_SIZE (CODE_CACHE_SIZE),
          .CACHE_LINE (DATA_CACHE_LINE)
      ) u_code_cache (
          .line_req(c_line_req),
          .line_addr(c_line_addr),
          .line_ready(c_line_ready),
          .line_reject(c_line_reject),
          .line_valid(c_line_valid),
          .line_data(cache_line_data),
          .line_wide(cache_line_wide),
          .line_last(cache_line_last),
          .line_error(cache_line_error),

          .i_clk  (i_clk),
          .i_stall(code_stall),
          .i_reset(s_reset),

          .i_address      ((cpu_iaddr & 32'hFFFF_FFFC)),       // Cut off lower 2 bits.
          .i_address_nxt  ((cpu_iaddr_nxt & 32'hFFFF_FFFC)),   // Cut off lower 2 bits.
          .i_address_check((cpu_iaddr_check & 32'hFFFF_FFFC)),

          .i_wr_check(1'd0),
          .i_rd_check(1'd1),

          .i_rd     (cpu_instr_stb),
          .i_discard(instr_discard),
          .i_wr     (1'd0),
          .i_ben    (4'b1111),
          .i_dat    (32'd0),
          .o_dat    (ic_data),
          .o_ack    (instr_ack),
          .o_err    (instr_err),

          /* verilator lint_off PINCONNECTEMPTY */
          .o_fsr(),
          .o_far(),
          /* verilator lint_on PINCONNECTEMPTY */

          .i_mmu_en             (cpu_mmu_en),
          .i_cache_en           (cpu_ic_en),
          .i_cache_rr           (cpu_cache_rr),
          .i_write_buffer_empty (dc_write_buffer_empty),
          .i_cache_lock_write   (cpu_ic_lock_write),
          .i_cache_lock_base    (cpu_ic_lock_base),
          .o_cache_lock_done    (ic_lock_done),
          .i_cache_op_single    (cpu_cache_op_single),
          .i_cache_op_by_mva    (cpu_cache_op_by_mva),
          .i_cache_op_address   (cpu_cache_op_address),
          .i_cache_prefetch     (cpu_icache_prefetch),
          .o_cache_prefetch_done(icache_prefetch_done),
          .i_cache_inv_req      (cpu_ic_inv),
          .i_cache_clean_req    (cpu_ic_clean),
          .o_cache_inv_done     (ic_inv_done),
          .o_cache_clean_done   (ic_clean_done),
          .i_cpsr               (cpu_cpsr[ZAP_CPSR_MODE:0]),
          .i_sr                 (cpu_sr),
          .i_baddr              (cpu_baddr),
          .i_dac_reg            (cpu_dac_reg),
          .i_tlb_inv            (cpu_itlb_inv),
          .i_tlb_inv_mva        (cpu_tlb_inv_mva),
          .i_tlb_inv_address    (cpu_tlb_inv_address),
          .i_tlb_lock_write     (cpu_itlb_lock_write),
          .i_tlb_lock_data      (cpu_tlb_lock_data),
          .o_tlb_lock_read      (itlb_lock_read),
          .o_err2               (icache_err2),

          /* verilator lint_off PINCONNECTEMPTY */
          .o_wb_stb(),
          .o_wb_cyc(),
          .o_wb_wen(),
          .o_wb_sel(),
          .o_wb_dat(),
          .o_wb_adr(),
          .o_wb_cti(),
          /* verilator lint_on PINCONNECTEMPTY */

          .i_wb_dat(wb_dat),
          .i_wb_ack(c_wb_ack),
          .i_wb_err(c_wb_err),

          .o_wb_stb_nxt(c_wb_stb),
          .o_wb_cyc_nxt(c_wb_cyc),
          .o_wb_wen_nxt(c_wb_wen),
          .o_wb_sel_nxt(c_wb_sel),
          .o_wb_dat_nxt(c_wb_dat),
          .o_wb_adr_nxt(c_wb_adr),
          .o_wb_cti_nxt(c_wb_cti)
      );

      assign o_wb_cyc = wb_cyc;
      assign o_wb_stb = wb_stb;
      assign o_wb_we  = wb_we;
      assign o_wb_sel = wb_sel;
      assign o_wb_dat = wb_idat;
      assign o_wb_adr = wb_adr;
      assign o_wb_cti = wb_cti;
      assign wb_dat   = i_wb_dat;
      assign wb_ack   = i_wb_ack;
      assign wb_err   = i_wb_err;

    end : l_generate_with_cache_mmu

  endgenerate
endmodule  // zap_top.v

///////////////////////////////////////////////////////////////////////////////
// EOF
///////////////////////////////////////////////////////////////////////////////

// Transaction-level refill ownership. Payload and response are registered;
// neither physical memory pins nor an unowned response drive CPU completion.
module arm920_line_owner #(
    parameter ENABLE = 0
) (
    input  wire        clk,
    input  wire        reset,
    input  wire        blocked,
    input  wire        c_req,
    input  wire [31:0] c_addr,
    output wire        c_ready,
    output reg         c_valid = 0,
    output reg         c_reject = 0,
    input  wire        d_req,
    input  wire [31:0] d_addr,
    output wire        d_ready,
    output reg         d_valid = 0,
    output reg         d_reject = 0,
    output reg  [63:0] out_data,
    output reg         out_wide,
    output reg         out_last,
    output reg         out_error,
    output wire        line_req,
    output reg  [31:0] line_addr,
    input  wire        line_ready,
    input  wire        line_reject,
    input  wire        line_valid,
    input  wire [63:0] line_data,
    input  wire        line_wide,
    input  wire        line_last,
    input  wire        line_error
);
  localparam IDLE = 0, OFFER = 1, ACTIVE = 2;
  reg [1:0] state = IDLE;
  reg owner = 0, prefer_data = 1;
  wire choose_data = d_req && (!c_req || prefer_data);
  assign line_req = ENABLE && state == OFFER && !blocked;
  assign c_ready  = line_req && !owner && line_ready;
  assign d_ready  = line_req && owner && line_ready;
  always @(posedge clk) begin
    c_valid  <= 0;
    d_valid  <= 0;
    c_reject <= 0;
    d_reject <= 0;
    if (reset || !ENABLE) begin
      state       <= IDLE;
      owner       <= 0;
      prefer_data <= 1;
      line_addr   <= 0;
      out_data    <= 0;
      out_wide    <= 0;
      out_last    <= 0;
      out_error   <= 0;
    end else
      case (state)
        IDLE:
        if (!blocked && (c_req || d_req)) begin
          owner       <= choose_data;
          prefer_data <= !choose_data;
          line_addr   <= choose_data ? d_addr : c_addr;
          state       <= OFFER;
        end
        OFFER:   if (line_req && line_ready) state <= ACTIVE;
        ACTIVE: begin
          if (line_reject) begin
            c_reject <= !owner;
            d_reject <= owner;
            state    <= IDLE;
          end else if (line_valid) begin
            c_valid   <= !owner;
            d_valid   <= owner;
            out_data  <= line_data;
            out_wide  <= line_wide;
            out_last  <= line_last;
            out_error <= line_error;
            if (line_last || line_error) state <= IDLE;
          end
        end
        default: state <= IDLE;
      endcase
  end
endmodule
