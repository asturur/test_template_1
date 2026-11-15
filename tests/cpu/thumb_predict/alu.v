`timescale 1ns / 1ps
module test;
  reg clk = 0, reset = 1, clear = 0, hold_data = 0, irq = 0, fiq = 0, abort_tag = 0, fault = 0;
  reg [31:0] cpsr = 32'h33, target = 32'h2469, predicted = 32'h2468;
  reg [31:0] left = 0, saved_psr = 32'h13;
  reg [4:0] operation = 13;
  reg exchange = 1, restore = 0;
  wire [31:0] observed_flags;
  reg  [ 3:0] condition = 14;
  reg  [ 1:0] taken = 3;
  wire owner, dav, confirm, redirect;
  wire [31:0] pc;
  integer checks = 0;
  always #5 clk = ~clk;
  zap_alu_main #(
      .CPSR_INIT(32'h13)
  ) dut (
      .i_decompile('0),
      .i_uop_last('0),
      .i_swp_tag('0),
      .i_clk(clk),
      .i_reset(reset),
      .i_clear_from_writeback(clear),
      .i_data_stall(hold_data),
      .i_cpu_pid('0),
      .i_cpsr_nxt(cpsr),
      .i_switch_ff(exchange),
      .i_taken_ff(taken),
      .i_ppc_ff(predicted),
      .i_pc_ff(32'h1000),
      .i_nozero_ff('0),
      .i_alu_source_value_ff(left),
      .i_shifted_source_value_ff(target),
      .i_shift_carry_ff('0),
      .i_shift_sat_ff('0),
      .i_pc_plus_8_ff(32'h1008),
      .i_condition_code_ff(condition),
      .i_destination_index_ff(6'd15),
      .i_alu_operation_ff(operation),
      .i_flag_update_ff(restore),
      .i_abt_ff(abort_tag),
      .i_irq_ff(irq),
      .i_fiq_ff(fiq),
      .i_swi_ff('0),
      .i_und_ff('0),
      .i_data_mem_fault(fault),
      .i_mem_srcdest_value_ff(saved_psr),
      .i_mem_srcdest_index_ff('0),
      .i_mem_load_ff('0),
      .i_mem_store_ff('0),
      .i_mem_pre_index_ff('0),
      .i_mem_unsigned_byte_enable_ff('0),
      .i_mem_signed_byte_enable_ff('0),
      .i_mem_signed_halfword_enable_ff('0),
      .i_mem_unsigned_halfword_enable_ff('0),
      .i_mem_translate_ff('0),
      .i_force32align_ff('0),
      .o_flags_ff(observed_flags),
      .o_feedback_valid_ff(owner),
      .o_dav_ff(dav),
      .o_confirm_from_alu(confirm),
      .o_clear_from_alu(redirect),
      .o_pc_from_alu(pc)
  );
  task tick;
    begin
      @(posedge clk);
      #1;
      @(negedge clk);
    end
  endtask
  // Golden control uses the address selected by writeback: PC[0] is zero.
  // BX's raw bit remains a separate input to the architectural T-state check.
  task trial(input [31:0] flags, input [31:0] raw, input [31:0] prediction, input [4:0] op,
             input [31:0] lhs, input bx, input restore_psr, input [3:0] cc, input [1:0] state);
    reg [31:0] result, expected_pc, expected_flags;
    reg passed, expected_redirect, expected_confirm;
    begin
      cpsr = flags;
      clear = 1;
      hold_data = 0;
      tick();
      clear = 0;
      target = raw;
      predicted = prediction;
      operation = op;
      left = lhs;
      exchange = bx;
      restore = restore_psr;
      condition = cc;
      taken = state;
      result = op == 4 ? lhs + raw : raw;
      passed = cc == 14 || (cc == 0 && flags[30]);
      expected_flags = flags;
      expected_redirect = 0;
      expected_pc = {result[31:1], 1'b0};
      if (passed) begin
        if (restore_psr) begin
          expected_redirect = 1;
          expected_flags = saved_psr;
        end else begin
          if (bx) expected_flags[5] = result[0];
          expected_redirect = (bx && result[0] != flags[5]) ||
                              !state[1] || ((prediction >> 1) != (result >> 1));
        end
      end else if (state[1]) begin
        expected_redirect = 1;
        expected_pc = flags[5] ? 32'h1002 : 32'h1004;
      end
      expected_confirm = !expected_redirect;
      tick();
      if (owner !== 1'b1 || dav !== passed || redirect !== expected_redirect ||
          confirm !== expected_confirm || pc !== expected_pc ||
          observed_flags !== expected_flags)
        $fatal(
            1,
            "prediction address flags=%h raw=%h pred=%h op=%d BX=%b S=%b CC=%d state=%d owner=%b dav=%b clear=%b/%b pc=%h/%h flags=%h/%h",
            flags,
            raw,
            prediction,
            op,
            bx,
            restore_psr,
            cc,
            state,
            owner,
            dav,
            redirect,
            expected_redirect,
            pc,
            expected_pc,
            observed_flags,
            expected_flags
        );
      checks = checks + 1;
    end
  endtask
  integer mode, low, difference, state, op, conditional;
  reg [31:0] flags, raw, prediction, lhs;
  initial begin
    tick();
    reset = 0;
    // First case reproduces the original warmed Thumb BX LR false redirect.
    trial(32'h33, 32'h505a9e47, 32'h505a9e46, 13, 0, 1, 0, 14, 3);
    for (mode = 0; mode < 2; mode = mode + 1)
    for (low = 0; low < 2; low = low + 1)
    for (difference = 0; difference < 4; difference = difference + 1)
    for (state = 0; state < 4; state = state + 1)
    for (op = 0; op < 2; op = op + 1)
    for (conditional = 0; conditional < 3; conditional = conditional + 1) begin
      flags = 32'h20000013 | (mode << 5) | ((conditional == 2) << 30);
      lhs = op ? 32'h0100 : 0;
      raw = 32'h81234560 | low;
      prediction = (raw + lhs) ^ difference;
      trial(flags, raw, prediction, op ? 4 : 13, lhs, 0, 0, conditional == 0 ? 14 : 0, state);
      trial(flags, raw, prediction, op ? 4 : 13, lhs, 1, 0, conditional == 0 ? 14 : 0, state);
    end
    // Exception returns still restore CPSR and redirect even on a target match.
    saved_psr = 32'h60000033;
    trial(32'h13, 32'h80000001, 32'h80000000, 13, 0, 0, 1, 14, 3);
    saved_psr = 32'ha0000013;
    trial(32'h33, 32'h80000003, 32'h80000002, 13, 0, 0, 1, 14, 3);
    // Address addition wraps, without changing the raw exchange mode bit.
    trial(32'h33, 32'hffffffff, 0, 4, 2, 1, 0, 14, 3);
    trial(32'h13, 32'h80000000, 32'h80000000, 13, 0, 1, 0, 14, 3);
    $display("PASS Thumb prediction: %0d address/state/condition/restore cases", checks);
    $finish;
  end
endmodule
