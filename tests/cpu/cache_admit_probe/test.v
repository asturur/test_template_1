`timescale 1ns / 1ps
module test;
  reg clk = 0, reset = 1, rd = 0, wr = 0, enabled = 1, cacheable = 1, bufferable = 1;
  reg fast_enable = 1;
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
  integer seg, cache_responses = 0;
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
      if (dut.cache.response_valid) cache_responses = cache_responses + 1;
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
      .fast_enable(fast_enable),
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
  // Observe the credit while the transaction is active, not just after ack.
  always @(negedge clk)
    if (!reset && dut.cache.admitted_probe_owner &&
        (swp != 0 || !cacheable || !enabled || fault || align_fault || tlb_busy))
      $fatal(1, "excluded access class received admission credit");
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
  integer early_responses = 0, fallback_responses = 0, old_requests;
  integer admitted_count = 0;
  reg [31:0] late_result;
  always @(posedge clk) if (!reset && dut.cache.accept_demand) admitted_count = admitted_count + 1;
  task prime_admission(input [31:0] address);
    begin
      if (!idle) $fatal(1, "prime while busy");
      probe = 0;
      fast_enable = 0;
      tick();
      fast_enable = 1;
      probe = 1;
      probe_addr = address;
      tick();
      if (!dut.cache.probe_owner_valid || dut.cache.probe_result_valid)
        $fatal(1, "expected an owned read scheduled for the next edge");
    end
  endtask
  task late_read(input [31:0] address, input [31:0] expect_value, input expect_short);
    integer saved_responses, saved_cache_responses, saved_beats, clocks;
    begin
      saved_responses = responses;
      saved_cache_responses = cache_responses;
      saved_beats = beats;
      addr = address;
      pa = address;
      rd = 1;
      wr = 0;
      ben = 15;
      #1;
      if (dut.fast_hit || !dut.cache.accept_demand)
        $fatal(1, "late read must use real cache admission");
      tick();
      clocks = 1;
      // P1 can immediately name another line. The reply belongs to accepted MVA.
      probe_addr = 32'hdeadffc0;
      #1;  // Let the next-address mux settle before checking the owned reply.
      if (dut.cache.admitted_probe_owner !== expect_short)
        $fatal(1, "admission credit mismatch address=%h expected=%b", address, expect_short);
      if (expect_short && (!request_ack || !dut.cache.early_reply))
        $fatal(1, "matching admission pre-read incurred an extra wait");
      while (!request_ack && clocks < 30) begin
        tick();
        clocks = clocks + 1;
      end
      if (!request_ack || err || err2 || dout !== expect_value)
        $fatal(
            1, "admitted read wrong value address=%h got=%h expect=%h", address, dout, expect_value
        );
      if (expect_short && clocks != 1) $fatal(1, "lost short read latency");
      if (!expect_short && clocks < 2) $fatal(1, "unowned pre-read used as response");
      late_result = dout;
      tick();
      rd = 0;
      probe = 0;
      tick();
      if (responses != saved_responses + 1 || cache_responses != saved_cache_responses + 1 ||
          request_ack || beats != saved_beats)
        $fatal(1, "missing/replayed read or unexpected backing traffic");
      if (expect_short) early_responses = early_responses + 1;
      else fallback_responses = fallback_responses + 1;
      checks = checks + 1;
    end
  endtask
  initial begin
    for (j = 0; j < 32768; j = j + 1) mem[j] = 32'h51000000 ^ (j * 4);
    repeat (4) tick();
    reset = 0;
    // Every segment and word: accepted line and RAM way must name the same read.
    for (seg = 0; seg < 8; seg = seg + 1) begin
      warm_pair(32'h1000 + seg * 32, 32'h3000 + seg * 32);
      for (k = 0; k < 8; k = k + 1) begin
        prime_admission(32'h1000 + seg * 32 + k * 4);
        late_read(32'h1000 + seg * 32 + k * 4, 32'h51001000 ^ (seg * 32 + k * 4), 1);
        prime_admission(32'h3000 + seg * 32 + k * 4);
        late_read(32'h3000 + seg * 32 + k * 4, 32'h51003000 ^ (seg * 32 + k * 4), 1);
      end
    end
    warm_pair(32'h1000, 32'h3000);
    prime_admission(32'h3000);
    late_read(32'h1000, 32'h51001000, 0);
    // Isolate the full-line guard while preserving way and segment. A
    // separate way mismatch would otherwise hide a missing address check.
    prime_admission(32'h3000);
    dut.cache.probe_owner_tag = dut.cache.probe_owner_tag ^ 27'h8;
    late_read(32'h3000, 32'h51003000, 0);
    // A valid tag with a different RAM way cannot grant a response credit.
    prime_admission(32'h3000);
    dut.cache.probe_owner_way = dut.cache.probe_owner_way ^ 6'd1;
    late_read(32'h3000, 32'h51003000, 0);
    // Same-slot stores, all masks and both dirty halves: reread fresh bytes.
    for (j = 0; j < 8; j = j + 1) expected[j] = 32'h51003000 ^ (j * 4);
    for (j = 0; j < 8; j = j + 1)
    for (k = 0; k < 16; k = k + 1) begin
      din = 32'h98765432 ^ (j << 12) ^ k;
      for (i = 0; i < 4; i = i + 1) if (k & (1 << i)) expected[j][i*8+:8] = din[i*8+:8];
      transaction(1, 32'h3000 + j * 4, 32'h3000 + j * 4, din, 0, k, 0);
      prime_admission(32'h3000 + j * 4);
      late_read(32'h3000 + j * 4, expected[j], 1);
    end
    // A pending maintenance offer cannot steal an already admitted read.
    prime_admission(32'h3000);
    addr = 32'h3000;
    pa   = addr;
    rd   = 1;
    tick();
    inv = 1;
    #1;
    if (!request_ack || dout !== expected[0]) $fatal(1, "maintenance stole accepted read");
    tick();
    rd = 0;
    while (!inv_done) tick();
    tick();
    inv   = 0;
    probe = 0;
    repeat (3) tick();
    warm_pair(32'h1000, 32'h3000);
    // P2 checks still precede acceptance even if an independent read is ready.
    prime_admission(32'h3000);
    old_requests = admitted_count;
    old_beats = beats;
    addr = 32'h3000;
    pa = addr;
    rd = 1;
    fault = 1;
    #1;
    if (!request_ack || !err || fsr != 8'h0d || far_addr != addr) $fatal(1, "permission bypass");
    tick();
    rd = 0;
    fault = 0;
    tick();
    if (admitted_count != old_requests || beats != old_beats || dut.cache.admitted_probe_owner)
      $fatal(1, "fault created a demand credit");
    prime_admission(32'h3000);
    rd = 1;
    align_fault = 1;
    #1;
    if (!request_ack || !err || fsr != 1) $fatal(1, "alignment bypass");
    tick();
    rd = 0;
    align_fault = 0;
    tick();
    if (admitted_count != old_requests || dut.cache.admitted_probe_owner)
      $fatal(1, "alignment fault created a demand credit");
    // A ready independent RAM result never bypasses translation ownership.
    prime_admission(32'h3000);
    old_requests = admitted_count;
    old_beats = beats;
    rd = 1;
    tlb_busy = 1;
    repeat (3) begin
      #1;
      if (request_ack || dut.cache.accept_demand || dut.cache.admitted_probe_owner)
        $fatal(1, "translation wait bypassed");
      tick();
    end
    rd = 0;
    tlb_busy = 0;
    probe = 0;
    tick();
    if (admitted_count != old_requests || beats != old_beats)
      $fatal(1, "translation wait created side effects");
    // SWP and uncached classes retain their existing response boundary.
    swp = 1;
    prime_admission(32'h3000);
    transaction(0, 32'h3000, 32'h3000, 0, mem['hc00], 15, 0);
    if (dut.cache.admitted_probe_owner) $fatal(1, "SWP got ordinary read credit");
    swp = 2;
    transaction(1, 32'h3000, 32'h3000, mem['hc00], 0, 15, 0);
    swp = 0;
    cacheable = 0;
    bufferable = 0;
    transaction(0, 32'h3000, 32'h7000, 0, mem['h1c00], 15, 0);
    cacheable  = 1;
    bufferable = 1;
    // Reset cancels a credit before its consumer samples it.
    warm_pair(32'h1000, 32'h3000);
    prime_admission(32'h3000);
    addr = 32'h3000;
    pa   = addr;
    rd   = 1;
    tick();
    if (!dut.cache.admitted_probe_owner) $fatal(1, "no reset credit fixture");
    reset = 1;
    #1;
    if (request_ack) $fatal(1, "response escaped reset");
    tick();
    rd = 0;
    probe = 0;
    tick();
    reset = 0;
    tick();
    if (request_ack || dut.cache.admitted_probe_owner) $fatal(1, "reset replayed a credit");
    if (early_responses != 256 || fallback_responses != 3)
      $fatal(1, "missing admission-response coverage");
    $display(
        "PASS admitted probe: %0d short reads, %0d mismatches, all segments/words/masks, faults, SWP, maintenance and reset",
        early_responses, fallback_responses);
    $finish;
  end
  initial begin
    repeat (200000) @(posedge clk);
    $fatal(1, "timeout");
  end
endmodule
