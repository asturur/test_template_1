`timescale 1ns / 1ps

module stream_tb #(
    parameter integer SYS_HZ = 78000000
);
  localparam [24:0] BASE = 25'h37fe0;
  reg clk = 0;
  always #(500000000.0 / SYS_HZ) clk = ~clk;

  reg cold = 1, phone_reset = 1, lock = 0;
  reg cpu_req = 0, cpu_we = 0, dma_req = 0, dma_we = 0;
  reg [24:0] cpu_addr = 0, dma_addr = 0;
  reg [31:0] cpu_data = 0, dma_data = 0;
  reg cpu_write_block = 0;
  reg [127:0] cpu_block_data = 0;
  reg [3:0] cpu_mask = 0, dma_mask = 0;
  wire cpu_ack, dma_ack, owner_ready, cpu_grant, dma_grant;
  wire [31:0] cpu_out, dma_out;
  wire req, we, ack, packet_lock;
  wire [24:0] addr;
  wire [31:0] write_data, read_data;
  wire write_block;
  wire [127:0] block_data;
  wire [3:0] mask;

  ngage_sdram_arbiter #(
      .CPU_BLOCK_WRITES(1)
  ) arbiter (
      .clk(clk),
      .reset(cold || phone_reset),
      .cpu_lock(lock),
      .cpu_req(cpu_req && owner_ready),
      .cpu_we(cpu_we),
      .cpu_addr(cpu_addr),
      .cpu_data(cpu_data),
      .cpu_be(cpu_mask),
      .cpu_ack(cpu_ack),
      .cpu_rdata(cpu_out),
      .cpu_write_block(cpu_write_block),
      .cpu_block_data(cpu_block_data),
      .dma_req(dma_req && owner_ready),
      .dma_we(dma_we),
      .dma_addr(dma_addr),
      .dma_data(dma_data),
      .dma_be(dma_mask),
      .dma_ack(dma_ack),
      .dma_rdata(dma_out),
      .mem_req(req),
      .mem_we(we),
      .mem_lock(packet_lock),
      .mem_addr(addr),
      .mem_data(write_data),
      .mem_be(mask),
      .mem_write_block(write_block),
      .mem_block_data(block_data),
      .mem_ack(ack),
      .mem_rdata(read_data),
      .cpu_accept(cpu_grant),
      .dma_accept(dma_grant)
  );

  reg line_req = 0;
  wire line_ready, line_valid, line_last, scrub_done;
  wire [15:0] line_data;
  wire req_mem, we_mem, line_mem, ready_mem, cmd_ready_mem, busy_mem, valid_mem;
  wire [ 24:2] addr_mem;
  wire [127:0] data_mem;
  wire [ 15:0] be_mem;
  wire [ 31:0] rdata_mem;
  ngage_sdram_stream stream (
      .clk(clk),
      .cold(cold),
      .phone_reset(phone_reset),
      .lock(packet_lock),
      .owner_ready(owner_ready),
      .grant_read((cpu_grant && !cpu_we) || (dma_grant && !dma_we)),
      .grant_addr(cpu_grant ? cpu_addr : dma_addr),
      .req(req),
      .we(we),
      .write_block(write_block),
      .block_data(block_data),
      .addr(addr),
      .din(write_data),
      .be(mask),
      .ack(ack),
      .dout(read_data),
      .line_req(line_req && !lock),
      .line_short(1'b0),
      .line_addr(BASE),
      .line_ready(line_ready),
      .line_valid(line_valid),
      .line_data(line_data),
      .line_last(line_last),
      .mem_req(req_mem),
      .mem_we(we_mem),
      .mem_line(line_mem),
      .mem_addr(addr_mem),
      .mem_wdata(data_mem),
      .mem_wbe(be_mem),
      .scrub_done(scrub_done),
      .mem_ready(ready_mem),
      .mem_cmd_ready(cmd_ready_mem),
      .mem_busy(busy_mem),
      .mem_valid(valid_mem),
      .mem_rdata(rdata_mem)
  );

  reg capture_pending = 0;
  reg [31:0] capture_data;
  always @(posedge clk) begin
    if (cold || phone_reset) begin
      capture_pending <= 0;
      if (cpu_ack || dma_ack) $fatal(1, "Scalar reply escaped reset");
    end else begin
      capture_pending <= stream.word_done && owner_ready;
      if (stream.word_done && owner_ready) begin
        capture_data <= rdata_mem;
        if (ack) $fatal(1, "Pin read completion bypassed the scalar reply register");
      end
      if (stream.read_reply != capture_pending) $fatal(1, "Wrong scalar reply cycle");
      if (capture_pending && (!req || cpu_ack == dma_ack || read_data !== capture_data))
        $fatal(1, "Registered scalar reply lost data or owner");
    end
  end

  wire pin_clk, cke, cs_n, ras_n, cas_n, we_n, dqml, dqmh;
  wire [ 1:0] pin_bank;
  wire [12:0] pin_addr;
  wire [15:0] pin_write, pin_read;
  tri [15:0] dq;
  ngage_sdram_clock clock_out (
      .clk(clk),
      .sdram_clk(pin_clk)
  );
  assign #5.5 pin_read = memory.Dq_reg;
  ngage_sdram_scheduler #(
      .CLK_HZ(SYS_HZ)
  ) controller (
      .clk(clk),
      .init(cold),
      .ready(ready_mem),
      .req(req_mem),
      .busy(busy_mem),
      .cmd_ready(cmd_ready_mem),
      .we(we_mem),
      .line(line_mem),
      .read_short(1'b0),
      .addr(addr_mem),
      .wdata(data_mem),
      .wbe(be_mem),
      .rvalid(valid_mem),
      .rword(),
      .rdata(rdata_mem),
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
  mt48lc16m16a2 memory (
      .Clk(pin_clk),
      .Cke(cke),
      .Dq(dq),
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

  // Compare each admitted packet with the one presented to the scheduler,
  // including packets accepted while the previous pin operation is active.
  integer accepted = 0, issued = 0, accepted_while_busy = 0, grant_reads = 0;
  bit queued = 0;
  reg [168:0] queued_packet;
  always @(posedge clk)
    if (!cold) begin
      if (stream.grant_read_word) begin
        if (!req_mem || we_mem || line_mem || !(cpu_grant || dma_grant))
          $fatal(1, "Early scalar read did not take both grants");
        grant_reads <= grant_reads + 1;
      end
      if (req_mem) begin
        if (!cmd_ready_mem || queued) $fatal(1, "Stream overwrote the queued SDRAM command");
        queued_packet <= {addr_mem, we_mem, line_mem, data_mem, be_mem};
        queued <= 1;
        accepted <= accepted + 1;
        if (busy_mem) accepted_while_busy <= accepted_while_busy + 1;
      end
      if (controller.take) begin
        if (!queued || {controller.cmd_addr, controller.cmd_we, controller.cmd_line,
                      controller.cmd_data, controller.cmd_be} !== queued_packet ||
          controller.cmd_short)
          $fatal(1, "Wrong SDRAM packet issued from command slot");
        queued <= 0;
        issued <= issued + 1;
      end
    end

  localparam integer REFRESH_LIMIT = 7812000 / (1000000000 / (SYS_HZ / 1000));
  integer refresh_count = 0, previous_refresh = 0, refresh_max = 0;
  integer block_beats = 0, previous_block_beat = 0;
  bit watch_block = 0;

  integer writes_by_bank[0:3] = '{default: 0};
  integer pin_cycle = 0, first_line_read = 0, line_reads = 0;
  bit watch_line = 0;
  always @(posedge pin_clk) begin
    pin_cycle++;
    case ({
      cs_n, ras_n, cas_n, we_n
    })
      4'b0001:
      if (ready_mem) begin
        refresh_count++;
        if (previous_refresh != 0) begin
          if (pin_cycle - previous_refresh > REFRESH_LIMIT) $fatal(1, "Refresh deadline exceeded");
          if (pin_cycle - previous_refresh > refresh_max)
            refresh_max = pin_cycle - previous_refresh;
        end
        previous_refresh = pin_cycle;
      end
      4'b0100: begin
        if (!scrub_done) begin
          writes_by_bank[pin_bank]++;
          if (pin_write !== 16'b0 || {dqmh, dqml} !== 2'b0)
            $fatal(1, "Cold scrub wrote nonzero data or used a write mask");
        end
        if (watch_block && block_beats < 8) begin
          if (block_beats != 0 && pin_cycle != previous_block_beat + 1)
            $fatal(1, "16-byte write contained gaps between pin beats");
          previous_block_beat = pin_cycle;
          block_beats++;
        end
      end
      4'b0101:
      if (watch_line) begin
        if (line_reads == 0) first_line_read = pin_cycle;
        else if (line_reads != 1 || pin_cycle - first_line_read != 8)
          $fatal(1, "32-byte read did not issue consecutive BL8s");
        line_reads++;
      end
      default: ;
    endcase
  end

  task automatic cpu_transfer(input bit wr, input [24:0] address, input [31:0] data, input [3:0] be,
                              input [31:0] expected);
    @(negedge clk);
    cpu_req  = 1;
    cpu_we   = wr;
    cpu_addr = address;
    cpu_data = data;
    cpu_mask = be;
    do @(posedge clk); while (!cpu_ack);
    if (!wr && cpu_out !== expected)
      $fatal(1, "CPU read %h saw %h expected %h", address, cpu_out, expected);
    @(negedge clk);
    cpu_req = 0;
  endtask

  reg [31:0] expected_words[0:7];
  initial begin
    repeat (4) @(negedge clk);
    cold = 0;
    wait (ready_mem);
    // Nonzero memory at the start and end of the mapped cold-scrub range.
    memory.Bank0[0] = 16'hbabe;
    memory.Bank3[2097151] = 16'hface;
    wait (scrub_done);
    @(negedge clk);
    for (integer bank = 0; bank < 4; bank++)
    if (writes_by_bank[bank] != 2097152)
      $fatal(1, "Wrong scrub length for bank %0d: %0d", bank, writes_by_bank[bank]);
    if (memory.Bank0[0] !== 0 || memory.Bank3[2097151] !== 0)
      $fatal(1, "Cold scrub boundaries were left dirty");
    $display("SCRUB PASS bytes=16777216 clocks=%0d all_four_banks=1", pin_cycle);
    phone_reset = 0;

    for (integer word = 0; word < 8; word++) begin
      expected_words[word] = 32'h89abcdef ^ (word * 32'h01070911);
      cpu_transfer(1, BASE + 25'(word * 4), expected_words[word], 4'hf, 0);
    end
    for (integer be = 0; be < 16; be++) begin
      reg [31:0] pattern;
      pattern = 32'h12233445 ^ (be * 32'h1f17230b);
      cpu_transfer(1, BASE, pattern, be[3:0], 0);
      for (integer lane = 0; lane < 4; lane++)
      if (be[lane]) expected_words[0][lane*8+:8] = pattern[lane*8+:8];
      cpu_transfer(0, BASE, 0, 0, expected_words[0]);
    end

    @(negedge clk);
    watch_line = 1;
    line_req   = 1;
    do @(posedge clk); while (!line_ready);
    @(negedge clk);
    line_req = 0;
    for (integer beat = 0; beat < 16; beat++) begin
      do @(posedge clk); while (!line_valid);
      if (line_last !== (beat == 15) || line_data !== expected_words[beat/2][(beat%2)*16+:16])
        $fatal(1, "Wrong 32-byte line beat %0d: %h", beat, line_data);
    end
    if (line_reads != 2) $fatal(1, "Wrong pin READ count for the 32-byte line");
    watch_line = 0;

    // The DMA read must see a locked CPU write and remain off the bus
    // for the entire read/modify/write reservation.
    @(negedge clk);
    lock = 1;
    dma_req = 1;
    dma_addr = BASE;
    repeat (4) begin
      @(posedge clk);
      if (dma_ack) $fatal(1, "DMA passed CPU lock");
    end
    cpu_transfer(0, BASE, 0, 0, expected_words[0]);
    cpu_transfer(1, BASE, 32'h2468ace0, 4'hf, 0);
    lock = 0;
    do @(posedge clk); while (!dma_ack);
    if (dma_out !== 32'h2468ace0) $fatal(1, "DMA saw stale locked data");
    @(negedge clk);
    dma_req = 0;
    @(negedge clk);
    dma_req  = 1;
    dma_we   = 1;
    dma_data = 32'hff990022;
    dma_mask = 4'b1001;
    do @(posedge clk); while (!dma_ack);
    @(negedge clk);
    dma_req = 0;
    dma_we  = 0;
    cpu_transfer(0, BASE, 0, 0, 32'hff68ac22);

    // Reset after posting a 16-byte write. Neither the remaining words in
    // its half nor the neighbouring half may be corrupted by cancellation.
    cpu_write_block = 1;
    cpu_block_data  = 128'h82fd1c37_0553befc_6ad19ffe_be49182d;
    cpu_transfer(1, BASE + 16, cpu_block_data[31:0], 4'hf, 0);
    cpu_write_block = 0;
    if (stream.drained) $fatal(1, "Expected block acceptance before pin drain");
    phone_reset = 1;
    repeat (3) @(negedge clk);
    phone_reset = 0;
    cpu_transfer(0, BASE + 12, 0, 0, expected_words[3]);
    for (integer word = 0; word < 4; word++)
    cpu_transfer(0, BASE + 16 + 25'(word * 4), 0, 0, cpu_block_data[word*32+:32]);

    // A logical reset cancels responses but cannot revoke a posted write.
    cpu_transfer(1, BASE + 4, 32'h13579bdf, 4'hf, 0);
    if (stream.drained) $fatal(1, "Expected acceptance before pin drain");
    phone_reset = 1;
    repeat (3) @(negedge clk);
    phone_reset = 0;
    cpu_transfer(0, BASE + 4, 0, 0, 32'h13579bdf);
    // An older CPU write accepted with the reservation clear also keeps
    // its posted completion when a younger SWP starts.
    @(negedge clk);
    cpu_req  = 1;
    cpu_we   = 1;
    cpu_addr = BASE;
    cpu_data = 32'hba12ca34;
    cpu_mask = 4'hf;
    do @(posedge clk); while (!cpu_grant);
    @(negedge clk);
    lock = 1;
    @(posedge clk);
    if (packet_lock || !cpu_ack || dma_ack)
      $fatal(1, "Older CPU write lost posted ownership when SWP locked");
    @(negedge clk);
    cpu_req = 0;
    cpu_transfer(0, BASE, 0, 0, 32'hba12ca34);
    lock = 0;

    // Post a full four-word block. Grant an older DMA byte write while
    // the pins are still busy, then raise the CPU lock before it can post.
    cpu_write_block = 1;
    watch_block = 1;
    cpu_block_data = 128'hffeeddcc_88776655_66554433_11223344;
    cpu_transfer(1, BASE, cpu_block_data[31:0], 4'hf, 0);
    cpu_write_block = 0;
    dma_req = 1;
    dma_we = 1;
    dma_addr = BASE;
    dma_data = 32'haabbccdd;
    dma_mask = 4'b0101;
    do @(posedge clk); while (!dma_grant);
    @(negedge clk);
    lock = 1;
    @(posedge clk);
    if (!busy_mem || !dma_ack || cpu_ack || packet_lock)
      $fatal(1, "Older DMA byte write lost posted ownership when SWP locked");
    @(negedge clk);
    dma_req = 0;
    dma_we  = 0;

    // The swap must read the block followed by the queued DMA lanes. A DMA
    // read requesting the same address cannot enter the read/write gap.
    cpu_transfer(0, BASE, 0, 0, 32'h11bb33dd);
    if (block_beats != 8) $fatal(1, "16-byte write did not issue eight pin beats");
    watch_block = 0;
    dma_req = 1;
    repeat (4) begin
      @(posedge clk);
      if (dma_grant || dma_ack) $fatal(1, "DMA entered the locked SWP gap");
    end
    @(negedge clk);
    cpu_req  = 1;
    cpu_we   = 1;
    cpu_addr = BASE;
    cpu_data = 32'h44000099;
    cpu_mask = 4'b1001;
    do @(posedge clk); while (!cpu_grant);
    @(negedge clk);
    if (!packet_lock || cpu_ack) $fatal(1, "Locked write received posted acknowledgement");
    do begin
      @(posedge clk);
      if (dma_grant || dma_ack) $fatal(1, "DMA passed an owned SWP write");
    end while (!cpu_ack);
    if (busy_mem) $fatal(1, "Locked write acknowledged before pin completion");
    @(negedge clk);
    cpu_req = 0;
    lock = 0;
    do @(posedge clk); while (!dma_ack);
    if (dma_out !== 32'h44bb3399) $fatal(1, "DMA saw stale data after locked byte write");
    @(negedge clk);
    dma_req = 0;
    for (integer word = 1; word < 4; word++)
    cpu_transfer(0, BASE + 25'(word * 4), 0, 0, cpu_block_data[word*32+:32]);

    // Once a CPU write is granted, it cannot become posted if the live
    // reservation is withdrawn before stream admission.
    @(negedge clk);
    lock = 1;
    cpu_req = 1;
    cpu_we = 1;
    cpu_addr = BASE;
    cpu_data = 32'h7685abcd;
    cpu_mask = 4'hf;
    do @(posedge clk); while (!cpu_grant);
    @(negedge clk);
    lock = 0;
    @(posedge clk);
    if (!packet_lock || cpu_ack) $fatal(1, "Held locked write became posted");
    do @(posedge clk); while (!cpu_ack);
    if (busy_mem) $fatal(1, "Held write acknowledged before pin completion");
    @(negedge clk);
    cpu_req = 0;
    cpu_transfer(0, BASE, 0, 0, 32'h7685abcd);

    // A simultaneous line wins the command slot. The scalar owner holds
    // its address and issues exactly once after the line's last beat.
    wait (stream.drained);
    @(negedge clk);
    line_req = 1;
    cpu_req  = 1;
    cpu_we   = 0;
    cpu_addr = BASE + 4;
    @(posedge clk);
    if (!cpu_grant || !line_ready || !stream.first_line || stream.grant_read_word)
      $fatal(1, "The line failed to win a simultaneous scalar read grant");
    @(negedge clk);
    line_req = 0;
    cpu_addr = BASE;
    do begin
      @(posedge clk);
      if (cpu_ack) $fatal(1, "Scalar ACK arrived during the line");
    end while (!line_last);
    @(posedge clk);
    if (!stream.scalar_read || !req_mem || addr_mem !== (BASE[24:2] + 23'd1))
      $fatal(1, "The held scalar read lost its granted address");
    do @(posedge clk); while (!cpu_ack);
    if (cpu_out !== cpu_block_data[63:32]) $fatal(1, "Wrong held scalar response");
    @(negedge clk);
    cpu_req = 0;

    // Cancel an accepted fast read before its pin response. A new owner
    // may request memory immediately, but must receive its own result.
    wait (stream.drained);
    @(negedge clk);
    cpu_addr = BASE;
    cpu_req  = 1;
    @(posedge clk);
    if (!cpu_grant || !stream.grant_read_word)
      $fatal(1, "Cancellation test missed grant-edge read admission");
    @(negedge clk);
    cpu_req = 0;
    phone_reset = 1;
    repeat (2) @(negedge clk);
    phone_reset = 0;
    dma_addr = BASE + 8;
    dma_req = 1;
    do begin
      @(posedge clk);
      if (cpu_ack) $fatal(1, "Cancelled scalar read acknowledged after reset");
    end while (!dma_ack);
    if (dma_out !== cpu_block_data[95:64]) $fatal(1, "New owner read a cancelled response");
    @(negedge clk);
    dma_req = 0;
    $display("PASS stream grant-edge read, held fallback and cancelled response");

    // The reply can retire on the same edge that the next line is admitted.
    wait (stream.drained);
    @(negedge clk);
    cpu_addr = BASE + 8;
    cpu_req  = 1;
    do @(posedge clk); while (!cpu_grant);
    @(negedge clk);
    line_req = 1;
    do @(posedge clk); while (!cpu_ack);
    if (!line_ready || !stream.first_line || cpu_out !== cpu_block_data[95:64])
      $fatal(1, "Line admission did not overlap the registered scalar reply");
    @(negedge clk);
    cpu_req  = 0;
    line_req = 0;
    do @(posedge clk); while (!line_last);

    // Reset again after the pin word is captured but before the CPU sees ACK.
    wait (stream.drained);
    @(negedge clk);
    cpu_addr = BASE;
    cpu_req  = 1;
    wait (stream.read_reply);
    @(negedge clk);
    cpu_req = 0;
    phone_reset = 1;
    @(negedge clk);
    phone_reset = 0;
    dma_addr = BASE + 8;
    dma_req = 1;
    do begin
      @(posedge clk);
      if (cpu_ack) $fatal(1, "Buffered scalar reply escaped reset");
    end while (!dma_ack);
    if (dma_out !== cpu_block_data[95:64]) $fatal(1, "DMA received a canceled CPU word");
    @(negedge clk);
    dma_req = 0;
    $display(
        "PASS stream scalar reply latency, concurrent line admission and buffered cancellation");
    $display(
        "PASS stream packet lock: older posted block/DMA, SWP gap, lane order and physical completion");
    while (busy_mem) @(negedge clk);
    if (queued || accepted != issued || accepted_while_busy == 0 || grant_reads == 0)
      $fatal(1, "Lost, duplicate, or uncovered command slot case");
    if (refresh_count < 2 || refresh_max == 0) $fatal(1, "Refresh interval was not exercised");
    $display("REFRESH PASS hz=%0d count=%0d max_interval_clocks=%0d limit=%0d", SYS_HZ,
             refresh_count, refresh_max, REFRESH_LIMIT);
    $display("PASS stream command slot: accepted=%0d issued=%0d while_busy=%0d grant_reads=%0d",
             accepted, issued, accepted_while_busy, grant_reads);
    $display("PASS stream masks, physical burst shape, DMA/SWP order and logical reset drain");
    $finish;
  end

  initial begin
    #200000000;
    $fatal(1, "SDRAM stream test timed out");
  end
endmodule
