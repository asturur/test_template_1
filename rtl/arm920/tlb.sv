// SPDX-License-Identifier: GPL-3.0-or-later
// ARM920T translation/permission controller. No direct-mapped page-size banks.
// Main-table lookup and bus walks are serialized; a checked 1KiB permission
// token serves adjacent accesses without another CAM/BRAM lookup. The minimum
// ARM920 permission granule is 1KiB (small-page AP quarters and tiny pages).
module arm920_tlb #(
    parameter CPSR_MODE = 4
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
               L2_WAIT=4, L2_DECODE=5, INSTALL=6;
  reg [2:0] state;
  reg token_valid, token_rd, token_wr;
  reg [31:0] token_va, token_dac, token_baddr;
  reg [21:0] token_pa;
  reg [CPSR_MODE:0] token_cpsr;
  reg [1:0] token_sr, token_cb;
  reg [7:0] token_fsr, token_external_fsr;
  reg [31:0] request_va, request_dac, request_baddr;
  reg [CPSR_MODE:0] request_cpsr;
  reg [1:0] request_sr;
  reg request_rd, request_wr, cancelled;
  reg [31:0] descriptor, bus_address;
  reg [3:0] domain;
  reg fine_table, bus_active;
  reg [37:0] fill_payload;
  wire mutation = i_inv || i_lock_write;
  wire owner = token_valid && token_va[31:10] == i_address[31:10] &&
                 token_cpsr == i_cpsr && token_sr == i_sr && token_dac == i_dac_reg &&
                 token_baddr == i_baddr && token_rd == i_request_rd && token_wr == i_request_wr;
  wire request = i_request_rd || i_request_wr;
  wire bank_lookup = state == IDLE && i_mmu_en && i_idle && request && !owner && !mutation;
  wire bank_valid, bank_hit;
  wire [37:0] bank_payload;
  wire obsolete = cancelled || mutation || !i_mmu_en || request_baddr != i_baddr;
  wire bank_fill = state == INSTALL && !obsolete;

  arm920_tlb_bank bank (
      .clk(i_clk),
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

  task publish;
    input [37:0] entry;
    input [7:0] fsr;
    begin
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
      token_fsr <= fsr;
      token_external_fsr <= {entry[33:30], entry[37:36] == 0 ? 4'h8 : 4'ha};
    end
  endtask

  assign o_busy = i_mmu_en && i_idle && (state != IDLE || (request && !owner) || mutation);
  // Waiting for translation does not architecturally restart an instruction.
  assign o_lookup_wait = o_busy;
  assign o_walk_pending = o_busy;
  assign o_phy_addr = i_mmu_en ? {token_pa, i_address[9:0]} : i_address;
  assign o_fault = i_mmu_en && owner && state == IDLE && !mutation && |token_fsr;
  assign o_fsr = o_fault ? token_fsr : 0;
  assign o_far = o_fault ? i_address : 0;
  assign o_external_fsr = i_mmu_en && owner ? token_external_fsr : 8'h08;
  assign o_cacheable = i_mmu_en && owner && token_cb[1];
  assign o_bufferable = i_mmu_en && owner && token_cb[0];
  // Exact ownership predicate for consumers. Avoid selecting a checked VA
  // through owner and comparing the selected address back to the request.
  assign o_checked_owner = !i_mmu_en || owner;
  assign o_checked_va = !i_mmu_en || owner ? i_address : token_va;
  assign o_checked_lookup = o_checked_va;
  assign o_checked_rd = !i_mmu_en ? i_request_rd : token_rd;
  assign o_checked_wr = !i_mmu_en ? i_request_wr : token_wr;
  assign o_checked_mmu = i_mmu_en && token_valid;
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
      if (i_complete && o_fault) token_valid <= 0;
      if (mutation || !i_mmu_en) token_valid <= 0;
      if (state != IDLE && (mutation || !i_mmu_en || request_baddr != i_baddr)) cancelled <= 1;
      case (state)
        IDLE:
        if (bank_lookup) begin
          token_valid <= 0;
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
            publish(bank_payload, permission_fault(
                    bank_payload,
                    request_va,
                    request_dac,
                    request_cpsr,
                    request_sr,
                    request_rd,
                    request_wr
                    ));
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
            publish(0, 8'h0c);
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
              publish(0, 8'h05);
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
            publish(0, {domain, 4'he});
            state <= IDLE;
          end else begin
            descriptor <= i_wb_dat;
            state <= L2_DECODE;
          end
        end
        L2_DECODE:
        if (obsolete) state <= IDLE;
        else if (descriptor[1:0] == 0 || (descriptor[1:0] == 3 && !fine_table)) begin
          publish(0, {domain, 4'h7});
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
          if (!obsolete)
            publish(fill_payload, permission_fault(
                    fill_payload,
                    request_va,
                    request_dac,
                    request_cpsr,
                    request_sr,
                    request_rd,
                    request_wr
                    ));
          state <= IDLE;
        end
        default: state <= IDLE;
      endcase
    end
  end
endmodule
