`timescale 1ns / 1ps

// Drive full-rate edges at the FIFO boundary. The public serial test uses
// ordinary commands and pin timing, including stalls and completion order.
module fifo_banks_tb;
  localparam DIV = 3, FIFO_DEPTH = 16;
  reg clk = 0, reset = 1;
  always #5 clk = !clk;

  reg acc = 1, we = 0, wr = 0, rd = 0;
  reg [ 5:0] off = 'h24;
  reg [ 3:0] be = 0;
  reg [31:0] wdata = 0;
  wire [31:0] rmask, rdata;
  wire busy, rx_ready, tx_ready;
  wire [3:0] irq;
  wire mmc_clk, cmd_o, cmd_oe, dat_o, dat_oe;
  wire cmd_i = 1;
  reg  dat_i = 0;
  ngage_mmc_host #(
      .DIV(DIV),
      .RESP_WAIT(12),
      .TIMEOUT_LOG2(10),
      .FIFO_DEPTH(FIFO_DEPTH)
  ) dut (
      .clk(clk),
      .reset(reset),
      .acc(acc),
      .we(we),
      .wr(wr),
      .rd(rd),
      .off(off),
      .be(be),
      .wdata(wdata),
      .rmask(rmask),
      .rdata(rdata),
      .busy(busy),
      .rx_ready(rx_ready),
      .tx_ready(tx_ready),
      .irq(irq),
      .mmc_clk(mmc_clk),
      .cmd_o(cmd_o),
      .cmd_oe(cmd_oe),
      .cmd_i(cmd_i),
      .dat_o(dat_o),
      .dat_oe(dat_oe),
      .dat_i(dat_i)
  );
  `include "fifo_reference.vh"

  reg [31:0] random_bits = 32'h5d492aab;
  reg pulse = 0;
  reg [15:0] write_masks = 0, read_masks = 0;
  integer writes_and_pops = 0, reads_and_pushes = 0, wraps = 0, forwards = 0;
  wire [3:0] bank_forward = {
    dut.banked_fifo.byte_bank[3].forward_byte,
    dut.banked_fifo.byte_bank[2].forward_byte,
    dut.banked_fifo.byte_bank[1].forward_byte,
    dut.banked_fifo.byte_bank[0].forward_byte
  };
  always @(posedge clk)
    if (!reset) begin
      // The old array is the oracle for every live byte, including the
      // serializer head when the CPU endpoint is looking elsewhere.
      for (integer i = 0; i < 4; i++)
      if (i < reference.fcnt &&
                    dut.fifo_bytes[i*8+:8] !== reference.fmem[(int'(reference.frp) + i) & 15])
        $fatal(1, "MMC bank returned the wrong byte at head offset %0d", i);
      if (wr) write_masks[be] <= 1;
      if (rd) read_masks[be] <= 1;
      if (wr && pulse) writes_and_pops <= writes_and_pops + 1;
      if (rd && pulse) reads_and_pushes <= reads_and_pushes + 1;
      if (reference.frp + int'(dut.pop_count) >= 16 || reference.fwp + int'(dut.push_count) >= 16)
        wraps <= wraps + 1;
      if (|bank_forward) forwards <= forwards + 1;
    end

  task automatic step_random;
    @(negedge clk);
    random_bits = {
      random_bits[30:0], random_bits[31] ^ random_bits[21] ^ random_bits[1] ^ random_bits[0]
    };
    be = random_bits[3:0];
    wdata = random_bits;
    dat_i = random_bits[15];
    if (we) begin
      wr = (16 - dut.fcnt >= $countones(be)) && random_bits[17];
      pulse = dut.fcnt != 0 && random_bits[30];
    end else begin
      rd = (dut.fcnt >= $countones(be)) && random_bits[17];
      pulse = dut.fcnt != 16 && random_bits[30];
    end
  endtask

  initial begin
    #1;
    be = 15;
    #1;
    be = 0;
    repeat (4) @(negedge clk);
    force dut.blen = 4096;
    force reference.blen = 4096;
    force dut.rise = 0;
    force reference.rise = 0;
    force dut.fall = pulse;
    force reference.fall = pulse;
    force dut.dbit = 0;
    force reference.dbit = 0;
    force dut.dstate = 5;
    force reference.dstate = 5;
    we = 1;
    reset = 0;
    repeat (2048) step_random();

    @(negedge clk);
    reset = 1;
    wr = 0;
    pulse = 0;
    repeat (2) @(negedge clk);
    force dut.rise = pulse;
    force reference.rise = pulse;
    force dut.fall = 0;
    force reference.fall = 0;
    force dut.dbit = 7;
    force reference.dbit = 7;
    force dut.dstate = 2;
    force reference.dstate = 2;
    we = 0;
    reset = 0;
    repeat (2048) step_random();

    @(negedge clk);
    if (write_masks != 16'hffff || read_masks != 16'hffff ||
            !wraps || !forwards || !writes_and_pops || !reads_and_pushes)
      $fatal(
          1,
          "incomplete MMC FIFO coverage w=%04x r=%04x wrap=%0d fwd=%0d tx=%0d rx=%0d",
          write_masks,
          read_masks,
          wraps,
          forwards,
          writes_and_pops,
          reads_and_pushes
      );
    $display("PASS MMC FIFO all masks, wrap=%0d forwarded=%0d simultaneous TX=%0d RX=%0d", wraps,
             forwards, writes_and_pops, reads_and_pushes);
    $finish;
  end
endmodule
