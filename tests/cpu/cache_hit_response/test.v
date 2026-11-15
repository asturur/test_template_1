`timescale 1ns / 1ps
module test;
  reg clk = 0, reset = 1, req = 0, wr = 0, early = 0, enabled = 1;
  reg [31:0] address = 0, din = 0;
  reg [3:0] mask = 4'hf;
  wire ready, valid, error, bus_valid, bus_write, empty;
  wire [31:0] data, bus_address, bus_data;
  wire [3:0] bus_mask;
  reg [31:0] mem[0:1023];
  integer i, acks = 0, reads = 0, writes = 0, checks = 0;
  integer latency, legacy_hit, early_hit, old_acks;
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
      .req_ordinary_store(1'b0),
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
      .fast_lookup_valid(),
      .fast_lookup_checked(),
      .fast_lookup_line(),
      .fast_lookup_word(),
      .invalidate_all(1'b0),
      .lock_write(1'b0),
      .lock_base_in(6'b0),
      .round_robin(1'b1),
      .maint_valid(1'b0),
      .maint_clean(1'b0),
      .maint_invalidate(1'b0),
      .maint_all(1'b0),
      .maint_by_mva(1'b0),
      .maint_address(32'b0),
      .maint_way(6'b0),
      .maint_segment(3'b0),
      .maint_ready(),
      .maint_done(),
      .maint_error(),
      .bus_valid(bus_valid),
      .bus_write(bus_write),
      .bus_address(bus_address),
      .bus_wdata(bus_data),
      .bus_byte_enable(bus_mask),
      .bus_ack(bus_valid),
      .bus_error(1'b0),
      .bus_rdata(mem[bus_address[11:2]])
  );
  always @(posedge clk)
    if (!reset) begin
      if (valid) acks = acks + 1;
      if (bus_valid) begin
        if (bus_write) begin
          writes = writes + 1;
          for (i = 0; i < 4; i = i + 1)
          if (bus_mask[i]) mem[bus_address[11:2]][i*8+:8] <= bus_data[i*8+:8];
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
      tick();  // consume the offered pulse before reusing the interface
      if (valid || acks != old_acks + 1) $fatal(1, "duplicate/missing completion");
      while (!empty) tick();
      checks = checks + 1;
    end
  endtask
  initial begin
    for (i = 0; i < 1024; i = i + 1) mem[i] = 32'h51000000 ^ (i * 4);
    repeat (3) tick();
    reset = 0;
    tick();
    // Miss retains its registered response, even when early delivery was allowed.
    access (0, 1, 32'h100, 0, 4'hf, 0);
    if (result !== mem['h40] || reads != 8) $fatal(1, "miss mismatch");
    access (0, 0, 32'h104, 0, 4'hf, 0);
    legacy_hit = latency;
    if (result !== mem['h41]) $fatal(1, "legacy word mismatch");
    access (0, 1, 32'h104, 0, 4'hf, 1);
    early_hit = latency;
    if (result !== mem['h41] || early_hit + 1 != legacy_hit) $fatal(1, "no one-clock saving");
    for (i = 0; i < 8; i = i + 1) begin
      access (0, 1, 32'h100 + 4 * i, 0, 4'hf, 1);
      if (result !== (32'h51000000 ^ (32'h100 + 4 * i))) $fatal(1, "word lane mismatch");
    end
    // Partial cached stores keep their old responder and update the real RAM.
    access (1, 1, 32'h104, 32'h11223344, 4'b0101, 0);
    access (0, 1, 32'h104, 0, 4'hf, 1);
    if (result !== 32'h51220144) $fatal(1, "partial store freshness %h", result);
    // SWP-class callers withhold early delivery, including after earlier fast reads.
    access (0, 0, 32'h104, 0, 4'hf, 0);
    if (result !== 32'h51220144) $fatal(1, "legacy-after-early mismatch");
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
        "PASS: hit response one clock earlier (%0d vs %0d), %0d exact-once requests; lanes/store/SWP-class/miss/uncached/reset",
        early_hit, legacy_hit, checks);
    $finish;
  end
  initial begin
    #1000000;
    $fatal(1, "timeout");
  end
endmodule
