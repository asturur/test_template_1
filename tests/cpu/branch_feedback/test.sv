`timescale 1ns / 1ps
module test;
  reg clk = 0, reset = 1, stall = 0, clear = 0;
  reg valid = 0, ok = 0, nok = 0;
  reg [31:0] source = 0, target = 0, address = 0;
  reg [1:0] state = 2'b11;
  wire predicted;
  wire [31:0] predicted_pc;
  wire [1:0] predicted_state;
  integer checks = 0;
  always #5 clk = ~clk;
  zap_btb #(
      .BP_ENTRIES(16)
  ) dut (
      .i_clk(clk),
      .i_reset(reset),
      .i_stall(stall),
      .i_clear(clear),
      .i_fb_valid(valid),
      .i_fb_ok(ok),
      .i_fb_nok(nok),
      .i_fb_branch_src_address(source),
      .i_fb_branch_dest_address(target),
      .i_fb_current_branch_state(state),
      .i_rd_addr(address),
      .i_rd_addr_del(address),
      .o_clear_from_btb(predicted),
      .o_pc_from_btb(predicted_pc),
      .o_branch_state(predicted_state)
  );
  task tick;
    begin
      @(posedge clk);
      #1;
      @(negedge clk);
    end
  endtask
  task train(input [31:0] src, input [31:0] dst, input [1:0] old_state, input correct);
    begin
      source = src;
      target = dst;
      state = old_state;
      valid = 1;
      ok = correct;
      nok = !correct;
      tick();
      valid = 0;
      ok = 0;
      nok = 0;
    end
  endtask
  task lookup(input [31:0] src, input taken, input [31:0] dst);
    begin
      address = src;
      repeat (3) tick();
      if (predicted !== taken || (taken && predicted_pc !== dst))
        $fatal(
            1,
            "lookup %h got taken=%b target=%h expected=%b/%h",
            src,
            predicted,
            predicted_pc,
            taken,
            dst
        );
      checks = checks + 1;
    end
  endtask
  initial begin
    tick();
    reset = 0;
    lookup(32'h1000, 0, 0);
    train(32'h1000, 32'h2000, 2'b11, 1);
    lookup(32'h1000, 1, 32'h2000);
    // No feedback, even with a stale/aliased address, must retain state.
    source = 32'h1020;
    repeat (8) tick();
    lookup(32'h1000, 1, 32'h2000);
    // Unowned stale branch strobes may not update predictor RAM either.
    source = 32'h1000;
    target = 32'hdead0000;
    nok = 1;
    repeat (3) tick();
    nok = 0;
    lookup(32'h1000, 1, 32'h2000);
    // Instruction fetch hold does not prevent independent ALU feedback.
    stall = 1;
    train(32'h1000, 32'h3000, 2'b11, 1);
    stall = 0;
    lookup(32'h1000, 1, 32'h3000);
    // A failed conditional branch still owns feedback: WT -> WNT.
    train(32'h1000, 32'h1004, 2'b10, 0);
    lookup(32'h1000, 0, 0);
    if (predicted_state !== 2'b01) $fatal(1, "failed condition lost feedback");
    // A real nonbranch invalidates a stale aliased branch entry.
    train(32'h1000, 32'h2000, 2'b11, 1);
    valid  = 1;
    source = 32'h1020;
    tick();
    valid = 0;
    lookup(32'h1000, 0, 0);
    train(32'h1020, 32'h4000, 2'b11, 1);
    lookup(32'h1000, 0, 0);
    lookup(32'h1020, 1, 32'h4000);
    // Clear must win with held fetch and simultaneous owned training.
    stall = 1;
    clear = 1;
    valid = 1;
    ok = 1;
    tick();
    clear = 0;
    valid = 0;
    ok = 0;
    stall = 0;
    lookup(32'h1020, 0, 0);
    train(32'h1000, 32'h2000, 2'b11, 1);
    reset = 1;
    stall = 1;
    valid = 1;
    ok = 1;
    tick();
    reset = 0;
    stall = 0;
    valid = 0;
    ok = 0;
    lookup(32'h1000, 0, 0);
    $display(
        "PASS branch feedback: %0d lookups, bubbles, aliases, failed condition, fetch hold, clear/reset",
        checks);
    $finish;
  end
endmodule
