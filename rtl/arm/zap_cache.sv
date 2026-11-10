//
// (C)2016-2024 Revanth Kamaraj (krevanth) <revanth91kamaraj@gmail.com>
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
// This is the instruction cache. Not that i_wr = 0.
//

module zap_cache #( // INSTRUCTION CACHE

parameter LINE_REFILL = 0,
parameter [31:0] CACHE_SIZE             = 32'd16384,
parameter [31:0] CACHE_LINE             = 32'd32,
parameter [31:0] CPSR_MODE              = 32'd4

)
(


    output wire line_req,
    output wire [31:0] line_addr,
    input wire line_ready,
    input wire line_reject,
    input wire line_valid,
    input wire [63:0] line_data,
    input wire line_wide,
    input wire line_last,
    input wire line_error,

// Clock and reset.
input   logic            i_clk,
input   logic            i_reset,

// RAM stall.
input   logic            i_stall,
input   wire             i_discard,

// Signals to check (Provide 1 cycle before TLB+cache access).
input   logic   [31:0]   i_address_check,
input   logic            i_wr_check,
input   logic            i_rd_check,

// Address of TLB+Cache access
input   logic    [31:0]  i_address,

// Address of RAM read.
input   logic    [31:0]  i_address_nxt,

// Other control signals from/to processor.
input   logic            i_rd,
input   logic            i_wr,
input   logic [3:0]      i_ben,
input   logic [31:0]     i_dat,
output logic  [31:0]     o_dat,
output  logic            o_ack,
output  logic            o_err,
output  logic [7:0]      o_fsr,
output  logic [31:0]     o_far,
output  logic            o_err2,

// MMU controls from/to processor.
input   logic            i_mmu_en,
input   logic            i_cache_en,
input   logic            i_cache_rr,
input   logic            i_write_buffer_empty,
input   logic            i_cache_lock_write,
input   logic [5:0]      i_cache_lock_base,
output  logic            o_cache_lock_done,
input   logic            i_cache_op_single,
input   logic            i_cache_op_by_mva,
input   logic [31:0]     i_cache_op_address,
input   logic            i_cache_prefetch,
output  logic            o_cache_prefetch_done,
input   logic            i_cache_inv_req,
input   logic            i_cache_clean_req,
output logic             o_cache_inv_done,
output  logic            o_cache_clean_done,

input   logic [CPSR_MODE:0]    i_cpsr,
input   logic [1:0]            i_sr,
input   logic [31:0]           i_baddr,
input   logic [31:0]           i_dac_reg,
input  logic                   i_tlb_inv,
input wire i_tlb_inv_mva,
input wire [31:0] i_tlb_inv_address,
input wire i_tlb_lock_write,
input wire [31:0] i_tlb_lock_data,
output wire [31:0] o_tlb_lock_read,

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
logic                            tlb_cacheable;
logic                            tlb_busy;
wire                             tlb_lookup_wait;
logic [2:0]                      wb_ack;
logic [2:0]                      state_ff, state_nxt;
logic [31:0]                     cache_address;
logic                            hold;
logic                            idle;
logic [2:0]                      wb_err;
logic                            unused;

// Selection 2 of Wishbone CTI[2x3] is always on all CPU supported modes.
assign wb_cti[2] = CTI_EOB;

// wb_err[1] is unused.
assign unused = |{wb_err[1]};

// Prefetch borrows the instruction TLB after any current fetch completes,
// then restores the normal TLB lookup pipeline before releasing CP15.
typedef enum logic [2:0] {P_IDLE,P_TRANSLATE,P_ISSUE,P_RESTORE,P_DONE,P_RESYNC} prefetch_state_t;
prefetch_state_t prefetch_state;
logic [2:0] prefetch_restore_count;
logic [31:0] prefetch_checked_va,prefetch_checked_lookup;
logic prefetch_checked_rd,prefetch_checked_wr,prefetch_checked_mmu;
logic [CPSR_MODE:0] prefetch_checked_cpsr;
logic [1:0] prefetch_checked_sr;
logic [31:0] prefetch_checked_dac,prefetch_checked_baddr;
logic adapter_ack,adapter_err,adapter_err2;
wire prefetch_busy=prefetch_state!=P_IDLE;
wire prefetch_address_selected=prefetch_state==P_TRANSLATE || prefetch_state==P_ISSUE;
wire [31:0] tlb_address_input=prefetch_address_selected ? i_cache_op_address : i_address;
assign o_cache_prefetch_done=prefetch_state==P_DONE;
assign o_ack=(prefetch_busy || i_cache_prefetch) ? 1'b0 : adapter_ack;
assign o_err=(prefetch_busy || i_cache_prefetch) ? 1'b0 : adapter_err;
assign o_err2=(prefetch_busy || i_cache_prefetch) ? 1'b0 : adapter_err2;
always_ff @(posedge i_clk) begin
 if(i_reset)begin prefetch_state<=P_IDLE;prefetch_restore_count<=0;end
 else case(prefetch_state)
  P_IDLE: if(i_cache_prefetch && idle)prefetch_state<=P_TRANSLATE;
  P_TRANSLATE: if(prefetch_checked_va==i_cache_op_address && prefetch_checked_lookup==i_cache_op_address &&
                  prefetch_checked_rd && !tlb_busy) begin
    if(!i_mmu_en || !i_cache_en || !tlb_cacheable || tlb_fault)begin prefetch_restore_count<=0;prefetch_state<=P_RESTORE;end
    else prefetch_state<=P_ISSUE;
  end
  P_ISSUE: if(adapter_ack && !adapter_err2)begin prefetch_restore_count<=0;prefetch_state<=P_RESTORE;end
  P_RESTORE: if(!tlb_busy && prefetch_checked_va==i_address && prefetch_checked_lookup==i_address) begin
    if(prefetch_restore_count==2)prefetch_state<=P_DONE;else prefetch_restore_count<=prefetch_restore_count+1'b1;
   end else prefetch_restore_count<=0;
  P_DONE: if(!i_cache_prefetch)begin prefetch_restore_count<=0;prefetch_state<=P_RESYNC;end
  P_RESYNC: if(!tlb_busy && prefetch_checked_va==i_address && prefetch_checked_lookup==i_address && prefetch_checked_rd) begin
    if(prefetch_restore_count==2)prefetch_state<=P_IDLE;else prefetch_restore_count<=prefetch_restore_count+1'b1;
   end else prefetch_restore_count<=0;
  default:prefetch_state<=P_IDLE;
 endcase
end
assign {wb_stb[1],wb_cyc[1],wb_wen[1]}='0;
assign wb_sel[1]='0;assign wb_dat[1]='0;assign wb_adr[1]='0;assign wb_cti[1]='0;
// L0 in cache_access registers the resident-only lookahead PC. It has no
// dependency on this cycle's ACK. Four ARM words cover owner/read/compare/line;
// Thumb requests advance more slowly. Actual completion still checks live TLB
// permission and the exact requested address. Context changes cancel all tokens.
reg [CPSR_MODE+68:0] fast_context_q;
wire [CPSR_MODE+68:0] fast_context = {i_mmu_en, i_cache_en, i_cpsr, i_sr, i_baddr, i_dac_reg};
wire fast_context_change = fast_context != fast_context_q;
always @(posedge i_clk) begin
        if (i_reset) fast_context_q <= 0;
        else fast_context_q <= fast_context;
end
arm920_cache_adapter #(.LINE_REFILL(LINE_REFILL)) cache_adapter(
.line_req(line_req),.line_addr(line_addr),.line_ready(line_ready),
    .line_reject(line_reject),.line_valid(line_valid),.line_data(line_data),
    .line_wide(line_wide),.line_last(line_last),.line_error(line_error),

 .clk(i_clk),.reset(i_reset),.discard_refill(i_discard && !prefetch_busy),.address(prefetch_address_selected ? i_cache_op_address : i_address),.physical(tlb_phy_addr),
 .swp_tag(2'b0),.swp_bus_lock(),.din(i_dat),.far_in(tlb_far),.rd(prefetch_busy ? prefetch_state==P_ISSUE : (i_rd && !i_cache_prefetch)),.wr(i_wr),.ben(i_ben),
 .alignment_fault(1'b0),.alignment_far(32'b0),.fault(tlb_fault),.fsr_in(tlb_fsr),
 .external_fsr(tlb_external_fsr),.tlb_busy(tlb_busy),.translation_wait(tlb_lookup_wait),
 .external_permit(i_write_buffer_empty),.write_buffer_empty(),
 .fast_enable(!prefetch_busy && !i_cache_prefetch && !fast_context_change && !i_tlb_inv),
 .fast_next_address(i_address + 32'd16),
 .cache_enable(i_cache_en),.cache_rr(i_cache_rr),.cache_lock_write(i_cache_lock_write),.cache_lock_base(i_cache_lock_base),.cache_lock_done(o_cache_lock_done),
 .cache_op_single(i_cache_op_single),.cache_op_by_mva(i_cache_op_by_mva),.cache_op_address(i_cache_op_address),
 .cacheable(tlb_cacheable),.bufferable(1'b1),
 .cache_invalidate(i_cache_inv_req),.cache_clean(i_cache_clean_req),
 .data(o_dat),.ack(adapter_ack),.request_ack(),.err(adapter_err),.err2(adapter_err2),.fsr(o_fsr),.far(o_far),.idle(idle),.hold(hold),
 .cache_inv_done(o_cache_inv_done),.cache_clean_done(o_cache_clean_done),
 .wb_cyc(wb_cyc[0]),.wb_stb(wb_stb[0]),.wb_wen(wb_wen[0]),.wb_sel(wb_sel[0]),
 .wb_adr(wb_adr[0]),.wb_data(wb_dat[0]),.wb_cti(wb_cti[0]),
 .wb_ack(wb_ack[0]),.wb_err(wb_err[0]),.wb_rdata(i_wb_dat));

logic tlb_raw_stb,tlb_raw_cyc;
arm920_tlb_bus_gate tlb_bus_order(.clk(i_clk),.reset(i_reset),.write_buffer_empty(i_write_buffer_empty),
 .in_cyc(tlb_raw_cyc),.in_stb(tlb_raw_stb),.out_cyc(wb_cyc[2]),.out_stb(wb_stb[2]),
 .ack(wb_ack[2]),.err(wb_err[2]));

// ARM920T translation controller and table-walk bus.
arm920_tlb #(.CPSR_MODE(CPSR_MODE))
u_zap_tlb (
        .i_clk          (i_clk),
        .i_reset        (i_reset),
        .i_address      (tlb_address_input),
        .i_idle         (idle),
        .i_request_rd   (i_rd || i_cache_prefetch),
        .i_request_wr   (i_wr),
        .o_checked_va(prefetch_checked_va),.o_checked_lookup(prefetch_checked_lookup),
        .o_checked_rd(prefetch_checked_rd),.o_checked_wr(prefetch_checked_wr),.o_checked_mmu(prefetch_checked_mmu),
        .o_checked_cpsr(prefetch_checked_cpsr),.o_checked_sr(prefetch_checked_sr),
        .o_checked_dac(prefetch_checked_dac),.o_checked_baddr(prefetch_checked_baddr),
        .i_cpsr         (i_cpsr),
        .i_sr           (i_sr),
        .i_dac_reg      (i_dac_reg),
        .i_baddr        (i_baddr),
        .i_mmu_en       (i_mmu_en),
        .i_inv          (i_tlb_inv),
        .i_inv_mva      (i_tlb_inv_mva),
        .i_inv_address  (i_tlb_inv_address),
        .i_lock_write   (i_tlb_lock_write),
        .i_lock_data    (i_tlb_lock_data),
        .o_lock_read    (o_tlb_lock_read),
        .i_complete     (o_ack || (i_cache_prefetch && tlb_fault)),
        .o_phy_addr     (tlb_phy_addr),
        .o_fsr          (tlb_fsr),
        .o_external_fsr (tlb_external_fsr),
        .o_far          (tlb_far),
        .o_fault        (tlb_fault),
        .o_cacheable    (tlb_cacheable),
        .o_busy         (tlb_busy),
        .o_lookup_wait  (tlb_lookup_wait),
        .o_wb_stb_nxt   (tlb_raw_stb),
        .o_wb_cyc_nxt   (tlb_raw_cyc),
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
        //
        // Change state only if strobe is inactive or strobe has just completed.
        // ERR follows ACK. There's an assertion to check that.
        //
        if ( !o_wb_stb || (o_wb_stb && i_wb_ack) )
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

// Route ERRs and ACKs to respective managers.
always_comb
begin
        case(state_ff)
        SELECT_CCH: {wb_err, wb_ack} = {2'd0, i_wb_err, 2'd0, i_wb_ack};
        SELECT_TAG: {wb_err, wb_ack} = {1'd0, i_wb_err, 2'd0, i_wb_ack, 1'd0};
        SELECT_TLB: {wb_err, wb_ack} = {i_wb_err, 2'd0, i_wb_ack, 2'd0};
        default:    {wb_err, wb_ack} = {6{1'dx}};
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
        default: // Assigning X will cause synthesis to better optimize.
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

endmodule : zap_cache

// ----------------------------------------------------------------------------
// END OF FILE
// ----------------------------------------------------------------------------
