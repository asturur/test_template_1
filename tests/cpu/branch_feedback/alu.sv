`timescale 1ns / 1ps
module test;
  reg clk = 0, reset = 1, clear = 0, hold_data = 0, irq = 0, fiq = 0, abort_tag = 0, fault = 0;
  reg [31:0] cpsr = 32'h13, target = 32'h2468;
  reg [3:0] condition = 14;
  reg [1:0] taken = 3;
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
      .i_switch_ff('0),
      .i_taken_ff(taken),
      .i_ppc_ff(target),
      .i_pc_ff(32'h1000),
      .i_nozero_ff('0),
      .i_alu_source_value_ff('0),
      .i_shifted_source_value_ff(target),
      .i_shift_carry_ff('0),
      .i_shift_sat_ff('0),
      .i_pc_plus_8_ff(32'h1008),
      .i_condition_code_ff(condition),
      .i_destination_index_ff(6'd15),
      .i_alu_operation_ff(5'd13),
      .i_flag_update_ff('0),
      .i_abt_ff(abort_tag),
      .i_irq_ff(irq),
      .i_fiq_ff(fiq),
      .i_swi_ff('0),
      .i_und_ff('0),
      .i_data_mem_fault(fault),
      .i_mem_srcdest_value_ff('0),
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
  task check(input own, input result_valid, input correct, input redir, input [31:0] dest);
    begin
      if(owner!==own || dav!==result_valid || confirm!==correct || redirect!==redir ||
               ((correct || redir) && pc!==dest))
        $fatal(
            1,
            "ALU feedback owner=%b dav=%b confirm=%b redirect=%b target=%h expected=%h",
            owner,
            dav,
            confirm,
            redirect,
            pc,
            dest
        );
      checks = checks + 1;
    end
  endtask
  initial begin
    tick();
    reset = 0;
    tick();
    check(1, 1, 1, 0, 32'h2468);
    hold_data = 1;
    target = 32'hdead0000;
    condition = 15;
    repeat (3) begin
      tick();
      check(1, 1, 1, 0, 32'h2468);
    end
    clear = 1;
    tick();
    if (owner !== 0) $fatal(1, "writeback clear lost under hold");
    clear = 0;
    hold_data = 0;
    condition = 0;
    taken = 0;
    target = 32'h1358;
    // EQ fails with Z clear, but this instruction still trains the BTB.
    tick();
    check(1, 0, 1, 0, 32'h1358);
    condition = 0;
    taken = 3;
    tick();
    check(1, 0, 0, 1, 32'h1004);
    condition = 15;
    tick();
    if (owner !== 0) $fatal(1, "redirect flush retained owner");
    tick();
    if (owner !== 0) $fatal(1, "bubble owns feedback");
    condition = 14;
    taken = 3;
    target = 32'h8642;
    tick();
    check(1, 1, 1, 0, 32'h8642);
    fault = 1;
    tick();
    if (owner !== 0) $fatal(1, "data fault retained owner");
    fault = 0;
    clear = 1;
    tick();
    clear = 0;
    irq   = 1;
    tick();
    if (owner !== 0) $fatal(1, "IRQ owns instruction feedback");
    irq   = 0;
    clear = 1;
    tick();
    clear = 0;
    fiq   = 1;
    tick();
    if (owner !== 0) $fatal(1, "FIQ owns instruction feedback");
    fiq   = 0;
    clear = 1;
    tick();
    clear = 0;
    abort_tag = 1;
    tick();
    if (owner !== 0) $fatal(1, "prefetch abort owns instruction feedback");
    reset = 1;
    hold_data = 1;
    tick();
    if (owner !== 0) $fatal(1, "reset under hold retained owner");
    $display("PASS ALU feedback: %0d targets/conditions/holds, fault and exception ownership",
             checks);
    $finish;
  end
endmodule
