`timescale 1ns / 1ps

// Common pin peer and data oracle for the two physical read/write routes.
module frame_gap_banks;
  parameter  integer DONOR  = 0;
  localparam integer SYS_HZ = 78000000;
  reg clk = 0;
  always #(500000000.0 / SYS_HZ) clk = ~clk;

  reg reset = 1, request = 0, write = 0, line_request = 0, donor_burst = 0;
  wire line_ready, line_valid, line_last;
  wire [15:0] line_data;
  localparam integer FRAME_WORDS = 176 * 208 / 2;
  localparam [24:0] FRAME_START = 25'h200000;
  reg [24:0] address = 0;
  reg [31:0] write_data = 0;
  wire ready, ack;
  wire [31:0] read_data;
  wire pin_clk, cke, cs_n, ras_n, cas_n, we_n, dqml, dqmh;
  wire [ 1:0] pin_bank;
  wire [12:0] pin_addr;
  wire [15:0] pin_write, pin_read;
  wire [ 3:0] pin_command = {cs_n, ras_n, cas_n, we_n};
  tri  [15:0] pin_dq;

  ngage_sdram_clock forwarded_clock (
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
  // The donor captures on the rising FPGA edge with its documented
  // external DQ delay. The v5 reference uses falling-edge capture.
  if (DONOR) assign #5.5 pin_read = memory.Dq_reg;
  else assign pin_read = memory.Dq_reg;

  generate
    if (DONOR) begin : donor_path
      assign {line_ready, line_valid, line_last, line_data} = 0;
      wire busy, req, we, line, rd_valid, error;
      wire [ 24:2] addr;
      wire [127:0] data;
      wire [ 15:0] mask;
      wire [  1:0] rd_word;
      wire [ 31:0] rd_data;
      wire [ 31:0] pa = 32'h0a000000 | {7'b0, address};
      upp_bus bus (
          .clk(clk),
          .reset(reset || !ready),
          .wb_cyc(request),
          .wb_stb(request),
          .wb_we(write),
          .wb_adr(pa),
          .decode_cpu_adr(pa),
          .decode_dma_adr(32'b0),
          .decode_dma_owner(1'b0),
          .wb_dat_i(write_data),
          .wb_sel(4'hf),
          .wb_cti(donor_burst ? 3'b010 : 3'b111),
          .wb_bte(2'b00),
          .wb_ack(ack),
          .wb_err(error),
          .wb_no_late_error(),
          .wb_dat_o(read_data),
          .fl0_req(),
          .fl0_we(),
          .fl0_addr(),
          .fl0_wdata(),
          .fl0_rdata(16'b0),
          .fl0_ack(1'b0),
          .fl0_array(1'b0),
          .fl0_lreq(),
          .fl0_laddr(),
          .fl0_ltaken(1'b0),
          .fl0_lrvalid(1'b0),
          .fl0_lrbeat(1'b0),
          .fl0_lrdata(64'b0),
          .fl1_req(),
          .fl1_we(),
          .fl1_addr(),
          .fl1_wdata(),
          .fl1_rdata(16'b0),
          .fl1_ack(1'b0),
          .fl1_array(1'b0),
          .fl1_lreq(),
          .fl1_laddr(),
          .fl1_ltaken(1'b0),
          .fl1_lrvalid(1'b0),
          .fl1_lrbeat(1'b0),
          .fl1_lrdata(64'b0),
          .sdr_req(req),
          .sdr_we(we),
          .sdr_line(line),
          .sdr_addr(addr),
          .sdr_wdata(data),
          .sdr_wbe(mask),
          .sdr_busy(busy),
          .sdr_rvalid(rd_valid),
          .sdr_rword(rd_word),
          .sdr_rdata(rd_data),
          .p_sel(),
          .p_we(),
          .p_addr(),
          .p_wdata(),
          .p_be(),
          .p_rdata(32'b0),
          .p_wait(1'b0),
          .unmapped(),
          .idle()
      );
      sdram #(
          .CLK_HZ(SYS_HZ)
      ) controller (
          .clk(clk),
          .init(reset),
          .ready(ready),
          .req(req),
          .busy(busy),
          .we(we),
          .line(line),
          .addr(addr),
          .wdata(data),
          .wbe(mask),
          .rvalid(rd_valid),
          .rword(rd_word),
          .rdata(rd_data),
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
      always @(posedge clk) if (error) $fatal(1, "Donor RAM response error");
    end else begin : v5_path
      wire init, refresh;
      wire [21:0] ba_addr;
      wire [15:0] din, dout;
      wire [1:0] dsn;
`ifdef FRAME_INTERLEAVE
      wire [3:0] line;
