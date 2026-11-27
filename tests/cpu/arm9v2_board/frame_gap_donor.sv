`timescale 1ns / 1ps

// Original ngage2 CPU, bus, NOR/DDR cache and SDRAM RTL. The bench preloads
// checked guest bytes into the HPS memory peer before releasing the CPU.
module frame_gap_donor #(
    parameter SCALAR_WRITEBACK = 0
);
  localparam integer SYS_HZ = 78000000;
  localparam [28:0] CS0_BASE = 29'h06200000;
  localparam [31:0] MAILBOX = 32'h0a100000;
  reg clk = 0, reset = 1;
  always #(500000000.0 / SYS_HZ) clk = ~clk;

  wire ready, req, we, burst, ack, err, no_late_error;
  wire [31:0] addr, wdata, rdata, debug_pc, cpsr;
  wire [3:0] be;
  wire [1:0] bte, data_abort;
  wire valid, skipped, last, prefetch_abort, undefined_inst, swi, irq, fiq;
  wire [7:0] fetch_stats;
  wire [3:0] data_stats;
  wire [31:0] retire_pc = debug_pc - (cpsr[5] ? 4 : 8);
  wire retire = (valid || skipped) && last &&
                  !(|{data_abort,prefetch_abort,undefined_inst,swi,irq,fiq});
  arm925t cpu (
      .clk(clk),
      .reset(reset || !ready),
      .irq(1'b0),
      .fiq(1'b0),
      .bus_req(req),
      .bus_we(we),
      .bus_addr(addr),
      .bus_be(be),
      .bus_wdata(wdata),
      .bus_burst(burst),
      .bus_bte(bte),
      .bus_rdata(rdata),
      .bus_ack(ack),
      .bus_err(err),
      .bus_no_late_error(no_late_error),
      .dbg_wb_pc(debug_pc),
      .dbg_wb_cpsr(cpsr),
      .dbg_wb_valid(valid),
      .dbg_wb_dvalid(skipped),
      .dbg_wb_uop_last(last),
      .dbg_wb_dabt(data_abort),
      .dbg_wb_pabt(prefetch_abort),
      .dbg_wb_und(undefined_inst),
      .dbg_wb_swi(swi),
      .dbg_wb_irq(irq),
      .dbg_wb_fiq(fiq),
      .dbg_icache(fetch_stats),
      .dbg_dcache(data_stats)
  );

  wire pin_clk, cke, cs_n, ras_n, cas_n, we_n, dqml, dqmh, periph, unmapped;
  wire [ 1:0] pin_bank;
  wire [12:0] pin_addr;
  wire [15:0] pin_write, pin_read;
  tri [15:0] pin_dq;
  ngage_sdram_clock forward_clock (
      .clk(clk),
      .sdram_clk(pin_clk)
  );
  mt48lc16m16a2 memory (
      .Clk(pin_clk),
      .Cke(cke),
      .Dq(pin_dq),
      .Dq_write(pin_write),
      .Addr(pin_addr),
      .Ba(pin_bank),
      .Cs_n(cs_n),
      .Ras_n(ras_n),
      .Cas_n(cas_n),
      .We_n(we_n),
      .Dqm({dqmh, dqml}),
      .downloading(1'b0),
      .VS(1'b0),
      .frame_cnt(32'b0)
  );
  assign #5.5 pin_read = memory.Dq_reg;

  wire [ 7:0] ddr_burst;
  wire [28:0] ddr_addr;
  wire ddr_rd, ddr_we;
  reg ddr_valid = 0;
  reg [63:0] ddr_data = 0;
  reg [63:0] flash[0:1048575];
  integer ddr_left = 0, ddr_wait = 0, ddr_slot = 0, ddr_reads = 0;
  wire ddr_busy = ddr_left != 0;
  wire memory_burst = burst && !(SCALAR_WRITEBACK && we);
  wire [1:0] memory_bte = memory_burst ? bte : 2'b0;
  ngage_mem #(
      .CLK_HZ(SYS_HZ)
  ) mem (
      .clk(clk),
      .reset(reset || !ready),
      .sdram_init(reset),
      .sdram_ready(ready),
      .flash_rst_n(1'b1),
      .wb_cyc(req),
      .wb_stb(req),
      .wb_we(we),
      .wb_adr(addr),
      .wb_dat_i(wdata),
      .wb_sel(be),
      .wb_cti(memory_burst ? 3'b010 : 3'b111),
      .wb_bte(memory_bte),
      .wb_ack(ack),
      .wb_err(err),
      .wb_no_late_error(no_late_error),
      .wb_dat_o(rdata),
      .dbg_dma_owner(),
      .dma_cyc(1'b0),
      .dma_stb(1'b0),
      .dma_we(1'b0),
      .dma_adr(32'b0),
      .dma_dat_i(32'b0),
      .dma_sel(4'b0),
      .dma_ack(),
      .dma_err(),
      .dma_dat_o(),
      .p_sel(periph),
      .p_we(),
      .p_addr(),
      .p_wdata(),
      .p_be(),
      .p_rdata(32'b0),
      .p_wait(1'b0),
      .flash_busy(),
      .unmapped(unmapped),
      .ld_we(1'b0),
      .ld_rd(1'b0),
      .ld_addr(29'b0),
      .ld_din(64'b0),
      .ld_be(8'b0),
      .ld_busy(),
      .ld_valid(),
      .ld_data(),
      .save_mark(),
      .save_mark_blk(),
      .c_blank(),
      .save_rd(1'b0),
      .save_blk(14'b0),
      .save_taken(),
      .save_valid(),
      .save_data(),
      .ddram_busy(ddr_busy),
      .ddram_burstcnt(ddr_burst),
      .ddram_addr(ddr_addr),
      .ddram_dout(ddr_data),
      .ddram_dout_ready(ddr_valid),
      .ddram_rd(ddr_rd),
      .ddram_din(),
      .ddram_be(),
      .ddram_we(ddr_we),
      .sdram_cke(cke),
      .sdram_cs_n(cs_n),
      .sdram_ras_n(ras_n),
      .sdram_cas_n(cas_n),
      .sdram_we_n(we_n),
      .sdram_ba(pin_bank),
      .sdram_a(pin_addr),
      .sdram_dqml(dqml),
      .sdram_dqmh(dqmh),
      .sdram_dq_o(pin_write),
      .sdram_dq_oe(),
      .sdram_dq_i(pin_read)
  );
  always @(posedge clk) begin
    ddr_valid <= 0;
    if (ddr_rd && !ddr_busy) begin
      if (ddr_addr < CS0_BASE || ddr_addr + 29'(ddr_burst) > CS0_BASE + 29'd1048576)
        $fatal(1, "Guest DDR read outside staged NOR array: %h", ddr_addr);
      ddr_slot  <= int'(ddr_addr - CS0_BASE);
      ddr_left  <= int'(ddr_burst);
      ddr_wait  <= 3;
      ddr_reads <= ddr_reads + 1;
    end else if (ddr_busy) begin
      if (ddr_wait > 1) ddr_wait <= ddr_wait - 1;
      else begin
        ddr_data  <= flash[ddr_slot];
        ddr_valid <= 1;
        ddr_left  <= ddr_left - 1;
        ddr_slot  <= ddr_slot + 1;
        ddr_wait  <= 0;
      end
    end
  end

  integer cycle = 0, window = 0, begin_cycle = -1;
  integer payload_ops, helper_ops, ddr_begin, data_reads, data_writes, wait_clocks;
  integer itlb, dtlb, ifills, dfills;
  integer act = 0, pre = 0, refreshes = 0;
  integer act_begin, pre_begin, refresh_begin;
  reg [31:0] begin_pc, end_pc, payload_base, helper_base;
  reg completed = 0;
  string flash_path, trace_path;
  integer trace_fd = 0;
  initial begin
    if (!$value$plusargs(
            "flash=%s", flash_path
        ) || !$value$plusargs(
            "begin_pc=%h", begin_pc
        ) || !$value$plusargs(
            "end_pc=%h", end_pc
        ) || !$value$plusargs(
            "payload_base=%h", payload_base
        ) || !$value$plusargs(
            "helper_base=%h", helper_base
        ))
      $fatal(1, "Missing donor payload options");
    if ($value$plusargs("trace=%s", trace_path)) trace_fd = $fopen(trace_path, "w");
    $readmemh(flash_path, flash);
    repeat (8) @(negedge clk);
    reset = 0;
  end
  always @(posedge pin_clk) begin
    case ({
      cs_n, ras_n, cas_n, we_n
    })
      4'b0011: act = act + 1;
      4'b0010: pre = pre + 1;
      4'b0001: refreshes = refreshes + 1;
      default: ;
    endcase
  end
  always @(posedge clk)
    if (!reset && ready) begin
      cycle = cycle + 1;
      if (cycle == 100000000) $fatal(1, "Payload timeout PC=%h", debug_pc);
      if (err || unmapped || periph || ddr_we)
        $fatal(1, "Unexpected guest access %h PC=%h", addr, debug_pc);
      if (retire && retire_pc == begin_pc) begin
        if (begin_cycle >= 0 || !cpu.u_zap.cpu_mmu_en || !cpu.u_zap.cpu_dc_en || !cpu.u_zap.cpu_ic_en)
          $fatal(1, "Invalid donor payload window");
        begin_cycle = cycle;
        payload_ops = 0;
        helper_ops = 0;
        data_reads = 0;
        data_writes = 0;
        wait_clocks = 0;
        itlb = 0;
        dtlb = 0;
        ifills = 0;
        dfills = 0;
        ddr_begin = ddr_reads;
        act_begin = act;
        pre_begin = pre;
        refresh_begin = refreshes;
      end
      if (begin_cycle >= 0) begin
        if (req && !ack) wait_clocks = wait_clocks + 1;
        if (fetch_stats[6]) itlb = itlb + 1;
        if (fetch_stats[7]) dtlb = dtlb + 1;
        if (fetch_stats[2]) ifills = ifills + 1;
        if (|data_stats[1:0]) dfills = dfills + 1;
        if (mem.sdr_req && !mem.sdr_busy) begin
          if (mem.sdr_we) data_writes = data_writes + 1;
          else data_reads = data_reads + 1;
          if (window == 2 && trace_fd)
            $fdisplay(
                trace_fd,
                "%0d %08x %b %0d",
                cycle - begin_cycle,
                {
                  mem.sdr_addr, 2'b0
                },
                mem.sdr_we,
                mem.sdr_line ? 16 : 4
            );
        end
        if (retire) begin
          if (retire_pc[31:20] == payload_base[31:20]) payload_ops = payload_ops + 1;
          if (retire_pc[31:20] == helper_base[31:20]) helper_ops = helper_ops + 1;
          if (retire_pc == end_pc) begin
            $display(
                "DONOR_WINDOW window=%0d cycles=%0d payload_ops=%0d helper_ops=%0d ddr_reads=%0d wait=%0d itlb=%0d dtlb=%0d ifills=%0d dfills=%0d sdram_reads=%0d sdram_writes=%0d act=%0d pre=%0d refresh=%0d",
                window, cycle - begin_cycle, payload_ops, helper_ops, ddr_reads - ddr_begin,
                wait_clocks, itlb, dtlb, ifills, dfills, data_reads, data_writes, act - act_begin,
                pre - pre_begin, refreshes - refresh_begin);
            begin_cycle = -1;
            window = window + 1;
          end
        end
      end
      if (req && ack && we && addr == MAILBOX) begin
        if (wdata != 32'h50415353) $fatal(1, "Guest output check rejected payload");
        if (window != 7 || begin_cycle >= 0) $fatal(1, "Incomplete donor payload windows");
        completed = 1;
      end
      if (completed && !mem.sdr_req && !mem.sdr_busy) begin
        if ({memory.Bank0[131073], memory.Bank0[131072]} !== 32'h50415353)
          $fatal(1, "Posted mailbox write never reached SDRAM");
        if (trace_fd) $fclose(trace_fd);
        $display("PASS donor checked payload cycles=%0d", cycle);
        $finish;
      end
    end
endmodule
