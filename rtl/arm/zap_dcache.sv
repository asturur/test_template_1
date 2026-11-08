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
// This is the top level cache module that contains the MMU and cache.
// This is the data cache.
//

module zap_dcache #(

parameter logic [31:0] CACHE_SIZE             = 32'd1024,
parameter logic [31:0] SPAGE_TLB_ENTRIES      = 32'd8,
parameter logic [31:0] LPAGE_TLB_ENTRIES      = 32'd8,
parameter logic [31:0] SECTION_TLB_ENTRIES    = 32'd8,
parameter logic [31:0] FPAGE_TLB_ENTRIES      = 32'd8,
parameter logic [31:0] CACHE_LINE             = 32'd8,
parameter logic        BE_32_ENABLE           = 1'd0,
parameter logic [31:0] CPSR_MODE              = 32'd4

)
(

// Clock and reset.
input   logic            i_clk,
input   logic            i_reset,

// RAM stall.
input   logic            i_stall,

// Signals to check (Provide 1 cycle before TLB+cache access).
input   logic   [31:0]   i_address_check,
input   logic            i_wr_check,
input   logic            i_rd_check,

// Address of TLB+Cache access
input   logic    [31:0]  i_address,

// Address of RAM read.
input   logic    [31:0]  i_address_nxt,

// Alignment faults are generated before address alignment/translation.
input logic i_alignment_fault,
input logic [31:0] i_alignment_far,

// Other control signals from/to processor.
input   logic [1:0]      i_swp_tag,
output  logic            o_swp_bus_lock,
input   logic            i_rd,
input   logic            i_wr,
input   logic [3:0]      i_ben,
input   logic [31:0]     i_dat,
output logic  [31:0]     o_dat,
output  logic            o_ack,
output  logic            o_request_ack, // Demand completion for CPU stall only.
output  logic            o_err,
output  logic [7:0]      o_fsr,
output  logic [31:0]     o_far,
output  logic            o_err2,
input   logic [63:0]     i_reg_idx,
input   logic [5:0]      i_reg_idx_bin,
input   logic [5:0]      i_load_info,
output  logic [63:0]     o_lock,
output  logic [31:0]     o_reg_dat,
output  logic [63:0]     o_reg_idx,

// MMU controls from/to processor.
input   logic            i_mmu_en,
input   logic            i_cache_en,
input   logic            i_cache_rr,
output  logic            o_write_buffer_empty,
input   logic            i_cache_lock_write,
input   logic [5:0]      i_cache_lock_base,
output  logic            o_cache_lock_done,
input   logic            i_cache_op_single,
input   logic            i_cache_op_by_mva,
input   logic [31:0]     i_cache_op_address,
input   logic            i_cache_inv_req,
input   logic            i_cache_clean_req,
output logic             o_cache_inv_done,
output  logic            o_cache_clean_done,

input   logic [CPSR_MODE:0]    i_cpsr,
input   logic [1:0]            i_sr,
input   logic [31:0]           i_baddr,
input   logic [31:0]           i_dac_reg,
input  logic                   i_tlb_inv,

// Wishbone. Signals from all 4 modules are ORed.
output logic              o_wb_stb, o_wb_stb_nxt,
output logic              o_wb_cyc, o_wb_cyc_nxt,
output logic              o_wb_wen, o_wb_wen_nxt,
output logic  [3:0]       o_wb_sel, o_wb_sel_nxt,
output logic  [31:0]      o_wb_dat, o_wb_dat_nxt,
output logic  [31:0]      o_wb_adr, o_wb_adr_nxt,
output logic  [2:0]       o_wb_cti, o_wb_cti_nxt,
input  logic [31:0]       i_wb_dat,
input  logic              i_wb_ack,
input  logic              i_wb_err

);

`include "zap_defines.svh"
`include "zap_localparams.svh"

