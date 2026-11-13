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
// The operand-read queue captures committed RF bases before this issue stage.
// Late forwarding and hazard resolution use its owned head. Register
// indices are also pumped forward to allow resolution in the shift
// stage. PC references must be resolved here since the value gives
// PC + 8. Instructions requiring shifts stall if the target registers
// are in the outputs of this stage. We do not issue a multiply if the
// source is still in the output of this stage just like shifts. That's
// to ensure incorrect registers are not read.
//

module zap_issue_main #(
    // Parameters.

    // Number of physical registers.
    parameter [31:0] PHY_REGS = 64,

    // Although DDI0100E mentions only 16 ALU operations, the processor
    // internally performs many more operations.
    parameter [31:0] ALU_OPS = 32,

    // Number of supported shift operations.
    parameter [31:0] SHIFT_OPS = 5
) (
    // Clock and reset.
    input logic i_clk,
    input logic i_reset,

    // UOP
    input  logic       i_uop_last,
    input  logic [1:0] i_swp_tag,
    output logic       o_uop_last,
    output logic [1:0] o_swp_tag,

    // MISC signals.

    input logic [31:0] i_cpu_mode,
    input logic        i_clear_from_writeback,
    input logic        i_data_stall,
    input logic        i_clear_from_alu,
    input logic        i_stall_from_shifter,

    // ------------------------------------------------------
    // Inputs from decode. Look at the decode stage for the
    // meaning of these ports...
    // ------------------------------------------------------

    input logic [                 31:0] i_pc_plus_8_ff,
    input logic [                 31:0] i_pc_ff,
    input logic                         i_switch_ff,
    input logic [                  1:0] i_taken_ff,
    input logic [                 31:0] i_ppc_ff,
    input logic [             64*8-1:0] i_decompile,
    input logic [                  3:0] i_condition_code_ff,
    input logic [$clog2(PHY_REGS )-1:0] i_destination_index_ff,
    input logic [                 32:0] i_alu_source_ff,
    input logic [  $clog2(ALU_OPS)-1:0] i_alu_operation_ff,
    input logic [                 32:0] i_shift_source_ff,
    input logic [$clog2(SHIFT_OPS)-1:0] i_shift_operation_ff,
    input logic [                 32:0] i_shift_length_ff,
    input logic                         i_flag_update_ff,
    input logic [$clog2(PHY_REGS )-1:0] i_mem_srcdest_index_ff,
    input logic                         i_mem_load_ff,
    input logic                         i_mem_store_ff,
    input logic                         i_mem_pre_index_ff,
    input logic                         i_mem_unsigned_byte_enable_ff,
    input logic                         i_mem_signed_byte_enable_ff,
    input logic                         i_mem_signed_halfword_enable_ff,
    input logic                         i_mem_unsigned_halfword_enable_ff,
    input logic                         i_mem_translate_ff,
    input logic                         i_irq_ff,
    input logic                         i_fiq_ff,
    input logic                         i_abt_ff,
    input logic                         i_swi_ff,
    input logic                         i_und_ff,
    input logic                         i_force32align_ff,

    // ---------------------
    // Feedback Network
    // ---------------------

    // Lock
    input logic [63:0] i_dc_lock,

    // Effective architectural RF writes, after writeback priority.
    input  logic        i_rf_wen,
    input  logic [ 5:0] i_rf_wr_addr_a,
    input  logic [ 5:0] i_rf_wr_addr_b,
    input  logic [39:0] i_rf_wr_addr_c,
    input  logic [31:0] i_rf_wr_data_a,
    input  logic [31:0] i_rf_wr_data_b,
    input  logic [31:0] i_rf_wr_data_c,
    output logic        o_operand_busy,

    // From register file. Read ports.
    input logic [31:0] i_rd_data_0,
    input logic [31:0] i_rd_data_1,
    input logic [31:0] i_rd_data_2,
    input logic [31:0] i_rd_data_3,

    //
    // Destination index feedback. Each stage is represented as
    // combinational logic followed by flops(FFs).
    //

    // The ALU never changes destination anyway. Destination from shifter.
    input logic [$clog2(PHY_REGS )-1:0] i_shifter_destination_index_ff,

    // Flopped destination from the ALU.
    input logic [$clog2(PHY_REGS )-1:0] i_alu_destination_index_ff,

    // Flopped destination from the post ALU.
    input logic [$clog2(PHY_REGS)-1:0] i_postalu0_destination_index_ff,
    input logic [$clog2(PHY_REGS)-1:0] i_postalu1_destination_index_ff,
    input logic [$clog2(PHY_REGS)-1:0] i_postalu_destination_index_ff,

    // Flopped destination from the memory stage.
    input logic [$clog2(PHY_REGS )-1:0] i_memory_destination_index_ff,

    //
    // Data valid(dav) for each stage in the pipeline. Used to validate the
    // pipeline vector when sniffing for register values yet to be written.
    //

    input logic i_shifter_dav_ff,
    input logic i_alu_dav_nxt,
    input logic i_alu_dav_ff,
    input logic i_postalu0_dav_ff,
    input logic i_postalu1_dav_ff,
    input logic i_postalu_dav_ff,
    input logic i_memory_dav_ff,

    //
    // The actual thing we need (i.e. data),
    // the value of stuff we are looking for.
    //

    // Taken from alu_nxt since ALU can change this.
    input logic [31:0] i_alu_destination_value_nxt,

    // ALU flopped result.
    input logic [31:0] i_alu_destination_value_ff,

    // PostALU result
    input logic [31:0] i_postalu0_destination_value_ff,
    input logic [31:0] i_postalu1_destination_value_ff,
    input logic [31:0] i_postalu_destination_value_ff,

    // Result in the memory stage of the pipeline.
    input logic [31:0] i_memory_destination_value_ff,

    //
    // For load-store locks and memory acceleration, we need srcdest
    // index. Memory loads can be accelerated with a direct load from
    // memory stage instead of register stage(WB).
    //
    input logic [5:0] i_shifter_mem_srcdest_index_ff,
    input logic [5:0] i_alu_mem_srcdest_index_ff,
    input logic [5:0] i_postalu0_mem_srcdest_index_ff,
    input logic [5:0] i_postalu1_mem_srcdest_index_ff,
    input logic [5:0] i_postalu_mem_srcdest_index_ff,
    input logic [5:0] i_memory_mem_srcdest_index_ff,

    input logic i_shifter_mem_load_ff,
    input logic i_alu_mem_load_ff,
    input logic i_postalu0_mem_load_ff,
    input logic i_postalu1_mem_load_ff,
    input logic i_postalu_mem_load_ff,
    input logic i_memory_mem_load_ff,

    // -----------------------------------
    // END OF FEEDBACK NETWORK
    // -----------------------------------

    // mode32 to compressed switch.
    output logic o_switch_ff,

    // Outputs to register file.
    output logic [$clog2(PHY_REGS )-1:0] o_rd_index_0,
    output logic [$clog2(PHY_REGS )-1:0] o_rd_index_1,
    output logic [$clog2(PHY_REGS )-1:0] o_rd_index_2,
    output logic [$clog2(PHY_REGS )-1:0] o_rd_index_3,

    // Outputs to shifter stage.
    output logic [                  3:0] o_condition_code_ff,
    output logic [$clog2(PHY_REGS )-1:0] o_destination_index_ff,
    output logic [  $clog2(ALU_OPS)-1:0] o_alu_operation_ff,
    output logic [$clog2(SHIFT_OPS)-1:0] o_shift_operation_ff,
    output logic                         o_flag_update_ff,

    // Memory operation related.
    output logic [$clog2(PHY_REGS )-1:0] o_mem_srcdest_index_ff,
    output logic                         o_mem_load_ff,
    output logic                         o_mem_store_ff,
    output logic                         o_mem_pre_index_ff,
    output logic                         o_mem_unsigned_byte_enable_ff,
    output logic                         o_mem_signed_byte_enable_ff,
    output logic                         o_mem_signed_halfword_enable_ff,
    output logic                         o_mem_unsigned_halfword_enable_ff,
    output logic                         o_mem_translate_ff,

    // Interrupts.
    output logic o_irq_ff,
    output logic o_fiq_ff,
    output logic o_abt_ff,
    output logic o_swi_ff,

    // Register values are given here.

    // ALU source value would be the value of non-shifted operand in mode32.
    output logic [31:0] o_alu_source_value_ff,

    // Shifter source value would be the value of the operand to be shifted.
    output logic [31:0] o_shift_source_value_ff,

    // Shift length i.e., amount to shift i.e, shamt.
    output logic [31:0] o_shift_length_value_ff,

    // For stores, value to be stored.
    output logic [31:0] o_mem_srcdest_value_ff,

    //
    // Indices/Immeds go here. It might seem odd that we are sending index
    // values and register values (above). The issue stage selects
    // the appropriate value. Note again that while the above are values,
    // these are indexes/immediates.
    //
    output logic [32:0] o_alu_source_ff,
    output logic [32:0] o_shift_source_ff,

    // Registered-capacity stop for stages before operand acquisition.
    output logic o_stall_from_issue,

    // The PC value.
    output logic [31:0] o_pc_plus_8_ff,

    //
    // Shifter disable. In the next stage, the output
    // will bypass the shifter. Not actually bypass it but will
    // go to the ALU value corrector unit via a MUX essentially bypassing
    // the shifter.
    //
    output logic o_shifter_disable_ff,

    // Outputs flopped from decode.
    output logic [64*8-1:0] o_decompile,
    output logic [    31:0] o_pc_ff,
    output logic [     1:0] o_taken_ff,
    output logic [    31:0] o_ppc_ff,
    output logic            o_force32align_ff,
    output logic            o_und_ff
);

  `include "zap_defines.svh"
  `include "zap_localparams.svh"

  logic o_shifter_disable_nxt;
  logic [31:0]
      o_alu_source_value_nxt,
      o_shift_source_value_nxt,
      o_shift_length_value_nxt,
      o_mem_srcdest_value_nxt;

  localparam CONTROL_W = 32 + 32 + 1 + 2 + 64 * 8 + 1 + 4 + $clog2(
      PHY_REGS
  ) + 33 + $clog2(
      ALU_OPS
  ) + 33 + $clog2(
      SHIFT_OPS
  ) + 33 + 1 + $clog2(
      PHY_REGS
  ) + 14 + 32 + 2 + 16;
  logic [CONTROL_W-1:0] operand_control;
  logic [15:0] operand_special;
  logic operand_valid, operand_pop, operand_push, issue_block;
  logic [127:0] operand_data;  // Raw bases; previous and current commits select below.
  logic [ 11:0] operand_pending;
  logic [31:0] operand_commit_a, operand_commit_b, operand_commit_c;
  logic [31:0] operand_rd_data_0, operand_rd_data_1, operand_rd_data_2, operand_rd_data_3;
  assign {operand_rd_data_3, operand_rd_data_2,
         operand_rd_data_1, operand_rd_data_0} = operand_data;

  // Individual lock signals. These are ORed to get the final lock.
  logic                         shift_lock;
  logic                         load_lock;
  logic                         lock;

  //
  // Hazard holds the owned head and bubbles issue; capacity stops upstream.
  //

  // Owned R0 context.
  logic [                 31:0] operand_pc_plus_8_ff;
  logic [                 31:0] operand_pc_ff;
  logic                         operand_switch_ff;
  logic [                  1:0] operand_taken_ff;
  logic [             64*8-1:0] operand_decompile;
  logic                         operand_uop_last;
  logic [                  1:0] operand_swp_tag;
  logic [                  3:0] operand_condition_code_ff;
  logic [$clog2(PHY_REGS )-1:0] operand_destination_index_ff;
  logic [                 32:0] operand_alu_source_ff;
  logic [  $clog2(ALU_OPS)-1:0] operand_alu_operation_ff;
  logic [                 32:0] operand_shift_source_ff;
  logic [$clog2(SHIFT_OPS)-1:0] operand_shift_operation_ff;
  logic [                 32:0] operand_shift_length_ff;
  logic                         operand_flag_update_ff;
  logic [$clog2(PHY_REGS )-1:0] operand_mem_srcdest_index_ff;
  logic                         operand_mem_load_ff;
  logic                         operand_mem_store_ff;
  logic                         operand_mem_pre_index_ff;
  logic                         operand_mem_unsigned_byte_enable_ff;
  logic                         operand_mem_signed_byte_enable_ff;
  logic                         operand_mem_signed_halfword_enable_ff;
  logic                         operand_mem_unsigned_halfword_enable_ff;
  logic                         operand_mem_translate_ff;
  logic                         operand_irq_ff;
  logic                         operand_fiq_ff;
  logic                         operand_abt_ff;
  logic                         operand_swi_ff;
  logic                         operand_force32align_ff;
  logic                         operand_und_ff;
  logic [                 31:0] operand_ppc_ff;
  logic                         clear;
  logic                         stall;

  assign lock  = (shift_lock | load_lock) & (operand_condition_code_ff != NV);

  assign clear = i_clear_from_writeback | i_clear_from_alu;
  assign stall = i_data_stall | i_stall_from_shifter;

  always_ff @(posedge i_clk) begin
    if (i_reset) begin
      o_condition_code_ff               <= NV;
      o_irq_ff                          <= 0;
      o_fiq_ff                          <= 0;
      o_abt_ff                          <= 0;
      o_swi_ff                          <= 0;
      o_und_ff                          <= 0;
      o_flag_update_ff                  <= 0;

      o_swp_tag                         <= 0;
      o_uop_last                        <= 0;

      o_destination_index_ff            <= 'x;
      o_alu_operation_ff                <= 'x;
      o_shift_operation_ff              <= 'x;
      o_mem_srcdest_index_ff            <= 'x;
      o_mem_load_ff                     <= 'x;
      o_mem_store_ff                    <= 'x;
      o_mem_pre_index_ff                <= 'x;
      o_mem_unsigned_byte_enable_ff     <= 'x;
      o_mem_signed_byte_enable_ff       <= 'x;
      o_mem_signed_halfword_enable_ff   <= 'x;
      o_mem_unsigned_halfword_enable_ff <= 'x;
      o_mem_translate_ff                <= 'x;
      o_pc_plus_8_ff                    <= 'x;
      o_shifter_disable_ff              <= 'x;
      o_alu_source_ff                   <= 'x;
      o_shift_source_ff                 <= 'x;
      o_alu_source_value_ff             <= 'x;
      o_shift_source_value_ff           <= 'x;
      o_shift_length_value_ff           <= 'x;
      o_mem_srcdest_value_ff            <= 'x;
      o_switch_ff                       <= 'x;
      o_force32align_ff                 <= 'x;
      o_taken_ff                        <= 'x;
      o_pc_ff                           <= 'x;
      o_decompile                       <= 'x;
      o_ppc_ff                          <= 'x;
    end else if (clear) begin
      o_condition_code_ff               <= NV;
      o_irq_ff                          <= 0;
      o_fiq_ff                          <= 0;
      o_abt_ff                          <= 0;
      o_swi_ff                          <= 0;
      o_und_ff                          <= 0;
      o_flag_update_ff                  <= 0;

      o_swp_tag                         <= 0;
      o_uop_last                        <= 0;

      o_destination_index_ff            <= 'x;
      o_alu_operation_ff                <= 'x;
      o_shift_operation_ff              <= 'x;
      o_mem_srcdest_index_ff            <= 'x;
      o_mem_load_ff                     <= 'x;
      o_mem_store_ff                    <= 'x;
      o_mem_pre_index_ff                <= 'x;
      o_mem_unsigned_byte_enable_ff     <= 'x;
      o_mem_signed_byte_enable_ff       <= 'x;
      o_mem_signed_halfword_enable_ff   <= 'x;
      o_mem_unsigned_halfword_enable_ff <= 'x;
      o_mem_translate_ff                <= 'x;
      o_pc_plus_8_ff                    <= 'x;
      o_shifter_disable_ff              <= 'x;
      o_alu_source_ff                   <= 'x;
      o_shift_source_ff                 <= 'x;
      o_alu_source_value_ff             <= 'x;
      o_shift_source_value_ff           <= 'x;
      o_shift_length_value_ff           <= 'x;
      o_mem_srcdest_value_ff            <= 'x;
      o_switch_ff                       <= 'x;
      o_force32align_ff                 <= 'x;
      o_taken_ff                        <= 'x;
      o_pc_ff                           <= 'x;
      o_decompile                       <= 'x;
      o_ppc_ff                          <= 'x;
    end else if (~stall) begin
      o_condition_code_ff               <= issue_block ? NV : operand_condition_code_ff;
      o_destination_index_ff            <= operand_destination_index_ff;
      o_alu_operation_ff                <= operand_alu_operation_ff;
      o_shift_operation_ff              <= operand_shift_operation_ff;
      o_flag_update_ff                  <= issue_block ? 1'd0 : operand_flag_update_ff;
      o_mem_srcdest_index_ff            <= operand_mem_srcdest_index_ff;
      o_mem_load_ff                     <= operand_mem_load_ff;
      o_mem_store_ff                    <= operand_mem_store_ff;
      o_mem_pre_index_ff                <= operand_mem_pre_index_ff;
      o_mem_unsigned_byte_enable_ff     <= operand_mem_unsigned_byte_enable_ff;
      o_mem_signed_byte_enable_ff       <= operand_mem_signed_byte_enable_ff;
      o_mem_signed_halfword_enable_ff   <= operand_mem_signed_halfword_enable_ff;
      o_mem_unsigned_halfword_enable_ff <= operand_mem_unsigned_halfword_enable_ff;
      o_mem_translate_ff                <= issue_block ? 1'd0 : operand_mem_translate_ff;
      o_irq_ff                          <= issue_block ? 1'd0 : operand_irq_ff;
      o_fiq_ff                          <= issue_block ? 1'd0 : operand_fiq_ff;
      o_abt_ff                          <= issue_block ? 1'd0 : operand_abt_ff;
      o_swi_ff                          <= issue_block ? 1'd0 : operand_swi_ff;
      o_pc_plus_8_ff                    <= operand_pc_plus_8_ff;
      o_shifter_disable_ff              <= o_shifter_disable_nxt;
      o_alu_source_ff                   <= operand_alu_source_ff;
      o_shift_source_ff                 <= operand_shift_source_ff;
      o_alu_source_value_ff             <= o_alu_source_value_nxt;
      o_shift_source_value_ff           <= o_shift_source_value_nxt;
      o_shift_length_value_ff           <= o_shift_length_value_nxt;
      o_mem_srcdest_value_ff            <= o_mem_srcdest_value_nxt;
      o_switch_ff                       <= operand_switch_ff;
      o_force32align_ff                 <= operand_force32align_ff;
      o_und_ff                          <= issue_block ? 1'd0 : operand_und_ff;
      o_taken_ff                        <= operand_taken_ff;
      o_ppc_ff                          <= operand_ppc_ff;
      o_pc_ff                           <= operand_pc_ff;
      o_decompile                       <= operand_decompile;
      o_uop_last                        <= issue_block ? 1'd0 : operand_uop_last;
      o_swp_tag                         <= issue_block ? 2'd0 : operand_swp_tag;

    end
  end

  // R owns both the current issue packet and the one reserved arrival slot.
  // Decode advances under this same capacity/stall condition.
  assign operand_push = !stall && !o_stall_from_issue &&
        (i_condition_code_ff != NV || i_irq_ff || i_fiq_ff || i_abt_ff ||
         i_swi_ff || i_und_ff);
  assign operand_pop = !stall && operand_valid && !lock;
  assign issue_block = !operand_valid || lock;

  zap_operand_read #(
      .CONTROL_W(CONTROL_W)
  ) u_operand_read (
      .i_clk(i_clk),
      .i_reset(i_reset),
      .i_clear(clear),
      .i_push(operand_push),
      .i_pop(operand_pop),
      .i_control({
        special_class({27'd0, i_mem_srcdest_index_ff}),
        special_class(i_shift_length_ff),
        special_class(i_shift_source_ff),
        special_class(i_alu_source_ff),
        i_pc_plus_8_ff,
        i_pc_ff,
        i_switch_ff,
        i_taken_ff,
        i_decompile,
        i_uop_last,
        i_swp_tag,
        i_condition_code_ff,
        i_destination_index_ff,
        i_alu_source_ff,
        i_alu_operation_ff,
        i_shift_source_ff,
        i_shift_operation_ff,
        i_shift_length_ff,
        i_flag_update_ff,
        i_mem_srcdest_index_ff,
        i_mem_load_ff,
        i_mem_store_ff,
        i_mem_pre_index_ff,
        i_mem_unsigned_byte_enable_ff,
        i_mem_signed_byte_enable_ff,
        i_mem_signed_halfword_enable_ff,
        i_mem_unsigned_halfword_enable_ff,
        i_mem_translate_ff,
        i_irq_ff,
        i_fiq_ff,
        i_abt_ff,
        i_swi_ff,
        i_force32align_ff,
        i_und_ff,
        i_ppc_ff
      }),
      .i_index({
        i_mem_srcdest_index_ff[5:0],
        i_shift_length_ff[5:0],
        i_shift_source_ff[5:0],
        i_alu_source_ff[5:0]
      }),
      .i_data({i_rd_data_3, i_rd_data_2, i_rd_data_1, i_rd_data_0}),
      .i_wen(i_rf_wen),
      .i_wr_addr_a(i_rf_wr_addr_a),
      .i_wr_addr_b(i_rf_wr_addr_b),
      .i_wr_addr_c(i_rf_wr_addr_c),
      .i_wr_data_a(i_rf_wr_data_a),
      .i_wr_data_b(i_rf_wr_data_b),
      .i_wr_data_c(i_rf_wr_data_c),
      .o_valid(operand_valid),
      .o_full(o_stall_from_issue),
      .o_busy(o_operand_busy),
      .o_control(operand_control),
      .o_base_data(operand_data),
      .o_pending(operand_pending),
      .o_commit_a(operand_commit_a),
      .o_commit_b(operand_commit_b),
      .o_commit_c(operand_commit_c)
  );

  // Get values from the feedback network.
  assign o_alu_source_value_nxt = get_register_value(
      operand_alu_source_ff,
      operand_pending[0+:3],
      operand_special[0+:4],
      i_shifter_destination_index_ff[5:0],
      i_alu_dav_nxt,
      i_alu_destination_value_nxt,
      i_alu_destination_value_ff,
      i_alu_destination_index_ff[5:0],
      i_alu_dav_ff,

      i_postalu0_destination_index_ff[5:0],
      i_postalu0_destination_value_ff,
      i_postalu0_dav_ff,

      i_postalu1_destination_index_ff[5:0],
      i_postalu1_destination_value_ff,
      i_postalu1_dav_ff,

      i_postalu_destination_index_ff[5:0],
      i_postalu_destination_value_ff,
      i_postalu_dav_ff,

      i_memory_destination_index_ff[5:0],
      i_memory_destination_value_ff,
      i_memory_dav_ff,
      operand_rd_data_0,
      i_cpu_mode,
      operand_pc_plus_8_ff,
      operand_force32align_ff
  );


  assign o_shift_source_value_nxt = get_register_value(
      operand_shift_source_ff,
      operand_pending[3+:3],
      operand_special[4+:4],
      i_shifter_destination_index_ff[5:0],
      i_alu_dav_nxt,
      i_alu_destination_value_nxt,
      i_alu_destination_value_ff,
      i_alu_destination_index_ff[5:0],
      i_alu_dav_ff,

      i_postalu0_destination_index_ff[5:0],
      i_postalu0_destination_value_ff,
      i_postalu0_dav_ff,

      i_postalu1_destination_index_ff[5:0],
      i_postalu1_destination_value_ff,
      i_postalu1_dav_ff,

      i_postalu_destination_index_ff[5:0],
      i_postalu_destination_value_ff,
      i_postalu_dav_ff,

      i_memory_destination_index_ff[5:0],
      i_memory_destination_value_ff,
      i_memory_dav_ff,
      operand_rd_data_1,
      i_cpu_mode,
      operand_pc_plus_8_ff,
      1'd0
  );

  assign o_shift_length_value_nxt = get_register_value(
      operand_shift_length_ff,
      operand_pending[6+:3],
      operand_special[8+:4],
      i_shifter_destination_index_ff[5:0],
      i_alu_dav_nxt,
      i_alu_destination_value_nxt,
      i_alu_destination_value_ff,
      i_alu_destination_index_ff[5:0],
      i_alu_dav_ff,

      i_postalu0_destination_index_ff[5:0],
      i_postalu0_destination_value_ff,
      i_postalu0_dav_ff,

      i_postalu1_destination_index_ff[5:0],
      i_postalu1_destination_value_ff,
      i_postalu1_dav_ff,

      i_postalu_destination_index_ff[5:0],
      i_postalu_destination_value_ff,
      i_postalu_dav_ff,

      i_memory_destination_index_ff[5:0],
      i_memory_destination_value_ff,
      i_memory_dav_ff,
      operand_rd_data_2,
      i_cpu_mode,
      operand_pc_plus_8_ff,
      1'd0
  );

  // Value of a register index, never an immediate.
  assign o_mem_srcdest_value_nxt = get_register_value(
      {
        27'd0, operand_mem_srcdest_index_ff
      },
      operand_pending[9+:3],
      operand_special[12+:4],
      i_shifter_destination_index_ff[5:0],
      i_alu_dav_nxt,
      i_alu_destination_value_nxt,
      i_alu_destination_value_ff,
      i_alu_destination_index_ff[5:0],
      i_alu_dav_ff,

      i_postalu0_destination_index_ff[5:0],
      i_postalu0_destination_value_ff,
      i_postalu0_dav_ff,

      i_postalu1_destination_index_ff[5:0],
      i_postalu1_destination_value_ff,
      i_postalu1_dav_ff,

      i_postalu_destination_index_ff[5:0],
      i_postalu_destination_value_ff,
      i_postalu_dav_ff,

      i_memory_destination_index_ff[5:0],
      i_memory_destination_value_ff,
      i_memory_dav_ff,
      operand_rd_data_3,
      i_cpu_mode,
      operand_pc_plus_8_ff,
      1'd0
  );

  // Apply index to register file.
  assign o_rd_index_0 = i_alu_source_ff[5:0];
  assign o_rd_index_1 = i_shift_source_ff[5:0];
  assign o_rd_index_2 = i_shift_length_ff[5:0];
  assign o_rd_index_3 = i_mem_srcdest_index_ff[5:0];

  assign {operand_special, operand_pc_plus_8_ff,
                 operand_pc_ff,
                 operand_switch_ff,
                 operand_taken_ff,
                 operand_decompile,
                 operand_uop_last,
                 operand_swp_tag,
                 operand_condition_code_ff,
                 operand_destination_index_ff,
                 operand_alu_source_ff,
                 operand_alu_operation_ff,
                 operand_shift_source_ff,
                 operand_shift_operation_ff,
                 operand_shift_length_ff,
                 operand_flag_update_ff,
                 operand_mem_srcdest_index_ff,
                 operand_mem_load_ff,
                 operand_mem_store_ff,
                 operand_mem_pre_index_ff,
                 operand_mem_unsigned_byte_enable_ff,
                 operand_mem_signed_byte_enable_ff,
                 operand_mem_signed_halfword_enable_ff,
                 operand_mem_unsigned_halfword_enable_ff,
                 operand_mem_translate_ff,
                 operand_irq_ff,
                 operand_fiq_ff,
                 operand_abt_ff,
                 operand_swi_ff,
                 operand_force32align_ff,
                 operand_und_ff,
                 operand_ppc_ff} = operand_control;

  logic operand_is_lsl_0;
  logic operand_is_rori;
  logic w_shift_lock;
  logic operand_is_mult;

  assign operand_is_lsl_0 = operand_shift_operation_ff    == {1'd0, LSL} &&
                       operand_shift_length_ff[31:0] == 32'd0 &&
                       operand_shift_length_ff[32]   == IMMED_EN;

  assign operand_is_rori = operand_shift_operation_ff == RORI;

  // Constant RORI #0 were converted to Constant LSL #0 in decode.
  assign o_shifter_disable_nxt = operand_is_lsl_0 | operand_is_mult;

  assign w_shift_lock = shifter_lock_check(
      operand_shift_source_ff, o_destination_index_ff, o_condition_code_ff
  ) || shifter_lock_check(
      operand_shift_length_ff, o_destination_index_ff, o_condition_code_ff
  ) || shifter_lock_check(
      operand_alu_source_ff, o_destination_index_ff, o_condition_code_ff
  ) || shifter_lock_check(
      {27'd0, operand_mem_srcdest_index_ff}, o_destination_index_ff, o_condition_code_ff
  );


  assign operand_is_mult = operand_alu_operation_ff == {1'd0, UMLALL}     ||
                      operand_alu_operation_ff == {1'd0, UMLALH}     ||
                      operand_alu_operation_ff == {1'd0, SMLALL}     ||
                      operand_alu_operation_ff == {1'd0, SMLALH}     ||
                      operand_alu_operation_ff == SMULW0             ||
                      operand_alu_operation_ff == SMULW1             ||
                      operand_alu_operation_ff == SMUL00             ||
                      operand_alu_operation_ff == SMUL01             ||
                      operand_alu_operation_ff == SMUL10             ||
                      operand_alu_operation_ff == SMUL11             ||
                      operand_alu_operation_ff == SMLA00             ||
                      operand_alu_operation_ff == SMLA01             ||
                      operand_alu_operation_ff == SMLA10             ||
                      operand_alu_operation_ff == SMLA11             ||
                      operand_alu_operation_ff == SMLAW0             ||
                      operand_alu_operation_ff == SMLAW1             ||
                      operand_alu_operation_ff == SMLAL00L           ||
                      operand_alu_operation_ff == SMLAL01L           ||
                      operand_alu_operation_ff == SMLAL10L           ||
                      operand_alu_operation_ff == SMLAL11L           ||
                      operand_alu_operation_ff == SMLAL00H           ||
                      operand_alu_operation_ff == SMLAL01H           ||
                      operand_alu_operation_ff == SMLAL10H           ||
                      operand_alu_operation_ff == SMLAL11H;

  //
  // Look for reads from registers to be loaded from memory. Four
  // register sources may cause a load lock.
  //
  assign load_lock = determine_load_lock(
          operand_alu_source_ff,
          o_mem_srcdest_index_ff,
          o_condition_code_ff,
          o_mem_load_ff,
          i_shifter_mem_srcdest_index_ff,
          i_shifter_dav_ff,
          i_shifter_mem_load_ff,
          i_alu_mem_srcdest_index_ff,
          i_alu_dav_ff,
          i_alu_mem_load_ff,
          i_postalu0_mem_srcdest_index_ff,
          i_postalu0_mem_load_ff,
          i_postalu0_dav_ff,
          i_postalu1_mem_srcdest_index_ff,
          i_postalu1_mem_load_ff,
          i_postalu1_dav_ff,
          i_postalu_mem_srcdest_index_ff,
          i_postalu_mem_load_ff,
          i_postalu_dav_ff,
          i_memory_mem_srcdest_index_ff,
          i_memory_mem_load_ff,
          i_memory_dav_ff,
          i_dc_lock,
          operand_irq_ff || operand_fiq_ff || operand_abt_ff || operand_swi_ff || operand_und_ff
      ) || determine_load_lock(
          operand_shift_source_ff,
          o_mem_srcdest_index_ff,
          o_condition_code_ff,
          o_mem_load_ff,
          i_shifter_mem_srcdest_index_ff,
          i_shifter_dav_ff,
          i_shifter_mem_load_ff,
          i_alu_mem_srcdest_index_ff,
          i_alu_dav_ff,
          i_alu_mem_load_ff,
          i_postalu0_mem_srcdest_index_ff,
          i_postalu0_mem_load_ff,
          i_postalu0_dav_ff,
          i_postalu1_mem_srcdest_index_ff,
          i_postalu1_mem_load_ff,
          i_postalu1_dav_ff,
          i_postalu_mem_srcdest_index_ff,
          i_postalu_mem_load_ff,
          i_postalu_dav_ff,
          i_memory_mem_srcdest_index_ff,
          i_memory_mem_load_ff,
          i_memory_dav_ff,
          i_dc_lock,
          operand_irq_ff || operand_fiq_ff || operand_abt_ff || operand_swi_ff || operand_und_ff
      ) || determine_load_lock(
          operand_shift_length_ff,
          o_mem_srcdest_index_ff,
          o_condition_code_ff,
          o_mem_load_ff,
          i_shifter_mem_srcdest_index_ff,
          i_shifter_dav_ff,
          i_shifter_mem_load_ff,
          i_alu_mem_srcdest_index_ff,
          i_alu_dav_ff,
          i_alu_mem_load_ff,
          i_postalu0_mem_srcdest_index_ff,
          i_postalu0_mem_load_ff,
          i_postalu0_dav_ff,
          i_postalu1_mem_srcdest_index_ff,
          i_postalu1_mem_load_ff,
          i_postalu1_dav_ff,
          i_postalu_mem_srcdest_index_ff,
          i_postalu_mem_load_ff,
          i_postalu_dav_ff,
          i_memory_mem_srcdest_index_ff,
          i_memory_mem_load_ff,
          i_memory_dav_ff,
          i_dc_lock,
          operand_irq_ff || operand_fiq_ff || operand_abt_ff || operand_swi_ff || operand_und_ff
      ) || determine_load_lock(
          {27'd0, operand_mem_srcdest_index_ff},
          o_mem_srcdest_index_ff,
          o_condition_code_ff,
          o_mem_load_ff,
          i_shifter_mem_srcdest_index_ff,
          i_shifter_dav_ff,
          i_shifter_mem_load_ff,
          i_alu_mem_srcdest_index_ff,
          i_alu_dav_ff,
          i_alu_mem_load_ff,
          i_postalu0_mem_srcdest_index_ff,
          i_postalu0_mem_load_ff,
          i_postalu0_dav_ff,
          i_postalu1_mem_srcdest_index_ff,
          i_postalu1_mem_load_ff,
          i_postalu1_dav_ff,
          i_postalu_mem_srcdest_index_ff,
          i_postalu_mem_load_ff,
          i_postalu_dav_ff,
          i_memory_mem_srcdest_index_ff,
          i_memory_mem_load_ff,
          i_memory_dav_ff,
          i_dc_lock,
          operand_irq_ff || operand_fiq_ff || operand_abt_ff || operand_swi_ff || operand_und_ff
      ) ||
      //
      // If a register is locked by load, don't issue an instruction that
      // writes to that register. Assert load lock. Else, background
      // load will overwrite the latest value.
      //
      (
                          operand_destination_index_ff[5:0] != PHY_RAZ_REGISTER[5:0]
                          &&
                          i_dc_lock[operand_destination_index_ff]
                        );

  //
  // A shift lock occurs if the current instruction requires a shift
  // amount as a register other than LSL #0 or RORI if the operands are
  // right on the output of this stage because in that case we do not
  // have the register value and thus a shift lock.
  //
  // Another case is when the output of this stage has a flag update, a
  // shift operation that is not LSL#0 or RORI cannot be issued since flags are
  // not actually available in the next cycle. They are only available in the
  // next-2-next cycle.
  //
  assign shift_lock =
  (((operand_is_mult |   ((~operand_is_lsl_0) & (~operand_is_rori)))) & w_shift_lock)
| (o_flag_update_ff & ((~operand_is_lsl_0) & (~operand_is_rori)));

  ////////////////////////////////////
  // Functions
  ////////////////////////////////////

  // ---------------------------------------------
  // Shifter lock check.
  // ---------------------------------------------

  function automatic shifter_lock_check(input [32:0] index,
                                        input [$clog2(PHY_REGS)-1:0] destination_index_ff,
                                        input [3:0] condition_code_ff);

    logic unused;
    unused = |index[31:6];

    // Simply check if the operand index is on the output of this unit
    // and that the output is valid.
    // If immediate, no lock obviously.

    if (index[32] == IMMED_EN || index[5:0] == PHY_RAZ_REGISTER) begin
      shifter_lock_check = 1'd0;
    end else if (destination_index_ff == index[5:0] && condition_code_ff != NV) begin
      shifter_lock_check = 1'd1;
    end else begin
      shifter_lock_check = 1'd0;
    end

  endfunction : shifter_lock_check

  // -----------------------------------------------
  // Load lock. Activated when a read from a register
  // follows a load to that register.
  // -----------------------------------------------

  function automatic determine_load_lock(
      input [32:0] index, input [$clog2(PHY_REGS)-1:0] mem_srcdest_index_ff,
      input [3:0] condition_code_ff, input mem_load_ff,
      input [$clog2(PHY_REGS)-1:0] shifter_mem_srcdest_index_ff, input alu_dav_nxt,
      input shifter_mem_load_ff, input [$clog2(PHY_REGS)-1:0] alu_mem_srcdest_index_ff,
      input alu_dav_ff, input alu_mem_load_ff,
      input [$clog2(PHY_REGS)-1:0] postalu0_mem_srcdest_index_ff, input postalu0_mem_load_ff,
      input postalu0_dav_ff, input [$clog2(PHY_REGS)-1:0] postalu1_mem_srcdest_index_ff,
      input postalu1_mem_load_ff, input postalu1_dav_ff,
      input [$clog2(PHY_REGS)-1:0] postalu_mem_srcdest_index_ff, input postalu_mem_load_ff,
      input postalu_dav_ff, input [$clog2(PHY_REGS)-1:0] memory_mem_srcdest_index_ff,
      input memory_mem_load_ff, input memory_dav_ff, input [63:0] xlock, input ext_lock);
    logic unused;

    //
    // Look for that load instruction in the required pipeline stages.
    // If found, we cannot issue the current instruction since old value
    // will be read.
    //

    if ( index[32] == IMMED_EN || index[5:0] == PHY_RAZ_REGISTER[5:0] )
        // Lock only occurs for indices.
        begin
      determine_load_lock = 1'd0;
    end else if (xlock[index[5:0]] || ((|xlock) && ext_lock)) begin
      determine_load_lock = 1'd1;
    end
        else if
        (
                ( index[5:0] == mem_srcdest_index_ff          &&
                  condition_code_ff != NV                     &&
                  mem_load_ff )                               || // ISSUE
        ( index[5:0] == shifter_mem_srcdest_index_ff  &&
                   alu_dav_nxt                                &&
                   shifter_mem_load_ff )                      || // SHIFT
        (index[5:0] == alu_mem_srcdest_index_ff && alu_dav_ff && alu_mem_load_ff) ||  // ALU
        (  index[5:0] == postalu0_mem_srcdest_index_ff&&
                   postalu0_dav_ff                            &&
                   postalu0_mem_load_ff )                     || // Post ALU0
        (  index[5:0] == postalu1_mem_srcdest_index_ff&&
                   postalu1_dav_ff                            &&
                   postalu1_mem_load_ff )                     || // Post ALU1
        (  index[5:0] == postalu_mem_srcdest_index_ff &&
                   postalu_dav_ff                             &&
                   postalu_mem_load_ff )                      || // Post ALU
        (  index[5:0] == memory_mem_srcdest_index_ff  &&
                   memory_mem_load_ff                         &&
                   memory_dav_ff   )                             // Memory
        ) begin
      determine_load_lock = 1'd1;
    end else begin
      determine_load_lock = 1'd0;
    end

    unused = |{index[31:6]};

  endfunction : determine_load_lock

  // ----------------------------------------------------------------------------

  //
  // Straightforward read feedback function. Looks at all stages of the pipeline
  // to extract the latest value of the register.
  //
  // These classifications depend only on the accepted instruction, not a live
  // producer. Capture with R ownership instead of decoding a held index again on
  // every issue priority path. Immediate remains the highest-priority class.
  function automatic [3:0] special_class(input [32:0] index);
    special_class = {
      index[5:0] == PHY_CPSR[5:0],
      index[5:0] == {2'd0, ARCH_PC[3:0]},
      index[5:0] == PHY_RAZ_REGISTER[5:0],
      index[32]
    };
  endfunction

  function automatic [31:0] get_register_value(

      // The register inex to search for. This might be a constant too.
      input [32:0] index,

      // Previous edge's C/B/A commit selector for this owned source.
      input [2:0] pending,
      input [3:0] special,

      // Destination on the output of the shifter stage.
      input [$clog2(PHY_REGS)-1:0] shifter_destination_index_ff,

      // ALU output is valid.
      input alu_dav_nxt,

      // ALU output.
      input [31:0] alu_destination_value_nxt,

      // ALU flopped result.
      input [31:0] alu_destination_value_ff,

      // ALU flopped destination index.
      input [$clog2(PHY_REGS)-1:0] alu_destination_index_ff,

      // Valid flopped (EX stage).
      input alu_dav_ff, input [$clog2(PHY_REGS)-1:0] postalu0_destination_index_ff,
      input [31:0] postalu0_destination_value_ff, input postalu0_dav_ff,

      input [$clog2(PHY_REGS)-1:0] postalu1_destination_index_ff,
      input [31:0] postalu1_destination_value_ff, input postalu1_dav_ff,

      input [$clog2(PHY_REGS)-1:0] postalu_destination_index_ff,
      input [31:0] postalu_destination_value_ff, input postalu_dav_ff,

      // Memory stage destination index (pointer)
      input [$clog2(PHY_REGS)-1:0] memory_destination_index_ff,
      input [31:0] memory_destination_value_ff, input memory_dav_ff,

      // Base is one commit edge behind; journal/current writes follow below.
      input [31:0] rf_data,

      // CPU mode and PC.
      input [31:0] cpu_mode,
      input [31:0] pc_plus_8_ff,

      // PC access control.
      input force32_align_ff);

    logic [31:0] get;
    logic [15:0] match_source, select_source;
    logic [31:0] selected[0:15];

    // Resolve priority on narrow controls, independently of the register
    // read tree. The word datapath is a masked OR, not a priority mux chain.
    // Lowest numbered match wins, exactly as in the original if/else chain.
    match_source[3:0] = special;
    match_source[4]   = index[5:0] == shifter_destination_index_ff[5:0] && alu_dav_nxt;
    match_source[5]   = index[5:0] == alu_destination_index_ff[5:0] && alu_dav_ff;
    match_source[6]   = index[5:0] == postalu0_destination_index_ff[5:0] && postalu0_dav_ff;
    match_source[7]   = index[5:0] == postalu1_destination_index_ff[5:0] && postalu1_dav_ff;
    match_source[8]   = index[5:0] == postalu_destination_index_ff[5:0] && postalu_dav_ff;
    match_source[9]   = index[5:0] == memory_destination_index_ff[5:0] && memory_dav_ff;
    // Commits are older than every in-flight producer. Keep CURRENT writes
    // visible on the issue edge (including exception/CP15 and legacy C),
    // then the registered previous edge, then the held base. One common
    // priority/reduction avoids serial commit muxes before forwarding.
    match_source[10]  = index[5:0] < 6'd40 && i_rf_wr_addr_c[index[5:0]];
    match_source[11]  = i_rf_wen && index[5:0] == i_rf_wr_addr_b;
    match_source[12]  = i_rf_wen && index[5:0] == i_rf_wr_addr_a;
    match_source[13]  = pending[2];
    match_source[14]  = pending[1];
    match_source[15]  = pending[0];
    select_source[0]  = match_source[0];
    for (int source_no = 1; source_no < 16; source_no++) begin
      select_source[source_no] = match_source[source_no] &&
                        !(|(match_source & ((16'b1 << source_no) - 16'b1)));
    end

    selected[0] = index[31:0] & {32{select_source[0]}};
    // RAZ contributes zero but still suppresses every lower-priority source.
    selected[1] = 32'd0;
    selected[2] = pc_plus_8_ff & {32{select_source[2]}};
    selected[3] = cpu_mode & {32{select_source[3]}};
    selected[4] = alu_destination_value_nxt & {32{select_source[4]}};
    selected[5] = alu_destination_value_ff & {32{select_source[5]}};
    selected[6] = postalu0_destination_value_ff & {32{select_source[6]}};
    selected[7] = postalu1_destination_value_ff & {32{select_source[7]}};
    selected[8] = postalu_destination_value_ff & {32{select_source[8]}};
    selected[9] = memory_destination_value_ff & {32{select_source[9]}};
    selected[10] = i_rf_wr_data_c & {32{select_source[10]}};
    selected[11] = i_rf_wr_data_b & {32{select_source[11]}};
    selected[12] = i_rf_wr_data_a & {32{select_source[12]}};
    selected[13] = operand_commit_c & {32{select_source[13]}};
    selected[14] = operand_commit_b & {32{select_source[14]}};
    selected[15] = operand_commit_a & {32{select_source[15]}};
    get = (rf_data & {32{!(|match_source)}}) |
              (((selected[0] | selected[1]) | (selected[2] | selected[3])) |
               ((selected[4] | selected[5]) | (selected[6] | selected[7]))) |
              (((selected[8] | selected[9]) | (selected[10] | selected[11])) |
               ((selected[12] | selected[13]) | (selected[14] | selected[15])));

    // If it's not a store or load, then align this to 4 bytes. Use
    // owned packet controls.
    get_register_value = !operand_mem_load_ff  &&
                             !operand_mem_store_ff &&
                             force32_align_ff   ? (get & 32'hffff_fffc) : get;

  endfunction : get_register_value

endmodule : zap_issue_main

// ----------------------------------------------------------------------------
// END OF FILE
// ----------------------------------------------------------------------------
