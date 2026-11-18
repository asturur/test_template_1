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
  reg [31:0] lock_data = 0;
  wire cb_cache, cb_buffer;
  wire [7:0] external_fsr;
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

  arm920_tlb
`ifdef TEST_THIRD_MAPPING
      #(.THIRD_MAPPING(1))
`endif
      dut (
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
      .i_lock_data(lock_data),
      .i_complete(complete),
      .i_idle(idle),
      .o_busy(busy),
      .o_cacheable(cb_cache),
      .o_bufferable(cb_buffer),
      .o_external_fsr(external_fsr),
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

  reg [31:0] first_va, second_address;
  reg [31:0] first_pa, second_physical;
  integer kind, n, context_case, before_lookups, before_beats;

  task reset_core;
    begin
      rd = 0;
      wr = 0;
      reset = 1;
      repeat (4) tick();
      reset = 0;
      mode_bits = 5'h10;
      sr = 0;
      dac = 32'h00001000;
      ttbr = 32'h0a074000;
      mmu = 1;
      idle = 1;
      inv = 0;
      lock_write = 0;
      complete = 0;
    end
  endtask

  task prepare_pair;
    input integer page_kind;
    begin
      reset_core();
      first_va = 32'h80600044;
      // Both mappings have equal low offsets. Tiny/small pages are also tested
      // only 4KiB apart, matching the original matrix kernel's source arrays.
      second_address = first_va + (page_kind >= 2 ? 4096 : 1048576);
      first_pa = 32'h0a100044;
      second_physical = 32'h0b200044;
      l1 = page_kind == 0 ? 32'h0a1008ca : page_kind == 3 ? 32'h0a2000c3 : 32'h0a2000c1;
      l2 = page_kind == 1 ? 32'h0a100aa9 : page_kind == 2 ? 32'h0a100aaa : 32'h0a10002b;
      va = first_va;
      rd = 1;
      settle();
      if (fault || physical != first_pa || !cb_cache || cb_buffer)
        $fatal(1, "first mapping publication failed kind=%0d PA=%h", page_kind, physical);
      l1 = page_kind == 0 ? 32'h0b200cce : page_kind == 3 ? 32'h0a2000c3 : 32'h0a2000c1;
      l2 = page_kind == 1 ? 32'h0b200ffd : page_kind == 2 ? 32'h0b200ffe : 32'h0b20003f;
      va = second_address;
      settle();
      if (fault || physical != second_physical || !cb_cache || !cb_buffer)
        $fatal(1, "second mapping publication failed kind=%0d PA=%h", page_kind, physical);
      before_beats = beats;
      va = first_va;
      settle();  // Main-table hit retains the previous primary as slot two.
      if (beats != before_beats) $fatal(1, "rewarming pair repeated a walk");
    end
  endtask

  task hot_pair;
    input integer page_kind;
    integer prior_lookups, prior_beats, index;
    begin
      prior_lookups = lookups;
      prior_beats   = beats;
      for (index = 0; index < 32; index = index + 1) begin
        va = index[0] ? first_va : second_address;
        rd = index[1] || !index[2];
        wr = !rd || index[3];  // Includes the combined R/W SWP permission class.
        #1;
        if (busy || !owner) $fatal(1, "two mappings repeated a lookup kind=%0d", page_kind);
        if (physical !== (index[0] ? first_pa : second_physical))
          $fatal(1, "mapping selected wrong physical address");
        if (fault !== (index[0] && wr) ||
            fsr !== (index[0] && wr ? (page_kind == 0 ? 8'h6d : 8'h6f) : 8'b0))
          $fatal(1, "mapping selected wrong direction permission/FSR");
        if (!cb_cache || cb_buffer !== !index[0] ||
            external_fsr !== (page_kind == 0 ? 8'h68 : 8'h6a))
          $fatal(1, "mapping selected wrong CB/external FSR");
        complete = 1;
        tick();
        complete = 0;
        checks   = checks + 1;
      end
      if (lookups != prior_lookups || beats != prior_beats)
        $fatal(1, "alternating mappings performed hidden lookup/walk");
    end
  endtask

`ifdef TEST_THIRD_MAPPING
  localparam [31:0] A=32'h80000044, B=32'h80100044,
                    C=32'h80200044, D=32'h80300044;

  task warm_three;
    begin
      reset_core();
      rd=1;
      va=A;
      l1=32'h100008ca;  // Domain 6, AP2 user reads only, C=1 B=0.
      settle();
      va=B;
      l1=32'h10100cce;  // Domain 6, AP3 read and write.
      settle();
      va=C;
      l1=32'h10200cce;
      settle();
      va=D;
      l1=32'h10300cce;
      settle();
      // Four fills left D as primary. A, B then C put A in the oldest slot.
      va=A; settle();
      va=B; settle();
      va=C; settle();
      va=A;
      #1;
      if (busy || !owner || !dut.use_third) $fatal(1, "third slot did not hit");
    end
  endtask

  task third_checks;
    integer c, prior_lookups, prior_beats;
    begin
      warm_three();
      prior_lookups=lookups;
      prior_beats=beats;
      va=A+32'h34;
      #1;
      if (busy || !owner || !dut.use_third || fault || physical!=32'h10000078 ||
          !cb_cache || cb_buffer || external_fsr!=8'h68)
        $fatal(1, "third-slot read tuple corrupted");
      rd=0;
      wr=1;
      #1;
      if (busy || !owner || !fault || fsr!=8'h6d || far_address!=A+32'h34)
        $fatal(1, "third-slot write denial lost exact FSR/FAR");
      complete=1;
      tick();
      complete=0;
      rd=1; wr=0;
      #1;
      if (busy || !owner || fault || !dut.use_third)
        $fatal(1, "permission denial revoked opposite-direction grant");
      va=B;
      rd=0; wr=1;
      #1;
      if (busy || !owner || fault) $fatal(1, "neighbor write denied");
      tick();
      if (lookups!=prior_lookups || beats!=prior_beats)
        $fatal(1, "hot third-slot access performed hidden lookup");

      // A hit did not refresh A's age. Fourth resident lookup evicts A only.
      va=D;
      settle();
      va=A;
      #1;
      if (!busy || owner) $fatal(1, "fourth region failed to evict oldest slot");
      settle();
      if (beats!=prior_beats) $fatal(1, "FIFO evicted a main-table entry");

      for (c=0; c<8; c=c+1) begin
        warm_three();
        rd=0;
        case (c)
          0: mode_bits=5'h13;
          1: sr=1;
          2: dac=32'h00003000;
          3: ttbr=32'h0a070000;
          4: mmu=0;
          5: begin inv=1; inv_mva=1; invalidate_address=B; end
          6: inv=1;
          7: lock_write=1;
        endcase
        tick();
        inv=0; inv_mva=0; lock_write=0; mmu=1;
        va=C;
        rd=1;
        settle();
        mode_bits=5'h10; sr=0; dac=32'h00001000; ttbr=32'h0a074000;
        va=A;
        #1;
        if (!busy || owner || dut.use_third) $fatal(1, "third slot survived context/mutation %0d",c);
        settle();
      end

      // An unrelated exact walk fault ages checked records normally. A
      // third-slot permission denial must not consume that primary fault.
      warm_three();
      va=D; settle();
      va=A; settle();
      va=B; settle();
      va=32'h90000044;
      l1=0;
      settle();
      if (!fault || fsr!=8'h05 || far_address!=va) $fatal(1, "walk fault tuple");
      va=A+8;
      rd=0; wr=1;
      #1;
      if (!dut.use_third || !fault || fsr!=8'h6d || far_address!=va)
        $fatal(1, "third-slot denied write while an exact fault is pending");
      complete=1;
      tick();
      complete=0;
      va=32'h90000044;
      rd=1; wr=0;
      #1;
      if (!fault || fsr!=8'h05 || far_address!=va)
        $fatal(1, "third-slot ACK consumed the primary walk fault");
      va=32'h90000048;
      #1;
      if (owner || !busy || fault) $fatal(1, "walk fault reused for another offset");
      va=32'h90000044;
      rd=0; wr=1;
      #1;
      if (owner || !busy || fault) $fatal(1, "walk fault reused in another direction");

      // Keep entry zero (A) locally as slot three while main-table capacity
      // wraps. Change its descriptor after a new section evicts entry zero.
      reset_core();
      rd=1;
      for (c=0; c<64; c=c+1) begin
        va=A+(c<<20);
        l1=(32'h10000000+(c<<20))|32'h00000cce;
        settle();
      end
      va=A; settle();
      va=B; settle();
      va=C; settle();
      va=A;
      #1;
      if (busy || !owner || !dut.use_third)
        $fatal(1, "victim was not in third slot before main-table wrap");
      va=32'h84000044;
      l1=32'h24000cce;
      settle();
      prior_beats=beats;
      va=A;
      l1=32'h30000cce;
      #1;
      if (!busy || owner) $fatal(1, "stale third-slot grant after main-table replacement");
      settle();
      if (beats!=prior_beats+1 || physical!=32'h30000044)
        $fatal(1, "replacement failed to reread A's new physical mapping");
      $display("PASS: third slot, FIFO eviction, read/write/FAR/FSR, eight revocations and main-table wrap");
    end
  endtask
`endif

  initial begin
    repeat (4) tick();
`ifdef TEST_THIRD_MAPPING
    third_checks();
`endif
    for (kind = 0; kind < 4; kind = kind + 1) begin
      prepare_pair(kind);
      hot_pair(kind);
      rd = 0;
      wr = 0;
      complete = 1;
      repeat (3) tick();
      complete = 0;
      hot_pair(kind);  // Idle ACK cannot revoke either mapping.
    end

    // Three resident main-bank pages exercise FIFO publication and equal-offset
    // aliases without a fill invalidating the local pair during the check.
    prepare_pair(2);
    va = first_va + 8192;
    rd = 1;
    wr = 0;
    l2 = 32'h0c300ffe;
    settle();
    va = second_address;
    settle();
    va = first_va;
    settle();
    before_beats = beats;
    va = first_va + 8192;
    settle();
    va = first_va + 4;
    #1;
    if (busy || !owner || physical != first_pa + 4)
      $fatal(1, "third publication lost retained mapping or current offset");
    va = second_address;
    #1;
`ifdef TEST_THIRD_MAPPING
    if (busy || !owner || !dut.use_second)
      $fatal(1, "hit on oldest mapping unexpectedly updated FIFO age");
`else
    if (!busy || owner) $fatal(1, "third publication did not evict oldest local mapping");
`endif
    settle();
    if (beats != before_beats) $fatal(1, "local replacement discarded main-table mapping");

    // Each shared context field must revoke both slots. Returning to the old
    // context must not resurrect a permission from before the intervening miss.
    for (context_case = 0; context_case < 5; context_case = context_case + 1) begin
      prepare_pair(2);
      va = second_address;
      rd = 1;
      wr = 0;
      case (context_case)
        0: mode_bits = 5'h13;
        1: sr = 1;
        2: dac = 32'h00003000;
        3: ttbr = 32'h0a070000;
        4: begin
          mmu = 0;
          tick();
          mmu = 1;
        end
      endcase
      #1;
      if (!busy || owner) $fatal(1, "secondary ignored context change %0d", context_case);
      settle();
      mode_bits = 5'h10;
      sr = 0;
      dac = 32'h00001000;
      ttbr = 32'h0a074000;
      va = first_va;
      #1;
      if (!busy || owner) $fatal(1, "old context mapping resurrected %0d", context_case);
      settle();
    end

    // A third same-context mapping replaces FIFO publications, not arbitrary
    // address-indexed entries. An exact walk fault must not become a mapping;
    // the remaining secondary still needs its own permission when fault ACKed.
    prepare_pair(2);
    va = 32'h80700044;
    rd = 1;
    wr = 0;
    l1 = 0;
    settle();
    if (!fault || fsr != 8'h05) $fatal(1, "invalid descriptor did not fault");
    rd = 0;
    complete = 1;
    repeat (2) tick();
    complete = 0;
    va = first_va;
    rd = 1;
    #1;
    if (busy || !owner || fault || physical != first_pa)
      $fatal(1, "fault publication lost retained mapping");
    wr = 1;
    #1;
    if (!fault || fsr != 8'h6f) $fatal(1, "retained mapping lost denied-write permission");
    complete = 1;
    tick();
    complete = 0;
    wr = 0;
    #1;
    if (busy || !owner || fault) $fatal(1, "mapping fault consumed another walk owner");
    va = 32'h80700044;
    #1;
    if (!fault || fsr != 8'h05) $fatal(1, "secondary permission ACK consumed exact fault");
    complete = 1;
    tick();
    complete = 0;
    #1;
    // Reconstruct the same checked tuple used by the production D wrapper.
    // The secondary is still valid, but cannot validate a consumed primary.
    if (owner || (dut.o_checked_mmu == mmu && dut.o_checked_va == va &&
                  dut.o_checked_lookup == va && dut.o_checked_rd == rd &&
                  dut.o_checked_wr == wr && dut.o_checked_cpsr == mode_bits &&
                  dut.o_checked_sr == sr && dut.o_checked_dac == dac &&
                  dut.o_checked_baddr == ttbr))
      $fatal(1, "consumed primary fault reconstructed an unowned checked tuple");

    // Full architectural table: hold A locally across 64 fills, rewarm A/B,
    // then fill entry65. Neither local slot may extend evicted A's lifetime.
    reset_core();
    rd = 1;
    for (n = 0; n < 64; n = n + 1) begin
      va = 32'h80000044 + (n << 20);
      l1 = (32'h10000000 + (n << 20)) | 32'h00000cce;
      settle();
    end
    va = 32'h80000044;
    settle();
    before_lookups = lookups;
    va = 32'h83f00044;
    #1;
    if (busy || !owner) $fatal(1, "secondary was not resident before entry65");
    va = 32'h84000044;
    l1 = 32'h24000cce;
    settle();
    before_beats = beats;
    va = 32'h80000044;
    l1 = 32'h30000cce;
    settle();
    if (beats != before_beats + 1 || physical != 32'h30000044)
      $fatal(1, "local mapping outlived main-table eviction");

    // Lockdown-preserved entry survives all-invalidate only in the main bank;
    // both local slots are revoked. MVA invalidate must also remove preserved A.
    reset_core();
    lock_data  = {6'd1, 6'd0, 19'b0, 1'b1};
    lock_write = 1;
    tick();
    lock_write = 0;
    va = 32'h80000044;
    l1 = 32'h10000cce;
    rd = 1;
    settle();
    lock_data  = {6'd1, 6'd1, 19'b0, 1'b0};
    lock_write = 1;
    tick();
    lock_write = 0;
    va = 32'h80100044;
    l1 = 32'h10100cce;
    settle();
    va = 32'h80000044;
    settle();
    rd  = 0;
    inv = 1;
    tick();
    inv = 0;
    before_beats = beats;
    rd = 1;
    #1;
    if (!busy || owner) $fatal(1, "all invalidate left a local mapping");
    settle();
    if (beats != before_beats || physical != 32'h10000044)
      $fatal(1, "preserved main entry was lost");
    rd = 0;
    inv = 1;
    inv_mva = 1;
    invalidate_address = va;
    tick();
    inv = 0;
    inv_mva = 0;
    l1 = 32'h20000cce;
    before_beats = beats;
    rd = 1;
    settle();
    if (beats != before_beats + 1 || physical != 32'h20000044)
      $fatal(1, "MVA invalidate retained preserved mapping");
    reset = 1;
    tick();
    reset = 0;
    #1;
    if (!busy || owner) $fatal(1, "reset retained a local mapping");
    $display(
        "PASS: %0d dual-slot hot checks; four page classes, independent PA/CB/permissions, contexts, exact faults, 65-entry replacement, preserved/all/MVA invalidation and reset",
        checks);
    $finish;
  end
  initial begin
    #10000000;
    $fatal(1, "timeout");
  end
endmodule
