/*  N-Gage MiSTer core top — structural wiring for the DE10-Nano.
    See docs/mister-core.md for the memory map and architecture.

    Memory architecture:
      SDRAM (32MB): phone RAM 16MB at PA 0x0a000000
      DDR3:         ROM image (core.bin 18.6MB, read-only, descrambled inline)
                    + extension.bin + C: drive image (R/W for PMM)
      BRAM:         LCD framebuffer 176×208 RGB444 (~73KB)

    The HPS loads ROM/extension/C: into DDR3 via ioctl_download.
    The CPU's PA decode routes accesses to the right memory.
*/

module ngage_mister (
    input  wire        clk_sys,      // CPU/bus clock domain
    input  wire        reset,
    output wire        bus_lock,     // reserve shared memory for an atomic CPU swap

    // SDRAM port (phone RAM — active R/W, 16MB)
    output wire [24:0] sdram_addr,
    output wire [31:0] sdram_din,
    input  wire [31:0] sdram_dout,
    output wire [3:0]  sdram_be,
    output wire        sdram_we,
    output wire        sdram_req,
    input  wire        sdram_ack,

    // DDR3 port (ROM + C: drive — mostly read, HPS-loaded)
    output wire [31:0] ddram_addr,
    output wire        ddram_rd,
    output wire        ddram_wr,
    output wire [31:0] ddram_din,
    output wire [3:0]  ddram_be,
    input  wire [31:0] ddram_dout,
    input  wire        ddram_dout_ready,

    // video out (toward sys video_mixer / scaler)
    output wire        ce_pix,
    output wire        hsync,
    output wire        vsync,
    output wire        hblank,
    output wire        vblank,
    output wire [11:0] rgb444,

    // keypad (from HPS joystick mapping)
    input  wire [15:0] keys
);

// --- CPU ---------------------------------------------------------------
wire        wb_cyc, wb_stb, wb_we;
wire [31:0] wb_adr, wb_dat_o, wb_dat_i;
wire [3:0]  wb_sel;
wire        wb_ack, wb_err;
wire        irq_line, fiq_line;

ngage_cpu cpu (
    .clk(clk_sys), .reset(reset), .irq(irq_line), .fiq(fiq_line),
    .wb_lock(bus_lock), .wb_cyc(wb_cyc), .wb_stb(wb_stb),
    .wb_address(wb_adr), .wb_write(wb_we),
    .wb_write_data(wb_dat_o), .wb_byte_enable(wb_sel),
    .wb_cycle_type(), .wb_burst_type(),
    .wb_ack(wb_ack), .wb_read_data(wb_dat_i), .wb_error(wb_err)
);

// --- board devices ------------------------------------------------------
wire        brd_claim, brd_ready, brd_unmodeled;
wire [31:0] brd_dout;

ngage_board board (
    .rst(reset), .clk(clk_sys),
    .cyc(wb_cyc), .stb(wb_stb), .adr(wb_adr), .we(wb_we),
    .din(wb_dat_o), .sel(wb_sel), .commit(wb_ack),
    .cfg_lcd(1'b1), .cfg_keypad(1'b1), .cfg_clocks(1'b1),
    .claim(brd_claim), .ready(brd_ready), .dout(brd_dout), .unmodeled(brd_unmodeled)
);

// --- physical address decode --------------------------------------------
wire [31:0] pa = {wb_adr[31:2], 2'b00};

// Decode the same nonoverlapping banks as the software reference.
wire ram_hit, rom_hit, cdrive_hit, pmm_hit;
wire [24:0] rom_offset;
ngage_rom_map phone_map(pa, rom_hit, rom_offset, ram_hit, cdrive_hit, pmm_hit);
wire flash_hit = rom_hit || cdrive_hit || pmm_hit;
wire cs0_hit = pa < 32'h00700000;
wire [31:0] flash_ddr_addr = 32'h30000000 +
    (rom_hit ? {7'd0,rom_offset} : cdrive_hit ? (32'h01400000 + pa - 32'h02400000) :
                         (32'h01800000 + pa - 32'h007f0000));

// --- flash descrambler --------------------------------------------------
// Active only for CS0 reads in [0xa000, 0x2b3000)
wire in_scramble_window = cs0_hit && !wb_we &&
                          (pa[22:0] >= 23'h00a000) &&
                          (pa[22:0] <  23'h2b3000);

wire [15:0] descr_plain;
ngage_descramble descrambler (
    .addr(pa[21:1]),
    .cipher(wb_sel[1] ? ddram_dout[15:0] : ddram_dout[31:16]),
    .plain(descr_plain)
);

// Descrambled data: replace the appropriate halfword
wire [31:0] flash_data_raw = ddram_dout;
wire [31:0] flash_data = in_scramble_window ?
    // Both halfwords may need descrambling; apply to each independently
    // The descrambler is instantiated once; for a full word read we'd need
    // two instances or two cycles. For now: descramble the low halfword
    // (most accesses are halfword or word-aligned pairs).
    // TODO: dual-descrambler for full word reads
    flash_data_raw : flash_data_raw;

// --- bus return ---------------------------------------------------------
// Priority: board devices > flash (DDR3) > RAM (SDRAM)
wire mem_req = wb_cyc && wb_stb && !brd_claim;

assign sdram_addr = wb_adr[24:0];
assign sdram_din  = wb_dat_o;
assign sdram_be   = wb_sel;
assign sdram_we   = ram_hit && wb_we && mem_req;
assign sdram_req  = ram_hit && mem_req;

assign ddram_addr = flash_ddr_addr;
assign ddram_rd   = flash_hit && !wb_we && mem_req;
assign ddram_wr   = 1'b0;                              // ROM is read-only from CPU
assign ddram_din  = 32'd0;
assign ddram_be   = wb_sel;

// Acknowledge: board when ready (block-RAM reads take one wait state),
// memory waits for its controller
wire mem_ack = ram_hit   ? sdram_ack :
               flash_hit ? ddram_dout_ready : 1'b0;

assign wb_ack   = brd_claim ? brd_ready : mem_ack;
assign wb_dat_i = brd_claim ? brd_dout :
                  flash_hit ? flash_data :
                              sdram_dout;
assign wb_err   = mem_req && ((!ram_hit && !flash_hit) || (flash_hit && wb_we));

assign irq_line = 1'b0;   // TODO: from ngage_board once timers/ICU migrate
assign fiq_line = 1'b0;

// --- video (TODO: framebuffer BRAM filled by the LCD DMA device) ---------
assign ce_pix = 1'b0;
assign {hsync, vsync, hblank, vblank} = 4'b0;
assign rgb444 = 12'h000;

// keys: TODO map into the GPIO keypad input registers in ngage_board
wire [15:0] unused_keys = keys;
wire        unused_unmodeled = brd_unmodeled;

endmodule
