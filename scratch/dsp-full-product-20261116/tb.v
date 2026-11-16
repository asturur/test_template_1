`timescale 1ns / 1ps
module test;
  reg clk = 0, reset = 1, kill_wb = 0, kill_alu = 0, hold_data = 0, cc = 0;
  always #5 clk = ~clk;
  `include "zap_localparams.svh"
  reg [4:0] op = 13;
  reg [31:0] rm = 0, rn = 0, rh = 0, rs = 0;
  wire [31:0] old_rd, new_rd;
  wire old_busy, new_busy, old_zero, new_zero, old_sat, new_sat;
  zap_shifter_multiply old_unit (
      .i_clk(clk),
      .i_reset(reset),
      .i_clear_from_writeback(kill_wb),
      .i_clear_from_alu(kill_alu),
      .i_data_stall(hold_data),
      .i_alu_operation_ff(op),
      .i_cc_satisfied(cc),
      .i_rm(rm),
      .i_rn(rn),
      .i_rh(rh),
      .i_rs(rs),
      .o_rd(old_rd),
      .o_busy(old_busy),
      .o_nozero(old_zero),
      .o_sat(old_sat)
  );
  dsp_full_product_candidate candidate (
      .i_clk(clk),
      .i_reset(reset),
      .i_clear_from_writeback(kill_wb),
      .i_clear_from_alu(kill_alu),
      .i_data_stall(hold_data),
      .i_alu_operation_ff(op),
      .i_cc_satisfied(cc),
      .i_rm(rm),
      .i_rn(rn),
      .i_rh(rh),
      .i_rs(rs),
      .o_rd(new_rd),
      .o_busy(new_busy),
      .o_nozero(new_zero),
      .o_sat(new_sat)
  );
  reg [195:0] vectors[0:2047];
  integer n, phase, step_count, total = 0, clears = 0;
  reg [31:0] rng = 32'h44535033;
  reg [63:0] expected;
  task tick;
    begin
      @(posedge clk);
      #1;
      @(negedge clk);
      #1;
    end
  endtask
  task check_busy;
    begin
      if (old_busy !== new_busy) $fatal(1, "busy schedule differs vector%0d phase%0d", n, phase);
    end
  endtask
  initial begin
    $readmemh("scratch/dsp-full-product-20261116/vectors.hex", vectors);
    repeat (3) tick();
    reset = 0;
    for (n = 0; n < 2048; n = n + 1) begin
      rm = vectors[n][191:160];
      rs = vectors[n][159:128];
      {rh, rn} = vectors[n][127:64];
      expected = vectors[n][63:0];
      // Failed-condition multiply must leave both units idle.
      cc = 0;
      op = vectors[n][192] ? SMLALL : UMLALL;
      #1;
      check_busy();
      if (old_busy || new_rd !== 0) $fatal(1, "failed condition starts multiply");
      tick();
      cc = 1;
      // Abort accepted work under a data hold, then restart as a new owner.
      if (n % 128 == 0) begin
        tick();
        hold_data = 1;
        kill_wb   = 1;
        tick();
        kill_wb = 0;
        cc = 0;
        tick();
        hold_data = 0;
        tick();
        cc = 1;
        clears = clears + 1;
      end
      for (phase = 0; phase < 2; phase = phase + 1) begin
        op = (vectors[n][192] ? SMLALL : UMLALL) + phase;
        step_count = 0;
        #1;
        while (old_busy && step_count < 50) begin
          check_busy();
          rng = {rng[30:0], rng[31] ^ rng[21] ^ rng[1] ^ rng[0]};
          hold_data = rng[0] && rng[2];
          tick();
          step_count = step_count + 1;
        end
        check_busy();
        if(old_busy || old_rd!==(phase?expected[63:32]:expected[31:0]) ||
                   new_rd!==old_rd || new_sat!==old_sat || new_zero!==old_zero)
          $fatal(
              1,
              "arithmetic/flags vector%0d phase%0d old%h new%h expected%h",
              n,
              phase,
              old_rd,
              new_rd,
              expected
          );
        if (phase && old_zero !== (|expected[31:0])) $fatal(1, "paired zero flag differs");
        hold_data = 0;
        tick();
        total = total + 1;
      end
      cc = 0;
      op = MOV;
      tick();
    end
    $display(
        "PASS DSP mapping-only candidate: %0d ordered low/high results, independent signed/unsigned/accumulate oracle, unchanged busy under random holds, %0d held flushes",
        total, clears);
    $finish;
  end
  initial begin
    #2000000;
    $fatal(1, "timeout");
  end
endmodule
