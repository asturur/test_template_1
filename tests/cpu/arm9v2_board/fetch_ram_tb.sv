`timescale 1ns / 1ps

module fetch_ram_tb;
  reg clk = 0, reset = 1;
  reg ack = 0, error = 0, retry = 0, ready = 0;
  reg fill_pending = 0, fill_done = 0, fill_fault = 0;
  reg redirect = 0, redirect_thumb = 0;
  reg [31:0] redirect_target = 0;
  reg [31:0] data = 0;
  reg update = 0;
  reg [31:0] update_pc = 0, update_target = 0;
  reg update_taken = 0;
  reg [1:0] update_kind = 0;

  wire [102:0] fetch_state[0:1];
  for (genvar leg = 0; leg < 2; leg++) begin : g_fetch
    ngage2_arm9v2_fetch #(
        .BRAM_QUEUE(leg == 1)
    ) dut (
        .i_clk(clk),
        .i_reset(reset),
        .i_redirect(redirect),
        .i_redirect_thumb(redirect_thumb),
        .i_redirect_target(redirect_target),
        .i_redirect_pointer(3'd0),
        .i_redirect_count(4'd0),
        .i_redirect_action(2'd0),
        .i_redirect_link(32'd0),
        .i_predictor_clear(1'b0),
        .i_update(update),
        .i_update_pc(update_pc),
        .i_update_target(update_target),
        .i_update_thumb(redirect_thumb),
        .i_update_taken(update_taken),
        .i_update_hit(1'b0),
        .i_update_state(2'd1),
        .i_update_kind(update_kind),
        .i_data(data),
        .i_ack(ack),
        .i_error(error),
        .i_retry(retry),
        .i_fill_pending(fill_pending),
        .i_fill_done(fill_done),
        .i_fill_fault(fill_fault),
        .i_ready(ready),
        .o_address_nxt(fetch_state[leg][102:71]),
        .o_address_check(fetch_state[leg][70:39]),
        .o_address(fetch_state[leg][38:7]),
        .o_request(fetch_state[leg][6]),
        .o_stall(fetch_state[leg][5]),
        .o_dbg_fetch(fetch_state[leg][4:3]),
        .o_valid(fetch_state[leg][2]),
        .o_thumb(fetch_state[leg][1]),
        .o_fault(fetch_state[leg][0])
    );
  end

  integer cycles = 0;
  integer empty_pushes = 0, one_entry_turns = 0, full_stalls = 0, wrapped_pushes = 0;
  integer bypassed_reads = 0, fault_responses = 0, fills = 0;
  integer redirect_stalls = 0, retry_responses = 0;
  wire [3:0] count = g_fetch[1].dut.count;
  wire push = g_fetch[1].dut.push;
  wire pop = g_fetch[1].dut.pop;
  always @(posedge clk) begin
    cycles <= cycles + 1;
    if (!reset) begin
      // The word and metadata are architecturally visible only while
      // owned. Include a pending head in the comparison before it can pop.
      if (fetch_state[0][102:2] !== fetch_state[1][102:2] ||
          {g_fetch[0].dut.count, g_fetch[0].dut.push, g_fetch[0].dut.pop} !==
          {count, push, pop})
        $fatal(1, "Fetch request, admission or dequeue changed at cycle %0d", cycles);
      if (count != 0 && g_fetch[0].dut.head_packet !== g_fetch[1].dut.head_packet)
        $fatal(1, "Owned fetch packet changed at cycle %0d", cycles);
      if (count == 0 && push) empty_pushes <= empty_pushes + 1;
      if (count == 1 && push && pop) one_entry_turns <= one_entry_turns + 1;
      if (count == 8 && !ready) full_stalls <= full_stalls + 1;
      if (push && g_fetch[1].dut.tail == 7) wrapped_pushes <= wrapped_pushes + 1;
      if (g_fetch[1].dut.g_fetch_ram.bypass_prefetch && count > 1)
        bypassed_reads <= bypassed_reads + 1;
      if (pop && fetch_state[1][0]) fault_responses <= fault_responses + 1;
      if (fill_done && count > 1) fills <= fills + 1;
      if (redirect && fetch_state[1][5]) redirect_stalls <= redirect_stalls + 1;
      if (g_fetch[1].dut.retry) retry_responses <= retry_responses + 1;
    end
  end

  task step;
    data = data + 32'h01011001;
    #1 clk = 1;
    #1 clk = 0;
    #1;
  endtask

  task empty_queue;
    ack   = 0;
    ready = 1;
    repeat (12) step();
    if (count != 0) $fatal(1, "Queue did not drain");
  endtask

  task redirect_to(input logic thumb, input logic [31:0] target);
    redirect = 1;
    redirect_thumb = thumb;
    redirect_target = target;
    step();
    redirect = 0;
    if (count != 0) $fatal(1, "Redirect left old queue entries visible");
  endtask

  reg [31:0] pattern = 32'h7ae128fd;
  initial begin
    step();
    reset = 0;
    ack   = 1;
    ready = 0;
    repeat (56) step();
    if (count != 8) $fatal(1, "Fetch queue capacity changed");
    ready = 1;
    repeat (96) step();

    // Sustained turns with one and two entries exercise both bypass paths.
    empty_queue();
    ack = 1;
    repeat (36) step();
    if (count != 1) $fatal(1, "One-entry fall-through changed cadence");
    ready = 0;
    step();
    ready = 1;
    repeat (48) step();
    if (count != 2) $fatal(1, "Concurrent pop/push changed cadence");

    // Broadcast fill completion to several pending heads, including
    // a new push on the same edge, then consume all faulted packets.
    empty_queue();
    fill_pending = 1;
    ready = 0;
    ack = 1;
    repeat (4) step();
    fill_done  = 1;
    fill_fault = 1;
    step();
    fill_pending = 0;
    fill_done = 0;
    fill_fault = 0;
    empty_queue();

    // Wrap the fetch epoch repeatedly while an old F2 response is stalled.
    ack = 0;
    repeat (7) begin
      redirect_to(1, 32'h0a008002 + 4 * cycles);
      repeat (3) step();
    end
    ack = 1;
    repeat (4) step();
    retry = 1;
    step();
    retry = 0;

    // Deterministic ARM/Thumb, predictor and bus activity with variable
    // consumer and cache stalls. Redirect and retry remain order-sensitive.
    repeat (8192) begin
      pattern = {pattern[30:0], pattern[31] ^ pattern[21] ^ pattern[1] ^ pattern[0]};
      ack = |pattern[1:0];
      ready = &pattern[4:2] || pattern[19];
      retry = &pattern[9:5];
      error = &pattern[14:10];
      redirect = &pattern[20:15];
      redirect_thumb = pattern[22];
      redirect_target = {pattern[31:1], 1'b0};
      fill_pending = pattern[27];
      fill_done = &pattern[26:23];
      fill_fault = pattern[28];
      update = &pattern[31:29];
      update_pc = fetch_state[0][38:7];
      update_target = {pattern[30:0], redirect_thumb};
      update_taken = pattern[22];
      update_kind = pattern[11:10];
      step();
    end

    if (empty_pushes == 0 || one_entry_turns < 30 || full_stalls < 40 || wrapped_pushes < 16 ||
        bypassed_reads < 32 || fills == 0 || fault_responses < 4 ||
        redirect_stalls < 7 || retry_responses == 0)
      $fatal(1, "Missing fetch queue coverage");
    $display(
        "PASS fetch RAM equivalence cycles=%0d empty=%0d turns=%0d full=%0d wraps=%0d bypass=%0d fills=%0d faults=%0d redirect_stalls=%0d retries=%0d",
        cycles, empty_pushes, one_entry_turns, full_stalls, wrapped_pushes, bypassed_reads, fills,
        fault_responses, redirect_stalls, retry_responses);
    $finish;
  end
endmodule
