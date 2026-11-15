`timescale 1ns / 1ps
// Actual bank, posted buffer and RAM; expected posted packets are independent
// of the cache FSM. No test writes internal cache state to create a shortcut.
module test;
  reg clk = 0, reset = 1;
  always #5 clk = ~clk;
  reg req = 0, wr = 0, ordinary = 1, enabled = 1, cached = 1, buffered = 1;
  reg [31:0] va = 0, pa = 0, din = 0;
  reg [3:0] mask = 4'hf;
  reg inv = 0, lock = 0, mv = 0, mc = 0, mi = 0;
  reg allow = 1, fail_once = 0, audit_posts = 1;
  wire ready, valid, error, empty, mr, md;
  wire bv, bw;
  wire [31:0] data, ba, bd;
  wire [ 3:0] bs;
  reg  [31:0] mem[0:32767];
  reg [31:0] expected_address[0:255], expected_data[0:255];
  reg [3:0] expected_mask[0:255];
  integer queued = 0, delivered = 0, replies = 0, reads = 0, writes = 0;
  integer errors = 0, checks = 0, latency = 0, cold_latency = 0, hot_latency = 0;
  integer i, byte_lane, prior_replies, block_cycles = 0;
  reg held = 0;
  reg [68:0] held_packet;
  reg [31:0] result, expected_word, second_word;
  wire ack = bv && allow && !fail_once;
  wire bus_error = bv && fail_once;

  arm920_cache_access dut (
      .clk(clk),
      .reset(reset),
      .discard_refill(1'b0),
      .req_valid(req),
      .req_ready(ready),
      .req_mva(va),
      .req_physical(pa),
      .req_write(wr),
      .req_early_read(1'b1),
      .req_ordinary_store(ordinary),
      .req_resident_access(1'b0),
      .req_cache_enable(enabled),
      .req_cacheable(cached),
      .req_bufferable(buffered),
      .req_wdata(din),
      .req_byte_enable(mask),
      .response_valid(valid),
      .response_error(error),
      .response_data(data),
      .write_buffer_empty(empty),
      .write_buffer_error(),
      .line_req(),
      .line_addr(),
      .line_ready(1'b0),
      .line_reject(1'b0),
      .line_valid(1'b0),
      .line_data(64'b0),
      .line_wide(1'b0),
      .line_last(1'b0),
      .line_error(1'b0),
      .fast_lookup_enable(1'b0),
      .fast_lookup_address(32'b0),
      .fast_lookup_valid(),
      .fast_lookup_checked(),
      .fast_lookup_line(),
      .fast_lookup_word(),
      .invalidate_all(inv),
      .lock_write(lock),
      .lock_base_in(6'b0),
      .round_robin(1'b1),
      .maint_valid(mv),
      .maint_clean(mc),
      .maint_invalidate(mi),
      .maint_all(1'b1),
      .maint_by_mva(1'b0),
      .maint_address(32'b0),
      .maint_way(6'b0),
      .maint_segment(3'b0),
      .maint_ready(mr),
      .maint_done(md),
      .maint_error(),
      .bus_valid(bv),
      .bus_write(bw),
      .bus_address(ba),
      .bus_wdata(bd),
      .bus_byte_enable(bs),
      .bus_ack(ack),
      .bus_error(bus_error),
      .bus_rdata(mem[ba[16:2]])
  );

  always @(posedge clk) begin
    if (reset) held <= 0;
    else begin
      if (valid) replies = replies + 1;
      if (held && (!bv || {bw, ba, bd, bs} !== held_packet))
        $fatal(1, "offered bus packet changed before ACK/retry");
      held <= bv && !ack && !bus_error;
      held_packet <= {bw, ba, bd, bs};
      if (bus_error) begin
        errors = errors + 1;
        fail_once <= 0;
      end
      if (ack) begin
        if (bw) begin
          if (audit_posts) begin
            if (delivered >= queued || ba !== expected_address[delivered] ||
                            bd !== expected_data[delivered] || bs !== expected_mask[delivered])
              $fatal(
                  1,
                  "posted packet lost/reordered index=%0d addr=%h data=%h be=%h",
                  delivered,
                  ba,
                  bd,
                  bs
              );
            delivered = delivered + 1;
          end
          for (byte_lane = 0; byte_lane < 4; byte_lane = byte_lane + 1)
          if (bs[byte_lane]) mem[ba[16:2]][byte_lane*8+:8] <= bd[byte_lane*8+:8];
          writes = writes + 1;
        end else reads = reads + 1;
      end
    end
  end

  function [31:0] merge;
    input [31:0] old_value, value;
    input [3:0] be;
    integer b;
    begin
      merge = old_value;
      for (b = 0; b < 4; b = b + 1) if (be[b]) merge[b*8+:8] = value[b*8+:8];
    end
  endfunction
  task tick;
    begin
      @(posedge clk);
      #1;
      @(negedge clk);
    end
  endtask
  task drain;
    integer n;
    begin
      n = 0;
      while (!empty && n < 500) begin
        tick();
        n = n + 1;
      end
      if (!empty || delivered != queued) $fatal(1, "posted writes failed to drain exactly once");
    end
  endtask
  task expect_post;
    input [31:0] address, value;
    input [3:0] be;
    begin
      expected_address[queued] = address;
      expected_data[queued] = value;
      expected_mask[queued] = be;
      queued = queued + 1;
    end
  endtask
  task access;
    input write_access;
    input [31:0] address, physical, value;
    input [3:0] be;
    input post, expect_shortcut;
    begin
      if (!ready) $fatal(1, "access offered before ready");
      prior_replies = replies;
      req = 1;
      wr = write_access;
      va = address;
      pa = physical;
      din = value;
      mask = be;
      if (post) expect_post(physical, value, be);
      tick();
      if ((dut.state == 8) !== expect_shortcut)
        $fatal(
            1, "wrong admission path state=%0d expected_shortcut=%0d", dut.state, expect_shortcut
        );
      req = 0;
      // Poison inputs: every later byte, physical address and class must
      // come from the accepted owner, including while the buffer is full.
      va = 32'hdead0ffc;
      pa = 32'hbadd0ffc;
      din = ~value;
      mask = ~be;
      wr = ~write_access;
      latency = 0;
      while (!valid && latency < 500) begin
        tick();
        latency = latency + 1;
        if (block_cycles != 0 && latency == 2) mv = 1;
        if (block_cycles != 0 && latency == block_cycles) begin
          allow = 1;
          mv = 0;
        end
      end
      block_cycles = 0;
      if (!valid || error) $fatal(1, "missing or failed owned response");
      result = data;
      tick();
      if (valid || replies != prior_replies + 1) $fatal(1, "replayed/missing completion");
      checks = checks + 1;
    end
  endtask
  task invalidate;
    begin
      inv = 1;
      tick();
      inv = 0;
      tick();
    end
  endtask

  initial begin
    for (i = 0; i < 32768; i = i + 1) mem[i] = 32'h51000000 ^ (i * 4);
    repeat (3) tick();
    reset = 0;
    tick();
    access (1, 'h100, 'h100, 'h11223344, 4'hf, 1, 0);
    cold_latency = latency;
    access (1, 'h104, 'h104, 'h55667788, 4'h5, 1, 1);
    hot_latency = latency;
    if (hot_latency + 3 != cold_latency) $fatal(1, "shortcut did not remove three lookup clocks");
    // All masks, all words and repeated writes remain nonallocating.
    for (i = 0; i < 16; i = i + 1)
    access (1, 'h100 + (i % 8) * 4, 'h100 + (i % 8) * 4, 32'h10203040 ^ i, i[3:0], 1, 1);
    drain();
    expected_word = mem['h40];
    second_word   = mem['h45];
    // A read of a remembered absent line must allocate normally and revoke
    // the absence. Subsequent WB hit stores must change cache, not memory.
    access (0, 'h100, 'h100, 0, 4'hf, 0, 0);
    if (result !== expected_word) $fatal(1, "read miss skipped queued writes/refill");
    expected_word = merge(expected_word, 32'habcd1234, 4'ha);
    access (1, 'h100, 'h100, 'habcd1234, 4'ha, 0, 0);
    second_word = merge(second_word, 32'h98765432, 4'h5);
    access (1, 'h114, 'h114, 'h98765432, 4'h5, 0, 0);
    access (0, 'h100, 'h100, 0, 4'hf, 0, 0);
    if (result !== expected_word) $fatal(1, "resident partial store was lost");
    access (0, 'h114, 'h114, 0, 4'hf, 0, 0);
    if (result !== second_word) $fatal(1, "second dirty half lost");
    drain();
    audit_posts = 0;
    mv = 1;
    mc = 1;
    mi = 1;
    while (!mr) tick();
    tick();
    mv = 0;
    while (!md) tick();
    tick();
    while (!empty) tick();
    mc = 0;
    mi = 0;
    audit_posts = 1;
    if (mem['h40] !== expected_word || mem['h45] !== second_word)
      $fatal(1, "data/dirty commits disagree after clean");
    access (1, 'h100, 'h100, 'h12340000, 4'hf, 1, 0);
    // Compare every MVA line bit, not only segment or low address bits.
    access (1, 'h20100, 'h6000, 'h22340000, 4'hf, 1, 0);
    access (1, 'h20104, 'h6004, 'h32340000, 4'hf, 1, 1);
    access (1, 'h100, 'h100, 'h42340000, 4'hf, 1, 1);
    access (1, 'h104, 'h7004, 'h52340000, 4'hf, 1, 1);
    drain();
    // SWP/unsupported classes do not train or consume the directory.
    ordinary = 0;
    access (1, 'h200, 'h200, 'h1, 4'hf, 1, 0);
    access (1, 'h204, 'h204, 'h2, 4'hf, 1, 0);
    ordinary = 1;
    access (1, 'h200, 'h200, 'h3, 4'hf, 1, 0);
    buffered = 0;
    access (1, 'h204, 'h204, 'h4, 4'hf, 1, 0);
    buffered = 1;
    cached   = 0;
    access (1, 'h208, 'h208, 'h5, 4'hf, 1, 0);
    cached  = 1;
    enabled = 0;
    access (1, 'h20c, 'h20c, 'h6, 4'hf, 1, 0);
    enabled = 1;
    access (1, 'h200, 'h200, 'h7, 4'hf, 1, 0);
    drain();
    invalidate();
    access (1, 'h204, 'h204, 'h8, 4'hf, 1, 0);
    drain();
    lock = 1;
    tick();
    lock = 0;
    tick();
    access (1, 'h208, 'h208, 'h9, 4'hf, 1, 0);
    drain();
    // Full queue: the fifth accepted shortcut waits, retains all owner
    // inputs, and drains before maintenance or any subsequent demand.
    allow = 0;
    access (1, 'h800, 'h1000, 'h10, 4'hf, 1, 0);
    access (1, 'h804, 'h2000, 'h20, 4'hf, 1, 1);
    access (1, 'h808, 'h3000, 'h30, 4'hf, 1, 1);
    access (1, 'h80c, 'h4000, 'h40, 4'hf, 1, 1);
    block_cycles = 8;
    access (1, 'h810, 'h5000, 'h50, 4'h3, 1, 1);
    if (latency < 8) $fatal(1, "full buffer did not hold the owner");
    drain();
    fail_once = 1;
    // The pending maintenance offer revoked the reusable record, while the
    // already admitted fifth store still completed exactly once.
    access (1, 'h814, 'h5004, 'h60, 4'hc, 1, 0);
    drain();
    if (errors != 1) $fatal(1, "posted error/retry test not exercised");
    // Reset cancels an admitted shortcut before it reserves a posted slot.
    prior_replies = replies;
    req = 1;
    wr = 1;
    va = 'h818;
    pa = 'h5008;
    din = 'hdeadbeef;
    mask = 4'hf;
    tick();
    if (dut.state != 8) $fatal(1, "reset test did not admit a shortcut");
    req   = 0;
    reset = 1;
    tick();
    reset = 0;
    tick();
    if (replies != prior_replies || !empty) $fatal(1, "reset leaked owned write/response");
    access (1, 'h818, 'h5008, 'h70, 4'hf, 1, 0);
    drain();
    $display(
        "PASS: %0d owned requests, %0d exact ordered posted writes; absence latency %0d vs %0d, masks/refill/hit/dirty/alias/PA/class/invalidate/lock/full-buffer/retry/reset",
        checks, delivered, hot_latency, cold_latency);
    $finish;
  end
  initial begin
    #10000000;
    $fatal(1, "timeout");
  end
endmodule
