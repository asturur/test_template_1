`timescale 1ns / 1ps
// Independent permission oracle drives the real table/walker publication path.
module test;
  reg clk = 0, reset = 1;
  always #5 clk = ~clk;
  reg rd = 1, wr = 0, mmu = 1, idle = 1, complete = 0;
  reg inv = 0, inv_mva = 0, lock_write = 0;
  reg [31:0] va = 32'h80601868, invalidate_address = 0;
  reg [31:0] ttbr = 32'h0a074000, dac = 32'h00003000;
  reg [4:0] mode_bits = 5'h13;
  reg [1:0] sr = 0;
  reg [31:0] l1 = 32'h0a2000c1, l2 = 32'h0a123ff2;
  reg abort_l1 = 0, abort_l2 = 0, hold_bus = 0;
  wire busy, fault, owner, cyc, stb;
  wire [7:0] fsr;
  wire [31:0] far_address, physical, bus_address;
  reg ack = 0, bus_error = 0;
  reg staged_request = 0;
  reg [31:0] staged_address = 0, bus_data = 0;
  integer lookups = 0, beats = 0, checks = 0;

  always @(posedge clk) begin
    staged_request <= cyc && stb;
    staged_address <= bus_address;
    if (!reset && dut.bank_lookup) lookups <= lookups + 1;
  end
  always @(negedge clk) begin
    ack = 0;
    bus_error = 0;
    if (staged_request && !hold_bus) begin
      bus_data = staged_address < 32'h0a200000 ? l1 : l2;
      bus_error = staged_address < 32'h0a200000 ? abort_l1 : abort_l2;
      ack = !bus_error;
      beats = beats + 1;
    end
  end

  arm920_tlb dut (
      .i_clk(clk),
      .i_reset(reset),
      .i_address(va),
      .i_request_rd(rd),
      .i_request_wr(wr),
      .i_cpsr(mode_bits),
      .i_sr(sr),
      .i_dac_reg(dac),
      .i_baddr(ttbr),
      .i_mmu_en(mmu),
      .i_inv(inv),
      .i_inv_mva(inv_mva),
      .i_inv_address(invalidate_address),
      .i_lock_write(lock_write),
      .i_lock_data(32'b0),
      .i_complete(complete),
      .i_idle(idle),
      .o_busy(busy),
      .o_checked_owner(owner),
      .o_fault(fault),
      .o_fsr(fsr),
      .o_far(far_address),
      .o_phy_addr(physical),
      .o_wb_cyc_nxt(cyc),
      .o_wb_stb_nxt(stb),
      .o_wb_adr_nxt(bus_address),
      .i_wb_dat(bus_data),
      .i_wb_ack(ack),
      .i_wb_err(bus_error)
  );

  task tick;
    begin
      @(negedge clk);
      #1;
    end
  endtask
  task settle;
    integer n;
    begin
      n = 0;
      #1;
      while (busy && n < 100) begin
        tick();
        n = n + 1;
      end
      if (busy || !owner) $fatal(1, "translation failed to settle VA=%h", va);
    end
  endtask
  task invalidate;
    begin
      inv = 1;
      tick();
      inv = 0;
      settle();
    end
  endtask

  // ARM920 AP/S/R/domain rules, independent of the DUT helper.
  function allowed;
    input integer ap, domain_access, system_bits, mode_value;
    input write_access;
    begin
      allowed = 0;
      if (domain_access == 3) allowed = 1;
      else if (domain_access == 1) begin
        case (ap)
          0:
          allowed = !write_access && (system_bits == 1 || (system_bits == 2 && mode_value != 16));
          1: allowed = mode_value != 16;
          2: allowed = mode_value != 16 || !write_access;
          3: allowed = 1;
        endcase
      end
    end
  endfunction

  task check_hot;
    input read_access, write_access, expect_allowed;
    input [7:0] expected_fsr;
    integer prior_lookups, prior_beats;
    begin
      prior_lookups = lookups;
      prior_beats = beats;
      rd = read_access;
      wr = write_access;
      #1;
      if (busy || !owner)
        $fatal(1, "direction change repeated lookup rd=%b wr=%b VA=%h", rd, wr, va);
      if (fault !== !expect_allowed || fsr !== (expect_allowed ? 8'b0 : expected_fsr))
        $fatal(
            1,
            "permission mismatch mode=%h SR=%h DAC=%h rd/wr=%b%b fsr=%h expected=%h",
            mode_bits,
            sr,
            dac,
            rd,
            wr,
            fsr,
            expected_fsr
        );
      if (fault && far_address !== va) $fatal(1, "fault lost actual request address");
      complete = 1;
      tick();
      complete = 0;
      if (lookups != prior_lookups || beats != prior_beats || busy)
        $fatal(1, "permission response evicted reusable mapping");
      checks = checks + 1;
    end
  endtask

  integer kind, ap, access_mode, system_bits, mode_index, quarter;
  integer saved_lookups, saved_beats, expected_code;
  reg can_read, can_write;
  initial begin
    repeat (4) tick();
    reset = 0;
    // Every page class, AP/domain/S/R combination, User/SVC/FIQ, and both
    // directions (including the combined read/write class used by SWP).
    for (kind = 0; kind < 4; kind = kind + 1)
    for (ap = 0; ap < 4; ap = ap + 1)
    for (access_mode = 0; access_mode < 4; access_mode = access_mode + 1)
    for (system_bits = 0; system_bits < 4; system_bits = system_bits + 1)
    for (mode_index = 0; mode_index < 3; mode_index = mode_index + 1) begin
      mode_bits = mode_index == 0 ? 5'h10 : mode_index == 1 ? 5'h13 : 5'h11;
      sr = system_bits;
      dac = access_mode << 12;  // Domain six.
      va = 32'h80601868;
      rd = 1;
      wr = 0;
      l1 = kind == 0 ? 32'h0a0000ce | (ap << 10) : kind == 3 ? 32'h0a2000c3 : 32'h0a2000c1;
      case (kind)
        1: l2 = 32'h0a10000d | ({4{ap[1:0]}} << 4);
        2: l2 = 32'h0a12300e | ({4{ap[1:0]}} << 4);
        3: l2 = 32'h0a123c0f | (ap << 4);
      endcase
      invalidate();
      can_read = allowed(ap, access_mode, system_bits, mode_bits, 0);
      can_write = allowed(ap, access_mode, system_bits, mode_bits, 1);
      expected_code = 8'h60 | (access_mode == 1 ? (kind == 0 ? 13 : 15) : (kind == 0 ? 9 : 11));
      check_hot(0, 1, can_write, expected_code);
      check_hot(1, 0, can_read, expected_code);
      check_hot(1, 1, can_write, expected_code);
      check_hot(1, 0, can_read, expected_code);
      rd = 0;
      wr = 0;
      complete = 1;
      repeat (2) tick();
      if (fault || fsr || !dut.token_valid) $fatal(1, "idle ACK consumed a mapping");
      complete = 0;
    end

    // AP quarters must be rechecked at their actual boundaries, without
    // external walks on already resident large/small-page descriptors.
    mode_bits = 5'h10;
    sr = 0;
    dac = 32'h00001000;
    for (kind = 1; kind <= 2; kind = kind + 1) begin
      va = 32'h80600040;
      rd = 1;
      wr = 0;
      l1 = 32'h0a2000c1;
      l2 = kind == 1 ? 32'h0a100e4d : 32'h0a123e4e;
      invalidate();
      saved_beats = beats;
      for (quarter = 0; quarter < 4; quarter = quarter + 1) begin
        va = 32'h80600040 + (quarter << (kind == 1 ? 14 : 10));
        settle();
        check_hot(0, 1, quarter == 3, 8'h6f);
        check_hot(1, 0, quarter >= 2, 8'h6f);
        if (beats != saved_beats) $fatal(1, "resident AP boundary walked again");
      end
    end

    // Context, invalidation and lock changes revoke a local permission.
    mode_bits = 5'h13;
    dac = 32'h00003000;
    va = 32'h80601868;
    l1 = 32'h0a2000c1;
    l2 = 32'h0a123ffe;
    rd = 1;
    wr = 0;
    invalidate();
    mode_bits = 5'h11;
    #1;
    if (!busy || owner) $fatal(1, "FIQ reused SVC permission");
    settle();
    sr = 1;
    #1;
    if (!busy || owner) $fatal(1, "S/R context was ignored");
    settle();
    dac = 32'h00001000;
    #1;
    if (!busy || owner) $fatal(1, "DACR context was ignored");
    settle();
    ttbr = 32'h0a070000;
    #1;
    if (!busy || owner) $fatal(1, "TTBR context was ignored");
    settle();
    va = 32'h80701868;
    #1;
    if (!busy || owner) $fatal(1, "different FCSE/MVA reused permission");
    settle();
    inv_mva = 1;
    invalidate_address = va;
    invalidate();
    inv_mva = 0;
    lock_write = 1;
    tick();
    lock_write = 0;
    if (owner) $fatal(1, "lock mutation retained token");
    settle();
    mmu = 0;
    tick();
    if (fault || physical !== va || !owner) $fatal(1, "MMU-off passthrough failed");
    mmu = 1;
    #1;
    if (!busy || owner) $fatal(1, "MMU enable retained stale permission");
    settle();

    // Failed translations/walks are exact operation results, not reusable
    // permission mappings. An idle ACK must not eat the pending fault.
    for (kind = 0; kind < 4; kind = kind + 1) begin
      l1 = kind == 0 ? 0 : 32'h0a2000c1;
      l2 = kind == 1 ? 0 : 32'h0a123ffe;
      abort_l1 = kind == 2;
      abort_l2 = kind == 3;
      va = 32'h80601868;
      rd = 1;
      wr = 0;
      invalidate();
      expected_code = kind == 0 ? 8'h05 : kind == 1 ? 8'h67 : kind == 2 ? 8'h0c : 8'h6e;
      if (!fault || fsr != expected_code) $fatal(1, "walk fault lost kind=%0d fsr=%h", kind, fsr);
      saved_lookups = lookups;
      rd = 0;
      complete = 1;
      repeat (2) tick();
      if (fault || !dut.token_valid) $fatal(1, "idle ACK consumed walk fault");
      idle = 0;
      rd   = 1;
      va   = va + 4;
      #1;
      if (fault || owner) $fatal(1, "walk fault reused for neighboring operation");
      va = va - 4;
      #1;
      if (!fault || fsr != expected_code) $fatal(1, "original fault owner lost");
      tick();
      complete = 0;
      abort_l1 = 0;
      abort_l2 = 0;
      l1 = 32'h0a2000c1;
      l2 = 32'h0a123ffe;
      idle = 1;
      settle();
      if (fault || lookups <= saved_lookups) $fatal(1, "fault was cached across retry");
      check_hot(0, 1, 1, 0);
    end
    $display(
        "PASS: %0d hot permission checks, all AP/domain/SR/User/SVC/FIQ/page classes, SWP direction, AP boundaries, context/invalidation/lock/MMU and exact walk-fault retry/idle ACK",
        checks);
    $finish;
  end
  initial begin
    #10000000;
    $fatal(1, "timeout");
  end
endmodule
