`timescale 1ns / 1ps
module test;
  `include "zap_defines.svh"
  `include "zap_localparams.svh"
  reg clk = 0, reset = 1, valid = 0, irq = 0, fiq = 0;
  reg data_hold = 0, issue_hold = 0, shift_hold = 0, wb_clear = 0, alu_clear = 0, decode_clear = 0;
  reg  [34:0] instruction = 0;
  wire [39:0] uop;
  wire uvalid, align_word, switch_mode, fetch_hold, irq_out, fiq_out, last;
  wire [1:0] swp;
  wire [4:0] destination, memory_reg;
  wire [32:0] source, shift_source, shift_length;
  wire [5:0] operation;
  wire [3:0] condition_code;
  wire memory_load, memory_store, pre_index, force_user;
  reg [31:0] regs[0:31], expected[0:31], got_address[0:15], got_store[0:15];
  reg [4:0] got_reg[0:15];
  integer sequences = 0, transfers = 0, n, k, m, r, mode, b, received, cycles, ends;
  integer count, target, shortened, expected_cycles;
  reg [31:0] original_base, first_address, effective, left, right, value, result;
  reg [15:0] list_bits;
  reg pass_condition;
  always #5 clk = ~clk;
  zap_predecode_uop_sequencer dut (
      .i_clk(clk),
      .i_reset(reset),
      .i_instruction(instruction),
      .i_instruction_valid(valid),
      .i_irq(irq),
      .i_fiq(fiq),
      .i_cpsr_t(1'b0),
      .i_l4_enable(1'b0),
      .i_clear_from_writeback(wb_clear),
      .i_data_stall(data_hold),
      .i_clear_from_alu(alu_clear),
      .i_stall_from_shifter(shift_hold),
      .i_issue_stall(issue_hold),
      .i_clear_from_decode(decode_clear),
      .o_instruction(uop),
      .o_instruction_valid(uvalid),
      .o_align(align_word),
      .o_switch(switch_mode),
      .o_stall_from_decode(fetch_hold),
      .o_irq(irq_out),
      .o_fiq(fiq_out),
      .o_uop_last(last),
      .o_swp_tag(swp)
  );
  zap_decode decoder (
      .i_irq(irq_out),
      .i_fiq(fiq_out),
      .i_abt(1'b0),
      .i_instruction(uop[35:0]),
      .i_instruction_valid(uvalid),
      .o_condition_code(condition_code),
      .o_destination_index(destination),
      .o_alu_source(source),
      .o_alu_operation(operation),
      .o_shift_source(shift_source),
      .o_shift_length(shift_length),
      .o_mem_srcdest_index(memory_reg),
      .o_mem_load(memory_load),
      .o_mem_store(memory_store),
      .o_mem_pre_index(pre_index),
      .o_mem_translate(force_user)
  );
  task tick;
    begin
      @(posedge clk);
      #1;
      @(negedge clk);
      #1;
    end
  endtask
  function [31:0] memory_value(input [31:0] address);
    memory_value = 32'h5a000000 ^ address;
  endfunction
  task execute_sequence(input [15:0] mask, input up, input before_index, input wb, input load_op,
                        input user_bank, input [3:0] base, input cond_pass);
    integer j, step, saved_sequences;
    reg setup_fused, tail_fused, pc_load, running;
    begin
      count = 0;
      for (j = 0; j < 16; j = j + 1) if (mask[j]) count = count + 1;
      original_base = 32'h80001000;
      for (j = 0; j < 32; j = j + 1) begin
        regs[j] = 32'h11000000 + j * 256;
        expected[j] = regs[j];
      end
      regs[RAZ_REGISTER] = 0;
      expected[RAZ_REGISTER] = 0;
      regs[base] = original_base;
      expected[base] = original_base;
      first_address=up ? original_base+(before_index?4:0) : original_base-count*4+(before_index?0:4);
      target = 0;
      for (j = 0; j < 16; j = j + 1)
      if (mask[j]) begin
        b = user_bank && (!load_op || !mask[15]) && j >= 8 && j <= 14 ? j + 10 : j;
        if (cond_pass && load_op) expected[b] = memory_value(first_address + target * 4);
        target = target + 1;
      end
      if (cond_pass && wb)
        expected[base] = up ? original_base + count * 4 : original_base - count * 4;
      instruction = {3'b0, 4'he, 3'b100, before_index, up, user_bank, wb, load_op, base, mask};
      // NE is false in this abstract execution model. The uop conditions
      // must remain intact even when the entire block is skipped.
      if (!cond_pass) instruction[31:28] = 4'h1;
      pass_condition = cond_pass;
      valid = 1;
      received = 0;
      cycles = 0;
      ends = 0;
      #1;
      setup_fused = !user_bank && base != 15 && mask != 0 && (!wb || !mask[base]);
      tail_fused = !user_bank && base != 15 && (!wb || (up && !mask[base]));
      pc_load = load_op && mask[15];
      expected_cycles = count + 2 + pc_load - setup_fused - tail_fused;
      running = 1;
      while (cycles < 25 && running) begin
        if (!uvalid || swp != 0 || (uop[31:0] != 0 && condition_code != (cond_pass ? 4'he : 4'h1)))
          $fatal(1, "invalid block uop or condition mask=%h cycles=%0d", mask, cycles);
        if (last) ends = ends + 1;
        if (irq_out || fiq_out) $fatal(1, "unexpected interrupt");
        left  = source[32] == IMMED_EN ? source[31:0] : regs[source[4:0]];
        right = shift_source[32] == IMMED_EN ? shift_source[31:0] : regs[shift_source[4:0]];
        case (operation)
          ADD: result = left + right;
          SUB: result = left - right;
          MOV: result = right;
          AND: result = left & right;
          default: $fatal(1, "unexpected uop operation=%d", operation);
        endcase
        if (memory_load || memory_store) begin
          if (force_user) $fatal(1, "block transfer changed memory privilege");
          if (!align_word) $fatal(1, "lost block word alignment");
          effective = pre_index ? result : left;
          if (pass_condition && effective !== first_address + received * 4)
            $fatal(
                1,
                "wrong address mask=%h mode=%b%b%b%b step=%0d got=%h want=%h",
                mask,
                up,
                before_index,
                wb,
                load_op,
                received,
                effective,
                first_address + received * 4
            );
          got_address[received] = effective;
          got_reg[received] = memory_reg;
          got_store[received] = regs[memory_reg];
          if (pass_condition && memory_store) begin
            target = 0;
            for (j = 0; j < 16; j = j + 1)
            if (mask[j]) begin
              if (target == received) begin
                b = user_bank && j >= 8 && j <= 14 ? j + 10 : j;
                if (memory_reg != b || regs[memory_reg] !== expected[b])
                  $fatal(1, "wrong store data/register");
              end
              target = target + 1;
            end
          end
          if (pass_condition && destination != RAZ_REGISTER) regs[destination] = result;
          if (pass_condition && memory_load) regs[memory_reg] = memory_value(effective);
          received = received + 1;
        end else if (pass_condition && destination != RAZ_REGISTER) regs[destination] = result;
        cycles = cycles + 1;
        tick();
        if (dut.state_ff == dut.IDLE) running = 0;
      end
      valid = 0;
      #1;
      if (received != count || cycles != expected_cycles || ends != 1)
        $fatal(
            1,
            "wrong sequence length mask=%h mode=%b%b%b%b user=%b base=%0d got=%0d expected=%0d beats=%0d ends=%0d",
            mask,
            up,
            before_index,
            wb,
            load_op,
            user_bank,
            base,
            cycles,
            expected_cycles,
            received,
            ends
        );
      if (pass_condition)
        for (j = 0; j < 25; j = j + 1)
        if (j != RAZ_REGISTER && j != ARCH_CPSR && regs[j] !== expected[j])
          $fatal(
              1,
              "wrong architectural register r%0d mask=%h mode=%b%b%b%b got=%h want=%h",
              j,
              mask,
              up,
              before_index,
              wb,
              load_op,
              regs[j],
              expected[j]
          );
      sequences = sequences + 1;
      transfers = transfers + received;
    end
  endtask
  integer held_checks = 0, interrupt_checks = 0, cancel_checks = 0;
  task check_holds_and_interrupts;
    integer kind, phase, cancel_kind;
    reg [39:0] held_uop;
    reg [7:0] held_state;
    reg [15:0] held_list;
    reg held_last;
    begin
      // Exercise first fused beat, later memory beats, and POP-to-PC.
      for (kind = 0; kind < 3; kind = kind + 1) begin
        instruction = {3'b0, 32'he8bd8003};
        valid = 1;
        #1;
        for (phase = 0; phase < 3; phase = phase + 1) begin
          held_uop   = uop;
          held_state = dut.state_ff;
          held_list  = dut.reglist_ff;
          held_last  = last;
          case (kind)
            0: data_hold = 1;
            1: issue_hold = 1;
            2: shift_hold = 1;
          endcase
          repeat (2) begin
            tick();
            if(uop!==held_uop || dut.state_ff!==held_state || dut.reglist_ff!==held_list || last!==held_last)
              $fatal(1, "block ownership moved under hold kind=%0d phase=%0d", kind, phase);
            held_checks = held_checks + 1;
          end
          data_hold  = 0;
          issue_hold = 0;
          shift_hold = 0;
          tick();
        end
        // Drain the PC-copy state without interpreting its data.
        while (dut.state_ff != dut.IDLE) tick();
        valid = 0;
        tick();
      end
      for (kind = 0; kind < 2; kind = kind + 1) begin
        instruction = {3'b0, 32'he8b00006};
        valid = 1;
        if (kind == 0) irq = 1;
        else fiq = 1;
        #1;
        if (irq_out !== irq || fiq_out !== fiq || memory_load || memory_store)
          $fatal(1, "first block beat failed interrupt priority");
        interrupt_checks = interrupt_checks + 1;
        tick();
        while (dut.state_ff != dut.IDLE) begin
          if (irq_out || fiq_out) $fatal(1, "interrupt split an accepted block");
          interrupt_checks = interrupt_checks + 1;
          tick();
        end
        valid = 0;
        irq   = 0;
        fiq   = 0;
        tick();
      end
      for (cancel_kind = 0; cancel_kind < 4; cancel_kind = cancel_kind + 1) begin
        instruction = {3'b0, 32'he8b0000e};
        valid = 1;
        tick();
        if (dut.state_ff == dut.IDLE) $fatal(1, "cancellation fixture did not enter block");
        valid = 0;
        case (cancel_kind)
          0: reset = 1;
          1: wb_clear = 1;
          2: alu_clear = 1;
          3: decode_clear = 1;
        endcase
        tick();
        if (dut.state_ff != dut.IDLE) $fatal(1, "block survived cancellation");
        reset = 0;
        wb_clear = 0;
        alu_clear = 0;
        decode_clear = 0;
        tick();
        if (uvalid || swp != 0) $fatal(1, "cancelled block replayed");
        cancel_checks = cancel_checks + 1;
      end
    end
  endtask
  initial begin
    repeat (3) tick();
    reset = 0;
    // All nonempty lists, all four address modes, both directions and
    // writeback settings. Exclude architecturally unpredictable base/list
    // combinations; base-in-list loads without WB remain covered.
    for (m = 1; m < 65536; m = m + 1)
    for (mode = 0; mode < 16; mode = mode + 1)
    if (!mode[1] || !m[13]) execute_sequence(m[15:0], mode[3], mode[2], mode[1], mode[0], 0, 13, 1);
    for (r = 0; r < 15; r = r + 1)
    for (mode = 0; mode < 16; mode = mode + 1) begin
      list_bits = 16'h91a5 & ~(16'd1 << r);
      execute_sequence(list_bits, mode[3], mode[2], mode[1], mode[0], 0, r, 0);
      execute_sequence(list_bits, mode[3], mode[2], mode[1], mode[0], 1, r, 1);
    end
    check_holds_and_interrupts();
    $display("PASS block holds=%0d interrupt-boundaries=%0d cancellations=%0d", held_checks,
             interrupt_checks, cancel_checks);
    $display(
        "PASS block transfers: %0d sequences, %0d ordered words; every list/mode, base aliases, user banks, PC, conditions and exact uop count",
        sequences, transfers);
    $finish;
  end
  initial begin
    repeat (30000000) @(posedge clk);
    $fatal(1, "timeout");
  end
endmodule