localparam [2:0] SELECT_CCH = 3'b001;
localparam [2:0] SELECT_TAG = 3'b010;
localparam [2:0] SELECT_TLB = 3'b100;

logic [2:0]                      wb_stb;
logic [2:0]                      wb_cyc;
logic [2:0]                      wb_wen;
logic [3:0]                      wb_sel [2:0];
logic [31:0]                     wb_dat [2:0];
logic [31:0]                     wb_adr [2:0];
logic [2:0]                      wb_cti [2:0];
logic [31:0]                     tlb_phy_addr;
logic [7:0]                      tlb_fsr, tlb_external_fsr;
logic [31:0]                     tlb_far;
logic                            tlb_fault;
logic                            tlb_cacheable, tlb_bufferable;
logic                            tlb_busy;
logic [CACHE_LINE*8-1:0]         tr_cache_line;
logic [CACHE_LINE*8-1:0]         cf_cache_line;
logic [CACHE_LINE-1:0]           cf_cache_line_ben;
logic                            cf_cache_tag_wr_en;
logic [`ZAP_CACHE_TAG_WDT-1:0]   tr_cache_tag, cf_cache_tag;
logic                            tr_cache_tag_valid;
logic                            tr_cache_tag_dirty, cf_cache_tag_dirty;
logic                            cf_cache_clean_req, cf_cache_inv_req;
logic                            tr_cache_inv_done, tr_cache_clean_done;
logic [2:0]                      wb_ack;
logic [2:0]                      state_ff, state_nxt;
logic [31:0]                     cache_address;
logic                            hold;
logic                            idle;
logic  [2:0]                     wb_err;
logic                            unused;

// Selection 2 of Wishbone CTI[2x3] is always on all CPU supported modes.
assign wb_cti[2] = CTI_EOB;

// wb_err[1] is unused.
assign unused = |{wb_err[1]};

// Experimental: retain translation for an outstanding stalled CPU request.
logic pending_translation, pending_request, tlb_walk_pending, background_refill;
logic lookup_resync, pending_recovery;
logic [31:0] pending_data_assert, pending_dac_assert, pending_baddr_assert;
logic [3:0] pending_ben_assert;
logic [5:0] pending_load_assert, pending_index_bin_assert;
logic [63:0] pending_index_assert;
logic [1:0] pending_sr_assert;
logic pending_mmu_assert;
logic [$clog2(CACHE_SIZE/CACHE_LINE)-1:0] checked_cache_index;
logic [31:0] checked_va, checked_lookup, checked_dac, checked_baddr;
logic checked_rd, checked_wr, checked_mmu;
logic [ZAP_CPSR_MODE:0] checked_cpsr;
logic [1:0] checked_sr;
logic checked_request, checked_request_prev;
always_ff @(posedge i_clk) begin
    if (i_reset) checked_request_prev <= 1'b0;
    else checked_request_prev <= checked_request && pending_request && !o_ack;
end
assign checked_request = checked_va == i_address && checked_lookup == i_address && checked_rd == i_rd && checked_wr == i_wr &&
 checked_mmu == i_mmu_en && checked_cpsr == i_cpsr && checked_sr == i_sr &&
 checked_dac == i_dac_reg && checked_baddr == i_baddr &&
 checked_cache_index == i_address[`ZAP_VA__CACHE_INDEX];
