`timescale 1ns / 1ps

module recovery_tb;
  localparam [31:0] BRANCH = 32'h0010_0130;
  reg clk, reset, redirect, thumb = 1, fall_repair, ram_hit = 1, barrier;
  reg clear_predictor, ack = 1, err, retry, pending, fill_done, fill_fault;
  reg update, ready = 1;
  reg [31:0] update_pc = BRANCH, update_target = 32'h0010_01c1;
  reg [ 1:0] update_kind = 0;
  reg [31:0] target = BRANCH;
  reg [ 1:0] action;
  reg [15:0] high = 16'h2407;
  wire [31:0] req_addr, check_addr, next_addr, pc, word;
  wire [31:0] data = req_addr[31:2] == BRANCH[31:2] ? {high, 16'hd044} : 32'h20212020;
  wire valid, fault, predicted, hit;
  wire [2:0] pointer;
  wire [3:0] count;
  wire request;

  ngage2_arm9v2_fetch dut (
      .i_clk(clk),
      .i_reset(reset),
      .i_redirect(redirect),
      .i_redirect_thumb(thumb),
      .i_redirect_target(target),
      .i_redirect_pointer(3'd3),
      .i_redirect_count(4'd3),
      .i_redirect_action(action),
      .i_redirect_link(32'h7789),
      .i_predictor_clear(clear_predictor),
      .i_update(update),
      .i_update_pc(update_pc),
      .i_update_target(update_target),
      .i_update_thumb(1'b1),
      .i_update_taken(1'b1),
      .i_update_hit(1'b1),
      .i_update_state(2'd3),
      .i_update_kind(update_kind),
      .i_data(data),
      .i_ack(ack),
      .i_error(err),
      .i_retry(retry),
      .i_fill_pending(pending),
      .i_fill_done(fill_done),
      .i_fill_fault(fill_fault),
      .i_ready(ready),
      .i_thumb_fall_repair(fall_repair),
      .i_fetch_cached(ram_hit),
      .i_recovery_barrier(barrier),
      .o_address_nxt(next_addr),
      .o_address_check(check_addr),
      .o_address(req_addr),
      .o_request(request),
      .o_stall(),
      .o_dbg_fetch(),
      .o_valid(valid),
      .o_pc(pc),
      .o_word(word),
      .o_thumb(),
      .o_fault(fault),
      .o_predicted(predicted),
      .o_pred_hit(hit),
      .o_pred_target(),
      .o_pred_state(),
      .o_pred_kind(),
      .o_ras_pointer(pointer),
      .o_ras_count(count)
  );

  integer cycles, expected_success, expected_reject;

  task tick;
    #1 clk = 1;
    #1 clk = 0;
    #1 cycles++;
  endtask

  task seed(input bit cache, input bit fetch_error, input bit fill_wait, input bit source_retry,
            input bit source_pending_fault, input [15:0] encoding);
    reset = 1;
    redirect = 0;
    fall_repair = 0;
    thumb = 1;
    barrier = 0;
    clear_predictor = 0;
    ack = 1;
    err = 0;
    retry = 0;
    pending = 0;
    fill_done = 0;
    fill_fault = 0;
    update = 0;
    update_pc = BRANCH;
    update_target = 32'h0010_01c1;
    update_kind = 0;
    ready = 1;
    ram_hit = cache;
    action = 0;
    high = encoding;
    tick();
    reset  = 0;
    update = 1;
    tick();
    update   = 0;
    redirect = 1;
    target   = BRANCH;
    tick();
    redirect = 0;
    tick();
    if (req_addr != BRANCH || !dut.f2_prediction[44])
      $fatal(1, "Did not reach the predicted Thumb source address");
    err = fetch_error;
    retry = source_retry;
    pending = fill_wait;
    fill_done = source_pending_fault;
    fill_fault = source_pending_fault;
    tick();
    err = 0;
    retry = 0;
    pending = 0;
    fill_done = 0;
    fill_fault = 0;
  endtask

  task repair(input bit expected, input bit owner = 1, input [31:0] repair_pc = BRANCH + 2);
    target = repair_pc;
    redirect = 1;
    fall_repair = owner;
    #1;
    if (dut.reuse_fall_half !== expected)
      $fatal(1, "Fall-through eligibility mismatch at cycle %0d", cycles);
    if (next_addr !== {repair_pc[31:1], 1'b0} ||
        dut.g_predictor.u_predict.i_pc_redirect !== {repair_pc[31:1], 1'b0})
      $fatal(1, "Recovery changed the ordinary redirect or BTB address");
    tick();
    redirect = 0;
    fall_repair = 0;
    if (expected) begin
      expected_success++;
      if (!valid || fault || pc != BRANCH + 2 || word != {16'd0, high} ||
                predicted || hit || pointer != 3 || count != 3 || check_addr != BRANCH + 2)
        $fatal(1, "Malformed recovered packet");
      tick();
      if (valid && pc == BRANCH + 2) $fatal(1, "Duplicated recovered packet");
      repeat (3) tick();
    end else begin
      expected_reject++;
      if (valid) $fatal(1, "Rejected recovery left a live packet");
    end
  endtask

  task start_recovery_held;
    ready = 0;
    target = BRANCH + 2;
    redirect = 1;
    fall_repair = 1;
    #1;
    if (!dut.reuse_fall_half || next_addr !== BRANCH + 2)
      $fatal(1, "Expected injection on the ordinary upper-half redirect");
    tick();
    redirect = 0;
    fall_repair = 0;
    #1;
    if (!valid || pc != BRANCH + 2 || !dut.duplicate_f1)
      $fatal(1, "Saved instruction or duplicate identity missing");
  endtask

  task duplicate_then_real_fault;
    seed(1, 0, 0, 0, 0, 16'h2407);
    update = 1;
    update_pc = BRANCH + 2;
    update_target = 32'h0010_0901;
    update_kind = 1;
    start_recovery_held();
    update = 0;
    #1;
    if (!dut.prediction[44] || dut.predicted || dut.g_predictor.u_predict.i_accept ||
        next_addr !== BRANCH + 4)
      $fatal(1, "Stale duplicate BTB call steered fetch or consumed RAS");
    tick();
    if (pointer != 3 || count != 3) $fatal(1, "Duplicate changed the RAS");
    ack = 0;
    repeat (3) begin
      tick();
      if (!request || !dut.duplicate_response || req_addr != BRANCH + 2 ||
          !valid || pc != BRANCH + 2 || word != 32'h2407 || fault)
        $fatal(1, "Held identity or checked packet changed");
    end
    // This response belongs to the redundant access. Its payload and
    // status cannot replace the checked entry, even when the I$ retries.
    ack = 1;
    err = 1;
    retry = 1;
    pending = 1;
    #1;
    if (dut.push || dut.retry) $fatal(1, "Redundant response affected fetch");
    tick();
    err = 0;
    pending = 0;
    ready = 1;
    #1;
    if (dut.duplicate_response || !request || req_addr != BRANCH + 4 || !dut.retry)
      $fatal(1, "Real successor retry did not retain its identity");
    tick();
    retry = 0;
    repeat (2) tick();
    if (!request || req_addr != BRANCH + 4) $fatal(1, "Wrong retry PC");
    err = 1;
    tick();
    err = 0;
    if (!valid || pc != BRANCH + 4 || !fault) $fatal(1, "Lost the real prefetch abort");
    expected_success++;
  endtask

  task redirect_away_from_duplicate;
    seed(1, 0, 0, 0, 0, 16'h2407);
    start_recovery_held();
    tick();
    ack = 0;
    redirect = 1;
    // A fresh owner at the same address must have no duplicate status.
    tick();
    redirect = 0;
    ack = 1;
    ready = 1;
    if (valid || dut.duplicate_f1 || dut.duplicate_f2) $fatal(1, "Killed duplicate leaked epoch");
    repeat (3) tick();
    if (!request || req_addr != BRANCH + 2 || dut.duplicate_response)
      $fatal(1, "New owner inherited duplicate state");
    err = 1;
    tick();
    err = 0;
    if (!valid || pc != BRANCH + 2 || !fault) $fatal(1, "New owner's abort was suppressed");
    expected_success++;
  endtask

  task reset_with_duplicate;
    seed(1, 0, 0, 0, 0, 16'h2407);
    start_recovery_held();
    tick();
    ack = 0;
    tick();
    if (!dut.duplicate_response || !request) $fatal(1, "No duplicate pending at reset");
    reset = 1;
    tick();
    if (valid || request || dut.duplicate_f1 || dut.duplicate_f2)
      $fatal(1, "Reset did not clear the pending duplicate");
    expected_success++;
  endtask

  task full_queue_blocks_recovery;
    seed(1, 0, 0, 0, 0, 16'h2407);
    ready = 0;
    repeat (12) tick();
    if (dut.count != 8 || !dut.saved_fall_valid)
      $fatal(1, "Expected full queue and saved halfword");
    redirect = 1;
    target = BRANCH + 2;
    fall_repair = 1;
    #1;
    if (dut.reuse_fall_half || next_addr !== BRANCH + 2)
      $fatal(1, "Full queue changed redirect or admitted recovery");
    tick();
    if (valid || dut.duplicate_f1 || dut.duplicate_f2)
      $fatal(1, "Blocked redirect inserted a packet");
    redirect = 0;
    fall_repair = 0;
    expected_reject++;
  endtask

  initial begin
    seed(1, 0, 0, 0, 0, 16'h2407);
    repair(1);
    seed(1, 0, 0, 0, 0, 16'h6000);
    repair(1);
    // A busy decoder can keep the injected packet as the real
    // queue head while the corrected stream fills RAM behind it.
    seed(1, 0, 0, 0, 0, 16'h2407);
    ready = 0;
    target = BRANCH + 2;
    redirect = 1;
    fall_repair = 1;
    #1;
    if (!dut.reuse_fall_half) $fatal(1, "Missing held decoder recovery");
    tick();
    redirect = 0;
    fall_repair = 0;
    repeat (12) begin
      tick();
      if (!valid || pc != BRANCH + 2 || word != 32'h00002407 || fault)
        $fatal(1, "Backpressure changed salvaged head");
    end
    if (dut.count != 8) $fatal(1, "Recovery left wrong queue capacity");
    ready = 1;
    tick();
    if (!valid || pc != BRANCH + 4) $fatal(1, "Wrong queued successor after recovery");
    expected_success++;
    duplicate_then_real_fault();
    redirect_away_from_duplicate();
    reset_with_duplicate();
    full_queue_blocks_recovery();
    seed(0, 0, 0, 0, 0, 16'h2407);
    repair(0);
    seed(1, 1, 0, 0, 0, 16'h2407);
    repair(0);
    seed(1, 0, 1, 0, 0, 16'h2407);
    repair(0);
    seed(1, 0, 0, 1, 0, 16'h2407);
    repair(0);
    seed(1, 0, 1, 0, 1, 16'h2407);
    repair(0);
    seed(1, 0, 0, 0, 0, 16'hbd00);
    repair(0);
    seed(1, 0, 0, 0, 0, 16'h4700);
    repair(0);
    seed(1, 0, 0, 0, 0, 16'hf800);
    repair(0);
    seed(1, 0, 0, 0, 0, 16'h2407);
    clear_predictor = 1;
    repair(0);
    seed(1, 0, 0, 0, 0, 16'h2407);
    barrier = 1;
    repair(0);
    seed(1, 0, 0, 0, 0, 16'h2407);
    barrier = 1;
    tick();
    barrier = 0;
    repair(0);
    seed(1, 0, 0, 0, 0, 16'h2407);
    action = 2'd1;
    repair(0);
    seed(1, 0, 0, 0, 0, 16'h2407);
    thumb = 0;
    repair(0);
    seed(1, 0, 0, 0, 0, 16'h2407);
    ack = 0;
    repair(0);
    seed(1, 0, 0, 0, 0, 16'h2407);
    repair(0, 0);
    seed(1, 0, 0, 0, 0, 16'h2407);
    repair(0, 1, BRANCH + 6);
    seed(1, 0, 0, 0, 0, 16'h2407);
    repair(0, 1, BRANCH);
    seed(1, 0, 0, 0, 0, 16'h2407);
    reset = 1;
    repair(0);
    seed(1, 0, 0, 0, 0, 16'h2407);
    redirect = 1;
    repeat (5) begin
      target += 32'h100;
      tick();
    end
    redirect = 0;
    repair(0);
    $display("PASS Thumb recovery cycles=%0d recovered=%0d rejected=%0d", cycles, expected_success,
             expected_reject);
    $finish;
  end
endmodule
