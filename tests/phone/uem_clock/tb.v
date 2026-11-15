`timescale 1ns / 1ps
module tb;
  reg clk = 0;
  always #5 clk = ~clk;
  // Accelerated seconds; the production divider bounds are linted separately.
  parameter SECOND_TICKS = 4096;
  reg reset = 1, req = 0, commit = 0, we = 0;
  reg [32:0] timestamp = 0;
  reg [31:0] addr = 0, din = 0;
  reg [3:0] sel = 0;
  wire claim, bad;
  wire [31:0] dout;
  ngage_cbus_uem #(
      .SECOND_TICKS(SECOND_TICKS)
  ) dut (
      .clk            (clk),
      .reset          (reset),
      .req            (req),
      .commit         (commit),
      .we             (we),
      .addr           (addr),
      .din            (din),
      .sel            (sel),
      .kernel_periodic(1'b1),
      .clear_irq      (1'b0),
      .claim          (claim),
      .bad            (bad),
      .dout           (dout),
      .power_pressed  (1'b0),
      .host_timestamp (timestamp)
  );
  task tick;
    begin
      @(posedge clk);
      #1;
    end
  endtask
  task write_half(input [31:0] address, input [15:0] value, input [3:0] lanes);
    begin
      @(negedge clk);
      req    = 1;
      commit = 1;
      we     = 1;
      addr   = address;
      sel    = lanes;
      din    = lanes == 12 ? {value, 16'b0} : {16'b0, value};
      #1;
      if (!claim || bad) $fatal(1, "CBUS write rejected %h %h", address, value);
      tick();
      @(negedge clk);
      req    = 0;
      commit = 0;
      we     = 0;
    end
  endtask
  task read_reg(input [7:0] index, input [15:0] expected);
    begin
      write_half(32'h0c150420, 7, 3);
      write_half(32'h0c150420, 16'h100 | {8'b0, index}, 12);
      @(negedge clk);
      req  = 1;
      addr = 32'h0c150424;
      sel  = 12;
      #1;
      if (!claim || bad || dout !== {expected, 16'b0})
        $fatal(1, "CBUS read %h = %h expected %h", index, dout, expected);
      @(negedge clk);
      req = 0;
    end
  endtask
  task write_reg(input [7:0] index, input [15:0] value);
    begin
      write_half(32'h0c150420, 7, 3);
      write_half(32'h0c150420, {8'b0, index}, 12);
      write_half(32'h0c150424, value, 12);
    end
  endtask
  task host_set(input [31:0] value);
    begin
      @(negedge clk);
      timestamp[31:0] = value;
      // Partial words/unchanged toggle must never set/restart the clock.
      repeat (8) tick();
      @(negedge clk);
      timestamp[32] = ~timestamp[32];
      repeat (125) tick();
    end
  endtask
  integer fd, got, sec, min, hr, days, k;
  reg [  31:0] value;
  reg [1023:0] vector_path;
  initial begin
    repeat (3) tick();
    reset = 0;
    read_reg(8'h24, 0);
    timestamp[15:0] = 16'hffff;
    repeat (4) tick();
    timestamp[31:16] = 16'hffff;
    repeat (4) tick();
    read_reg(8'h24, 0);
    if (dut.clock_backend.valid) $fatal(1, "partial timestamp accepted");
    if (!$value$plusargs("vectors=%s", vector_path)) $fatal(1, "missing vectors");
    fd = $fopen(vector_path, "r");
    if (!fd) $fatal(1, "vectors open");
    k = 0;
    while (!$feof(
        fd
    )) begin
      got = $fscanf(fd, "%h %d %d %d %d\n", value, hr, min, sec, days);
      if (got == 5) begin
        host_set(value);
        read_reg(8'h24, 1);
        read_reg(8'h31, sec[15:0]);
        read_reg(8'h32, min[15:0]);
        read_reg(8'h33, hr[15:0]);
        read_reg(8'h21, days[15:0]);
        k = k + 1;
      end
    end
    $fclose(fd);
    // Original NOS uses day zero relative to its PMM calendar base.
    host_set(32'd86399);
    write_reg(8'h21, 16'd254);
    // Writes at these aliases are watchdog/vibrator controls, not time.
    write_reg(8'h32, 16'h20);
    read_reg(8'h32, 59);
    @(negedge clk);
    reset = 1;
    repeat (3) tick();
    reset = 0;
    read_reg(8'h24, 1);
    read_reg(8'h31, 59);
    read_reg(8'h21, 254);
    while (dut.clock_backend.second == 59) tick();
    read_reg(8'h31, 0);
    read_reg(8'h32, 0);
    read_reg(8'h33, 0);
    read_reg(8'h21, 255);
    host_set(32'd172800);
    read_reg(8'h21, 0);
    write_reg(8'h21, 0);
    read_reg(8'h21, 0);
    // Calibration guest state is retained by CBUS until phone reset.
    write_reg(8'h24, 16'h37);
    read_reg(8'h24, 16'h37);
    @(negedge clk);
    reset = 1;
    repeat (2) tick();
    reset = 0;
    read_reg(8'h24, 1);
    read_reg(8'h21, 0);
    $display(
        "PASS UEM Unix RTC: %0d epoch vectors, atomic toggles, native aliases, validity, reset retention, day writes and midnight",
        k);
    $finish;
  end
endmodule