logic [31:0] pending_va_assert;
logic pending_rd_assert, pending_wr_assert;
logic [ZAP_CPSR_MODE:0] pending_cpsr_assert;
logic [31:0] pending_pa, pending_far;
logic [7:0] pending_fsr, pending_external_fsr;
logic pending_fault, pending_cacheable, pending_bufferable;
always_ff @(posedge i_clk) begin
    if (i_reset || !(i_rd || i_wr) || o_ack) begin
        pending_translation <= 1'b0; pending_request <= 1'b0;
    end else if (pending_request || background_refill || lookup_resync || tlb_busy || tlb_walk_pending) begin
        if (!pending_request) begin
            pending_va_assert <= i_address;
            pending_rd_assert <= i_rd;
            pending_wr_assert <= i_wr;
            pending_cpsr_assert <= i_cpsr;
            pending_data_assert <= i_dat; pending_ben_assert <= i_ben;
            pending_load_assert <= i_load_info; pending_index_assert <= i_reg_idx;
            pending_index_bin_assert <= i_reg_idx_bin; pending_sr_assert <= i_sr;
            pending_dac_assert <= i_dac_reg; pending_baddr_assert <= i_baddr;
            pending_mmu_assert <= i_mmu_en;
        end else begin
            assert(i_address == pending_va_assert && i_rd == pending_rd_assert &&
                   i_wr == pending_wr_assert && i_cpsr == pending_cpsr_assert &&
                   (!i_wr || (i_dat == pending_data_assert && i_ben == pending_ben_assert)) &&
                   (!i_rd || (i_load_info == pending_load_assert && i_reg_idx == pending_index_assert &&
                              i_reg_idx_bin == pending_index_bin_assert && i_ben == pending_ben_assert)) &&
                   i_sr == pending_sr_assert && i_dac_reg == pending_dac_assert &&
                   i_baddr == pending_baddr_assert && i_mmu_en == pending_mmu_assert)
                else $fatal(1, "pending translation context changed without cancellation");
        end
        pending_request <= 1'b1;
        if (!pending_translation && checked_request && checked_request_prev && idle && !tlb_busy && !tlb_walk_pending) begin
            pending_translation <= 1'b1;
            pending_pa <= tlb_phy_addr; pending_far <= tlb_far; pending_fsr <= tlb_fsr; pending_external_fsr <= tlb_external_fsr;
            pending_fault <= tlb_fault; pending_cacheable <= tlb_cacheable; pending_bufferable <= tlb_bufferable;
        end
    end
end

always_ff @(posedge i_clk) begin
    if (i_reset) begin lookup_resync <= 1'b0; pending_recovery <= 1'b0; end
    else begin
        if (pending_request && o_ack) begin
            lookup_resync <= 1'b1;
            pending_recovery <= 1'b0;
        end else if (!pending_request && lookup_resync && (i_rd || i_wr) && !o_ack)
            pending_recovery <= 1'b1;
        else if (pending_request && !(i_rd || i_wr)) begin
            lookup_resync <= 1'b0; pending_recovery <= 1'b0;
        end
    end
end

