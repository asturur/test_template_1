module tb;
  parameter RESET_OVERLAP = 0;
  parameter BULK_COMPETITION = 0;
  integer bulk_beats = 0, bulk_snapshots = 0;
  wire arb_bulk, bulk_valid, bulk_last, bulk_error;
  wire [63:0] bulk_data;
  wire bulk_ready = cycles % 7 != 0;
  reg reset_injected = 0;
  reg clk = 0, reset = 1, cold = 1;
  always #5 clk = ~clk;
  wire init_done;
  wire [31:0] da, wd, back;
  wire [3:0] be;
  wire dr, dw, accept, done;
  wire [24:0] saddr, rladdr;
  wire sreq, swrite;
  wire [31:0] sdata;
  wire [3:0] sbe;
  reg [31:0] sresult = 0;
  reg sack = 0;
  reg [31:0] ram[0:65535];
  reg [31:0] rom[0:8191];
  reg spending = 0, rlpending = 0, rlvalid = 0, rllast = 0;
  reg [15:0] rldata = 0;
  reg [24:0] held_addr;
  reg [31:0] held_data;
  reg [3:0] held_be;
  reg held_write;
  integer sdelay = 0, rldelay = 0, rlindex = 0, rlbase = 0, successes = 0;
  wire rlreq, rlready;
  wire saccept = sreq && !spending && !sack && !rlpending && !rlreq;
  assign rlready = !rlpending && !spending && !sack;
  wire coreline, bv, bl;
  wire [63:0] beat;
  ngage_mister #(
      .ENABLE_DEBUGGER(1),
      .LINE_REFILL(1),
      .DIRECT_SDRAM(1),
      .DMA_LOCAL(0),
      .GENERAL_DMA(0)
  ) dut (
      .clk_sys(clk),
      .reset(reset),
      .cold_reset(cold),
      .debug_freeze_trace(1'b0),
      .sim_present(1'b0),
      .board_init_done(init_done),
      .sdram_addr(saddr),
      .sdram_req(sreq),
      .sdram_we(swrite),
      .sdram_din(sdata),
      .sdram_be(sbe),
      .sdram_accept(saccept),
      .sdram_dout(sresult),
      .sdram_ack(sack),
      .ram_line_req(rlreq),
      .ram_line_addr(rladdr),
      .ram_line_ready(rlready),
      .ram_line_valid(rlvalid),
      .ram_line_data(rldata),
      .ram_line_last(rllast),
      .ddram_addr(da),
      .ddram_din(wd),
      .ddram_be(be),
      .ddram_rd(dr),
      .ddram_wr(dw),
      .ddram_dout(back),
      .ddram_dout_ready(done),
      .ddram_accept(accept),
      .keys(27'b0),
      .ddram_line(coreline),
      .ddram_beat_valid(bv),
      .ddram_beat_data(beat),
      .ddram_beat_last(bl)
  );
  wire rv, rr, rw, rsp, rline;
  wire [31:0] ra, rd, rdata;
  wire [3:0] rb;
  reg aux = 0;
  wire auxready, auxdone;
  wire obv, obl;
  wire [63:0] obeat;
  ngage_ddr_arbiter arb (
      .clk(clk),
      .reset(cold),
      .cpu_lock(1'b0),
      .l_valid(aux),
      .l_ready(auxready),
      .l_done(auxdone),
      .l_addr(BULK_COMPETITION ? 32'h31440000 : 32'h313f0010),
      .l_data(32'b0),
      .l_be(4'hf),
      .l_write(1'b0),
      .l_bulk(BULK_COMPETITION != 0),
      .req_bulk(arb_bulk),
      .c_bulk(1'b0),
      .c_valid(dr || dw),
      .c_ready(accept),
      .c_write(dw),
      .c_addr(da),
      .c_data(wd),
      .c_be(be),
      .c_done(done),
      .c_rdata(back),
      .c_line(coreline),
      .req_line(rline),
      .rsp_beat_valid(obv),
      .rsp_beat_data(obeat),
      .rsp_beat_last(obl),
      .c_beat_valid(bv),
      .c_beat_data(beat),
      .c_beat_last(bl),
      .req_valid(rv),
      .req_ready(rr),
      .req_write(rw),
      .req_addr(ra),
      .req_data(rd),
      .req_be(rb),
      .rsp_valid(rsp),
      .rsp_data(rdata)
  );
  wire [28:0] pa;
  wire [63:0] pd;
  wire [7:0] pb, burst;
  wire pr, pw;
  reg ready = 0;
  reg [63:0] memdata = 0;
  integer deferred_wait = 0;
  integer
      cycles = 0, left = 0, delay = 0, writes = 0, auxcount = 0, lines = 0, linebeats = 0, j, ix;
  reg [28:0] cursor = 0;
  reg [63:0] memory[0:8191];
  wire busy = (cycles % 11 == 0);
  ngage_ddr_flash_adapter #(
      .LINE_REFILL(1),
      .FLASH_CACHE_BYTES(8192),
      .STREAM_TRANSPORT(1),
      .BULK_PERSISTENCE(1)
  ) adapter (
      .clk(clk),
      .reset(cold),
      .req_valid(rv),
      .req_ready(rr),
      .req_write(rw),
      .req_addr(ra),
      .req_wdata(rd),
      .req_be(rb),
      .req_line(rline),
      .req_fetch(1'b0),
      .rsp_valid(rsp),
      .rsp_data(rdata),
      .rsp_beat_valid(obv),
      .rsp_beat_data(obeat),
      .rsp_beat_last(obl),
      .req_bulk(arb_bulk),
      .bulk_cancel(1'b0),
      .bulk_read_ready(bulk_ready),
      .bulk_read_valid(bulk_valid),
      .bulk_read_data(bulk_data),
      .bulk_read_last(bulk_last),
      .bulk_error(bulk_error),
      .bulk_write_valid(1'b0),
      .bulk_write_data(64'b0),
      .bulk_write_last(1'b0),
      .ddr_addr(pa),
      .ddr_din(pd),
      .ddr_be(pb),
      .ddr_rd(pr),
      .ddr_we(pw),
      .ddr_busy(busy),
      .ddr_dout(memdata),
      .ddr_dout_ready(ready),
      .ddr_burstcount(burst)
  );
  always @(posedge clk) begin
    cycles <= cycles + 1;
    ready  <= 0;
    if(!cold&&!reset&&dut.user_flash.erase_pending&&dut.user_ready&&dut.line_req&&
    !dut.line_ready&&!dut.memory_req&&!dut.flash_issued)begin
      deferred_wait <= deferred_wait + 1;
      if (deferred_wait == 1024)
        $fatal(
            1,
            "DEFERRED_ERASE_REFILL_DEADLOCK pc%h line%h user%h",
            dut.cpu_pc,
            dut.line_addr,
            dut.user_debug_state
        );
    end else deferred_wait <= 0;
    if (!cold) begin
      if (!aux && cycles % (BULK_COMPETITION ? 257 : 13) == 3) aux <= 1;
      if (auxready) aux <= 0;
      if (bulk_error) $fatal(1, "sector transfer error");
      if (bulk_valid && bulk_ready) begin
        if (bulk_data !== memory[bulk_beats] || bulk_last != (bulk_beats == 63))
          $fatal(1, "sector snapshot data/extent %0d", bulk_beats);
        bulk_beats <= bulk_beats + 1;
      end
      if (auxdone) begin
        if (BULK_COMPETITION && bulk_beats != 64) $fatal(1, "short sector snapshot");
        if (BULK_COMPETITION) bulk_snapshots <= bulk_snapshots + 1;
        bulk_beats <= 0;
        auxcount   <= auxcount + 1;
      end
      if (dut.line_valid) begin
        linebeats <= linebeats + 1;
        if (dut.line_last) lines <= lines + 1;
      end
      if (delay > 0) delay <= delay - 1;
      else if (left > 0) begin
        ready  <= 1;
        left   <= left - 1;
        cursor <= cursor + 1;
        if (cursor >= ('h31440000 >> 3) && cursor < ('h31450000 >> 3))
          memdata <= memory[cursor-('h31440000>>3)];
        else if (cursor < ('h30008000 >> 3) && cursor >= ('h30000000 >> 3))
          memdata <= {rom[(cursor-('h30000000>>3))*2+1], rom[(cursor-('h30000000>>3))*2]};
        else memdata <= 64'hffffffffffffffff;
      end
      if (pr && !busy) begin
        if (left != 0) $fatal(1, "overlap read");
        left   <= burst;
        cursor <= pa;
        delay  <= cycles % 17 + 1;
      end
      if (pw && !busy) begin
        if (pa < ('h31440000 >> 3) || pa >= ('h31450000 >> 3)) $fatal(1, "write escaped C");
        ix = pa - ('h31440000 >> 3);
        for (j = 0; j < 8; j = j + 1) if (pb[j]) memory[ix][j*8+:8] <= pd[j*8+:8];
        writes <= writes + 1;
      end
    end
  end

  always @(posedge clk) begin
    sack <= 0;
    rlvalid <= 0;
    rllast <= 0;
    if (saccept) begin
      spending <= 1;
      held_addr <= saddr;
      held_data <= sdata;
      held_be <= sbe;
      held_write <= swrite;
      sdelay <= cycles % 7 + 1;
    end
    if (spending) begin
      if (sdelay != 0) sdelay <= sdelay - 1;
      else begin
        spending <= 0;
        sack <= 1;
        if (held_addr >= 262144) $fatal(1, "RAM escaped %h", held_addr);
        if (held_write) begin
          for (integer lane = 0; lane < 4; lane = lane + 1)
          if (held_be[lane]) ram[held_addr>>2][lane*8+:8] <= held_data[lane*8+:8];
          if (held_addr == 25'h100) begin
            if (BULK_COMPETITION && bulk_snapshots < 100) $fatal(1, "missing sector competition");
            if (RESET_OVERLAP && !reset_injected) $fatal(1, "missing reset overlap");
            if (held_data !== 32'h50415353)
              $fatal(1, "CPU reported failure %h PC%h", held_data, dut.cpu_pc);
            if (memory[0] !== 64'hffffffffffffffff || memory[8191] !== 64'hffffffffffffffff)
              $fatal(1, "erase bytes wrong");
            $display(
                "PASS real CPU erase-suspend, posted/unbuffered NOR, instruction/data lines, D2 early replies, competing diagnostics: cycles%0d aux%0d writes%0d",
                cycles, auxcount, writes);
            $finish;
          end
        end else sresult <= ram[held_addr>>2];
      end
    end
    if (rlreq && rlready) begin
      rlpending <= 1;
      rlbase <= rladdr;
      rlindex <= 0;
      rldelay <= 11;
    end
    if (rlpending) begin
      if (rldelay != 0) rldelay <= rldelay - 1;
      else begin
        if (rlbase + rlindex * 2 >= 262144) $fatal(1, "RAM line escaped");
        rldata  <= ram[(rlbase+rlindex*2)>>2] >> (rlindex[0] * 16);
        rlvalid <= 1;
        rllast  <= rlindex == 15;
        rlindex <= rlindex + 1;
        rldelay <= 1;
        if (rlindex == 15) rlpending <= 0;
      end
    end
  end
  initial begin
    for (integer k = 0; k < 8192; k = k + 1) begin
      memory[k] = 64'hffffffffffffffff;
      rom[k] = 0;
    end
    memory[0] = 0;
    memory[8191] = 0;
    for (integer k = 0; k < 65536; k = k + 1) ram[k] = 0;
    $readmemh("build/sim/unit-flash-refill-suspend/program.hex", rom);
    repeat (3) @(negedge clk);
    cold = 0;
    wait (init_done);
    repeat (3) @(negedge clk);
    reset = 0;
  end
  // Cancel a cold data refill after acceptance while a deferred erase exists.
  // The accepted mutation must drain before CPU restart; no stale line reply
  // may be mistaken for the restarted request.
  initial begin
    if (RESET_OVERLAP) begin
      wait (!cold && !reset && dut.user_flash.erase_pending && rlreq && rlready);
      @(negedge clk);
      reset = 1;
      reset_injected = 1;
      repeat (2) @(negedge clk);
      reset = 0;
    end
  end
  initial begin
    #120000000;
    $display(
        "DDR left%0d delay%0d ready%b pr%b busy%b burst%0d lineowner%b lineFSM%0d wordFSM%0d count%0d received%0d index%0d head%b cachebeat%0d",
        left, delay, ready, pr, busy, burst, adapter.transport.owner_line,
        adapter.transport.line_port.backend.state,
        adapter.transport.word_port.uncached.backend.state,
        adapter.transport.line_port.backend.streaming.backend.transport.count,
        adapter.transport.line_port.backend.streaming.backend.transport.received,
        adapter.transport.line_port.backend.streaming.backend.transport.index,
        adapter.transport.line_port.backend.streaming.backend.transport.head_valid,
        adapter.shared_cache.cache.beat);
    $fatal(1, "CPU timeout PC%h state%h adaptercache%0d", dut.cpu_pc, dut.debug_memory,
           adapter.shared_cache.cache.state);
  end
endmodule
