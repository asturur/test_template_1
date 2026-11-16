`timescale 1ns / 1ps
module test;
  reg
      clk = 0,
      reset = 1,
      valid = 0,
      data_hold = 0,
      issue_hold = 0,
      shift_hold = 0,
      wb_clear = 0,
      alu_clear = 0,
      thumb = 0;
  reg [34:0] instruction = 0;
  reg [31:0] pc = 0;
  reg [1:0] taken = 0;
  integer checks = 0;
  always #5 clk = ~clk;
  zap_predecode_main #(
      .RAS_DEPTH(4)
  ) dut (
      .i_clk(clk),
      .i_reset(reset),
      .i_l4_enable(1'b0),
      .i_pred(33'd0),
      .i_taken(taken),
      .i_force32(1'b0),
      .i_und(1'b0),
      .i_clear_from_writeback(wb_clear),
      .i_data_stall(data_hold),
      .i_clear_from_alu(alu_clear),
      .i_stall_from_shifter(shift_hold),
      .i_stall_from_issue(issue_hold),
      .i_irq(1'b0),
      .i_fiq(1'b0),
      .i_abt(1'b0),
      .i_pipeline_dav(1'b0),
      .i_copro_done(1'b0),
      .i_wfi_irq(1'b0),
      .i_wfi_fiq(1'b0),
      .i_pc_ff(pc),
      .i_pc_plus_8_ff(pc + (thumb ? 32'd4 : 32'd8)),
      .i_cpu_mode_t(thumb),
      .i_cpu_mode_mode(5'h13),
      .i_instruction(instruction),
      .i_instruction_valid(valid),
      .o_uop_last(),
      .o_swp_tag(),
      .o_clear_btb(),
      .o_instruction_ff(),
      .o_instruction_valid_ff(),
      .o_stall_from_decode(),
      .o_switch_ff(),
      .o_pc_plus_8_ff(),
      .o_pc_ff(),
      .o_ppc_ff(),
      .o_irq_ff(),
      .o_fiq_ff(),
      .o_abt_ff(),
      .o_und_ff(),
      .o_force32align_ff(),
      .o_copro_dav_ff(),
      .o_copro_word_ff(),
      .o_taken_ff(),
      .o_clear_from_decode(),
      .o_pc_from_decode()
  );
  task tick;
    begin
      @(posedge clk);
      #1;
      @(negedge clk);
    end
  endtask
  task drain;
    begin
      valid = 0;
      repeat (3) tick();
    end
  endtask
  task push(input [31:0] addr);
    integer previous;
    begin
      previous = dut.ras_ptr_ff;
      pc = addr;
      instruction = 35'heb000000;
      valid = 1;
      taken = 3;
      #1;
      if (dut.ras_ptr_nxt !== ((previous + 1) % 4)) $fatal(1, "call not pushed");
      tick();
      drain();
      checks = checks + 1;
    end
  endtask
  task returns(input [31:0] opcode, input should_pop, input [31:0] expected_pc,
               input [1:0] prediction);
    integer previous;
    begin
      previous = dut.ras_ptr_ff;
      instruction = {3'd0, opcode};
      valid = 1;
      taken = prediction;
      pc = 32'h9000;
      #1;
      if (dut.ras_ptr_nxt !== (should_pop ? ((previous + 3) % 4) : previous))
        $fatal(
            1,
            "return classification opcode=%h previous=%0d next=%0d",
            opcode,
            previous,
            dut.ras_ptr_nxt
        );
      if (should_pop && dut.w_pc_from_decode !== expected_pc)
        $fatal(
            1,
            "return address opcode=%h got=%h expected=%h",
            opcode,
            dut.w_pc_from_decode,
            expected_pc
        );
      tick();
      drain();
      checks = checks + 1;
    end
  endtask
  integer return_reg;
  task pop_hint(input integer r);
    begin
      reset = 1;
      data_hold = 0;
      issue_hold = 0;
      shift_hold = 0;
      valid = 0;
      tick();
      reset = 0;
      thumb = 1;
      drain();
      push(32'ha000);
      instruction = {3'd0, (32'he8bd0000 | (32'b1 << r))};
      valid = 1;
      pc = 32'hb000;
      repeat (5) tick();
      drain();
      if (!dut.pop_return_valid) $fatal(1, "POP hint not learned r%0d", r);
    end
  endtask
  initial begin
    tick();
    reset = 0;
    drain();
    push(32'h1000);
    push(32'h2000);
    push(32'h3000);
    returns(32'he1a0f00f, 0, 0, 3);  // MOV pc,pc is not a function return.
    returns(32'he1a0f000, 0, 0, 3);  // Nor MOV pc,r0.
    returns(32'he1b0f00e, 0, 0, 3);  // MOVS pc,lr is exception return.
    returns(32'h01a0f00e, 0, 0, 0);  // Conditional return predicted not taken.
    returns(32'h01a0f00e, 1, 32'h3004, 3);
    returns(32'he1a0f00e, 1, 32'h2004, 3);
    returns(32'he12fff1e, 1, 32'h1004, 3);  // BX lr remains supported.
    // Existing circular overflow/underflow behavior is preserved.
    push(32'h4000);
    push(32'h5000);
    push(32'h6000);
    push(32'h7000);
    push(32'h8000);
    returns(32'he1a0f00e, 1, 32'h8004, 3);
    returns(32'he1a0f00e, 1, 32'h7004, 3);
    returns(32'he1a0f00e, 1, 32'h6004, 3);
    returns(32'he1a0f00e, 1, 32'h5004, 3);
    returns(32'he1a0f00e, 1, 32'h8004, 3);
    thumb = 1;
    push(32'ha000);
    returns(32'he1a0f00e, 1, 32'ha002, 3);
    thumb = 0;
    instruction = 35'heb000000;
    pc = 32'hb000;
    valid = 1;
    data_hold = 1;
    repeat (3) tick();
    if (dut.ras_ptr_ff !== 0) $fatal(1, "RAS moved while data held");
    wb_clear = 1;
    tick();
    wb_clear  = 0;
    data_hold = 0;
    drain();
    valid = 1;
    issue_hold = 1;
    repeat (3) tick();
    if (dut.ras_ptr_ff !== 0) $fatal(1, "RAS moved while issue held");
    wb_clear = 1;
    tick();
    wb_clear   = 0;
    issue_hold = 0;
    drain();
    valid = 1;
    shift_hold = 1;
    repeat (3) tick();
    if (dut.ras_ptr_ff !== 0) $fatal(1, "RAS moved while shifter held");
    alu_clear  = 1;
    shift_hold = 0;
    tick();
    alu_clear = 0;
    drain();
    if (dut.ras_ptr_ff !== 0) $fatal(1, "squashed call changed RAS");
    reset = 1;
    data_hold = 1;
    tick();
    if (dut.ras_ptr_ff !== 0 || dut.ras_ff !== 0) $fatal(1, "reset under hold");
    for (return_reg = 0; return_reg < 8; return_reg = return_reg + 1) begin
      pop_hint(return_reg);
      returns(32'he12fff10 | return_reg, 1, 32'ha002, 0);
      pop_hint(return_reg);
      returns(32'he12fff10 | ((return_reg + 1) % 8), 0, 0, 0);
      pop_hint(return_reg);
      instruction = 35'he1a00000;
      valid = 1;
      tick();
      drain();
      returns(32'he12fff10 | return_reg, 0, 0, 0);
      pop_hint(return_reg);
      wb_clear = 1;
      tick();
      wb_clear = 0;
      drain();
      returns(32'he12fff10 | return_reg, 0, 0, 0);
      pop_hint(return_reg);
      alu_clear = 1;
      tick();
      alu_clear = 0;
      drain();
      returns(32'he12fff10 | return_reg, 0, 0, 0);
      pop_hint(return_reg);
      thumb = 0;
      returns(32'he12fff10 | return_reg, 0, 0, 0);
    end
    $display(
        "PASS return predictor: %0d classifications, nested/circular stack, Thumb, holds and clears",
        checks);
    $finish;
  end
endmodule
