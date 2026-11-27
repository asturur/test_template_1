`timescale 1ns / 1ps

// Focused internal schedule for three simultaneous lookups with a pending
// publication. Public command and HPS protocol are covered by the wire tests.
module stream_lookup_tb;
  reg clk = 0, reset = 1, publish = 0;
  always #5 clk = !clk;
  reg [3:0] slot = 0;
  reg [22:0] sector = 0, low = 0, high = 0, prefetch = 0;
  wire present;

  mmc_card_equivalence dut (
      .clk(clk),
      .reset(reset),
      .mmc_clk(1'b0),
      .cmd_i(1'b1),
      .dat_i(1'b1),
      .stop_queued(1'b0),
      .img_mounted(1'b0),
      .img_readonly(1'b0),
      .img_size(64'b0),
      .sd_ack(1'b1),
      .sd_buff_wr(publish),
      .sd_buff_addr(13'h0ff),
      .sd_buff_dout(16'b0),
      .present(present)
  );

  // Drive both implementations from the same deliberately concurrent
  // lookup and publication schedule. No private tag storage is initialized.
  initial begin
    force dut.ported.s0_rlo = low;
    force dut.reference.s0_rlo = low;
    force dut.ported.s0_rhi = high;
    force dut.reference.s0_rhi = high;
    force dut.ported.s0_pchunk = prefetch;
    force dut.reference.s0_pchunk = prefetch;
    repeat (4) @(negedge clk);
    reset = 0;
    force dut.ported.present = 1;
    force dut.reference.present = 1;
    force dut.ported.h_state = 2'd2;
    force dut.reference.h_state = 2'd2;
    force dut.ported.h_meta = 0;
    force dut.reference.h_meta = 0;
    force dut.ported.h_wr = 0;
    force dut.reference.h_wr = 0;
    force dut.ported.h_cur_slot = slot;
    force dut.reference.h_cur_slot = slot;
    force dut.ported.h_stream_sec = sector;
    force dut.reference.h_stream_sec = sector;

    // Fill all four lanes of each modulo-three quarter. Every port
    // receives a separate publication collision against the poisoned RAM.
    for (integer index = 0; index < 12; index++) begin
      slot = index[3:0];
      sector = 23'(index);
      low = 23'(index);
      high = 23'((index + 11) % 12);
      prefetch = 23'((index + 10) % 12);
      publish = 1;
      @(negedge clk);
      publish = 0;
      @(negedge clk);
      if (dut.ported.s1_forward !== 3'b001 || !dut.ported.s2_slo_ok)
        $fatal(1, "low slot %0d bypass missed", index);
    end
    for (integer index = 0; index < 12; index++) begin
      // Replace occupied slots with sectors 12–23, which map to the
      // original physical addresses. The untouched ports retain hits.
      slot = index[3:0];
      sector = 23'(index + 12);
      low = 23'((index + 11) % 12);
      high = index[0] ? sector : 23'((index + 10) % 12);
      prefetch = index[0] ? 23'((index + 10) % 12) : sector;
      publish = 1;
      @(negedge clk);
      publish = 0;
      @(negedge clk);
      if (dut.ported.s1_forward !== (index[0] ? 3'b010 : 3'b100) ||
                !(index[0] ? dut.ported.s2_shi_ok : dut.ported.s2_spc_ok))
        $fatal(1, "high/prefetch slot %0d bypass missed", index);
    end
    repeat (3) @(negedge clk);
    if (dut.colliding_hits != 24)
      $fatal(1, "expected 24 observed collision hits, got %0d", dut.colliding_hits);
    $display("PASS MMC all 12 stream slots and three poisoned lookup ports");
    $finish;
  end
endmodule