`else
      wire [1:0] line;
`endif
      wire [3:0] rd, wr, ba_ack, dst, rdy;
      ngage_sdram_adapter #(
          .LINE_REFILL(1),
          .RAM_BYTES(32),
          .REFRESH_PERIOD(5100)
      ) adapter (
          .line_req(line_request),
          .line_addr(address),
          .line_ready(line_ready),
          .line_valid(line_valid),
          .line_data(line_data),
          .line_last(line_last),
          .ba_line(line),
          .clk(clk),
          .rst(reset),
          .phone_reset(1'b0),
          .init(init),
          .req(request),
          .we(write),
          .addr(address),
          .din(write_data),
          .be(4'hf),
          .ack(ack),
          .dout(read_data),
          .scrub_done(ready),
          .ba_addr(ba_addr),
          .ba_din(din),
          .ba_dsn(dsn),
          .rd(rd),
          .wr(wr),
          .ba_ack(ba_ack),
          .ba_dst(dst),
          .ba_rdy(rdy),
          .ba_dout(dout),
          .rfsh(refresh),
          .owner_ready()
      );
      jtframe_sdram64 #(
          .SHORT_READS(1),
          .DYNAMIC_LINE(1),
          .AW(22),
          .HF(1),
          .READ_CAPTURE_NEGEDGE(1),
          .BA0_LEN(256),
          .BA1_LEN(256),
          .PROG_LEN(16),
          .BA0_WEN(1),
          .BA1_WEN(1),
`ifdef FRAME_INTERLEAVE
          .BANKS(4),
          .BA2_LEN(256),
          .BA3_LEN(256),
          .BA2_WEN(1),
          .BA3_WEN(1)
`else
          .BA2_LEN(16),
          .BA3_LEN(16)
`endif
      ) controller (
          .line_read(line),
          .rst(reset),
          .clk(clk),
          .init(init),
          .ba0_addr(ba_addr),
          .ba1_addr(ba_addr),
          .rd(rd),
          .wr(wr),
          .ba0_din(din),
          .ba1_din(din),
          .ba0_dsn(dsn),
          .ba1_dsn(dsn),
`ifdef FRAME_INTERLEAVE
          .ba2_addr(ba_addr),
          .ba3_addr(ba_addr),
          .ba2_din(din),
          .ba3_din(din),
          .ba2_dsn(dsn),
          .ba3_dsn(dsn),
`else
          .ba2_addr(22'b0),
          .ba3_addr(22'b0),
          .ba2_din(16'b0),
          .ba3_din(16'b0),
          .ba2_dsn(2'b11),
          .ba3_dsn(2'b11),
`endif
          .prog_en(1'b0),
          .prog_addr(22'b0),
          .prog_rd(1'b0),
          .prog_wr(1'b0),
          .prog_din(16'b0),
          .prog_dsn(2'b11),
          .prog_ba(2'b0),
          .prog_dst(),
          .prog_dok(),
          .prog_rdy(),
          .prog_ack(),
          .rfsh(refresh),
          .ack(ba_ack),
          .dst(dst),
          .dok(),
          .rdy(rdy),
          .dout(dout),
          .sdram_dq(pin_read),
          .sdram_din(pin_write),
          .sdram_a(pin_addr),
          .sdram_dqml(dqml),
          .sdram_dqmh(dqmh),
          .sdram_ba(pin_bank),
          .sdram_nwe(we_n),
          .sdram_ncas(cas_n),
          .sdram_nras(ras_n),
          .sdram_ncs(cs_n),
          .sdram_cke(cke)
      );
    end
  endgenerate

  integer timeline = 0;
  string  timeline_path;
  integer cycle = 0, act = 0, pre = 0, ref_count = 0, reads = 0, writes = 0;
  always @(posedge clk) cycle = cycle + 1;
  always @(posedge pin_clk) begin
    if (timeline && (pin_command == 1 || pin_command == 2 || pin_command == 3 ||
                         pin_command == 4 || pin_command == 5))
      $fdisplay(timeline, "C %0d %0d %0d %0d", cycle, pin_command, pin_bank, pin_addr);
    case (pin_command)
      4'b0011: act = act + 1;
      4'b0010: pre = pre + 1;
      4'b0001: ref_count = ref_count + 1;
      4'b0101: reads = reads + 1;
      4'b0100: writes = writes + 1;
      default: ;
    endcase
  end

  task automatic word_access(input bit wr, input [24:0] addr, input [31:0] expected);
    integer start_cycle;
    @(negedge clk);
    write = wr;
    address = addr;
    write_data = expected;
    request = 1;
    start_cycle = cycle;
    if (timeline) $fdisplay(timeline, "T %0d %0d %h 4", cycle, wr, addr);
    do @(negedge clk); while (!ack && cycle - start_cycle < 2000);
    if (!ack || (!wr && read_data !== expected))
      $fatal(
          1,
          "RAM address=%h write=%b ACK=%b data=%h expected=%h",
          addr,
          wr,
          ack,
          read_data,
          expected
      );
    if (timeline) $fdisplay(timeline, "A %0d", cycle);
    request = 0;
    do @(negedge clk); while (ack);
  endtask

  task automatic replay(input [24:0] separation, input bit wr);
    integer start_cycle, start_act, start_pre, start_ref, start_rd, start_wr;
    word_access(1, 0, 32'h12345678);
    word_access(1, separation, 32'h89abcdef);
    repeat (32) @(negedge clk);
    start_cycle = cycle;
    start_act = act;
    start_pre = pre;
    start_ref = ref_count;
    start_rd = reads;
    start_wr = writes;
    for (integer i = 0; i < 512; i = i + 1) begin
      word_access(wr, 0, 32'h12345678);
      word_access(wr, separation, 32'h89abcdef);
    end
    // Drain the final posted write before measuring physical completion.
    if (wr) begin
      word_access(0, 0, 32'h12345678);
      word_access(0, separation, 32'h89abcdef);
    end
    $display(
        "BANK_RESULT donor=%0d write=%0d stride=%0d requests=1024 cycles=%0d act=%0d pre=%0d refresh=%0d reads=%0d writes=%0d",
        DONOR, wr, separation, cycle - start_cycle, act - start_act, pre - start_pre,
        ref_count - start_ref, reads - start_rd, writes - start_wr);
  endtask

  reg [31:0] expected_mem[0:4194303];
  bit seen_word[0:4194303];
  bit written_word[0:4194303];
  integer write_verify_queue[$];
  string trace_path;

  task automatic line_access(input [24:0] addr);
    integer start_cycle, slot;
    reg [15:0] expected;
    @(negedge clk);
    address = addr;
    if (!line_ready) $fatal(1, "Line peer was not idle");
    line_request = 1;
    if (timeline) $fdisplay(timeline, "T %0d 0 %h 32", cycle, addr);
    @(negedge clk);
    line_request = 0;
    start_cycle  = cycle;
    for (integer i = 0; i < 16; i = i + 1) begin
      if (i != 0) @(negedge clk);
      while (!line_valid && cycle - start_cycle < 2000) @(negedge clk);
      slot = int'(addr >> 2) + i / 2;
      expected = i[0] ? expected_mem[slot][31:16] : expected_mem[slot][15:0];
      if (!line_valid || line_data !== expected || line_last !== (i == 15))
        $fatal(
            1,
            "Line %h beat=%0d data=%h expected=%h last=%b",
            addr,
            i,
            line_data,
            expected,
            line_last
        );
    end
    if (timeline) $fdisplay(timeline, "A %0d", cycle);
  endtask

  task automatic donor_line_access(input [24:0] addr);
    integer start_cycle, slot;
    @(negedge clk);
    request = 1;
    write = 0;
    start_cycle = cycle;
    if (timeline) $fdisplay(timeline, "T %0d 0 %h 32", cycle, addr);
    for (integer i = 0; i < 8; i = i + 1) begin
      address = addr + 25'(4 * i);
      donor_burst = i != 7;
      do @(posedge clk); while (!ack && cycle - start_cycle < 2000);
      slot = int'(address >> 2);
      if (!ack || read_data !== expected_mem[slot])
        $fatal(
            1, "Donor line %h word=%0d data=%h expected=%h", addr, i, read_data, expected_mem[slot]
        );
      @(negedge clk);
    end
    if (timeline) $fdisplay(timeline, "A %0d", cycle);
    request = 0;
    do @(negedge clk); while (ack);
  endtask

  task automatic trace_accesses(input string path);
    reg [24:0] addr;
    integer fd, file_cycle, trace_write, width, read_fields, slot, count;
    integer begin_cycle, begin_act, begin_pre, begin_ref, begin_reads, begin_writes;
    fd = $fopen(path, "r");
    if (!fd) $fatal(1, "Unable to open %s", path);
    read_fields = $fscanf(fd, "%d %h %d %d", file_cycle, addr, trace_write, width);
    while (read_fields == 4) begin
      if ((width != 4 && width != 32) || (trace_write && width != 4))
        $fatal(1, "Unexpected trace request width=%0d write=%0d", width, trace_write);
      for (integer i = 0; i < width / 4; i = i + 1) begin
        slot = int'(addr >> 2) + i;
        if (!seen_word[slot]) begin
          expected_mem[slot] = 32'h687d1e47 ^ slot;
          word_access(1, 25'(slot * 4), expected_mem[slot]);
          seen_word[slot] = 1;
        end
      end
      read_fields = $fscanf(fd, "%d %h %d %d", file_cycle, addr, trace_write, width);
    end
    if ($fseek(fd, 0, 0) != 0) $fatal(1, "Unable to rewind trace");
    repeat (32) @(negedge clk);
    begin_cycle = cycle;
    if ($value$plusargs("timeline=%s", timeline_path)) begin
      timeline = $fopen(timeline_path, "w");
      if (!timeline) $fatal(1, "Unable to create %s", timeline_path);
    end
    begin_act = act;
    begin_pre = pre;
    begin_ref = ref_count;
    begin_reads = reads;
    begin_writes = writes;
    count = 0;
    read_fields = $fscanf(fd, "%d %h %d %d", file_cycle, addr, trace_write, width);
    while (read_fields == 4) begin
      slot = int'(addr >> 2);
      if (trace_write != 0) begin
        expected_mem[slot] = expected_mem[slot] ^ (32'h12345678 + count);
        if (!written_word[slot]) write_verify_queue.push_back(slot);
        written_word[slot] = 1;
      end
      if (width == 32) begin
        if (DONOR) donor_line_access(addr);
        else line_access(addr);
      end else word_access(trace_write != 0, addr, expected_mem[slot]);
      count = count + 1;
      read_fields = $fscanf(fd, "%d %h %d %d", file_cycle, addr, trace_write, width);
    end
    $fclose(fd);
    if (write_verify_queue.size()) begin
      slot = write_verify_queue[0];
      word_access(0, 25'(slot * 4), expected_mem[slot]);
    end
    if (timeline) $fclose(timeline);
    timeline = 0;
    $display(
        "TRACE_RESULT requests=%0d cycles=%0d act=%0d pre=%0d refresh=%0d reads=%0d writes=%0d",
        count, cycle - begin_cycle, act - begin_act, pre - begin_pre, ref_count - begin_ref,
        reads - begin_reads, writes - begin_writes);
    foreach (write_verify_queue[i]) begin
      slot = write_verify_queue[i];
      word_access(0, 25'(slot * 4), expected_mem[slot]);
    end
  endtask

  task automatic scan_frame;
    integer begin_cycle, begin_act, begin_pre, begin_ref;
    for (integer i = 0; i < FRAME_WORDS; i = i + 1)
      word_access(1, FRAME_START + 25'(i * 4), 32'ha4c00000 + i);
    repeat (32) @(negedge clk);
    begin_cycle = cycle;
    begin_act   = act;
    begin_pre   = pre;
    begin_ref   = ref_count;
    for (integer i = 0; i < FRAME_WORDS; i = i + 1)
      word_access(0, FRAME_START + 25'(i * 4), 32'ha4c00000 + i);
    $display("SCAN_RESULT donor=%0d bytes=%0d cycles=%0d act=%0d pre=%0d refresh=%0d", DONOR,
             FRAME_WORDS * 4, cycle - begin_cycle, act - begin_act, pre - begin_pre,
             ref_count - begin_ref);
  endtask

  initial begin
    repeat (8) @(negedge clk);
    reset = 0;
    wait (ready);
    if ($value$plusargs("trace=%s", trace_path)) begin
      trace_accesses(trace_path);
      $display("PASS fixed post-L1 SDRAM trace");
      $finish;
    end
    replay(32, 0);
    replay(4096, 0);
    replay(8192, 0);
    replay(16384, 0);
    replay(8388608, 0);
    replay(32, 1);
    replay(4096, 1);
    scan_frame();
    $display("PASS frame gap SDRAM pins");
    $finish;
  end
  initial begin
    #250000000;
    $fatal(1, "SDRAM pin test timed out");
  end
endmodule
