`timescale 1ns / 1ps

module tb;
  localparam [31:0] UPLOAD = 32'h31a00000, NOS = 32'h31a10000, FLASH = 32'h30000000;
  reg clk = 0, reset = 1;
  always #5 clk = !clk;

  reg valid = 0, write = 0, flash_active = 0;
  reg [31:0] addr = 0, wdata = 0;
  reg [3:0] mask = 0;
  wire ready, done, flash_ready, flash_done;
  wire [31:0] rdata;
  reg [31:0] flash_addr = FLASH;
  integer flash_completed = 0;

  wire req_valid, req_ready, req_write, req_line, req_bulk, rsp_valid;
  wire [31:0] req_addr, req_data, rsp_data;
  wire [ 3:0] req_be;
  wire [28:0] ddr_addr;
  wire [63:0] ddr_din;
  wire [7:0] ddr_be, burst;
  wire ddr_rd, ddr_we;
  reg [63:0] ddr_dout = 0;
  reg ddr_dout_ready = 0;

  // Retained Template puts bulk save/loading on one side and the core on the
  // other. Here a second client offers independent scalar flash misses to
  // emulate competing DDR traffic, including the retained 32-byte cache fill.
  ngage_ddr_arbiter arb (
      .clk(clk),
      .reset(reset),
      .cpu_lock(1'b0),
      .l_valid(flash_active),
      .l_ready(flash_ready),
      .l_write(1'b0),
      .l_addr(flash_addr),
      .l_data(32'b0),
      .l_be(4'hf),
      .l_done(flash_done),
      .l_bulk(1'b0),
      .c_valid(valid),
      .c_ready(ready),
      .c_write(write),
      .c_addr(addr),
      .c_data(wdata),
      .c_be(mask),
      .c_done(done),
      .c_rdata(rdata),
      .c_bulk(1'b0),
      .c_line(1'b0),
      .req_valid(req_valid),
      .req_ready(req_ready),
      .req_write(req_write),
      .req_addr(req_addr),
      .req_data(req_data),
      .req_be(req_be),
      .req_bulk(req_bulk),
      .req_line(req_line),
      .rsp_valid(rsp_valid),
      .rsp_data(rsp_data),
      .rsp_beat_valid(1'b0),
      .rsp_beat_data(64'b0),
      .rsp_beat_last(1'b0)
  );

  integer cycles = 0, busy_cycles = 0, read_delay = 1, beat_gap = 1;
  wire busy = cycles % 32 < busy_cycles;
  ngage_ddr_flash_adapter #(
      .STREAM_TRANSPORT(1),
      .FLASH_CACHE_BYTES(32768),
      .BULK_PERSISTENCE(1),
      .LINE_REFILL(1)
  ) adapter (
      .clk(clk),
      .reset(reset),
      .req_valid(req_valid),
      .req_ready(req_ready),
      .req_write(req_write),
      .req_line(req_line),
      .req_addr(req_addr),
      .req_wdata(req_data),
      .req_be(req_be),
      .req_fetch(1'b0),
      .rsp_valid(rsp_valid),
      .rsp_data(rsp_data),
      .req_bulk(req_bulk),
      .bulk_cancel(1'b0),
      .bulk_read_ready(1'b0),
      .bulk_write_valid(1'b0),
      .bulk_write_data(64'b0),
      .bulk_write_last(1'b0),
      .ddr_addr(ddr_addr),
      .ddr_din(ddr_din),
      .ddr_be(ddr_be),
      .ddr_burstcount(burst),
      .ddr_rd(ddr_rd),
      .ddr_we(ddr_we),
      .ddr_busy(busy),
      .ddr_dout(ddr_dout),
      .ddr_dout_ready(ddr_dout_ready)
  );

  reg [63:0] backing [0:16383];
  reg [31:0] expected[0:32767];
  integer remaining = 0, next_response = 0;
  reg [28:0] cursor = 0;
  integer scalar_writes = 0, scalar_reads = 0, flash_reads = 0;
  wire [31:0] physical_byte_addr = {ddr_addr, 3'b0};
  wire [31:0] cursor_byte_addr = {cursor, 3'b0};
  wire in_candidate = physical_byte_addr >= UPLOAD && physical_byte_addr < NOS + 65536;

  always @(posedge clk) begin
    cycles <= cycles + 1;
    if (flash_ready) flash_addr <= flash_addr + 32;
    if (flash_done) flash_completed <= flash_completed + 1;
    ddr_dout_ready <= 0;

    if (!busy && ddr_rd) begin
      if (remaining || ddr_we || (in_candidate && burst != 1) || (!in_candidate && burst != 4))
        $fatal(1, "invalid DDR read at %08x, burst %0d", physical_byte_addr, burst);
      if (in_candidate) scalar_reads <= scalar_reads + 1;
      else flash_reads <= flash_reads + 1;
      remaining <= burst;
      cursor <= ddr_addr;
      next_response <= cycles + read_delay - 1;
    end
    if (remaining && cycles >= next_response) begin
      ddr_dout_ready <= 1;
      if (cursor_byte_addr >= UPLOAD && cursor_byte_addr < NOS + 65536)
        ddr_dout <= backing[(cursor_byte_addr-UPLOAD)>>3];
      else ddr_dout <= {cursor_byte_addr ^ 32'h01234567, cursor_byte_addr};
      remaining <= remaining - 1;
      cursor <= cursor + 1;
      next_response <= cycles + beat_gap;
    end
    if (!busy && ddr_we) begin
      if (remaining || ddr_rd || !in_candidate || burst != 1 ||
                physical_byte_addr != (addr & ~7) ||
                ddr_be != (addr[2] ? {mask, 4'b0} : {4'b0, mask}) ||
                ddr_din != {wdata, wdata})
        $fatal(1, "invalid DDR write at %08x, burst %0d", physical_byte_addr, burst);
      for (integer lane = 0; lane < 8; lane++)
      if (ddr_be[lane]) backing[(physical_byte_addr-UPLOAD)>>3][8*lane+:8] <= ddr_din[8*lane+:8];
      scalar_writes <= scalar_writes + 1;
    end
    if (cycles > 6000000) $fatal(1, "timeout");
  end

  integer worst, best, service_sum, admission_sum;

  // Entry/exit at the falling edge. Completion and next admission are
  // separated by only the registered arbiter handoff.
  task automatic access (input bit writing, input int byte_addr, input int data,
                         input logic [3:0] enables);
    integer offered, admitted, finished, word_index;
    offered = cycles;
    valid = 1;
    write = writing;
    addr = byte_addr & ~3;
    mask = enables;
    wdata = data;
    do @(posedge clk); while (!ready);
    admitted = cycles;
    @(negedge clk);
    valid = 0;
    do @(posedge clk); while (!done);
    finished   = cycles;
    word_index = (byte_addr - UPLOAD) >> 2;
    if (writing) begin
      for (integer lane = 0; lane < 4; lane++)
      if (enables[lane]) expected[word_index][8*lane+:8] = data[8*lane+:8];
    end else if (rdata !== expected[word_index]) begin
      $fatal(1, "read at %08x returned %08x, expected %08x", byte_addr, rdata,
             expected[word_index]);
    end
    service_sum += finished - admitted;
    admission_sum += admitted - offered;
    if (finished - offered > worst) worst = finished - offered;
    if (finished - offered < best) best = finished - offered;
    @(negedge clk);
  endtask

  task automatic measure(input string name, input int base, input int size, input int writes,
                         input int reads);
    integer i, offset, start, nw, nr, nf, nfinished;
    start = cycles;
    nw = scalar_writes;
    nr = scalar_reads;
    nf = flash_reads;
    nfinished = flash_completed;
    service_sum = 0;
    admission_sum = 0;
    best = 1000000;
    worst = 0;
    for (i = 0; i < writes || i < reads; i++) begin
      offset = i * size & 65535;
      if (i < writes) begin
        if (size == 1) access (1, base + offset, 32'h31c801ab ^ i, 4'b0001 << (offset & 3));
        else if (size == 2) access (1, base + offset, 32'h83c71eab ^ i, 4'b0011 << (offset & 3));
        else access (1, base + offset, name == "clear" ? 0 : 32'hde081f3a ^ i, 4'hf);
      end
      if (i < reads) begin
        // Spread reads across the window, checking both word lanes.
        offset = (i * 2092 + (i & 1) * 4) & 65535;
        access (0, base + offset, 0, 4'hf);
      end
    end
    if (scalar_writes - nw != writes || scalar_reads - nr != reads)
      $fatal(1, "each access must produce exactly one accepted scalar DDR command");
    $display("%s,%08x,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d", name, base, size, writes, reads,
             cycles - start, service_sum, admission_sum, best, worst, flash_reads - nf,
             flash_completed - nfinished);
    $fflush();
  endtask

  task automatic scenario(input int stall, input int delay, input int gap, input bit compete);
    busy_cycles = stall;
    read_delay = delay;
    beat_gap = gap;
    flash_active = compete;
    $display("settings busy=%0d/32 read_latency=%0d beat_gap=%0d competing=%0d", stall,
             delay < 2 ? 2 : delay, gap, compete);
    $fflush();
    measure("sega", UPLOAD, 2, 18124, 0);
    measure("sonic", UPLOAD, 2, 18904, 0);
    measure("bytes", UPLOAD, 1, 2048, 0);
    measure("nos_writes", NOS, 2, 32, 0);
    measure("nos_reads", NOS, 4, 0, 30);
    measure("nos_interleaved", NOS, 2, 32, 30);
    flash_active = 0;
    repeat (64) @(negedge clk);
    if (!compete) begin
      measure("clear", UPLOAD, 4, 16384, 0);
      measure("clear", NOS, 4, 16384, 0);
    end
  endtask

  initial begin
    for (integer i = 0; i < 16384; i++) begin
      backing[i] = {32'hcafeface + i, 32'h1234ed76 - i};
      expected[i*2] = backing[i][31:0];
      expected[i*2+1] = backing[i][63:32];
    end
    repeat (4) @(negedge clk);
    reset = 0;
    repeat (1025) @(negedge clk);
    $display(
        "case,backing,size,writes,reads,total_cycles,accepted_to_done_sum,offer_to_accept_sum,min_offer_to_done,max_offer_to_done,flash_commands,flash_completions");
    scenario(0, 2, 1, 0);
    scenario(8, 8, 2, 0);
    scenario(16, 20, 4, 0);
    scenario(8, 8, 2, 1);
    scenario(16, 20, 4, 1);
    for (integer i = 0; i < 16384; i++)
    if (backing[i] !== {expected[i*2+1], expected[i*2]})
      $fatal(1, "incorrect partial write at backing entry %0d", i);
    $display("PASS");
    $finish;
  end
endmodule
