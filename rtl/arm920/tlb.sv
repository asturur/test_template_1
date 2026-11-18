// SPDX-License-Identifier: GPL-3.0-or-later
// ARM920T translation/permission controller. No direct-mapped page-size banks.
// Main-table lookup and bus walks are serialized; a checked 1KiB permission
// pair serves adjacent reads/writes without another CAM/BRAM lookup. The minimum
// ARM920 permission granule is 1KiB (small-page AP quarters and tiny pages).
module arm920_tlb #(
    parameter CPSR_MODE = 4,
    parameter THIRD_MAPPING = 0
) (
    input wire i_clk,
    input wire i_reset,
    input wire [31:0] i_address,
    input wire i_request_rd,
    input wire i_request_wr,
    input wire [CPSR_MODE:0] i_cpsr,
    input wire [1:0] i_sr,
    input wire [31:0] i_dac_reg,
    input wire [31:0] i_baddr,
    input wire i_mmu_en,
    input wire i_inv,
    input wire i_inv_mva,
    input wire [31:0] i_inv_address,
    input wire i_lock_write,
    input wire [31:0] i_lock_data,
    output wire [31:0] o_lock_read,
    output wire o_mutation_busy,
    input wire i_complete,
    input wire i_idle,
    output wire [31:0] o_phy_addr,
    output wire [7:0] o_fsr,
    output wire [7:0] o_external_fsr,
    output wire [31:0] o_far,
    output wire o_fault,
    output wire o_bufferable,
    output wire o_cacheable,
    output wire o_busy,
    output wire o_walk_pending,
    output wire o_lookup_wait,
    output wire o_checked_owner,
    output wire [31:0] o_checked_va,
    output wire [31:0] o_checked_lookup,
    output wire o_checked_rd,
    output wire o_checked_wr,
    output wire o_checked_mmu,
    output wire [CPSR_MODE:0] o_checked_cpsr,
    output wire [1:0] o_checked_sr,
    output wire [31:0] o_checked_dac,
    output wire [31:0] o_checked_baddr,
    output wire o_wb_stb_nxt,
    output wire o_wb_cyc_nxt,
    output wire [31:0] o_wb_adr_nxt,
    output wire o_wb_wen_nxt,
    output wire [3:0] o_wb_sel_nxt,
    input wire [31:0] i_wb_dat,
    output wire [31:0] o_wb_dat_nxt,
    input wire i_wb_ack,
    input wire i_wb_err
);
  localparam IDLE=0, LOOKUP=1, L1_WAIT=2, L1_DECODE=3,
               L2_WAIT=4, L2_DECODE=5, INSTALL=6, INSTALL_WAIT=7;
  reg [2:0] state;
  reg token_valid, token_rd, token_wr;
  // A reusable mapping has separately checked direction permissions. Invalid
  // descriptors and table-bus aborts instead publish an exact request result.
  reg token_mapping, token_read_allowed, token_write_allowed;
  reg [31:0] token_va, token_dac, token_baddr;
  reg [21:0] token_pa;
  reg [CPSR_MODE:0] token_cpsr;
  reg [1:0] token_sr, token_cb;
  reg [7:0] token_fsr, token_external_fsr;
  // One secondary mapping shares the primary context. It never holds a walk
  // fault: those remain exact, consumable results in the primary record.
  // FIFO publication needs no access-time payload swap or recency register.
  reg second_valid;
  reg [21:0] second_va, second_pa;
  reg [1:0] second_cb;
  reg second_read_allowed, second_write_allowed;
  reg [7:0] second_fsr, second_external_fsr;
  // Older FIFO record, enabled only in the data controller. Like the second
  // record it can hold a checked mapping, never an exact walk fault.
  reg third_valid;
  reg [21:0] third_va, third_pa;
  reg [1:0] third_cb;
  reg third_read_allowed, third_write_allowed;
  reg [7:0] third_fsr, third_external_fsr;
  reg [31:0] request_va, request_dac, request_baddr;
  reg [CPSR_MODE:0] request_cpsr;
  reg [1:0] request_sr;
  reg request_rd, request_wr, cancelled;
  reg [31:0] descriptor, bus_address;
  reg [3:0] domain;
  reg fine_table, bus_active;
  reg [37:0] fill_payload;
  wire mutation = i_inv || i_lock_write;
  wire request = i_request_rd || i_request_wr;
  wire shared_context = token_cpsr == i_cpsr && token_sr == i_sr &&
                        token_dac == i_dac_reg && token_baddr == i_baddr;
  wire token_context = token_valid && token_va[31:10] == i_address[31:10] && shared_context;
  wire primary_match = token_context && (token_mapping ||
               (token_va[9:0] == i_address[9:0] &&
                token_rd == i_request_rd && token_wr == i_request_wr));
  wire second_match = second_valid && second_va == i_address[31:10] && shared_context;
  wire third_match = THIRD_MAPPING && third_valid &&
                     third_va == i_address[31:10] && shared_context;
  wire use_third = !primary_match && !second_match && third_match;
  wire use_second = !primary_match && second_match;
  wire owner = request && (primary_match || second_match || third_match);
  wire read_allowed = use_third ? third_read_allowed : use_second ? second_read_allowed : token_read_allowed;
  wire write_allowed = use_third ? third_write_allowed : use_second ? second_write_allowed : token_write_allowed;
  wire permission_denied = (i_request_rd && !read_allowed) ||
                           (i_request_wr && !write_allowed);
  wire [7:0] selected_fsr = use_third ? third_fsr : use_second ? second_fsr : token_fsr;
  wire bank_busy;
  assign o_mutation_busy = bank_busy || mutation;
  wire bank_lookup = state == IDLE && i_mmu_en && i_idle && request && !owner && !mutation && !bank_busy;
  wire bank_valid, bank_hit;
  wire [37:0] bank_payload;
  wire obsolete = cancelled || mutation || !i_mmu_en || request_baddr != i_baddr;
  wire bank_fill = state == INSTALL && !obsolete;

  arm920_tlb_bank bank (
      .clk(i_clk),
      .busy(bank_busy),
      .cancel_fill(state==INSTALL_WAIT && (!i_mmu_en || request_baddr!=i_baddr)),
      .reset(i_reset),
      .lookup(bank_lookup),
      .lookup_mva(i_address),
      .result_valid(bank_valid),
      .result_hit(bank_hit),
      .result_payload(bank_payload),
      .fill(bank_fill),
      .fill_mva(request_va),
      .fill_payload(fill_payload),
      .invalidate(i_inv),
      .invalidate_mva(i_inv_mva),
      .invalidate_address(i_inv_address),
      .lock_write(i_lock_write),
      .lock_data(i_lock_data),
      .lock_read(o_lock_read)
  );

  // Payload: kind[37:36], CB[35:34], domain[33:30], AP[29:22], PA[21:0].
  function [7:0] permission_fault;
    input [37:0] entry;
    input [31:0] va, dac;
    input [CPSR_MODE:0] mode_bits;
    input [1:0] sr;
    input rd, wr;
    reg [1:0] ap, access;
    reg allowed, user_mode;
    begin
      case (entry[37:36])
        1: ap = (entry[29:22] >> (va[15:14] * 2)) & 3;
        2: ap = (entry[29:22] >> (va[11:10] * 2)) & 3;
        default: ap = entry[23:22];
      endcase
      access = (dac >> (entry[33:30] * 2)) & 3;
      user_mode = mode_bits == 5'h10;
      allowed = 0;
      case (ap)
        0:
        case (sr)
          1: allowed = rd && !wr;
          2: allowed = !user_mode && rd && !wr;
          default: allowed = 0;
        endcase
        1: allowed = !user_mode;
        2: allowed = !user_mode || (rd && !wr);
        3: allowed = 1;
      endcase
      if (access == 3 || (access == 1 && allowed)) permission_fault = 0;
      else if (access == 1) permission_fault = {entry[33:30], entry[37:36] == 0 ? 4'hd : 4'hf};
      else permission_fault = {entry[33:30], entry[37:36] == 0 ? 4'h9 : 4'hb};
    end
  endfunction

  function [21:0] physical_subpage;
    input [37:0] entry;
    input [31:0] va;
    begin
      case (entry[37:36])
        0: physical_subpage = {entry[21:10], va[19:10]};
        1: physical_subpage = {entry[21:6], va[15:10]};
        2: physical_subpage = {entry[21:2], va[11:10]};
        default: physical_subpage = entry[21:0];
      endcase
    end
  endfunction

  // Shared context is published only after the registered descriptor lookup or
  // walk completes. Keep this record independent of the consumer's completion
  // owner so future address-only probes need not allocate architectural work.
  task publish_context;
    input [37:0] entry;
    begin
      // Never let a local mapping outlive a main-table replacement or cross a
      // context boundary. A main-table hit may retain the prior primary mapping;
      // a fill drops all older records before publishing its new primary result.
      if (bank_fill || state==INSTALL_WAIT || token_cpsr != request_cpsr || token_sr != request_sr ||
          token_dac != request_dac || token_baddr != request_baddr) begin
        second_valid <= 0;
        third_valid <= 0;
      end else if (token_valid && token_mapping) begin
        if (THIRD_MAPPING) begin
          third_valid <= second_valid;
          third_va <= second_va;
          third_pa <= second_pa;
          third_cb <= second_cb;
          third_read_allowed <= second_read_allowed;
          third_write_allowed <= second_write_allowed;
          third_fsr <= second_fsr;
          third_external_fsr <= second_external_fsr;
        end
        second_valid <= 1;
        second_va <= token_va[31:10];
        second_pa <= token_pa;
        second_cb <= token_cb;
        second_read_allowed <= token_read_allowed;
        second_write_allowed <= token_write_allowed;
        second_fsr <= token_fsr;
        second_external_fsr <= token_external_fsr;
      end
      token_valid <= 1;
      token_va <= request_va;
      token_rd <= request_rd;
      token_wr <= request_wr;
      token_cpsr <= request_cpsr;
      token_sr <= request_sr;
      token_dac <= request_dac;
      token_baddr <= request_baddr;
      token_pa <= physical_subpage(entry, request_va);
      token_cb <= entry[35:34];
      token_external_fsr <= {entry[33:30], entry[37:36] == 0 ? 4'h8 : 4'ha};
    end
  endtask

  task publish_mapping;
    input [37:0] entry;
    reg [7:0] read_fsr, write_fsr;
    begin
      read_fsr = permission_fault(entry, request_va, request_dac,
                                 request_cpsr, request_sr, 1'b1, 1'b0);
      write_fsr = permission_fault(entry, request_va, request_dac,
                                  request_cpsr, request_sr, 1'b0, 1'b1);
      publish_context(entry);
      token_mapping <= 1;
      token_read_allowed <= read_fsr == 0;
      token_write_allowed <= write_fsr == 0;
      // Both denied directions have the same AP/domain fault code. Share its
      // eight bits rather than duplicating the whole context or FSR per access.
      token_fsr <= read_fsr | write_fsr;
    end
  endtask

  task publish_fault;
    input [7:0] fsr;
    begin
      publish_context(38'b0);
      token_mapping <= 0;
      token_read_allowed <= 0;
      token_write_allowed <= 0;
      token_fsr <= fsr;
    end
  endtask

  assign o_busy = i_mmu_en && i_idle && (state != IDLE || bank_busy || (request && !owner) || mutation);
  // Waiting for translation does not architecturally restart an instruction.
  assign o_lookup_wait = o_busy;
  assign o_walk_pending = o_busy;
  assign o_phy_addr = i_mmu_en ? {use_third ? third_pa : use_second ? second_pa : token_pa, i_address[9:0]} : i_address;
  assign o_fault = i_mmu_en && owner && state == IDLE && !mutation &&
                   (use_third || use_second || token_mapping ? permission_denied : |token_fsr);
  assign o_fsr = o_fault ? selected_fsr : 0;
  assign o_far = o_fault ? i_address : 0;
  assign o_external_fsr = i_mmu_en && owner ?
                         (use_third ? third_external_fsr : use_second ? second_external_fsr : token_external_fsr) : 8'h08;
  assign o_cacheable = i_mmu_en && owner && (use_third ? third_cb[1] : use_second ? second_cb[1] : token_cb[1]);
  assign o_bufferable = i_mmu_en && owner && (use_third ? third_cb[0] : use_second ? second_cb[0] : token_cb[0]);
  // Exact ownership predicate for consumers. Avoid selecting a checked VA
  // through owner and comparing the selected address back to the request.
  assign o_checked_owner = !i_mmu_en || owner;
  assign o_checked_va = !i_mmu_en || owner ? i_address : token_va;
  assign o_checked_lookup = o_checked_va;
  assign o_checked_rd = !i_mmu_en || owner ? i_request_rd : token_rd;
  assign o_checked_wr = !i_mmu_en || owner ? i_request_wr : token_wr;
  assign o_checked_mmu = i_mmu_en && (token_valid || use_second || use_third);
  assign o_checked_cpsr = !i_mmu_en ? i_cpsr : token_cpsr;
  assign o_checked_sr = !i_mmu_en ? i_sr : token_sr;
  assign o_checked_dac = !i_mmu_en ? i_dac_reg : token_dac;
  assign o_checked_baddr = !i_mmu_en ? i_baddr : token_baddr;
  assign o_wb_cyc_nxt = bus_active && !(i_wb_ack || i_wb_err);
  assign o_wb_stb_nxt = o_wb_cyc_nxt;
  assign o_wb_adr_nxt = bus_address;
  assign o_wb_wen_nxt = 0;
  assign o_wb_sel_nxt = 4'hf;
  assign o_wb_dat_nxt = 0;

  always @(posedge i_clk) begin
    if (i_reset) begin
      state <= IDLE;
      token_valid <= 0;
      token_mapping <= 0;
      token_read_allowed <= 0;
      token_write_allowed <= 0;
      token_rd <= 0;
      token_wr <= 0;
      token_va <= 0;
      token_pa <= 0;
      token_cpsr <= 0;
      token_sr <= 0;
      token_cb <= 0;
      token_dac <= 0;
      token_baddr <= 0;
      token_fsr <= 0;
      token_external_fsr <= 0;
      second_valid <= 0;
      second_va <= 0;
      second_pa <= 0;
      second_cb <= 0;
      second_read_allowed <= 0;
      second_write_allowed <= 0;
      second_fsr <= 0;
      second_external_fsr <= 0;
      third_valid <= 0;
      third_va <= 0;
      third_pa <= 0;
      third_cb <= 0;
      third_read_allowed <= 0;
      third_write_allowed <= 0;
      third_fsr <= 0;
      third_external_fsr <= 0;
      request_va <= 0;
      request_rd <= 0;
      request_wr <= 0;
      request_cpsr <= 0;
      request_sr <= 0;
      request_dac <= 0;
      request_baddr <= 0;
      descriptor <= 0;
      domain <= 0;
      fine_table <= 0;
      bus_address <= 0;
      bus_active <= 0;
      cancelled <= 0;
      fill_payload <= 0;
    end else begin
      // Legacy completion ACKs also occur while no request is live. Only a
      // consumed exact walk fault is discarded; denied directions do not evict
      // the reusable mapping or its independent opposite-direction permission.
      if (i_complete && o_fault && !use_third && !use_second && !token_mapping) token_valid <= 0;
      if (mutation || !i_mmu_en) begin
        token_valid <= 0;
        second_valid <= 0;
        third_valid <= 0;
      end
      if (state != IDLE && (mutation || !i_mmu_en || request_baddr != i_baddr)) cancelled <= 1;
      case (state)
        IDLE:
        if (bank_lookup) begin
          // Keep same-context mappings during a serialized bank hit so the
          // previous primary can become the secondary publication. Busy gates
          // consumers until lookup/walk completes; exact faults are not cached.
          if (!shared_context) begin
            token_valid <= 0;
            second_valid <= 0;
            third_valid <= 0;
          end else if (!token_mapping) token_valid <= 0;
          request_va <= i_address;
          request_rd <= i_request_rd;
          request_wr <= i_request_wr;
          request_cpsr <= i_cpsr;
          request_sr <= i_sr;
          request_dac <= i_dac_reg;
          request_baddr <= i_baddr;
          cancelled <= 0;
          state <= LOOKUP;
        end
        LOOKUP:
        if (obsolete) state <= IDLE;
        else if (bank_valid) begin
          if (bank_hit) begin
            publish_mapping(bank_payload);
            state <= IDLE;
          end else begin
            bus_address <= {request_baddr[31:14], request_va[31:20], 2'b0};
            bus_active <= 1;
            state <= L1_WAIT;
          end
        end
        L1_WAIT:
        if (i_wb_ack || i_wb_err) begin
          bus_active <= 0;
          if (obsolete) state <= IDLE;
          else if (i_wb_err) begin
            publish_fault(8'h0c);
            state <= IDLE;
          end else begin
            descriptor <= i_wb_dat;
            state <= L1_DECODE;
          end
        end
        L1_DECODE:
        if (obsolete) state <= IDLE;
        else
          case (descriptor[1:0])
            0: begin
              publish_fault(8'h05);
              state <= IDLE;
            end
            2: begin
              fill_payload <= {
                2'd0,
                descriptor[3:2],
                descriptor[8:5],
                {4{descriptor[11:10]}},
                descriptor[31:20],
                10'b0
              };
              state <= INSTALL;
            end
            default: begin
              domain <= descriptor[8:5];
              fine_table <= descriptor[1:0] == 3;
              bus_address <= descriptor[1:0] == 3 ?
                            {descriptor[31:12],request_va[19:10],2'b0} :
                            {descriptor[31:10],request_va[19:12],2'b0};
              bus_active <= 1;
              state <= L2_WAIT;
            end
          endcase
        L2_WAIT:
        if (i_wb_ack || i_wb_err) begin
          bus_active <= 0;
          if (obsolete) state <= IDLE;
          else if (i_wb_err) begin
            publish_fault({domain, 4'he});
            state <= IDLE;
          end else begin
            descriptor <= i_wb_dat;
            state <= L2_DECODE;
          end
        end
        L2_DECODE:
        if (obsolete) state <= IDLE;
        else if (descriptor[1:0] == 0 || (descriptor[1:0] == 3 && !fine_table)) begin
          publish_fault({domain, 4'h7});
          state <= IDLE;
        end else begin
          case (descriptor[1:0])
            1:
            fill_payload <= {
              2'd1, descriptor[3:2], domain, descriptor[11:4], descriptor[31:16], 6'b0
            };
            2:
            fill_payload <= {
              2'd2, descriptor[3:2], domain, descriptor[11:4], descriptor[31:12], 2'b0
            };
            3:
            fill_payload <= {
              2'd3, descriptor[3:2], domain, {4{descriptor[5:4]}}, descriptor[31:10]
            };
          endcase
          state <= INSTALL;
        end
        INSTALL: begin
          // One fill pulse; publish only after overlap invalidation and RAM
          // commit. CP15 mutations revoke this owner and drain after the fill.
          state <= obsolete ? IDLE : INSTALL_WAIT;
        end
        INSTALL_WAIT: begin
          if (!bank_busy) begin
            if (!obsolete) publish_mapping(fill_payload);
            state <= IDLE;
          end
        end
        default: state <= IDLE;
      endcase
    end
  end
endmodule
