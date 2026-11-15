`timescale 1ns / 1ps

module fifo_case #(
    parameter DEPTH = 4
) (
    output reg done = 0
);
  reg clk = 0;
  always #1 clk = ~clk;
  reg reset = 1, clear = 0, wr = 0, rd = 0;
  reg  [31:0] data = 0;
  wire [31:0] result;
  wire empty, empty_n, full, full_n;
  reg [31:0] expected                   [0:DEPTH-1];
  reg [31:0] rng = 32'h90cafe01 ^ DEPTH;
  integer count = 0, head = 0, tail = 0;
  integer step, writes = 0, reads = 0, pairs = 0, wraps = 0;
  integer empty_pairs = 0, full_pairs = 0, clears = 0, resets = 0;
  reg take_read, take_write;

  zap_sync_fifo #(
      .WIDTH(32),
      .DEPTH(DEPTH)
  ) dut (
      .i_clk    (clk),
      .i_reset  (reset),
      .i_clear  (clear),
      .i_ack    (rd),
      .i_wr_en  (wr),
      .i_data   (data),
      .o_data   (result),
      .o_empty  (empty),
      .o_empty_n(empty_n),
      .o_full   (full),
      .o_full_n (full_n)
  );

  initial begin
    @(negedge clk);
    for (step = 0; step < 100000; step = step + 1) begin
      rng   = rng ^ (rng << 13);
      rng   = rng ^ (rng >> 17);
      rng   = rng ^ (rng << 5);
      reset = (step == 0) || (step > 1000 && rng[15:4] == 0);
      clear = step > 1000 && rng[27:16] == 1;
      wr    = rng[0];
      rd    = rng[1];
      // Repeated fill/full-pair/drain/empty-pair sequences force every
      // boundary and pointer wrap, independently of random coverage.
      if (step % (4 * DEPTH + 8) < DEPTH + 2) begin
        wr = 1;
        rd = 0;
      end else if (step % (4 * DEPTH + 8) == DEPTH + 2) begin
        wr = 1;
        rd = 1;
      end else if (step % (4 * DEPTH + 8) < 2 * DEPTH + 5) begin
        wr = 0;
        rd = 1;
      end else if (step % (4 * DEPTH + 8) == 2 * DEPTH + 5) begin
        wr = 1;
        rd = 1;
      end
      data = rng ^ step;
      #0.1;
      if (empty !== (count == 0) || full !== (count == DEPTH) ||
                empty_n !== !empty || full_n !== !full)
        $fatal(1, "flags depth=%0d step=%0d count=%0d", DEPTH, step, count);
      if (count && result !== expected[head]) $fatal(1, "data depth=%0d step=%0d", DEPTH, step);
      take_read  = rd && count != 0;
      take_write = wr && count != DEPTH;
      if (wr && rd && count == 0) empty_pairs = empty_pairs + 1;
      if (wr && rd && count == DEPTH) full_pairs = full_pairs + 1;
      if (take_read && take_write) pairs = pairs + 1;
      @(posedge clk);
      if (reset || clear) begin
        count = 0;
        head  = 0;
        tail  = 0;
        if (reset) resets = resets + 1;
        if (clear) clears = clears + 1;
      end else begin
        if (take_read) begin
          head  = (head + 1) % DEPTH;
          reads = reads + 1;
          if (head == 0) wraps = wraps + 1;
        end
        if (take_write) begin
          expected[tail] = data;
          tail           = (tail + 1) % DEPTH;
          writes         = writes + 1;
        end
        count = count + integer'(take_write) - integer'(take_read);
      end
      @(negedge clk);
    end
    if (!pairs || !wraps || !empty_pairs || !full_pairs || !clears || resets < 2)
      $fatal(1, "missing coverage depth=%0d", DEPTH);
    $display(
        "PASS FIFO depth=%0d clocks=%0d writes=%0d reads=%0d pairs=%0d wraps=%0d empty_pairs=%0d full_pairs=%0d clear=%0d reset=%0d",
        DEPTH, step, writes, reads, pairs, wraps, empty_pairs, full_pairs, clears, resets);
    done = 1;
  end
endmodule

module test;
  wire [5:0] done;
  fifo_case #(.DEPTH(2)) d2 (done[0]);
  fifo_case #(.DEPTH(4)) d4 (done[1]);
  fifo_case #(.DEPTH(8)) d8 (done[2]);
  fifo_case #(.DEPTH(16)) d16 (done[3]);
  fifo_case #(.DEPTH(32)) d32 (done[4]);
  fifo_case #(.DEPTH(64)) d64 (done[5]);
  initial begin
    wait (&done);
    $display("PASS FIFO occupancy and data ordering");
    $finish;
  end
endmodule
