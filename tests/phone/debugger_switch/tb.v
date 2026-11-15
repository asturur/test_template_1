`timescale 1ns / 1ps
module tb;
  reg clk = 0, reset = 1, valid = 0, ready = 0, done = 0;
  reg [31:0] address = 0, data = 0;
  reg [3:0] be = 0;
  wire a_valid, a_write, a_ready, a_done, b_valid, b_write, b_ready, b_done;
  wire [31:0] a_address, a_data, b_address, b_data;
  wire [3:0] a_be, b_be;
  integer i, seed = 1511;
  always #5 clk = ~clk;
  production_loader_only actual (
      .clk_sys(clk),
      .transport_reset(reset),
      .load_req(valid),
      .load_addr(address),
      .load_data(data),
      .load_be(be),
      .service_ready(ready),
      .service_done(done),
      .service_valid(a_valid),
      .service_write(a_write),
      .service_addr(a_address),
      .service_data(a_data),
      .service_be(a_be),
      .load_ready(a_ready),
      .load_done(a_done)
  );
  ngage_diag_loader_port reference (
      .clk(clk),
      .reset(reset),
      .load_valid(valid),
      .load_addr(address),
      .load_data(data),
      .load_be(be),
      .load_ready(b_ready),
      .load_done(b_done),
      .diag_valid(1'b0),
      .diag_write(1'b0),
      .diag_addr(32'b0),
      .diag_data(32'b0),
      .diag_ready(),
      .diag_done(),
      .diag_rdata(),
      .mem_valid(b_valid),
      .mem_ready(ready),
      .mem_write(b_write),
      .mem_addr(b_address),
      .mem_data(b_data),
      .mem_be(b_be),
      .mem_done(done),
      .mem_rdata(32'b0)
  );
  initial begin
    repeat (2) @(negedge clk);
    reset = 0;
    for (i = 0; i < 5000; i = i + 1) begin
      reset = (i % 113) == 0;
      valid = $random(seed) & 1;
      ready = $random(seed) & 1;
      done = $random(seed) & 1;
      address = $random(seed);
      data = $random(seed);
      be = $random(seed);
      #1;
      if(a_valid!==b_valid || a_ready!==b_ready || a_done!==b_done ||
      (a_valid && (a_write!==b_write || a_address!==b_address || a_data!==b_data || a_be!==b_be)))
        $fatal(1, "loader-only ownership differs clock=%0d", i);
      @(negedge clk);
    end
    $display(
        "PASS disabled-debugger loader:5000cycles, ready/done stalls, overlap and reset, exact retained-loader behavior");
    $finish;
  end
endmodule
