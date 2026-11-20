`timescale 1ns / 1ps
module physical_lcd_stream_tb #(
    parameter LCD_LINE_BYTES = 0,
    parameter integer SYS_HZ = 78000000
);
  localparam integer PIXEL_WORDS = 18304;
  localparam integer CPU_READS = 1024;
  localparam integer CPU_LINES = 256;
  localparam [24:0] FB = 25'h200000;
  localparam [24:0] CPU_RAM = 25'h240000;
  reg clk = 0;
  always #(500000000.0 / SYS_HZ) clk = ~clk;

  reg cold = 1, reg_cycle = 0;
  wire panel_reset, board_ready, reg_claim, reg_ready, reg_bad;
  reg [31:0] command_addr = 0, command_data = 0;
  reg [24:0] start_addr = FB;
  wire lcd_req, lcd_ack, lcd_accept, lcd_line, lcd_ready, lcd_valid, lcd_last;
  wire [24:0] lcd_addr, lcd_line_addr;
  wire [31:0] lcd_rdata;
  wire [15:0] ram_line_data;
  wire [ 7:0] dma_errors;
  wire dma_claim, dma_ready, dma_bad;

  ngage_board #(
      .LCD_ENABLE(1),
      .GENERAL_DMA(1),
      .LCD_LINE_BYTES(LCD_LINE_BYTES),
      .SYS_CLK_HZ(SYS_HZ)
  ) board (
      .clk(clk),
      .rst(panel_reset),
      .init_rst(cold),
      .init_done(board_ready),
      .cyc(reg_cycle),
      .stb(reg_cycle),
      .commit(reg_cycle),
      .we(reg_cycle),
      .adr(command_addr),
      .din(command_data),
      .sel(4'hf),
      .claim(reg_claim),
      .ready(reg_ready),
      .unmodeled(reg_bad),
      .keys(27'b0),
      .sim_present(1'b0),
      .diagnostic_video(1'b0),
      .diagnostic_status(8'b0),
      .save_state(3'b0),
      .cfg_lcd(1'b1),
      .cfg_keypad(1'b0),
      .cfg_clocks(1'b1),
      .dma_irq_pending(1'b0),
      .sim_fiq_pending(1'b0),
      .dma_mem_req(lcd_req),
      .dma_mem_addr(lcd_addr),
      .dma_mem_accept(lcd_accept),
      .dma_mem_ack(lcd_ack),
      .dma_mem_data(lcd_rdata),
      .lcd_line_req(lcd_line),
      .lcd_line_addr(lcd_line_addr),
      .lcd_line_ready(lcd_ready),
      .lcd_line_valid(lcd_valid),
      .lcd_line_data(ram_line_data),
      .lcd_line_last(lcd_last),
      .lcd_dma_claim(dma_claim),
      .lcd_dma_ready(dma_ready),
      .lcd_dma_bad(dma_bad),
      .dma_error_pending(dma_errors),
      .dma_cmd_ready(1'b0),
      .dma_rsp_valid(1'b0),
      .dma_rsp_error(1'b0),
      .dma_rsp_data(32'b0),
      .dma_local_valid(1'b0),
      .dma_local_waiting(1'b0),
      .dma_local_addr(32'b0),
      .dma_local_data(32'b0),
      .dma_local_be(4'b0),
      .dma_local_write(1'b0)
  );
  wire dma_irq = board.upp.general_dma_irq[1];
  wire active = board.upp.dma_active[1];

  reg cpu_req = 0, cpu_line = 0, cpu_lock = 0;
  reg [24:0] cpu_line_addr = CPU_RAM;
  wire cpu_line_ready, cpu_line_valid, cpu_line_last;
  reg [24:0] cpu_addr = CPU_RAM;
  wire cpu_ack, cpu_accept, hold_scalar, owner_ready, ack, scalar_req;
  wire [24:0] scalar_addr;
  wire [31:0] cpu_data, scalar_data;
  wire dma_req, dma_grant, dma_response;
  wire [24:0] dma_addr;
  wire [31:0] dma_data;
  ngage_dma_ram_mux dma_mux (
      .clk(clk),
      .reset(panel_reset),
      .lcd_req(lcd_req),
      .lcd_addr(lcd_addr),
      .lcd_accept(lcd_accept),
      .lcd_ack(lcd_ack),
      .lcd_rdata(lcd_rdata),
      .dma_req(1'b0),
      .dma_write(1'b0),
      .dma_addr(25'b0),
      .dma_data(32'b0),
      .dma_be(4'b0),
      .dma_ack(),
      .dma_rdata(),
      .pcm_req(1'b0),
      .pcm_addr(25'b0),
      .pcm_ack(),
      .pcm_rdata(),
      .mem_req(dma_req),
      .mem_write(),
      .mem_addr(dma_addr),
      .mem_data(),
      .mem_be(),
      .mem_accept(dma_grant),
      .mem_ack(dma_response),
      .mem_rdata(dma_data)
  );
  wire ram_req, ram_ready, ram_valid, ram_last, scrub_done, ram_short, mem_short;
  wire [24:0] ram_line_addr;
  assign panel_reset = cold || !scrub_done || !board_ready;
  ngage_sdram_line_mux #(
      .LCD_LINE_BYTES(LCD_LINE_BYTES)
  ) line_mux (
      .clk(clk),
      .reset(panel_reset),
      .cpu_lock(cpu_lock),
      .scalar_waiting(cpu_req || dma_req),
      .scalar_accept(cpu_accept || dma_grant),
      .scalar_active(scalar_req),
      .hold_scalar(hold_scalar),
      .cpu_req(cpu_line),
      .cpu_addr(cpu_line_addr),
      .cpu_ready(cpu_line_ready),
      .cpu_valid(cpu_line_valid),
      .cpu_last(cpu_line_last),
      .lcd_req(lcd_line),
      .lcd_addr(lcd_line_addr),
      .lcd_ready(lcd_ready),
      .lcd_valid(lcd_valid),
      .lcd_last(lcd_last),
      .ram_req(ram_req),
      .ram_short(ram_short),
      .ram_addr(ram_line_addr),
      .ram_ready(ram_ready),
      .ram_valid(ram_valid),
      .ram_last(ram_last)
  );
  wire packet_lock;
  ngage_sdram_arbiter arbiter (
      .clk(clk),
      .reset(panel_reset),
      .cpu_lock(cpu_lock),
      .cpu_req(cpu_req && owner_ready && !hold_scalar),
      .cpu_we(1'b0),
      .cpu_addr(cpu_addr),
      .cpu_data(32'b0),
      .cpu_be(4'hf),
      .cpu_ack(cpu_ack),
      .cpu_rdata(cpu_data),
      .cpu_accept(cpu_accept),
      .dma_req(dma_req && owner_ready && !hold_scalar),
      .dma_we(1'b0),
      .dma_addr(dma_addr),
      .dma_data(32'b0),
      .dma_be(4'hf),
      .dma_ack(dma_response),
      .dma_rdata(dma_data),
      .dma_accept(dma_grant),
      .mem_req(scalar_req),
      .mem_we(),
      .mem_lock(packet_lock),
      .mem_addr(scalar_addr),
      .mem_data(),
      .mem_be(),
      .mem_ack(ack),
      .mem_rdata(scalar_data)
  );

  wire pin_request, pin_write_op, pin_line, mem_ready, mem_cmd_ready, mem_busy, mem_valid;
  wire [ 24:2] mem_addr;
  wire [127:0] mem_write_data;
  wire [ 15:0] mem_mask;
  wire [ 31:0] mem_read_data;
  ngage_sdram_stream #(
      .SCRUB_BYTES(25'd32)
  ) stream (
      .clk(clk),
      .cold(cold),
      .phone_reset(panel_reset),
      .lock(packet_lock),
      .owner_ready(owner_ready),
      .grant_read(cpu_accept || dma_grant),
      .grant_addr(cpu_accept ? cpu_addr : dma_addr),
      .req(scalar_req),
      .we(1'b0),
      .write_block(1'b0),
      .block_data(128'b0),
      .addr(scalar_addr),
      .din(32'b0),
      .be(4'hf),
      .ack(ack),
      .dout(scalar_data),
      .line_req(ram_req),
      .line_short(ram_short),
      .line_addr(ram_line_addr),
      .line_ready(ram_ready),
      .line_valid(ram_valid),
      .line_data(ram_line_data),
      .line_last(ram_last),
      .mem_req(pin_request),
      .mem_we(pin_write_op),
      .mem_line(pin_line),
      .mem_short(mem_short),
      .mem_addr(mem_addr),
      .mem_wdata(mem_write_data),
      .mem_wbe(mem_mask),
      .scrub_done(scrub_done),
      .mem_ready(mem_ready),
      .mem_cmd_ready(mem_cmd_ready),
      .mem_busy(mem_busy),
      .mem_valid(mem_valid),
      .mem_rdata(mem_read_data)
  );
  wire pin_clk, cke, cs_n, ras_n, cas_n, we_n, dqml, dqmh;
  wire [ 1:0] pin_bank;
  wire [12:0] pin_addr;
  wire [15:0] write_to_pins, read_from_pins;
  tri [15:0] dq;
  ngage_sdram_clock clock_out (
      .clk(clk),
      .sdram_clk(pin_clk)
  );
  assign #5.5 read_from_pins = memory.Dq_reg;
  ngage_sdram_scheduler #(
      .CLK_HZ(SYS_HZ)
  ) controller (
      .clk(clk),
      .init(cold),
      .ready(mem_ready),
      .req(pin_request),
      .busy(mem_busy),
      .cmd_ready(mem_cmd_ready),
      .we(pin_write_op),
      .line(pin_line),
      .read_short(mem_short),
      .addr(mem_addr),
      .wdata(mem_write_data),
      .wbe(mem_mask),
      .rvalid(mem_valid),
      .rword(),
      .rdata(mem_read_data),
      .sdram_cke(cke),
      .sdram_cs_n(cs_n),
      .sdram_ras_n(ras_n),
      .sdram_cas_n(cas_n),
      .sdram_we_n(we_n),
      .sdram_ba(pin_bank),
      .sdram_a(pin_addr),
      .sdram_dqml(dqml),
      .sdram_dqmh(dqmh),
      .sdram_dq_o(write_to_pins),
      .sdram_dq_oe(),
      .sdram_dq_i(read_from_pins)
  );
  mt48lc16m16a2 memory (
      .Clk(pin_clk),
      .Cke(cke),
      .Dq(dq),
      .Dq_write(write_to_pins),
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

  function automatic [31:0] word_at(input [24:0] address);
    word_at = (32'h9d4b03a7 ^ {7'b0, address}) + ((address >> 2) * 32'h1234567);
  endfunction
  task automatic seed_halfword(input [24:0] address, input [15:0] value);
    integer cell_addr;
    cell_addr = int'({address[24:14], address[11:1]});
    case (address[13:12])
      0: memory.Bank0[cell_addr] = value;
      1: memory.Bank1[cell_addr] = value;
      2: memory.Bank2[cell_addr] = value;
      3: memory.Bank3[cell_addr] = value;
    endcase
  endtask
  task automatic seed_word(input [24:0] address);
    reg [31:0] value;
    value = word_at(address);
    seed_halfword(address, value[15:0]);
    seed_halfword(address + 2, value[31:16]);
  endtask
  task automatic lcd_command(input [31:0] address, input [31:0] value);
    @(negedge clk);
    reg_cycle = 1;
    command_addr = address;
    command_data = value;
    do @(posedge clk); while (!(dma_claim ? dma_ready : reg_ready));
    if (dma_claim ? dma_bad : (!reg_claim || reg_bad))
      $fatal(1, "LCD host register rejected %h", address);
    @(negedge clk);
    reg_cycle = 0;
  endtask
  task automatic open_panel;
    lcd_command(32'h0c121200, 32'h09200000);
    lcd_command(32'h0c121208, 32'h0000005c);
    lcd_command(32'h0c121200, 32'h8924d67f);
  endtask

  task automatic program_dma;
    lcd_command(32'h0c120344, 1);
    lcd_command(32'h0c120354, 32'h0a000000 | {7'b0, start_addr});
    lcd_command(32'h0c120358, 1);
    lcd_command(32'h0c12035c, 32);
    lcd_command(32'h0c120360, 32'h10121208);
    lcd_command(32'h0c120364, 0);
    lcd_command(32'h0c120368, 32);
    lcd_command(32'h0c12036c, PIXEL_WORDS - 1);
  endtask

  integer cycle = 0, start = 0, end_pixel = 0, pixels = 0, read_cursor = 0;
  integer scalar_reads = 0, line_reads = 0, pin_reads = 0;
  integer cpu_count = 0, cpu_latency = 0, cpu_max_latency = 0;
  integer cpu_period = 24, cpu_service_max = 0;
  integer refills_done = 0, refill_wait_sum = 0, refill_wait_max = 0;
  bit contend, unaligned, cancel_case, refill_case, measured = 0;
  always @(posedge pin_clk) if (measured && {cs_n, ras_n, cas_n, we_n} == 4'b0101) pin_reads++;
  always @(posedge clk) begin
    cycle++;
    if (measured) begin
      if (lcd_accept || (lcd_ready && lcd_line)) begin
        if ((lcd_accept ? lcd_addr : lcd_line_addr) != start_addr + 25'(read_cursor * 4))
          $fatal(1, "LCD source sequence advanced out of order");
        if (lcd_accept) scalar_reads++;
        else line_reads++;
        read_cursor += lcd_accept ? 1 : LCD_LINE_BYTES / 4;
        if (read_cursor > PIXEL_WORDS) $fatal(1, "Read beyond LCD descriptor");
      end
      if (board.lcd_dma_pixel) begin
        if (board.display.queued_data !== word_at(start_addr + 25'(pixels * 4)))
          $fatal(1, "LCD pixel %0d differs from source", pixels);
        pixels++;
        end_pixel = cycle;
      end
    end
  end

  initial begin : concurrent_cpu
    integer planned, elapsed, offered;
    wait (measured);
    if (contend) begin
      for (integer i = 0; i < CPU_READS; i++) begin
        planned = start + (i + 1) * cpu_period;
        do @(negedge clk); while (cycle < planned);
        offered  = cycle;
        cpu_req  = 1;
        cpu_addr = CPU_RAM + 25'(4 * (i % 64));
        do @(posedge clk); while (!cpu_ack);
        if (cpu_data !== word_at(cpu_addr)) $fatal(1, "Contending CPU read mismatch");
        elapsed = cycle - planned;
        cpu_latency += elapsed;
        if (elapsed > cpu_max_latency) cpu_max_latency = elapsed;
        if (cycle - offered > cpu_service_max) cpu_service_max = cycle - offered;
        cpu_count++;
        @(negedge clk);
        cpu_req = 0;
      end
    end
  end

  initial begin : concurrent_refills
    reg [31:0] value;
    integer offered, elapsed;
    wait (measured);
    if (refill_case) begin
      @(negedge clk);
      cpu_lock = 1;
      repeat (24) begin
        @(posedge clk);
        if (ram_req || lcd_accept) $fatal(1, "LCD started while CPU held its SWP lock");
      end
      @(negedge clk);
      cpu_lock = 0;
      for (integer i = 0; i < CPU_LINES; i++) begin
        do @(negedge clk); while (cycle < start + (i + 1) * 96);
        offered = cycle;
        cpu_line_addr = CPU_RAM + 25'(32 * (i % 8));
        cpu_line = 1;
        do @(posedge clk); while (!cpu_line_ready);
        @(negedge clk);
        cpu_line = 0;
        for (integer beat = 0; beat < 16; beat++) begin
          do @(posedge clk); while (!cpu_line_valid);
          value = word_at(cpu_line_addr + 25'((beat / 2) * 4));
          if (cpu_line_last !== (beat == 15) || ram_line_data !== value[(beat%2)*16+:16])
            $fatal(1, "CPU refill response was misrouted at beat %0d", beat);
        end
        elapsed = cycle - offered;
        refill_wait_sum += elapsed;
        if (elapsed > refill_wait_max) refill_wait_max = elapsed;
        refills_done++;
      end
    end
  end

  initial begin
    reg [31:0] expected;
    contend = $test$plusargs("contend") || $test$plusargs("moderate");
    if ($test$plusargs("moderate")) cpu_period = 40;
    unaligned   = $test$plusargs("unaligned");
    cancel_case = $test$plusargs("cancel");
    refill_case = $test$plusargs("refills");
    if (unaligned) start_addr = FB + 4;
    repeat (4) @(negedge clk);
    cold = 0;
    wait (!panel_reset);
    for (integer word = 0; word < PIXEL_WORDS; word++) seed_word(start_addr + 25'(word * 4));
    for (integer word = 0; word < 64; word++) seed_word(CPU_RAM + 25'(word * 4));
    lcd_command(32'h0c121204, 1);
    lcd_command(32'h0c120068, 32'hf0);
    lcd_command(32'h0c120064, 32'h70);
    open_panel();
    program_dma();
    if (cancel_case) begin
      lcd_command(32'h0c120348, 2);
      if (LCD_LINE_BYTES) wait (lcd_valid);
      else wait (lcd_accept);
      lcd_command(32'h0c120348, 0);
      wait (!active && board.lcd_queue_empty);
      if (dma_irq || dma_errors) $fatal(1, "LCD cancel produced an interrupt or error");
      open_panel();
    end
    @(negedge clk);
    measured = 1;
    start = cycle;
    lcd_command(32'h0c120348, 2);
    wait (dma_irq || dma_errors);
    @(negedge clk);
    measured = 0;
    if (!dma_irq || dma_errors || !board.lcd_queue_empty ||
            !board.display.lcd.frame_complete || board.display.lcd.incomplete ||
            pixels != PIXEL_WORDS || read_cursor != PIXEL_WORDS)
      $fatal(1, "LCD full-frame count or completion is wrong");
    for (integer word = 0; word < PIXEL_WORDS; word++) begin
      expected = word_at(start_addr + 25'(word * 4));
      if (board.display.lcd.framebuffer.memory[word] !== {expected[27:16], expected[11:0]})
        $fatal(1, "Panel BRAM pixel word %0d differs", word);
    end
    if (contend && cpu_count != CPU_READS) $fatal(1, "CPU overlap window fell outside upload");
    if (refill_case && refills_done != CPU_LINES) $fatal(1, "Missing competing CPU refills");
    if (LCD_LINE_BYTES && !unaligned &&
            (scalar_reads != 0 || line_reads != PIXEL_WORDS*4/LCD_LINE_BYTES ||
             pin_reads != PIXEL_WORDS/4 + cpu_count + 2*refills_done))
      $fatal(1, "Unexpected aligned LCD request count or BL8 command count");
    $display(
        "LCD_RESULT line_bytes=%0d contend=%0d unaligned=%0d cancel=%0d clocks=%0d scalar=%0d lines=%0d pin_reads=%0d cpu_reads=%0d cpu_wait_sum=%0d cpu_wait_max=%0d cpu_offer_max=%0d cpu_period=%0d cpu_refills=%0d refill_wait_sum=%0d refill_wait_max=%0d",
        LCD_LINE_BYTES, contend, unaligned, cancel_case, end_pixel - start, scalar_reads,
        line_reads, pin_reads, cpu_count, cpu_latency, cpu_max_latency, cpu_service_max,
        cpu_period, refills_done, refill_wait_sum, refill_wait_max);
    $display("PASS checked LCD upload with SDRAM pins and panel BRAM");
    $finish;
  end

  initial begin
    #10000000;
    $fatal(1, "LCD physical replay timed out");
  end
endmodule
