`timescale 1ns / 1ps
module frac_clock_tb;
  reg clk = 0;
  always #4.808 clk = ~clk;
  reg reset = 1;
  reg wr = 0;
  reg [5:0] off = 0;
  reg [31:0] wdata = 0;
  wire mmc_clk, cmd_o, cmd_oe;
  wire [3:0] irq;

  ngage_mmc_host #(
      .FRAC_3_8(1)
  ) dut (
      .clk(clk),
      .reset(reset),
      .acc(wr),
      .we(wr),
      .wr(wr),
      .rd(1'b0),
      .off(off),
      .be(4'hf),
      .wdata(wdata),
      .rmask(),
      .rdata(),
      .busy(),
      .rx_ready(),
      .tx_ready(),
      .irq(irq),
      .mmc_clk(mmc_clk),
      .cmd_o(cmd_o),
      .cmd_oe(cmd_oe),
      .cmd_i(1'b1),
      .dat_o(),
      .dat_oe(),
      .dat_i(1'b1)
  );

  integer clocks = 0, rises = 0, falls = 0, first_rise = 0;
  integer last_rise = 0, last_fall = 0, high_sum = 0;
  integer pulses_in_command = 0, commands = 0;
  reg last_clk = 0;
  reg [47:0] command;

  // Sample on the host and card's shared clock, before NB updates.
  always @(posedge clk)
    if (!reset) begin
      clocks = clocks + 1;
      if (dut.rise !== (mmc_clk && !last_clk)) $fatal(1, "Host and peer sample at different edges");
      if (mmc_clk && !last_clk) begin
        if (pulses_in_command == 0) first_rise = clocks;
        else if (clocks - last_rise < 2 || clocks - last_rise > 3 ||
                         clocks - last_fall < 1 || clocks - last_fall > 2)
          $fatal(1, "Illegal MMC rising/low interval");
        if (pulses_in_command == 3 && clocks - first_rise != 8)
          $fatal(1, "Expected three MMC periods in eight system clocks");
        last_rise = clocks;
        pulses_in_command = pulses_in_command + 1;
        rises = rises + 1;
        if (cmd_oe) command = {command[46:0], cmd_o};
      end
      if (!mmc_clk && last_clk) begin
        if (clocks - last_rise < 1 || clocks - last_rise > 2)
          $fatal(1, "Illegal MMC high interval");
        if (pulses_in_command <= 3) high_sum = high_sum + clocks - last_rise;
        if (pulses_in_command == 3 && high_sum != 4) $fatal(1, "Expected equal high and low time");
        last_fall = clocks;
        falls = falls + 1;
      end
      last_clk = mmc_clk;
    end

  task command_zero;
    begin
      @(negedge clk);
      pulses_in_command = 0;
      high_sum = 0;
      command = 0;
      wr = 1;
      off = 6'h04;
      wdata = 1;
      @(negedge clk);
      wr = 0;
      wait (!irq[2]);
      wait (irq[2]);
      repeat (3) @(negedge clk);
      repeat (12) begin
        @(negedge clk);
        if (mmc_clk) $fatal(1, "MMC clock kept running while idle");
      end
      if (command !== 48'h400000000095 || pulses_in_command < 48 || rises != falls)
        $fatal(1, "CMD0 frame or pulse accounting failed: %h", command);
      commands = commands + 1;
    end
  endtask

  initial begin
    repeat (4) @(negedge clk);
    reset = 0;
    @(negedge clk);
    wr = 1;
    off = 6'h1c;
    wdata = 0;
    @(negedge clk);
    off = 6'h20;
    @(negedge clk);
    wr = 0;
    command_zero;
    command_zero;
    $display("PASS MMC fractional 3/8 clock: CMD0=%0d, rises=%0d, falls=%0d", commands, rises,
             falls);
    $finish;
  end

  initial begin
    #50000;
    $fatal(1, "MMC fractional clock test timed out");
  end
endmodule