`ifdef NGAGE_ASSOC_EXPERIMENT
// Experimental CPU integration: isolated behind a compile-time flag until
// directed CPU, maintenance and bus tests all pass.
assign checked_cache_index=checked_lookup[`ZAP_VA__CACHE_INDEX];
assign background_refill=1'b0;
assign o_lock='0;
assign o_reg_dat='0;
assign o_reg_idx='0;
assign {wb_stb[1],wb_cyc[1],wb_wen[1]}='0;
assign wb_sel[1]='0;assign wb_dat[1]='0;assign wb_adr[1]='0;assign wb_cti[1]='0;
arm920_zap_dcache_adapter experimental_cache(
 .clk(i_clk),.reset(i_reset),.address(i_address),.physical(pending_translation ? pending_pa : tlb_phy_addr),
 .swp_tag(i_swp_tag),.swp_bus_lock(o_swp_bus_lock),.din(i_dat),.far_in(pending_translation ? pending_far : tlb_far),.rd(i_rd),.wr(i_wr),.ben(i_ben),
 .alignment_fault(i_alignment_fault),.alignment_far(i_alignment_far),
 .fault(pending_translation ? pending_fault : (tlb_busy ? 1'b0 : tlb_fault)),.fsr_in(pending_translation ? pending_fsr : tlb_fsr),
 .external_fsr(pending_translation ? pending_external_fsr : tlb_external_fsr),
 .tlb_busy(pending_translation ? 1'b0 : tlb_busy),
 .translation_wait((pending_request && !pending_translation) || (lookup_resync && !pending_request) || (tlb_busy && !pending_translation)),
 .external_permit(1'b1),.write_buffer_empty(o_write_buffer_empty),
 .fast_enable(1'b0),.fast_next_address(32'b0),
 .cache_enable(i_cache_en),.cache_rr(i_cache_rr),.cache_lock_write(i_cache_lock_write),.cache_lock_base(i_cache_lock_base),.cache_lock_done(o_cache_lock_done),
 .cache_op_single(i_cache_op_single),.cache_op_by_mva(i_cache_op_by_mva),.cache_op_address(i_cache_op_address),.cacheable(pending_translation ? pending_cacheable : tlb_cacheable),
 .bufferable(pending_translation ? pending_bufferable : tlb_bufferable),
 .cache_invalidate(i_cache_inv_req),.cache_clean(i_cache_clean_req),
 .data(o_dat),.ack(o_ack),.request_ack(o_request_ack),.err(o_err),.err2(o_err2),.fsr(o_fsr),.far(o_far),.idle(idle),.hold(hold),
 .cache_inv_done(o_cache_inv_done),.cache_clean_done(o_cache_clean_done),
 .wb_cyc(wb_cyc[0]),.wb_stb(wb_stb[0]),.wb_wen(wb_wen[0]),.wb_sel(wb_sel[0]),
 .wb_adr(wb_adr[0]),.wb_data(wb_dat[0]),.wb_cti(wb_cti[0]),
 .wb_ack(wb_ack[0]),.wb_err(wb_err[0]),.wb_rdata(i_wb_dat));
`else
// Legacy cache retains its existing completion contract.
assign o_request_ack=o_ack;
assign o_swp_bus_lock=1'b0;
assign o_cache_lock_done=1'b1;
assign o_write_buffer_empty=1'b1;
// Basic cache FSM - serves as manager 0.
zap_dcache_fsm #(.CACHE_SIZE(CACHE_SIZE), .CACHE_LINE(CACHE_LINE), .BE_32_ENABLE(BE_32_ENABLE)) u_zap_cache_fsm (
        .i_clk                  (i_clk),
        .i_reset                (i_reset),
        .i_address              (i_address),
        .i_alignment_fault      (i_alignment_fault),
        .i_alignment_far        (i_alignment_far),
        .i_rd                   (i_rd),
        .i_wr                   (i_wr),
        .i_din                  (i_dat),
        .o_idle                 (idle),
        .i_ben                  (i_ben),
        .i_load_info            (i_load_info),
        .o_dat                  (o_dat),
        .o_ack                  (o_ack),
        .o_err                  (o_err),
        .o_fsr                  (o_fsr),
        .o_far                  (o_far),
        .i_cache_en             (i_cache_en),
        .i_cache_inv            (i_cache_inv_req),
        .i_cache_clean          (i_cache_clean_req),
        .o_cache_inv_done       (o_cache_inv_done),
        .o_cache_clean_done     (o_cache_clean_done),
        .i_cache_line           (tr_cache_line),
        .i_cache_tag_dirty      (tr_cache_tag_dirty),
        .i_cache_tag            (tr_cache_tag),
        .i_cache_tag_valid      (tr_cache_tag_valid),
        .o_cache_tag            (cf_cache_tag),
        .o_cache_tag_dirty      (cf_cache_tag_dirty),
        .o_cache_tag_wr_en      (cf_cache_tag_wr_en),
        .o_cache_line           (cf_cache_line),
        .o_cache_line_ben       (cf_cache_line_ben),
        .o_cache_clean_req      (cf_cache_clean_req),
        .i_cache_clean_done     (tr_cache_clean_done),
        .o_cache_inv_req        (cf_cache_inv_req),
        .i_cache_inv_done       (tr_cache_inv_done),
        .i_phy_addr             (pending_translation ? pending_pa : tlb_phy_addr),
        .i_fsr                  (pending_translation ? pending_fsr : tlb_fsr),
        .i_far                  (pending_translation ? pending_far : tlb_far),
        .i_fault                (pending_translation ? pending_fault : tlb_fault),
        .i_cacheable            (pending_translation ? pending_cacheable : tlb_cacheable),
        .i_bufferable           (pending_translation ? pending_bufferable : tlb_bufferable),
        .i_busy                 (pending_translation ? 1'b0 : tlb_busy),
        .i_translation_wait     ((pending_request && !pending_translation) || (lookup_resync && !pending_request)),
        .o_background_refill    (background_refill),
        .o_err2                 (o_err2),
        .o_address              (cache_address),
        .o_wb_cyc_nxt           (wb_cyc[0]),
        .o_hold                 (hold),
        .i_reg_idx              (i_reg_idx),
        .i_reg_idx_bin          (i_reg_idx_bin),
        .o_lock                 (o_lock),
        .o_reg_dat              (o_reg_dat),
        .o_reg_idx              (o_reg_idx),

        /* verilator lint_off PINCONNECTEMPTY */
        .o_wb_cyc_ff            (),
        .o_wb_stb_ff            (),
        .o_wb_adr_ff            (),
        .o_wb_dat_ff            (),
        .o_wb_sel_ff            (),
        .o_wb_wen_ff            (),
        .o_wb_cti_ff            (),
        /* verilator lint_on PINCONNECTEMPTY */

        .o_wb_stb_nxt           (wb_stb[0]),
        .o_wb_adr_nxt           (wb_adr[0]),
        .o_wb_dat_nxt           (wb_dat[0]),
        .o_wb_sel_nxt           (wb_sel[0]),
        .o_wb_wen_nxt           (wb_wen[0]),
        .o_wb_cti_nxt           (wb_cti[0]),
        .i_wb_dat               (i_wb_dat),
        .i_wb_ack               (wb_ack[0]),
        .i_wb_err               (wb_err[0])
);

// Cache Tag RAM - As a manager - this performs cache clean - manager 1.
zap_cache_tag_ram #(.CACHE_SIZE(CACHE_SIZE), .CACHE_LINE(CACHE_LINE)) u_zap_cache_tag_ram     (
        .i_clk                  (i_clk),
        .i_reset                (i_reset),
        .i_address_nxt          (pending_request ? i_address : i_address_nxt),
        .o_checked_index        (checked_cache_index),
        .i_address              (cache_address),
        .i_hold                 (hold || i_stall),
        .i_cache_en             (i_cache_en),
        .i_cache_line           (cf_cache_line),
        .o_cache_line           (tr_cache_line),
        .i_cache_line_ben       (cf_cache_line_ben),
        .i_cache_tag_wr_en      (cf_cache_tag_wr_en),
        .i_cache_tag            (cf_cache_tag),
        .i_cache_tag_dirty      (cf_cache_tag_dirty),
        .o_cache_tag            (tr_cache_tag),
        .o_cache_tag_valid      (tr_cache_tag_valid),
        .o_cache_tag_dirty      (tr_cache_tag_dirty),
        .i_cache_inv_req        (cf_cache_inv_req),
        .o_cache_inv_done       (tr_cache_inv_done),
        .i_cache_clean_req      (cf_cache_clean_req),
        .o_cache_clean_done     (tr_cache_clean_done),

        /* verilator lint_off PINCONNECTEMPTY */
        .o_wb_cyc_ff            (),
        .o_wb_stb_ff            (),
        .o_wb_adr_ff            (),
        .o_wb_dat_ff            (),
        .o_wb_sel_ff            (),
        .o_wb_wen_ff            (),
        .o_wb_cti_ff            (),
        /* verilator lint_on PINCONNECTEMPTY */

        .o_wb_cyc_nxt           (wb_cyc[1]),
        .o_wb_stb_nxt           (wb_stb[1]),
        .o_wb_adr_nxt           (wb_adr[1]),
        .o_wb_dat_nxt           (wb_dat[1]),
        .o_wb_sel_nxt           (wb_sel[1]),
        .o_wb_wen_nxt           (wb_wen[1]),
        .o_wb_cti_nxt           (wb_cti[1]),
        .i_wb_dat               (i_wb_dat),
        .i_wb_ack               (wb_ack[1])
);

`endif

`ifdef NGAGE_ASSOC_EXPERIMENT
logic tlb_raw_stb,tlb_raw_cyc;
arm920_tlb_bus_gate tlb_bus_order(.clk(i_clk),.reset(i_reset),.write_buffer_empty(o_write_buffer_empty),
 .in_cyc(tlb_raw_cyc),.in_stb(tlb_raw_stb),.out_cyc(wb_cyc[2]),.out_stb(wb_stb[2]),
 .ack(wb_ack[2]),.err(wb_err[2]));
`endif

// ZAP TLB control module. Includes TLB RAM inside - Manager 2.
zap_tlb #(
        .LPAGE_TLB_ENTRIES      (LPAGE_TLB_ENTRIES),
        .SPAGE_TLB_ENTRIES      (SPAGE_TLB_ENTRIES),
        .SECTION_TLB_ENTRIES    (SECTION_TLB_ENTRIES),
        .FPAGE_TLB_ENTRIES      (FPAGE_TLB_ENTRIES)
)
u_zap_tlb (
        .i_clk          (i_clk),
        .i_reset        (i_reset),
        .i_address      (i_address),
        .i_address_nxt  (pending_request ? i_address : i_address_nxt),
        .i_address_check(pending_request ? i_address : i_address_check),
        .i_idle         (idle),
        .i_wr_check     (pending_request ? i_wr : i_wr_check),
        .i_rd_check     (pending_request ? i_rd : i_rd_check),
        .i_hold         (hold || i_stall),
        .i_cpsr         (i_cpsr),
        .i_sr           (i_sr),
        .i_dac_reg      (i_dac_reg),
        .i_baddr        (i_baddr),
        .i_mmu_en       (i_mmu_en),
        .i_inv          (i_tlb_inv),
        .o_phy_addr     (tlb_phy_addr),
        .o_fsr          (tlb_fsr),
        .o_external_fsr (tlb_external_fsr),
        .o_far          (tlb_far),
        .o_fault        (tlb_fault),
        .o_cacheable    (tlb_cacheable),
        .o_bufferable   (tlb_bufferable),
        .o_busy         (tlb_busy),
        .o_walk_pending (tlb_walk_pending),
        .o_checked_va (checked_va), .o_checked_lookup (checked_lookup), .o_checked_rd (checked_rd), .o_checked_wr (checked_wr),
        .o_checked_mmu (checked_mmu), .o_checked_cpsr (checked_cpsr), .o_checked_sr (checked_sr),
        .o_checked_dac (checked_dac), .o_checked_baddr (checked_baddr),
        `ifdef NGAGE_ASSOC_EXPERIMENT
        .o_wb_stb_nxt   (tlb_raw_stb),
        .o_wb_cyc_nxt   (tlb_raw_cyc),
`else
        .o_wb_stb_nxt   (wb_stb[2]),
        .o_wb_cyc_nxt   (wb_cyc[2]),
`endif
        .o_wb_adr_nxt   (wb_adr[2]),
        .o_wb_wen_nxt   (wb_wen[2]),
        .o_wb_sel_nxt   (wb_sel[2]),
        .o_wb_dat_nxt   (wb_dat[2]),
        .i_wb_dat       (i_wb_dat),
        .i_wb_ack       (wb_ack[2]),
        .i_wb_err       (wb_err[2])
);

// Sequential Block
always_ff @ ( posedge i_clk )
begin
        if ( i_reset )
        begin
                state_ff <= SELECT_CCH;
                o_wb_stb <= 1'd0;
                o_wb_cyc <= 1'd0;
                o_wb_adr <= 'x;
                o_wb_cti <= CTI_EOB;
                o_wb_sel <= 'x;
                o_wb_dat <= 'x;
                o_wb_wen <= 'x;
        end
        else
        begin
                state_ff <= state_nxt;
                o_wb_stb <= o_wb_stb_nxt;
                o_wb_cyc <= o_wb_cyc_nxt;
                o_wb_adr <= o_wb_adr_nxt;
                o_wb_cti <= o_wb_cti_nxt;
                o_wb_sel <= o_wb_sel_nxt;
                o_wb_dat <= o_wb_dat_nxt;
                o_wb_wen <= o_wb_wen_nxt;
        end
end

// Next state logic.
always_comb
begin
        // Change state only if strobe is inactive or strobe has just completed.
        if ( !o_wb_stb || (o_wb_stb && (i_wb_ack || i_wb_err)) )
        begin
                casez({wb_cyc[2],wb_cyc[1],wb_cyc[0]})
                3'b1?? : state_nxt = SELECT_TLB; // TLB.
                3'b01? : state_nxt = SELECT_TAG; // Tag.
                3'b001 : state_nxt = SELECT_CCH; // Cache.
                default: state_nxt = state_ff;
                endcase
        end
        else
        begin
            state_nxt = state_ff;
        end
end

// Route ACKs to respective managers.
always_comb
begin
        case(state_ff)
        SELECT_CCH      : {wb_err, wb_ack} = {2'd0, i_wb_err, 2'd0, i_wb_ack};
        SELECT_TAG      : {wb_err, wb_ack} = {1'd0, i_wb_err, 2'd0, i_wb_ack, 1'd0};
        SELECT_TLB      : {wb_err, wb_ack} = {i_wb_err, 2'd0, i_wb_ack, 2'd0};
        default         : {wb_err, wb_ack } = {6{1'dx}};
        endcase
end

// Combo signals for external MUXing.
always_comb
begin
        case(state_nxt)
        SELECT_CCH:
        begin
                o_wb_stb_nxt = wb_stb[0];
                o_wb_cyc_nxt = wb_cyc[0];
                o_wb_adr_nxt = wb_adr[0];
                o_wb_dat_nxt = wb_dat[0];
                o_wb_cti_nxt = wb_cti[0];
                o_wb_sel_nxt = wb_sel[0];
                o_wb_wen_nxt = wb_wen[0];
        end
        SELECT_TAG:
        begin
                o_wb_stb_nxt = wb_stb[1];
                o_wb_cyc_nxt = wb_cyc[1];
                o_wb_adr_nxt = wb_adr[1];
                o_wb_dat_nxt = wb_dat[1];
                o_wb_cti_nxt = wb_cti[1];
                o_wb_sel_nxt = wb_sel[1];
                o_wb_wen_nxt = wb_wen[1];
        end
        SELECT_TLB:
        begin
                o_wb_stb_nxt = wb_stb[2];
                o_wb_cyc_nxt = wb_cyc[2];
                o_wb_adr_nxt = wb_adr[2];
                o_wb_dat_nxt = wb_dat[2];
                o_wb_cti_nxt = wb_cti[2];
                o_wb_sel_nxt = wb_sel[2];
                o_wb_wen_nxt = wb_wen[2];
        end
        default:
        begin
                o_wb_stb_nxt = 'x;
                o_wb_cyc_nxt = 'x;
                o_wb_adr_nxt = 'x;
                o_wb_dat_nxt = 'x;
                o_wb_cti_nxt = 'x;
                o_wb_sel_nxt = 'x;
                o_wb_wen_nxt = 'x;
        end
        endcase
end

endmodule : zap_dcache

// ----------------------------------------------------------------------------
// END OF FILE
// ----------------------------------------------------------------------------
