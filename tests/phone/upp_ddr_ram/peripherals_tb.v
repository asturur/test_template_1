`timescale 1ns / 1ps
module tb;
  reg clk = 0;
  always #5 clk = ~clk;

  localparam UPLOAD = 32'h0c0303f0;
  localparam NOS = 32'h0c1003f0;
  localparam UPLOAD_END = 32'h0c03fffc;
  localparam NOS_END = 32'h0c10fffc;
  localparam MDI_PTR = 32'h0c1003e8;
  localparam MDI_RING = 32'h0c1003e4;
  localparam AUX = 32'h0c06ff00;
  localparam NOS4K = 32'h0c0047fc;

  reg rst = 1, cold = 1, req = 0, wr = 0, authorize = 0, complete = 1;
  reg [31:0] adr = 0, data = 0;
  reg [3:0] lanes = 15;
  wire claim, ready, bad, init_done;
  wire [31:0] result;
  wire ddr_req, ddr_we, ddr_ack, ddr_clear, ddr_clear_done, ddr_idle, ddr_pending;
  wire [16:2] ddr_addr;
  wire [31:0] ddr_wdata, ddr_rdata;
  wire [3:0] ddr_be;

  ngage_board #(
      .DDR_UPP_RAM(1)
  ) dut (
      .clk(clk),
      .rst(rst),
      .init_rst(cold),
      .cyc(req),
      .stb(req),
      .we(wr),
      .adr(adr),
      .din(data),
      .sel(lanes),
      .commit(authorize && !rst),
      .cfg_lcd(1'b1),
      .cfg_keypad(1'b1),
      .cfg_clocks(1'b1),
      .keys(27'd0),
      .sim_present(1'b0),
      .dma_irq_pending(1'b0),
      .sim_fiq_pending(1'b0),
      .claim(claim),
      .ready(ready),
      .unmodeled(bad),
      .dout(result),
      .init_done(init_done),
      .upp_ddr_req(ddr_req),
      .upp_ddr_we(ddr_we),
      .upp_ddr_addr(ddr_addr),
      .upp_ddr_wdata(ddr_wdata),
      .upp_ddr_be(ddr_be),
      .upp_ddr_ack(ddr_ack),
      .upp_ddr_rdata(ddr_rdata),
      .upp_ddr_clear(ddr_clear),
      .upp_ddr_clear_done(ddr_clear_done),
      .upp_ddr_idle(ddr_idle)
  );
  defparam dut.upp.peripherals.REGISTER_RESPONSES = 1;

  upp_ddr_test_peer peer (
      .clk(clk),
      .cold(cold),
      .complete(complete),
      .req(ddr_req),
      .we(ddr_we),
      .addr(ddr_addr),
      .wdata(ddr_wdata),
      .be(ddr_be),
      .ack(ddr_ack),
      .rdata(ddr_rdata),
      .clear(ddr_clear),
      .clear_done(ddr_clear_done),
      .pending(ddr_pending)
  );

  task step;
    begin
      @(negedge clk);
      #1;
    end
  endtask

  task start;
    input write_op;
    input [31:0] address, value;
    input [3:0] mask;
    begin
      req = 1;
      wr = write_op;
      adr = address;
      data = value;
      lanes = mask;
    end
  endtask

  task read_or_write;
    input write_op, expect_bad, external_access;
    input [31:0] address, value, expect_read;
    input [3:0] mask;
    integer count_before;
    reg [31:0] held_result;
    begin
      step();
      count_before = peer.accepted;
      authorize = 0;
      start(write_op, address, value, mask);
      repeat (3) step();
      if (ddr_req || ready) $fatal(1, "Completion or DDR request before authorization");
      authorize = 1;
      while (!ready) step();
      if (!claim || bad !== expect_bad || (!write_op && result !== expect_read))
        $fatal(1, "Bad result @%h: %h vs %h, error=%b", address, result, expect_read, bad);
      held_result = result;
      repeat (3) begin
        step();
        if (!ready || result !== held_result) $fatal(1, "Response changed while held");
      end
      if (peer.accepted != count_before + external_access)
        $fatal(1, "Wrong DDR launch count @%h", address);
      req = 0;
      authorize = 0;
      step();
    end
  endtask

  task put;
    input [31:0] addr, value;
    input [3:0] mask;
    input external_access;
    begin
      read_or_write(1, 0, external_access, addr, value, 0, mask);
    end
  endtask

  task get;
    input [31:0] addr, value;
    input external_access;
    begin
      read_or_write(0, 0, external_access, addr, 0, value, 15);
    end
  endtask

  initial begin
    repeat (4) step();
    cold = 0;
    repeat (16395) step();
    if (init_done || peer.clear_count != 0) $fatal(1, "CPU release raced slow DDR initialization");
    wait (init_done);
    step();
    rst = 0;
    get(UPLOAD, 0, 1);
    get(NOS, 0, 1);
    get(UPLOAD_END, 0, 1);
    get(NOS_END, 0, 1);
    put(UPLOAD, 32'h12345678, 15, 1);
    put(NOS, 32'h87654321, 15, 1);
    put(NOS, 32'h0000aabb, 3, 1);
    put(NOS, 32'hccdd0000, 12, 1);
    put(UPLOAD, 32'h23, 1, 1);
    put(UPLOAD, 32'hff00, 2, 1);
    put(UPLOAD, 32'h110000, 4, 1);
    put(UPLOAD, 32'h07000000, 8, 1);
    put(UPLOAD + 4, 32'h8300face, 15, 1);
    put(NOS + 4, 32'h8300bead, 15, 1);
    put(UPLOAD_END, 32'h01234567, 15, 1);
    put(NOS_END, 32'h89abcdef, 15, 1);
    read_or_write(1, 1, 0, NOS, 0, 0, 5);
    get(UPLOAD, 32'h0711ff23, 1);
    get(NOS, 32'hccddaabb, 1);
    get(UPLOAD + 4, 32'h8300face, 1);
    get(NOS + 4, 32'h8300bead, 1);
    put(MDI_PTR, 32'h00030002, 15, 0);
    get(MDI_PTR, 32'h00030002, 0);
    put(MDI_RING, 32'h10203040, 15, 0);
    get(MDI_RING, 32'h10203040, 0);
    put(AUX, 32'h01020304, 15, 0);
    put(NOS4K, 32'h05060708, 15, 0);

    // Withdraw an authorized read in flight. Its replacement cannot
    // use the stale completion, even when requesting the other bank.
    complete  = 0;
    authorize = 1;
    start(0, UPLOAD, 0, 15);
    wait (ddr_pending);
    step();
    req = 0;
    step();
    start(0, NOS, 0, 15);
    complete = 1;
    while (!ready) step();
    if (result !== 32'hccddaabb) $fatal(1, "Stale DDR result completed a new request");
    req = 0;
    step();

    // A warm reset suppresses the guest's result but retains accepted
    // write data and keeps transport ownership until ACK.
    complete = 0;
    start(1, NOS_END, 32'hff000000, 8);
    wait (ddr_pending);
    step();
    rst = 1;
    req = 0;
    repeat (4) begin
      step();
      if (ddr_idle || ready || !ddr_req || ddr_clear)
        $fatal(1, "Warm reset dropped a live command or restarted clear");
    end
    complete = 1;
    wait (ddr_idle);
    step();
    rst = 0;
    get(UPLOAD_END, 32'h01234567, 1);
    get(NOS_END, 32'hffabcdef, 1);
    get(MDI_PTR, 0, 0);
    get(AUX, 32'h01020304, 0);
    get(NOS4K, 32'h05060708, 0);
    if (peer.clear_count != 1) $fatal(1, "Warm reset cleared DDR");

    step();
    rst  = 1;
    cold = 1;
    step();
    cold = 0;
    wait (init_done);
    step();
    rst = 0;
    get(UPLOAD, 0, 1);
    get(NOS, 0, 1);
    get(UPLOAD_END, 0, 1);
    get(NOS_END, 0, 1);
    get(AUX, 0, 0);
    get(NOS4K, 0, 0);
    if (peer.clear_count != 2) $fatal(1, "Expected one completed clear per cold reset");
    $display(
        "PASS UPP DDR owner, all legal lanes and invalid mask, exactly-once handshakes, warm drain, cold clear");
    $finish;
  end

  initial begin
    #2000000;
    $fatal(1, "Timeout");
  end
endmodule
