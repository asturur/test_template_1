`timescale 1ns / 1ps

module tb;
  localparam [31:0] FLASH = 32'h30000000;
  localparam [31:0] SAVE  = 32'h31400020;
  reg clk_sys = 0;
  always #5 clk_sys = !clk_sys;

  reg transport_reset = 1, reset = 1, cpu_bus_lock = 0;
  reg [16:2] guest_word = 0;
  reg guest_req = 0, guest_write = 0, guest_clear = 0;
  reg [31:0] guest_data = 0;
  reg [ 3:0] guest_be = 0;

  reg firmware_aux_valid = 0, firmware_aux_write = 0;
  reg [31:0] firmware_aux_addr = SAVE, firmware_aux_data = 0;
  reg [3:0] firmware_aux_be = 4'hf;
  wire firmware_aux_ready, firmware_aux_done;
  wire [31:0] firmware_aux_rdata;
  reg core_flash = 0;
  reg [31:0] flash_addr = FLASH;

  wire [28:0] DDRAM_ADDR;
  wire [63:0] DDRAM_DIN;
  wire [7:0] DDRAM_BE, DDRAM_BURSTCNT;
  wire DDRAM_RD, DDRAM_WE;
  reg [63:0] DDRAM_DOUT = 0;
  reg DDRAM_DOUT_READY = 0;
  reg force_busy = 0, periodic_busy = 1;
  integer cycles = 0;
  wire DDRAM_BUSY = force_busy || (periodic_busy && cycles % 17 < 6);

  `include "route.vh"

  assign upp_ddr_req = guest_req;
  assign upp_ddr_we = guest_write;
  assign upp_ddr_addr = guest_word;
  assign upp_ddr_wdata = guest_data;
  assign upp_ddr_be = guest_be;
  assign upp_ddr_clear = guest_clear;
  assign core_ddr_addr = flash_addr;
  assign core_ddr_rd = core_flash;
  assign core_ddr_wr = 0;
  assign core_ddr_din = 0;
  assign core_ddr_be = 4'hf;
  assign core_ddr_line = 1'b0;
  assign core_ddr_fetch = 1'b0;
  assign save_mem_valid = 1'b0;
  assign bulk_cancel = reset;
  assign bulk_read_ready = 1'b0;
  assign bulk_write_valid = 1'b0;
  assign bulk_write_data = 64'b0;
  assign bulk_write_last = 1'b0;

  wire [31:0] physical = {DDRAM_ADDR, 3'b0};
  wire is_upp = physical >= UPP_RAM_BASE && physical < UPP_RAM_BASE + 131072;
  reg [63:0] contents[0:16383];
  reg [63:0] save_word = 64'h8c785634ab23def0;
  reg [31:0] read_cursor = 0;
  integer read_pending = 0, flash_reads = 0, save_reads = 0, guest_reads = 0, guest_writes = 0;
  integer scrub_count = 0;
  reg check_scrub = 0;
  reg held_write = 0;
  reg [28:0] held_addr;
  reg [63:0] held_data;
  reg [7:0] held_be;

  always @(posedge clk_sys) begin
    cycles <= cycles + 1;
    if (cycles > 100000) $fatal(1, "transport timeout");
    if (cpu_bus_lock && !reset && (firmware_aux_ready || firmware_aux_done))
      $fatal(1, "loader-side traffic escaped SWP lock");

    if (held_write && (!DDRAM_WE || DDRAM_ADDR !== held_addr ||
            DDRAM_DIN !== held_data || DDRAM_BE !== held_be))
      $fatal(1, "physical write changed under waitrequest");
    held_write <= DDRAM_WE && DDRAM_BUSY;
    if (DDRAM_WE && DDRAM_BUSY) begin
      held_addr <= DDRAM_ADDR;
      held_data <= DDRAM_DIN;
      held_be   <= DDRAM_BE;
    end

    if (guest_clear && (bulk_read_valid || bulk_write_ready || bulk_error))
      $fatal(1, "UPP scrub used persistence's stream sidebands");
    if (DDRAM_WE && !DDRAM_BUSY) begin
      if (DDRAM_BURSTCNT != 1 || !is_upp || DDRAM_RD)
        $fatal(1, "unexpected physical write at %08x", physical);
      for (integer lane = 0; lane < 8; lane++)
      if (DDRAM_BE[lane]) contents[(physical-UPP_RAM_BASE)>>3][8*lane+:8] <= DDRAM_DIN[8*lane+:8];
      if (check_scrub) begin
        if (physical != UPP_RAM_BASE + scrub_count * 8 || DDRAM_DIN != 0 || DDRAM_BE != 8'hff)
          $fatal(1, "bad scrub write at beat %0d addr %08x", scrub_count, physical);
        scrub_count <= scrub_count + 1;
      end else guest_writes <= guest_writes + 1;
    end

    DDRAM_DOUT_READY <= 0;
    if (DDRAM_RD && !DDRAM_BUSY) begin
      if (read_pending || (DDRAM_BURSTCNT != (is_upp ? 1 : 4)))
        $fatal(1, "invalid physical read at %08x", physical);
      read_cursor  <= physical;
      read_pending <= DDRAM_BURSTCNT;
      if (is_upp) guest_reads <= guest_reads + 1;
      else if (physical == SAVE) save_reads <= save_reads + 1;
      else if (physical == FLASH) flash_reads <= flash_reads + 1;
      else $fatal(1, "unexpected physical read at %08x", physical);
    end
    if (read_pending != 0 && cycles % 3 == 0) begin
      DDRAM_DOUT_READY <= 1;
      if (read_cursor >= UPP_RAM_BASE && read_cursor < UPP_RAM_BASE + 131072)
        DDRAM_DOUT <= contents[(read_cursor-UPP_RAM_BASE)>>3];
      else if (read_cursor >= SAVE) DDRAM_DOUT <= save_word;
      else DDRAM_DOUT <= 64'h10203040aabbccdd;
      read_pending <= read_pending - 1;
      read_cursor  <= read_cursor + 8;
    end
  end

  task automatic guest_access(input bit writing, input logic [16:2] word_offset,
                              input logic [3:0] enables, input logic [31:0] data,
                              input logic [31:0] expected);
    guest_req = 1;
    guest_write = writing;
    guest_word = word_offset;
    guest_be = enables;
    guest_data = data;
    do @(posedge clk_sys); while (!upp_ddr_ack);
    if (!writing && upp_ddr_rdata !== expected)
      $fatal(1, "UPP read returned %08x, expected %08x", upp_ddr_rdata, expected);
    // Hold beyond ACK to catch duplicate admissions.
    repeat (4) begin
      @(posedge clk_sys);
      if (upp_ddr_ack) $fatal(1, "duplicate UPP ACK");
    end
    @(negedge clk_sys);
    guest_req = 0;
    @(negedge clk_sys);
  endtask

  task automatic flash_read;
    core_flash = 1;
    do @(posedge clk_sys); while (!core_accept);
    @(negedge clk_sys);
    core_flash = 0;
    do @(posedge clk_sys); while (!core_ddr_ready);
    if (core_ddr_dout !== 32'haabbccdd) $fatal(1, "lost core flash response");
    @(negedge clk_sys);
  endtask

  task automatic wait_scrub;
    while (!upp_ddr_clear_done) @(negedge clk_sys);
    if (scrub_count != 16384) $fatal(1, "scrub completed at %0d/16384 beats", scrub_count);
    for (integer i = 0; i < 16384; i++)
      if (contents[i] !== 0) $fatal(1, "scrub did not clear word %0d", i);
    guest_clear = 0;
    check_scrub = 0;
    @(negedge clk_sys);
    if (upp_ddr_clear_done) $fatal(1, "clear acknowledgement stayed high");
  endtask

  initial begin
    for (integer i = 0; i < 16384; i++) contents[i] = 64'hfbbe093712ab9835;
    repeat (4) @(negedge clk_sys);
    guest_clear = 1;
    check_scrub = 1;
    transport_reset = 0;
    // Test ordinary flash and loader-side traffic while a cold scrub
    // keeps requesting chunks, with phone reset still asserted.
    fork
      begin
        wait_scrub();
        if (!flash_reads || !save_reads) $fatal(1, "scrub starved another requester");
      end
      begin
        flash_read();
      end
      begin
        repeat (8000) @(negedge clk_sys);
        firmware_aux_valid = 1;
        do @(posedge clk_sys); while (!firmware_aux_ready);
        @(negedge clk_sys);
        firmware_aux_valid = 0;
        do @(posedge clk_sys); while (!firmware_aux_done);
        if (firmware_aux_rdata !== save_word[31:0]) $fatal(1, "lost loader-side response");
      end
    join
    reset = 0;
    flash_read();
    if (flash_reads != 1) $fatal(1, "scrub invalidated the flash cache");
    // Emulate CPU SWP across the two operations with a competing
    // outer client. That client must stay parked until lock release.
    cpu_bus_lock = 1;
    firmware_aux_valid = 1;
    guest_access(0, 15'h0000, 4'hf, 0, 0);
    guest_access(1, 15'h0000, 4'hf, 32'h10203040, 0);
    firmware_aux_valid = 0;
    cpu_bus_lock = 0;
    guest_access(1, 15'h4000, 4'b0100, 32'h00ab0000, 0);
    guest_access(1, 15'h4001, 4'b1100, 32'h13570000, 0);
    guest_access(0, 15'h0000, 4'hf, 0, 32'h10203040);
    guest_access(0, 15'h4000, 4'hf, 0, 32'h00ab0000);
    guest_access(0, 15'h4001, 4'hf, 0, 32'h13570000);

    // Warm reset must drain the already held physical command and
    // acknowledge it without starting another scrub.
    force_busy = 1;
    fork
      begin
        guest_access(1, 15'h7fff, 4'b0011, 32'h0000ab57, 0);
      end
      begin
        wait (DDRAM_WE);
        repeat (3) @(negedge clk_sys);
        reset = 1;
        repeat (4) @(negedge clk_sys);
        force_busy = 0;
      end
    join
    reset = 0;
    guest_access(0, 15'h7fff, 4'hf, 0, 32'h0000ab57);
    if (guest_reads != 5 || guest_writes != 4)
      $fatal(1, "scalar transactions repeated or went missing");

    // A cold reset retires logical ownership, while allowing the DDR
    // endpoint to accept the already held command before the new scrub.
    force_busy = 1;
    guest_req = 1;
    guest_write = 1;
    guest_word = 15'h0002;
    guest_be = 4'hf;
    guest_data = 32'hfeedbeef;
    wait (DDRAM_WE);
    repeat (3) @(negedge clk_sys);
    transport_reset = 1;
    reset = 1;
    guest_req = 0;
    repeat (4) @(negedge clk_sys);
    transport_reset = 0;
    guest_clear = 1;
    force_busy = 0;
    wait (guest_writes == 5);
    @(negedge clk_sys);
    scrub_count = 0;
    check_scrub = 1;
    wait_scrub();
    reset = 0;
    guest_access(0, 15'h0002, 4'hf, 0, 0);

    $display(
        "PASS production UPP DDR route, byte lanes, both banks, full scrubs, contention, SWP and reset drain");
    $finish;
  end
endmodule
