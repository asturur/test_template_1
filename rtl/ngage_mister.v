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
    input  wire        cold_reset,
    output wire        board_init_done,
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
    input  wire        ddram_accept,
    output wire        flash_dirty,
    output wire [13:0] flash_dirty_sector,
    output wire        flash_busy,

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
    .rst(reset), .init_rst(cold_reset), .clk(clk_sys),
    .cyc(wb_cyc), .stb(wb_stb), .adr(wb_adr), .we(wb_we),
    .din(wb_dat_o), .sel(wb_sel), .commit(wb_ack),
    .cfg_lcd(1'b1), .cfg_keypad(1'b1), .cfg_clocks(1'b1), .dma_irq_pending(1'b0),.sim_fiq_pending(1'b0),.dma_irq_clear(),
    .claim(brd_claim), .ready(brd_ready), .dout(brd_dout), .unmodeled(brd_unmodeled), .irq(irq_line), .fiq(fiq_line), .init_done(board_init_done)
);

// --- physical address decode --------------------------------------------
wire [31:0] pa = {wb_adr[31:2], 2'b00};

// Decode the same nonoverlapping banks as the software reference.
wire ram_hit, rom_hit, cdrive_hit, pmm_hit;
wire [24:0] rom_offset;
ngage_rom_map phone_map(pa, rom_hit, rom_offset, ram_hit, cdrive_hit, pmm_hit);
wire flash_hit = rom_hit || cdrive_hit || pmm_hit;
// Flash request ownership is retained until the command or DDR operation
// completes. The C: range has priority over the overlapping CS1 window.
wire mem_req = wb_cyc && wb_stb && !brd_claim;
reg flash_issued = 0;
wire code_ready,code_rsp,code_err,cm_valid,cm_write,cm_ready,cm_done,code_dirty,code_pending;
wire [31:0] code_data,cm_addr,cm_data;wire [3:0] cm_be;wire [13:0] code_dirty_sector;
wire user_ready,user_rsp,user_err,um_valid,um_write,um_ready,um_done,user_dirty,user_pending;
wire [31:0] user_data,um_addr,um_data;wire [3:0] um_be;wire [12:0] user_dirty_sector;
wire flash_start = mem_req && flash_hit && !flash_issued;
wire flash_response = code_rsp || user_rsp;
always @(posedge clk_sys) begin
 if(reset) flash_issued<=0;
 else begin
  if(flash_start && (cdrive_hit ? user_ready : code_ready)) flash_issued<=1;
  if(flash_response) flash_issued<=0;
 end
end
ngage_codeflash code_flash(
 .clk(clk_sys),.reset(reset),.req_valid(flash_start && !cdrive_hit),.req_ready(code_ready),
 .req_write(wb_we),.req_address(pa),.req_data(wb_dat_o),.req_be(wb_sel),
 .rsp_valid(code_rsp),.rsp_error(code_err),.rsp_data(code_data),
 .mem_valid(cm_valid),.mem_ready(cm_ready),.mem_write(cm_write),.mem_addr(cm_addr),.mem_data(cm_data),.mem_be(cm_be),
 .mem_done(cm_done),.mem_rdata(ddram_dout),.dirty_valid(code_dirty),.dirty_sector(code_dirty_sector),.pending(code_pending)
);
ngage_cflash user_flash(
 .clk(clk_sys),.reset(reset),.req_valid(flash_start && cdrive_hit),.req_ready(user_ready),
 .req_write(wb_we),.req_offset(pa[21:0]),.req_data(wb_dat_o),.req_be(wb_sel),
 .rsp_valid(user_rsp),.rsp_error(user_err),.rsp_data(user_data),
 .mem_valid(um_valid),.mem_ready(um_ready),.mem_write(um_write),.mem_addr(um_addr),.mem_wdata(um_data),.mem_be(um_be),
 .mem_done(um_done),.mem_rdata(ddram_dout),.dirty_valid(user_dirty),.dirty_sector(user_dirty_sector),.pending(user_pending)
);
reg mem_owner_user=0;
always @(posedge clk_sys) if(ddram_accept && (cm_valid || um_valid)) mem_owner_user<=um_valid;
assign cm_ready=ddram_accept && cm_valid; assign um_ready=ddram_accept && um_valid;
assign cm_done=ddram_dout_ready && !mem_owner_user; assign um_done=ddram_dout_ready && mem_owner_user;
assign ddram_addr=um_valid ? um_addr : cm_addr;
assign ddram_din=um_valid ? um_data : cm_data;
assign ddram_be=um_valid ? um_be : cm_be;
assign ddram_wr=(um_valid && um_write) || (cm_valid && cm_write);
assign ddram_rd=(um_valid && !um_write) || (cm_valid && !cm_write);
assign flash_busy=flash_issued || code_pending || user_pending;
assign flash_dirty=code_dirty || user_dirty;
assign flash_dirty_sector=user_dirty ? {1'b0,user_dirty_sector} : code_dirty_sector;
assign sdram_addr=wb_adr[24:0];assign sdram_din=wb_dat_o;assign sdram_be=wb_sel;
assign sdram_we=ram_hit && wb_we && mem_req;assign sdram_req=ram_hit && mem_req;
wire flash_error=(code_rsp && code_err) || (user_rsp && user_err);
wire mem_ack=ram_hit ? sdram_ack : flash_hit ? (flash_response && !flash_error) : 1'b0;
// Register board/decode faults so Wishbone STB suppression on ERR cannot
// form a combinational loop. No invalid access is acknowledged as success.
reg invalid_response=0;
always @(posedge clk_sys) begin
 if(reset) invalid_response<=0;
 else invalid_response<=!invalid_response && ((brd_claim && brd_ready && brd_unmodeled) ||
                                              (mem_req && !ram_hit && !flash_hit));
end
assign wb_ack=brd_claim ? (brd_ready && !brd_unmodeled) : mem_ack;
assign wb_dat_i=brd_claim ? brd_dout : flash_hit ? (user_rsp ? user_data : code_data) : sdram_dout;
assign wb_err=invalid_response || flash_error;


// --- video (TODO: framebuffer BRAM filled by the LCD DMA device) ---------
assign ce_pix = 1'b0;
assign {hsync, vsync, hblank, vblank} = 4'b0;
assign rgb444 = 12'h000;

// keys: TODO map into the GPIO keypad input registers in ngage_board
wire [15:0] unused_keys = keys;
wire        unused_unmodeled = brd_unmodeled;

endmodule
