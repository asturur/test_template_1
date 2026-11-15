`timescale 1ns / 1ps
module test;
  reg clk = 0, reset = 1, req = 0, wr = 0, early = 0, enabled = 1;
  reg [31:0] address = 0, din = 0;
  reg resident = 1, ordinary = 1;
  reg inv = 0, lock = 0, mv = 0, mc = 0, mi = 0;
  wire mr, md;
  reg pending_maintenance = 0;
  reg [31:0] expected[0:7];
  integer j, old_writes;
  parameter STORES = 1;
  reg [3:0] mask = 4'hf;
  wire ready, valid, error, bus_valid, bus_write, empty;
  wire [31:0] data, bus_address, bus_data;
  wire [3:0] bus_mask;
  reg [31:0] mem[0:32767];
  integer i, acks = 0, reads = 0, writes = 0, checks = 0;
  integer latency, legacy_hit, early_hit, old_acks;
  integer normal_read, fast_read, resident_store;
  reg [31:0] result;
  always #5 clk = ~clk;
  arm920_cache_access dut (
      .clk(clk),
      .reset(reset),
      .discard_refill(1'b0),
      .req_valid(req),
      .req_ready(ready),
      .req_mva(address),
      .req_physical(address),
      .req_write(wr),
      .req_early_read(early),
      .req_ordinary_store(ordinary),
      .req_resident_access(resident),
      .req_cache_enable(enabled),
      .req_cacheable(enabled),
      .req_bufferable(1'b1),
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
      .data_probe_valid(1'b0),
      .data_probe_address(32'b0),
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
      .bus_valid(bus_valid),
      .bus_write(bus_write),
      .bus_address(bus_address),
      .bus_wdata(bus_data),
      .bus_byte_enable(bus_mask),
      .bus_ack(bus_valid),
      .bus_error(1'b0),
      .bus_rdata(mem[bus_address[16:2]])
  );
  always @(posedge clk)
    if (!reset) begin
      if (valid) acks = acks + 1;
      if (bus_valid) begin
        if (bus_write) begin
          writes = writes + 1;
          for (i = 0; i < 4; i = i + 1)
          if (bus_mask[i]) mem[bus_address[16:2]][i*8+:8] <= bus_data[i*8+:8];
        end else reads = reads + 1;
      end
    end
  task tick;
    begin
      @(posedge clk);
      #1;
      @(negedge clk);
    end
  endtask
  task access;
    input write_access, allow_early;
    input [31:0] addr, value;
    input [3:0] be;
    input expect_early;
    begin
      if (!ready) $fatal(1, "not ready");
      old_acks = acks;
      req = 1;
      wr = write_access;
      early = allow_early;
      address = addr;
      din = value;
      mask = be;
      tick();
      req = 0;
      if (pending_maintenance) mv = 1;
      // A response must belong to the accepted packet, not live inputs.
      address = 32'hdead0ffc;
      din = ~value;
      mask = ~be;
      wr = ~write_access;
      early = ~allow_early;
      latency = 0;
      while (!valid) begin
        tick();
        latency = latency + 1;
      end
      if (error) $fatal(1, "unexpected fault");
      if ((dut.state == 2) !== expect_early) $fatal(1, "wrong response stage state=%0d", dut.state);
      result = data;
      if (pending_maintenance) begin
        mv = 0;
        pending_maintenance = 0;
      end
      tick();  // consume the offered pulse before reusing the interface
      if (valid || acks != old_acks + 1) $fatal(1, "duplicate/missing completion");
      while (!empty) tick();
      checks = checks + 1;
    end
  endtask
  initial begin
    for (i = 0; i < 32768; i = i + 1) mem[i] = 32'h51000000 ^ (i * 4);
    repeat (3) tick();
    reset = 0;
    tick();
    // Miss retains its registered response, even when early delivery was allowed.
    access (0, 1, 32'h100, 0, 4'hf, 0);
    if (result !== mem['h40] || reads != 8) $fatal(1, "miss mismatch");
    resident = 0;
    access (0, 1, 32'h104, 0, 4'hf, 1);
    normal_read = latency;
    resident = 1;
    access (0, 1, 32'h104, 0, 4'hf, 1);
    fast_read = latency;
    if (result !== mem['h41] || fast_read + 2 != normal_read)
      $fatal(1, "indexed read did not remove two clocks: %0d vs %0d", fast_read, normal_read);
    for (i = 0; i < 8; i = i + 1) begin
      access (0, 1, 32'h100 + 4 * i, 0, 4'hf, 1);
      if (result !== (32'h51000000 ^ (32'h100 + 4 * i))) $fatal(1, "word lane mismatch");
    end
    // Partial cached stores complete on their owned RAM commit edge.
    access (1, 1, 32'h104, 32'h11223344, 4'b0101, 0);
    resident_store = latency;
    if (resident_store != (STORES ? 2 : 4)) $fatal(1, "indexed store latency %0d", resident_store);
    access (0, 1, 32'h104, 0, 4'hf, 1);
    if (result !== 32'h51220144) $fatal(1, "partial store freshness %h", result);
    // A maintenance offer cannot steal the accepted store's commit owner.
    pending_maintenance = 1;
    access (1, 1, 32'h104, 0, 4'h0, 0);
    if (latency != (STORES ? 2 : 4)) $fatal(1, "maintenance stole store completion");
    // An unsupported/SWP-class store retains the full registered responder.
    ordinary = 0;
    access (1, 1, 32'h104, 0, 4'h0, 0);
    if (latency != 5) $fatal(1, "SWP-class store used ordinary completion");
    ordinary = 1;
    // SWP-class callers withhold early delivery, including after earlier fast reads.
    access (0, 0, 32'h104, 0, 4'hf, 0);
    if (result !== 32'h51220144) $fatal(1, "legacy-after-early mismatch");
    // Validate every mask, both dirty halves and freshly reread data. No line
    // data or dirty flags may be copied into the directory.
    for (j = 0; j < 8; j = j + 1) begin
      access (0, 1, 32'h100 + 4 * j, 0, 4'hf, 1);
      expected[j] = result;
    end
    for (j = 0; j < 16; j = j + 1) begin
      for (i = 0; i < 4; i = i + 1) if (j[i]) expected[j%8][i*8+:8] = (32'h81020304 ^ j) >> (i * 8);
      access (1, 1, 32'h100 + 4 * (j % 8), 32'h81020304 ^ j, j[3:0], 0);
      if (latency != (STORES ? 2 : 4)) $fatal(1, "store reused a stale/unowned way");
      access (0, 1, 32'h100 + 4 * (j % 8), 0, 4'hf, 1);
      if (result !== expected[j%8]) $fatal(1, "indexed store/read mask freshness");
    end
    old_writes = writes;
    mv = 1;
    mc = 1;
    while (!mr) tick();
    tick();
    mv = 0;
    while (!md) tick();
    tick();
    while (!empty) tick();
    mc = 0;
    if (writes - old_writes != 8) $fatal(1, "both dirty halves were not preserved");
    for (j = 0; j < 8; j = j + 1)
    if (mem['h40+j] !== expected[j]) $fatal(1, "dirty data did not reach correct physical address");
    access (0, 1, 32'h100, 0, 4'hf, 1);
    if (latency != normal_read) $fatal(1, "maintenance did not revoke directory");
    access (0, 1, 32'h104, 0, 4'hf, 1);
    pending_maintenance = 1;
    access (0, 1, 32'h108, 0, 4'hf, 0);
    if (result !== expected[2]) $fatal(1, "pending maintenance redirected accepted read");
    // Different RAM segments and dirty halves must use the captured indexed
    // owner, not the previous CAM's delayed segment/word selection.
    for (j = 0; j < 8; j = j + 1) begin
      access (0, 1, 32'h4000 + 32 * j + 16 * (j % 2), 0, 4'hf, 0);
      access (1, 1, 32'h4000 + 32 * j + 16 * (j % 2), 32'h82000000 | j, 4'hf, 0);
      if (latency != (STORES ? 2 : 4)) $fatal(1, "indexed segment store latency");
      access (0, 1, 32'h4000 + 32 * j + 16 * (j % 2), 0, 4'hf, 1);
      if (result !== (32'h82000000 | j)) $fatal(1, "indexed segment/half data mismatch");
    end
    old_writes = writes;
    mv = 1;
    mc = 1;
    while (!mr) tick();
    tick();
    mv = 0;
    while (!md) tick();
    tick();
    while (!empty) tick();
    mc = 0;
    if (writes - old_writes != 32) $fatal(1, "per-segment dirty half mismatch");
    for (j = 0; j < 8; j = j + 1)
    if (mem[(32'h4000+32*j+16*(j%2))>>2] !== (32'h82000000 | j))
      $fatal(1, "indexed segment physical writeback mismatch");
    // Allocate a second line, then seed both resident facts without refills.
    access (0, 1, 32'h1100, 0, 4'hf, 0);
    access (0, 1, 32'h100, 0, 4'hf, 1);
    if (latency != normal_read) $fatal(1, "refill did not revoke prior way");
    access (0, 1, 32'h1104, 0, 4'hf, 1);
    if (latency != fast_read) $fatal(1, "two associative records aliased");
    access (0, 1, 32'h108, 0, 4'hf, 1);
    if (latency != fast_read) $fatal(1, "two alternating lines lost capacity");
    // Full MVA tag differs while physical data/index are intentionally equal.
    access (0, 1, 32'h20100, 0, 4'hf, 0);
    if (result !== mem['h40]) $fatal(1, "high line bits were ignored");
    access (0, 1, 32'h20104, 0, 4'hf, 1);
    if (latency != fast_read) $fatal(1, "high-tag fact was not reusable");
    lock = 1;
    tick();
    lock = 0;
    tick();
    access (0, 1, 32'h20108, 0, 4'hf, 1);
    if (latency != normal_read) $fatal(1, "lock did not revoke selected way");
    inv = 1;
    tick();
    inv = 0;
    tick();
    access (0, 1, 32'h20100, 0, 4'hf, 0);
    enabled = 0;
    access (0, 1, 32'h200, 0, 4'hf, 0);
    if (result !== mem['h80]) $fatal(1, "uncached response mismatch");
    enabled = 1;
    access (0, 1, 32'h300, 0, 4'hf, 0);
    if (result !== mem['hc0]) $fatal(1, "second miss mismatch");
    // Reset must revoke an early pulse before any consumer captures it.
    req = 1;
    wr = 0;
    early = 1;
    address = 32'h300;
    mask = 4'hf;
    tick();
    req = 0;
    while (!valid) tick();
    reset = 1;
    #1;
    if (valid) $fatal(1, "early reply survived reset");
    tick();
    reset = 0;
    tick();
    access (0, 1, 32'h300, 0, 4'hf, 0);
    if (result !== mem['hc0]) $fatal(1, "post-reset miss mismatch");
    $display(
        "PASS: %0d resident requests; normal read %0d indexed %0d, store %0d; lanes/fresh stores/two slots/high tags/refill/class/cache/reset",
        checks, normal_read, fast_read, resident_store);
    $finish;
  end
  initial begin
    #1000000;
    $fatal(1, "timeout");
  end
endmodule
