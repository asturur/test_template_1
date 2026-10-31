/*  N-Gage MiSTer core top - STRUCTURAL SKELETON (untested; written with
    Claude 2026-10-31 as the wiring contract for the FPGA bring-up; see
    docs/hdl-migration.md step 7).

    What exists today:
      - ZAP ARM920T (rtl/ngage_cpu.sv, SystemVerilog) - the CPU, proven by
        the Verilated boot (both boot logos render from real firmware).
      - rtl/ngage_board.v - migrated devices (LCD transport, GPIO banks),
        lockstep-validated against the C++ model.
    What this top still needs before first light (in order):
      1. SDRAM controller (sys/ or jtframe-style) mapping:
           PA 0x0a000000..0x0bffffff  16MB SDRAM (the phone's RAM)
           ROM window: the 18MB flash image loaded by the HPS into SDRAM
           above the RAM image (or DDR3 via ddram.v) and served read-only.
      2. The remaining board devices in ngage_board (timers/ICU heartbeat,
         CBUS/UEM, flash state machines, LCD DMA against the SDRAM port).
      3. Video: the LCD DMA writes land in a 176x208 RGB444 framebuffer
         (BRAM, 2 words/pixel-pair as on the real transport); a scandoubler
         or the MiSTer scaler centers it. The sim's render_lcd_frame.py
         colour mapping (0x0RGB, x17 per nibble) is the reference.
      4. Keypad: MiSTer joystick/keys -> the GPIO keypad matrix the
         firmware scans (ekeyb reads modeled banks; sim serves zeros=idle).
      5. The modem answerer (the sim's C++ stub behavior, as HDL or as an
         HPS-side helper) - without it the boot stops at the System-error
         loop the sim reproduces.

    Clocking: the sim runs ideal 1-access/cycle memory. Real SDRAM adds
    waits the firmware tolerates (it ran on real hardware), but keep the
    CPU clock modest first (ZAP timing on Cyclone V is unproven; start
    ~25-50 MHz and let the boot take longer).
*/

module ngage_mister (
    input  wire        clk_sys,      // CPU/bus clock domain
    input  wire        reset,

    // SDRAM port (to sys SDRAM controller; TODO arbitrate CPU/DMA/video)
    output wire [24:0] sdram_addr,
    output wire [31:0] sdram_din,
    input  wire [31:0] sdram_dout,
    output wire [3:0]  sdram_be,
    output wire        sdram_we,
    output wire        sdram_req,
    input  wire        sdram_ack,

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
    .wb_cyc(wb_cyc), .wb_stb(wb_stb),
    .wb_address(wb_adr), .wb_write(wb_we),
    .wb_write_data(wb_dat_o), .wb_byte_enable(wb_sel),
    .wb_cycle_type(), .wb_burst_type(),
    .wb_ack(wb_ack), .wb_read_data(wb_dat_i), .wb_error(wb_err)
);

// --- board devices ------------------------------------------------------
wire        brd_claim, brd_unmodeled;
wire [31:0] brd_dout;

ngage_board board (
    .rst(reset), .clk(clk_sys),
    .cyc(wb_cyc), .stb(wb_stb), .adr(wb_adr), .we(wb_we),
    .din(wb_dat_o), .sel(wb_sel), .commit(wb_ack),
    .cfg_lcd(1'b1), .cfg_keypad(1'b1),
    .claim(brd_claim), .dout(brd_dout), .unmodeled(brd_unmodeled)
);

// --- memory + bus return (TODO: SDRAM state machine) ---------------------
// Contract: exactly one wb_ack per wb_stb request; board-claimed requests
// return brd_dout, memory requests return sdram_dout, everything else is
// still unimplemented on the FPGA (the C++ model is the spec, device by
// device). Until the SDRAM path exists this top cannot boot.
assign sdram_addr = wb_adr[24:0];
assign sdram_din  = wb_dat_o;
assign sdram_be   = wb_sel;
assign sdram_we   = wb_we && !brd_claim;
assign sdram_req  = wb_cyc && wb_stb && !brd_claim;   // TODO qualify ranges
assign wb_ack     = brd_claim ? (wb_cyc && wb_stb) : sdram_ack;
assign wb_dat_i   = brd_claim ? brd_dout : sdram_dout;
assign wb_err     = 1'b0;                              // TODO fault model

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
