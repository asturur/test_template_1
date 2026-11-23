`timescale 1ns / 1ps

module walker_case #(
    parameter bit CHECK_WALK = 1'b0
) (
    output bit done
);
  bit clk, reset, inv, mmu_enable = 1, access_rd, hold, access_done;
  bit pause_response, allow_walk = 1;
  bit [31:0] address;
  wire [1:0] busy, hit, fast_hit, ready, fault, cacheable, bufferable, wt;
  wire [1:0] wb_stb, wb_cyc, wb_wen;
  wire [31:0] physical[2], far[2], wb_address[2];
  wire [7:0] fsr[2];
  wire [3:0] wb_sel[2];

  integer cycles = 0, l1_reads = 0, l2_reads = 0, writes = 0, resolved = 0;
  wire registered_request = reference_dut.u_zap_tlb_fsm.wb_stb_ff;
  wire [31:0] registered_address = reference_dut.u_zap_tlb_fsm.wb_adr_ff;
  wire bus_ack = !reset && !pause_response && registered_request && cycles % 4 != 0;
  wire [31:0] bus_data = registered_address[31:28] == 4'h1 ? 32'h2000_0001 :
                          32'h3000_0ffe | (reference_dut.tlb_address & 32'h0fff_f000);

  `define WALKER_PORTS(leg) \
      .i_clk(clk), .i_reset(reset), .i_address(address), .i_address_check(address), \
      .i_address_nxt(address), .i_wr_check(1'b0), .i_rd_check(access_rd), .i_hold(hold), \
      .i_cpsr(5'h13), .i_sr(2'b00), .i_dac_reg(32'hffff_ffff), \
      .i_baddr(32'h1000_0000), .i_mmu_en(mmu_enable), .i_inv(inv), \
      .o_phy_addr(physical[leg]), .o_fsr(fsr[leg]), .o_far(far[leg]), .o_fault(fault[leg]), \
      .o_cacheable(cacheable[leg]), .o_bufferable(bufferable[leg]), .o_wt(wt[leg]), \
      .o_busy(busy[leg]), .o_hit_ready(ready[leg]), .o_hit_ok(hit[leg]), \
      .o_hit_ok_short(fast_hit[leg]), .i_idle(allow_walk), .i_access_done(access_done), \
      .i_access(access_rd), .o_wb_stb_nxt(wb_stb[leg]), .o_wb_cyc_nxt(wb_cyc[leg]), \
      .o_wb_adr_nxt(wb_address[leg]), .o_wb_wen_nxt(wb_wen[leg]), .o_wb_sel_nxt(wb_sel[leg]), \
      .i_wb_dat(bus_data), .o_wb_dat_nxt(), .i_wb_ack(bus_ack), .i_wb_err(1'b0)

  reference_zap_tlb #(
      .SPAGE_TLB_ENTRIES(256),
      .SPAGE_TLB_WAYS(2),
      .CHECK_WALK(CHECK_WALK),
      .SECTION_INDEX_XOR(CHECK_WALK)
  ) reference_dut (
      `WALKER_PORTS(0)
  );
  ngage2_zap_tlb #(
      .SPAGE_TLB_ENTRIES(256),
      .SPAGE_TLB_WAYS(2),
      .CHECK_WALK(CHECK_WALK),
      .SECTION_INDEX_XOR(CHECK_WALK)
  ) ram_dut (
      `WALKER_PORTS(1)
  );
  `undef WALKER_PORTS

  task automatic check_same;
    if ({busy[0], hit[0], fast_hit[0], ready[0], fault[0], fsr[0], far[0], cacheable[0],
             bufferable[0], wt[0], physical[0], wb_stb[0], wb_cyc[0], wb_wen[0], wb_sel[0]} !==
            {busy[1], hit[1], fast_hit[1], ready[1], fault[1], fsr[1], far[1], cacheable[1],
             bufferable[1], wt[1], physical[1], wb_stb[1], wb_cyc[1], wb_wen[1], wb_sel[1]} ||
            (wb_stb[0] && wb_address[0] !== wb_address[1]) ||
            {reference_dut.sptlb_wen, reference_dut.sptlb_wen_way, reference_dut.sp_way,
             reference_dut.sp_again} !==
            {ram_dut.sptlb_wen, ram_dut.sptlb_wen_way, ram_dut.sp_way, ram_dut.sp_again})
      $fatal(1, "check walk %0d: TLB difference at cycle %0d VA %h", CHECK_WALK, cycles, address);
  endtask

  task automatic tick;
    #1;
    if (cycles > 1) check_same();
    if (bus_ack) begin
      if (registered_address[31:28] == 4'h1) l1_reads++;
      else if (registered_address[31:28] == 4'h2) l2_reads++;
      else $fatal(1, "Unexpected descriptor address %h", registered_address);
    end
    if (!reset && ram_dut.sptlb_wen) writes++;
    clk = 1;
    #1;
    clk = 0;
    #1;
    if (cycles > 1) check_same();
    cycles++;
  endtask

  task automatic lookup(input bit [31:0] va, input bit miss);
    int l1_before, l2_before, for_cycles;
    bit [31:0] physical_expected;
    access_rd = 0;
    address   = va;
    tick();
    access_rd = 1;
    allow_walk = 1;
    l1_before = l1_reads;
    l2_before = l2_reads;
    physical_expected = 32'h3000_0000 | va;
    for_cycles = 0;
    do begin
      tick();
      // Once admitted, the cache owns this access until its
      // translation returns. Suppress stale miss re-admission.
      if (reference_dut.u_zap_tlb_fsm.state_ff != 7'd1) allow_walk = 0;
      for_cycles++;
      if (for_cycles == 48)
        $fatal(
            1,
            "CHECK_WALK=%0d lookup timeout at %h physical=%h hit=%b busy=%b %d:%d",
            CHECK_WALK,
            va,
            physical[0],
            fast_hit[0],
            busy[0],
            l1_reads,
            l2_reads
        );
    end while (!fast_hit[0] || busy[0] || physical[0] != physical_expected);
    if (l1_reads - l1_before != int'(miss) || l2_reads - l2_before != int'(miss))
      $fatal(
          1,
          "CHECK_WALK=%0d lookup %h missed %0d:%0d, expected miss=%b",
          CHECK_WALK,
          va,
          l1_reads - l1_before,
          l2_reads - l2_before,
          miss
      );
    resolved++;
    access_rd   = 0;
    allow_walk  = 0;
    access_done = 1;
    tick();
    access_done = 0;
  endtask

  task automatic reset_tlb;
    reset = 1;
    access_rd = 0;
    tick();
    reset = 0;
    repeat (3) tick();
  endtask

  initial begin
    reset_tlb();
    // Populate and hit both ways of every set through real L1/L2 walks.
    for (int tag_idx = 1; tag_idx < 3; tag_idx++)
    for (int idx = 0; idx < 256; idx++) lookup((tag_idx << 20) | (idx << 12), 1);
    for (int tag_idx = 1; tag_idx < 3; tag_idx++)
    for (int idx = 0; idx < 256; idx++) lookup((tag_idx << 20) | (idx << 12), 0);

    // A third page evicts the original way, preserving the second.
    for (int idx = 0; idx < 256; idx += 17) begin
      lookup(32'h0030_0000 | (idx << 12), 1);
      lookup(32'h0020_0000 | (idx << 12), 0);
      lookup(32'h0010_0000 | (idx << 12), 1);
    end
    // Repeat a warm reset with an in-flight descriptor request.
    for (int pass = 0; pass < 12; pass++) begin
      address = 32'h0040_0000 | (pass << 12);
      tick();
      access_rd = 1;
      allow_walk = 1;
      pause_response = 1;
      repeat (6) tick();
      if (!busy[0] || !registered_request) $fatal(1, "Warm reset did not interrupt an active walk");
      reset_tlb();
      pause_response = 0;
      lookup(32'h0100_0000 | (pass << 12), 1);
      lookup(32'h0110_0000 | (pass << 12), 1);
      lookup(32'h0100_0000 | (pass << 12), 0);
      inv  = 1;
      hold = 1;
      tick();
      inv  = 0;
      hold = 0;
      tick();
      lookup(32'h0100_0000 | (pass << 12), 1);
      mmu_enable = 0;
      repeat (2) tick();
      mmu_enable = 1;
      lookup(32'h0100_0000 | (pass << 12), 1);
    end
    $display("PASS walker check=%0d cycles=%0d resolved=%0d l1=%0d l2=%0d small_fills=%0d",
             CHECK_WALK, cycles, resolved, l1_reads, l2_reads, writes);
    done = 1;
  end
endmodule

module walker_tb;
  wire code_done, data_done;
  walker_case #(.CHECK_WALK(1'b0)) code_tlb (code_done);
  walker_case #(.CHECK_WALK(1'b1)) data_tlb (data_done);
  initial begin
    wait (code_done && data_done);
    $finish;
  end
endmodule
