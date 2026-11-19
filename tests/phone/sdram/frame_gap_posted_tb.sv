`timescale 1ns / 1ps

module frame_gap_posted_tb;
  reg clk = 0;
  always #5 clk = ~clk;

  reg cold_reset = 1, client_reset = 1, lock = 0, req = 0, we = 0;
  reg [24:0] addr = 0;
  reg [31:0] data = 0;
  reg [ 3:0] mask = 0;
  wire ack, line_idle, backend_reset, backend_req, backend_we;
  wire [24:0] backend_addr;
  wire [31:0] backend_data;
  wire [3:0] backend_mask;
  reg backend_ack = 0;
  frame_gap_posted dut (.*);

  integer writes = 0;
  reg [31:0] word = 32'h11223344;
  reg [31:0] read_word = 0;

  task automatic expect_write(input [31:0] value, input [3:0] select);
    if (!backend_req || !backend_we || backend_addr != 25'h4000 ||
            backend_data !== value || backend_mask !== select)
      $fatal(
          1,
          "Unexpected write: req=%b write=%b addr=%h data=%h mask=%b",
          backend_req,
          backend_we,
          backend_addr,
          backend_data,
          backend_mask
      );
  endtask

  task automatic commit(input bit write_request);
    if (!backend_req || backend_we != write_request || backend_reset)
      $fatal(1, "Unexpected backend transaction");
    if (write_request) begin
      for (integer lane = 0; lane < 4; lane = lane + 1)
      if (backend_mask[lane]) word[8*lane+:8] = backend_data[8*lane+:8];
      writes = writes + 1;
    end else begin
      if (backend_addr != 25'h4000) $fatal(1, "Unexpected read address");
      read_word = word;
    end
    backend_ack = 1;
    #1;
    @(negedge clk);
    backend_ack = 0;
  endtask

  initial begin
    repeat (2) @(negedge clk);
    cold_reset   = 0;
    client_reset = 0;
    @(negedge clk);
    req  = 1;
    we   = 1;
    addr = 25'h4000;
    data = 32'haabbccdd;
    mask = 4'b0101;
    @(negedge clk);
    if (!ack || line_idle) $fatal(1, "First write did not post");
    expect_write(32'haabbccdd, 4'b0101);

    // A second write must wait and cannot overwrite the retained mask.
    req = 0;
    @(negedge clk);
    req  = 1;
    data = 32'heeff9988;
    mask = 4'b1010;
    repeat (4) begin
      @(negedge clk);
      if (ack || line_idle) $fatal(1, "Full queue lost its ordering");
      expect_write(32'haabbccdd, 4'b0101);
    end
    commit(1);
    @(negedge clk);
    if (!ack) $fatal(1, "Second write did not post after drain");
    expect_write(32'heeff9988, 4'b1010);
    req = 0;
    @(negedge clk);

    // An independent master cannot read the old data while the queue drains.
    req = 1;
    we  = 0;
    @(negedge clk);
    if (ack || line_idle) $fatal(1, "Read or line overtook a posted write");
    expect_write(32'heeff9988, 4'b1010);
    commit(1);
    @(negedge clk);
    commit(0);
    if (read_word != 32'heebb99dd) $fatal(1, "Partial writes were reordered or lost");
    req = 0;
    @(negedge clk);
    if (!line_idle) $fatal(1, "Line stayed stalled after drain");

    // The locked write must stay synchronous, as required by SWP.
    req  = 1;
    we   = 1;
    lock = 1;
    data = 32'h98765432;
    mask = 4'hf;
    @(negedge clk);
    if (ack) $fatal(1, "Locked write was posted");
    expect_write(32'h98765432, 4'hf);
    commit(1);
    req  = 0;
    lock = 0;
    @(negedge clk);

    // A write already acknowledged must complete across a logical reset.
    req  = 1;
    data = 32'h01020304;
    @(negedge clk);
    if (!ack) $fatal(1, "Reset-test write did not post");
    client_reset = 1;
    req = 0;
    repeat (3) begin
      @(negedge clk);
      if (ack || backend_reset || line_idle) $fatal(1, "Reset interrupted accepted write");
      expect_write(32'h01020304, 4'hf);
    end
    commit(1);
    if (!backend_reset || word != 32'h01020304 || writes != 4)
      $fatal(1, "Wrong number or final value of physical writes");
    $display("PASS ordered SDRAM posting masks, full queue, RAW, locked write, reset drain");
    $finish;
  end
endmodule
