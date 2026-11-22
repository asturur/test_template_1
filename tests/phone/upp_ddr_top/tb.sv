`timescale 1ns / 1ps
module cold_top;
  // DDRAM_ADDR counts 64-bit beats. The byte reservation starts at 0x31820000.
  localparam [28:0] BASE  = 29'h06304000;
  localparam [28:0] BEATS = 29'd16384;
  reg clk = 0;
  reg warm_reset = 0;
  integer cycles = 0;
  integer accepted = 0;
  integer busy_clocks = 0;
  integer last_beat_at = 0;
  reg expected_ready = 0;
  wire [28:0] addr;
  wire [63:0] data;
  wire [7:0] be, burst;
  wire rd, we;
  reg busy = 1;
  reg [16383:0] seen = 0;
  tri [45:0] hps;
  tri [15:0] sdram_data;

  always #4.808 clk = !clk;
  emu dut (
      .CLK_50M(clk),
      .RESET(warm_reset),
      .HPS_BUS(hps),
      .SDRAM_DQ(sdram_data),
      .DDRAM_BUSY(busy),
      .DDRAM_ADDR(addr),
      .DDRAM_DOUT(64'b0),
      .DDRAM_DOUT_READY(1'b0),
      .DDRAM_DIN(data),
      .DDRAM_BE(be),
      .DDRAM_BURSTCNT(burst),
      .DDRAM_RD(rd),
      .DDRAM_WE(we)
  );

  always @(negedge clk) begin
    // Vary backpressure independently of the offered command.
    busy = (cycles % 19 < 7) || (cycles >= 20 && cycles < 63);
  end

  always @(posedge clk) begin
    cycles = cycles + 1;
    if (we && busy) busy_clocks = busy_clocks + 1;
    if (we && !busy) begin
      if (addr < BASE || addr >= BASE + BEATS)
        $fatal(1, "DDR scrub escaped reservation at %h", addr);
      if (data != 0 || be != 8'hff || burst != 1)
        $fatal(1, "DDR scrub offered bad beat %h : %h mask %h burst %d", addr, data, be, burst);
      if (seen[14'(addr-BASE)]) $fatal(1, "Duplicate scrub beat %h", addr);
      seen[14'(addr-BASE)] = 1;
      accepted = accepted + 1;
      last_beat_at = cycles;
    end
    if (rd) $fatal(1, "Unexpected DDR read before firmware load");
    if (dut.board_init_done && accepted != BEATS)
      $fatal(1, "Board released init while %0d of %0d DDR beats had been written", accepted, BEATS);
    if (!dut.reset || dut.loader_valid || dut.save_mounted)
      $fatal(1, "Fixture accidentally let firmware or mount gate pass");
    if (expected_ready && !dut.board_init_done)
      $fatal(1, "Warm reset unexpectedly discarded scrub state");
    if (cycles > 200000)
      $fatal(1, "DDR cold initialization timeout with %0d beats accepted", accepted);
  end

  initial begin
    force dut.pll_locked = 0;
    repeat (8) @(negedge clk);
    release dut.pll_locked;
    wait (accepted > 200);
    @(negedge clk);
    warm_reset = 1;
    repeat (16) @(negedge clk);
    warm_reset = 0;
    wait (dut.board_init_done);
    @(negedge clk);
    if (~&seen) $fatal(1, "DDR scrub left an address uncleared");
    if (busy_clocks == 0) $fatal(1, "DDR scrub did not encounter backpressure");
    $display("PASS cold scrub %0d exactly-once beats across board initialization, last at %0d",
             accepted, last_beat_at);
    expected_ready = 1;
    warm_reset = 1;
    repeat (16) @(negedge clk);
    warm_reset = 0;
    repeat (16) @(negedge clk);
    $display("PASS warm reset retains both scrubbed banks, CPU waits for external boot gates");
    $finish;
  end
endmodule
