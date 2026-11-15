`timescale 1ns / 1ps
module test;
  reg clk = 0, reset = 1, rd = 0, wr = 0, enabled = 1, cacheable = 1, bufferable = 1;
  reg probe = 0, inv = 0, clean = 0, lock = 0, fault = 0, align_fault = 0, tlb_busy = 0;
  reg [31:0] addr = 0, din = 0, pa = 0, probe_addr = 0;
  reg [3:0] ben = 15;
  reg [1:0] swp = 0;
  wire ack, request_ack, err, err2, idle, hold_request, empty, inv_done, clean_done, lock_done;
  wire cyc, stb, we;
  wire [31:0] dout, bus_addr, bus_data, far_addr;
  wire [3:0] bus_sel;
  wire [7:0] fsr;
  reg [31:0] mem[0:32767], expected[0:7];
  integer seg;
  integer
      i,
      j,
      k,
      checks = 0,
      requests = 0,
      responses = 0,
      beats = 0,
      writes = 0,
      parallel = 0,
      collisions = 0;
  integer waits = 0, latency, fast_reads = 0, old_responses, old_beats;
  wire bus_ack = dut.inflight && waits >= 1;
  always #5 clk = ~clk;
  always @(posedge clk) begin
    if (reset || !dut.inflight || bus_ack) waits <= 0;
    else waits <= waits + 1;
    if (!reset) begin
      if ((rd || wr) && request_ack) responses = responses + 1;
      if (bus_ack) begin
        beats = beats + 1;
        if (we) begin
          writes = writes + 1;
          for (i = 0; i < 4; i = i + 1)
          if (bus_sel[i]) mem[bus_addr[16:2]][i*8+:8] <= bus_data[i*8+:8];
        end
      end
      if (dut.cache.probe_read && dut.cache.data_commit_valid) parallel = parallel + 1;
      if (dut.cache.probe_read_collision) collisions = collisions + 1;
    end
  end
  arm920_cache_adapter #(
      .DATA_PROBE(1)
  ) dut (
      .clk(clk),
      .reset(reset),
      .discard_refill(1'b0),
      .external_permit(1'b1),
      .write_buffer_empty(empty),
      .fast_enable(1'b1),
      .fast_next_address(32'b0),
      .data_probe_valid(probe),
      .data_probe_address(probe_addr),
      .address(addr),
      .physical(pa),
      .din(din),
      .far_in(addr),
      .rd(rd),
      .wr(wr),
      .ben(ben),
      .swp_tag(swp),
      .swp_bus_lock(),
      .alignment_fault(align_fault),
      .alignment_far(addr),
      .fault(fault),
      .fsr_in(8'h0d),
      .external_fsr(8'h08),
      .tlb_busy(tlb_busy),
      .translation_wait(tlb_busy),
      .cache_enable(enabled),
      .cache_rr(1'b1),
      .cacheable(cacheable),
      .bufferable(bufferable),
      .cache_invalidate(inv),
      .cache_clean(clean),
      .cache_lock_write(lock),
      .cache_lock_base(6'b0),
      .cache_lock_done(lock_done),
      .cache_op_single(1'b0),
      .cache_op_by_mva(1'b0),
      .cache_op_address(32'b0),
      .data(dout),
      .ack(ack),
      .request_ack(request_ack),
      .err(err),
      .err2(err2),
      .fsr(fsr),
      .far(far_addr),
      .idle(idle),
      .hold(hold_request),
      .cache_inv_done(inv_done),
      .cache_clean_done(clean_done),
      .wb_cyc(cyc),
      .wb_stb(stb),
      .wb_wen(we),
      .wb_sel(bus_sel),
      .wb_adr(bus_addr),
      .wb_data(bus_data),
      .wb_cti(),
      .wb_ack(bus_ack),
      .wb_err(1'b0),
      .wb_rdata(mem[bus_addr[16:2]]),
      .line_req(),
      .line_addr(),
      .line_ready(1'b0),
      .line_reject(1'b0),
      .line_valid(1'b0),
      .line_data(64'b0),
      .line_wide(1'b0),
      .line_last(1'b0),
      .line_error(1'b0)
  );
  reg collision_seen;
  always @(posedge clk)
    if (!reset) begin
      collision_seen=dut.cache.data_commit_valid &&
   dut.cache.data_commit_index==dut.cache.bank.lines.read_index;
      #1;
      if (collision_seen && dut.cache.probe_result_valid)
        $fatal(1, "published unspecified mixed-port RAM result");
    end
  task tick;
    begin
      @(posedge clk);
      #1;
      @(negedge clk);
      #1;
    end
  endtask
  task transaction;
    input write_access;
    input [31:0] address, physical, value, expect_value;
    input [3:0] mask;
    input expect_fast;
    integer n;
    begin
      if (!idle) $fatal(1, "adapter not idle");
      old_responses = responses;
      requests = requests + 1;
      addr = address;
      pa = physical;
      din = value;
      ben = mask;
      rd = !write_access;
      wr = write_access;
      #1;
      latency = 0;
      if (expect_fast && !dut.fast_hit)
        $fatal(1, "prepared probe did not complete immediately VA=%h", addr);
      if (!expect_fast && (swp != 0 || !enabled || !cacheable) && dut.fast_hit)
        $fatal(1, "SWP used speculative data probe");
      n = 0;
      while (!request_ack && n < 1000) begin
        tick();
        n = n + 1;
        latency = latency + 1;
      end
      if (!request_ack || err || err2) $fatal(1, "transaction failed VA=%h", addr);
      if (!write_access && dout !== expect_value)
        $fatal(1, "wrong word VA=%h got=%h expect=%h", addr, dout, expect_value);
      if (!write_access && dut.fast_hit) fast_reads = fast_reads + 1;
      tick();
      rd = 0;
      wr = 0;
      tick();
      if (responses != old_responses + 1 || request_ack) $fatal(1, "missing/duplicate response");
      checks = checks + 1;
    end
  endtask
  task prepare;
    input [31:0] address;
    begin
      probe = 1;
      probe_addr = address;
      repeat (4) tick();
      if (!dut.cache.probe_result_valid || dut.cache.probe_result_tag != address[31:5])
        $fatal(1, "probe fixture was not primed VA=%h", address);
    end
  endtask
  task warm_pair;
    input [31:0] a, b;
    begin
      transaction(0, a, a, 0, mem[a[16:2]], 15, 0);
      transaction(0, b, b, 0, mem[b[16:2]], 15, 0);
      transaction(0, a, a, 0, mem[a[16:2]], 15, 0);
      transaction(0, b, b, 0, mem[b[16:2]], 15, 0);
    end
  endtask
  initial begin
    for (j = 0; j < 32768; j = j + 1) mem[j] = 32'h51000000 ^ (j * 4);
    repeat (4) tick();
    reset = 0;
    // Two live lines; port B may pre-read B during an independent A store.
    warm_pair(32'h1000, 32'h3000);
    prepare(32'h3000);
    old_beats = beats;
    repeat (8) tick();
    if (beats != old_beats) $fatal(1, "address-only probe issued external traffic");
    transaction(1, 32'h1000, 32'h1000, 32'h12345678, 0, 15, 0);
    transaction(0, 32'h3000, 32'h3000, 0, 32'h51003000, 15, 1);
    if (parallel == 0) $fatal(1, "no concurrent A write/B read");
    // Every cache segment uses the registered physical selector. Change the
    // live P1 target while consuming the previous result, never its payload.
    for (seg = 1; seg < 8; seg = seg + 1) begin
      warm_pair(32'h1000 + seg * 32, 32'h3000 + seg * 32);
      prepare(32'h3000 + seg * 32);
      transaction(1, 32'h1000 + seg * 32, 32'h1000 + seg * 32, 32'h13572468 + seg, 0, 15, 0);
      transaction(0, 32'h3000 + seg * 32, 32'h3000 + seg * 32, 0, 32'h51003000 ^ (seg * 32), 15, 1);
    end
    transaction(0, 32'h1000, 32'h1000, 0, 32'h12345678, 15, 0);
    transaction(0, 32'h3000, 32'h3000, 0, 32'h51003000, 15, 0);
    prepare(32'h3000);
    for (seg = 0; seg < 8; seg = seg + 1) begin
      probe_addr = 32'h1000;
      transaction(0, 32'h3000, 32'h3000, 0, 32'h51003000, 15, 1);
      probe_addr = 32'h3000;
      transaction(0, 32'h1000, 32'h1000, 0, 32'h12345678, 15, 1);
    end
    // Every word and byte mask: collide with the saved read line, then demand
    // its fresh contents. Probe validity must not rely on mixed-port RAM results.
    for (j = 0; j < 8; j = j + 1) expected[j] = 32'h51003000 ^ (j * 4);
    for (j = 0; j < 8; j = j + 1)
    for (k = 0; k < 16; k = k + 1) begin
      prepare(32'h3000 + j * 4);
      din = 32'h98765432 ^ (j << 12) ^ k;
      for (i = 0; i < 4; i = i + 1) if (k & (1 << i)) expected[j][i*8+:8] = din[i*8+:8];
      transaction(1, 32'h3000 + j * 4, 32'h3000 + j * 4, din, 0, k, 0);
      transaction(0, 32'h3000 + j * 4, 32'h3000 + j * 4, 0, expected[j], 15, 0);
    end
    if (collisions == 0) $fatal(1, "same-slot collision path not exercised");
    // Probe result cannot bypass actual P2 permission/alignment/translation.
    prepare(32'h3000);
    old_beats = beats;
    old_responses = responses;
    rd = 1;
    addr = 32'h3000;
    pa = addr;
    fault = 1;
    #1;
    if (!request_ack || !err || dut.fast_hit || fsr != 8'h0d || far_addr != addr)
      $fatal(1, "permission bypass");
    tick();
    rd = 0;
    fault = 0;
    tick();
    if (beats != old_beats || responses != old_responses + 1) $fatal(1, "fault side effect");
    rd = 1;
    align_fault = 1;
    #1;
    if (!request_ack || !err || dut.fast_hit || fsr != 1) $fatal(1, "alignment bypass");
    tick();
    rd = 0;
    align_fault = 0;
    tick();
    rd = 1;
    tlb_busy = 1;
    repeat (5) begin
      #1;
      if (request_ack || dut.fast_hit) $fatal(1, "translation not checked");
      tick();
    end
    tlb_busy = 0;
    #1;
    if (!request_ack || !dut.fast_hit || dout !== expected[0])
      $fatal(1, "lost probe across translation wait");
    tick();
    rd = 0;
    tick();
    // SWP class and uncached requests keep normal admission/ordering.
    swp = 1;
    transaction(0, 32'h3000, 32'h3000, 0, expected[0], 15, 0);
    swp = 2;
    transaction(1, 32'h3000, 32'h3000, expected[0], 0, 15, 0);
    swp = 0;
    cacheable = 0;
    bufferable = 0;
    transaction(0, 32'h3000, 32'h7000, 0, 32'h51007000, 15, 0);
    cacheable = 1;
    bufferable = 1;
    // All metadata/data dirty halves must survive a full clean.
    clean = 1;
    while (!clean_done) tick();
    tick();
    clean = 0;
    repeat (3) tick();
    for (j = 0; j < 8; j = j + 1)
    if (mem['hc00+j] !== expected[j]) $fatal(1, "probe/store lost dirty half word=%0d", j);
    transaction(0, 32'h3000, 32'h3000, 0, expected[0], 15, 0);
    // High VA alias has the same low cache index but different data/PA.
    prepare(32'h3000);
    transaction(0, 32'h10003000, 32'h5000, 0, 32'h51005000, 15, 0);
    transaction(0, 32'h10003000, 32'h5000, 0, 32'h51005000, 15, 0);
    prepare(32'h10003000);
    transaction(0, 32'h10003000, 32'h5000, 0, 32'h51005000, 15, 1);
    enabled = 0;
    transaction(0, 32'h10003000, 32'h7000, 0, 32'h51007000, 15, 0);
    enabled = 1;
    transaction(0, 32'h3000, 32'h3000, 0, expected[0], 15, 0);
    // Revocation cannot leave an old RAM output usable after invalidation/refill.
    prepare(32'h3000);
    inv = 1;
    #1;
    if (dut.fast_hit) $fatal(1, "invalidate retained fast response");
    while (!inv_done) tick();
    tick();
    inv = 0;
    repeat (3) tick();
    mem['hc00] = 32'habcdef01;
    transaction(0, 32'h3000, 32'h3000, 0, 32'habcdef01, 15, 0);
    transaction(0, 32'h3000, 32'h3000, 0, 32'habcdef01, 15, 0);
    prepare(32'h3000);
    transaction(0, 32'h3000, 32'h3000, 0, 32'habcdef01, 15, 1);
    enabled = 0;
    tick();
    enabled = 1;
    #1;
    if (dut.cache.probe_result_valid) $fatal(1, "cache disable retained probe");
    transaction(0, 32'h3000, 32'h3000, 0, 32'habcdef01, 15, 0);
    prepare(32'h3000);
    lock = 1;
    tick();
    lock = 0;
    #1;
    if (dut.cache.probe_owner_valid) $fatal(1, "lock retained probe");
    transaction(0, 32'h3000, 32'h3000, 0, 32'habcdef01, 15, 0);
    prepare(32'h3000);
    reset = 1;
    tick();
    reset = 0;
    #1;
    if (dut.cache.probe_result_valid) $fatal(1, "reset retained probe");
    $display(
        "PASS: %0d requests; %0d fast reads, %0d concurrent A/B clocks, %0d blocked collisions; all words/masks/dirty halves, permission/alignment/translation/SWP/uncached/revocation/reset",
        checks, fast_reads, parallel, collisions);
    $finish;
  end
  initial begin
    #10000000;
    $fatal(1, "timeout");
  end
endmodule
