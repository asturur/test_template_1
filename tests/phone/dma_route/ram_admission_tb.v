`timescale 1ns / 1ps

module ram_admission_tb;
  reg clk = 0, reset = 1, lock = 0, valid = 0, write = 0;
  reg local_ready = 0, ram_ack = 0;
  reg [31:0] address = 0, data = 0;
  reg [3:0] mask = 0;
  wire ready, response, error, local_valid, ram_req, ram_write;
  wire [31:0] ram_data, response_data;
  wire [24:0] ram_addr;
  wire [ 3:0] ram_be;

  always #5 clk = ~clk;
  ngage_dma_route dut (
      .clk(clk),
      .reset(reset),
      .cpu_lock(lock),
      .cmd_valid(valid),
      .cmd_ready(ready),
      .cmd_write(write),
      .cmd_addr(address),
      .cmd_data(data),
      .cmd_be(mask),
      .rsp_valid(response),
      .rsp_error(error),
      .rsp_data(response_data),
      .ram_req(ram_req),
      .ram_write(ram_write),
      .ram_addr(ram_addr),
      .ram_data(ram_data),
      .ram_be(ram_be),
      .ram_ack(ram_ack),
      .ram_rdata(32'h12345678),
      .local_valid(local_valid),
      .local_ready(local_ready),
      .local_done(1'b0),
      .local_error(1'b0),
      .local_rdata(32'b0)
  );

  task check_ram_packet;
    if ({ram_req, ram_write, ram_addr, ram_data, ram_be} !==
            {1'b1, 1'b1, 25'h123454, 32'hfeed7654, 4'b1010})
      $fatal(1, "Wrong RAM command fields");
  endtask

  initial begin
    @(negedge clk);
    reset = 0;
    address = 32'h0a123454;
    data = 32'hfeed7654;
    mask = 4'b1010;
    write = 1;
    valid = 1;
    #1;
    if (!ready || local_valid) $fatal(1, "Local readiness blocked RAM admission");
    check_ram_packet();

    // A different command and a younger CPU lock cannot change the owned RAM word.
    @(negedge clk);
    address = 32'h10120624;
    data = 32'h01020304;
    mask = 1;
    write = 0;
    local_ready = 1;
    lock = 1;
    #1;
    if (ready || response || local_valid) $fatal(1, "RAM command lost ownership");
    check_ram_packet();

    @(negedge clk);
    ram_ack = 1;
    #1;
    if (!response || error || response_data !== 32'h12345678)
      $fatal(1, "RAM reply did not retire on the original edge");
    @(negedge clk);
    ram_ack = 0;
    lock = 0;
    local_ready = 0;
    #1;
    if (ready || response || ram_req || !local_valid)
      $fatal(1, "MMC offer did not wait for local readiness after RAM completion");
    $display(
        "PASS DMA RAM admission independent of MMC readiness, with exact held packet and reply");
    $finish;
  end
endmodule
