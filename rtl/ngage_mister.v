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

module ngage_mister #(
    parameter UEM_POWERUP_STATUS = 2
) (
    input  wire        clk_sys,             // CPU/bus clock domain
    input  wire        reset,
    input  wire        cold_reset,
    input  wire        sim_present,
    output wire        dma_sdram_req,
    output wire [24:0] dma_sdram_addr,
    input  wire        dma_sdram_ack,
    input  wire [31:0] dma_sdram_data,
    input  wire        diagnostic_video,
    input  wire [ 7:0] diagnostic_status,
    input  wire [ 2:0] save_state,
    input  wire        debug_freeze_trace,
    input  wire [10:0] debug_read_word,
    output wire [15:0] debug_read_data,
    output wire        debug_fault_seen,
    output wire        lcd_unsupported,
    output wire        board_init_done,
    output wire        bus_lock,            // reserve shared memory for an atomic CPU swap

    // SDRAM port (phone RAM — active R/W, 16MB)
    output wire [24:0] sdram_addr,
    output wire [31:0] sdram_din,
    input  wire [31:0] sdram_dout,
    output wire [ 3:0] sdram_be,
    output wire        sdram_we,
    output wire        sdram_req,
    input  wire        sdram_ack,

    // DDR3 port (ROM + C: drive — mostly read, HPS-loaded)
    output wire [31:0] ddram_addr,
    output wire        ddram_rd,
    output wire        ddram_wr,
    output wire [31:0] ddram_din,
    output wire [ 3:0] ddram_be,
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
    input wire [26:0] keys
);

    // --- CPU ---------------------------------------------------------------
    wire wb_cyc, wb_stb, wb_we, wb_code;
    wire [31:0] wb_adr, wb_dat_o, wb_dat_i;
    wire [3:0] wb_sel;
    wire wb_ack, wb_err;
    wire irq_line, fiq_line;

    // Keep the CPU in reset until any accepted flash transaction has drained.
    // Command state is cleared while draining; pending command setup alone must
    // not prevent release. Cold reset cancels controller state with the transport.
    wire code_idle, user_idle;
    reg reset_drain = 1'b1;
    always @(posedge clk_sys) begin
        if (reset || cold_reset) reset_drain <= 1'b1;
        else if (reset_drain && code_idle && user_idle) reset_drain <= 1'b0;
    end
    wire core_reset = reset || cold_reset || reset_drain;

    // --- board devices ------------------------------------------------------
    wire brd_claim, brd_ready, brd_unmodeled;
    wire dma_claim, dma_bad, dma_lcd_valid, dma_frame_full;
    wire [31:0] dma_reg_data, dma_lcd_data;
    wire [14:0] dma_lcd_addr;
    wire [31:0] brd_dout;
    wire        lcd_unsupported_valid;
    wire [31:0] lcd_unsupported_data;
    wire        board_trace_valid;
    wire [31:0] board_trace_addr, board_trace_data;
    wire [3:0] board_trace_sel;

    ngage_board #(
        .INTERNAL_CPU      (1),
        .SIMIF_ENABLE      (1),
        .KEYPAD_ENABLE     (1),
        .LCD_ENABLE        (1),
        .LCD_DMA_ENABLE    (1),
        .UEM_POWERUP_STATUS(UEM_POWERUP_STATUS)
    ) board (
        .diagnostic_video     (diagnostic_video),
        .diagnostic_status    (diagnostic_status),
        .save_state           (save_state),
        .dma_mem_req          (dma_sdram_req),
        .dma_mem_addr         (dma_sdram_addr),
        .dma_mem_ack          (dma_sdram_ack),
        .dma_mem_data         (dma_sdram_data),
        .lcd_dma_claim        (dma_claim),
        .lcd_dma_bad          (dma_bad),
        .lcd_dma_reg_data     (dma_reg_data),
        .lcd_dma_valid        (dma_lcd_valid),
        .lcd_dma_full         (dma_frame_full),
        .lcd_dma_addr         (dma_lcd_addr),
        .lcd_dma_data         (dma_lcd_data),
        .lcd_unsupported      (lcd_unsupported),
        .lcd_unsupported_valid(lcd_unsupported_valid),
        .lcd_unsupported_data (lcd_unsupported_data),
        .video_ce             (ce_pix),
        .video_hsync          (hsync),
        .video_vsync          (vsync),
        .video_hblank         (hblank),
        .video_vblank         (vblank),
        .video_rgb            (rgb444),
        .keys                 (keys),
        .sim_present          (sim_present),
        .rst                  (core_reset),
        .init_rst             (cold_reset),
        .clk                  (clk_sys),
        .cyc                  (1'b0),
        .stb                  (1'b0),
        .adr                  (32'b0),
        .we                   (1'b0),
        .din                  (32'b0),
        .sel                  (4'b0),
        .commit               (1'b0),
        .cpu_ack              (wb_ack),
        .cpu_err              (wb_err),
        .cpu_rdata            (wb_dat_i),
        .cpu_lock             (bus_lock),
        .bus_cyc              (wb_cyc),
        .bus_stb              (wb_stb),
        .bus_code             (wb_code),
        .bus_adr              (wb_adr),
        .bus_we               (wb_we),
        .bus_din              (wb_dat_o),
        .bus_sel              (wb_sel),
        .cfg_lcd              (1'b1),
        .cfg_keypad           (1'b1),
        .cfg_clocks           (1'b1),
        .dma_irq_pending      (1'b0),
        .sim_fiq_pending      (1'b0),
        .dma_irq_clear        (),
        .claim                (brd_claim),
        .ready                (brd_ready),
        .dout                 (brd_dout),
        .unmodeled            (brd_unmodeled),
        .irq                  (irq_line),
        .fiq                  (fiq_line),
        .init_done            (board_init_done),
        .trace_valid          (board_trace_valid),
        .trace_addr           (board_trace_addr),
        .trace_data           (board_trace_data),
        .trace_sel            (board_trace_sel)
    );

    // --- physical address decode --------------------------------------------
    wire [31:0] pa = {wb_adr[31:2], 2'b00};

    // Decode the same nonoverlapping banks as the software reference.
    wire ram_hit, rom_hit, cdrive_hit, pmm_hit;
    wire [24:0] rom_offset;
    ngage_rom_map phone_map (
        pa,
        rom_hit,
        rom_offset,
        ram_hit,
        cdrive_hit,
        pmm_hit
    );
    wire flash_hit = rom_hit || cdrive_hit || pmm_hit;
    // Flash request ownership is retained until the command or DDR operation
    // completes. The C: range has priority over the overlapping CS1 window.
    wire mem_req = wb_cyc && wb_stb && !(brd_claim || dma_claim);
    reg  flash_issued = 0;
    wire code_ready,code_rsp,code_err,cm_valid,cm_write,cm_ready,cm_done,code_dirty,code_pending;
    wire [31:0] code_data, cm_addr, cm_data;
    wire [ 3:0] cm_be;
    wire [13:0] code_dirty_sector;
    wire user_ready,user_rsp,user_err,um_valid,um_write,um_ready,um_done,user_dirty,user_pending;
    wire [31:0] user_data, um_addr, um_data;
    wire [ 3:0] um_be;
    wire [12:0] user_dirty_sector;
    wire        flash_start = mem_req && flash_hit && !flash_issued && !core_reset;
    wire        flash_response = code_rsp || user_rsp;
    always @(posedge clk_sys) begin
        if (core_reset) flash_issued <= 0;
        else begin
            if (flash_start && (cdrive_hit ? user_ready : code_ready)) flash_issued <= 1;
            if (flash_response) flash_issued <= 0;
        end
    end
    ngage_codeflash code_flash (
        .clk         (clk_sys),
        .reset       (core_reset),
        .cold_reset  (cold_reset),
        .req_valid   (flash_start && !cdrive_hit),
        .req_ready   (code_ready),
        .req_write   (wb_we),
        .req_address (pa),
        .req_data    (wb_dat_o),
        .req_be      (wb_sel),
        .rsp_valid   (code_rsp),
        .rsp_error   (code_err),
        .rsp_data    (code_data),
        .mem_valid   (cm_valid),
        .mem_ready   (cm_ready),
        .mem_write   (cm_write),
        .mem_addr    (cm_addr),
        .mem_data    (cm_data),
        .mem_be      (cm_be),
        .mem_done    (cm_done),
        .mem_rdata   (ddram_dout),
        .dirty_valid (code_dirty),
        .dirty_sector(code_dirty_sector),
        .pending     (code_pending),
        .idle        (code_idle)
    );
    ngage_cflash user_flash (
        .clk         (clk_sys),
        .reset       (core_reset),
        .cold_reset  (cold_reset),
        .req_valid   (flash_start && cdrive_hit),
        .req_ready   (user_ready),
        .req_write   (wb_we),
        .req_offset  (pa[21:0]),
        .req_data    (wb_dat_o),
        .req_be      (wb_sel),
        .rsp_valid   (user_rsp),
        .rsp_error   (user_err),
        .rsp_data    (user_data),
        .mem_valid   (um_valid),
        .mem_ready   (um_ready),
        .mem_write   (um_write),
        .mem_addr    (um_addr),
        .mem_wdata   (um_data),
        .mem_be      (um_be),
        .mem_done    (um_done),
        .mem_rdata   (ddram_dout),
        .dirty_valid (user_dirty),
        .dirty_sector(user_dirty_sector),
        .pending     (user_pending),
        .idle        (user_idle)
    );
    reg mem_owner_user = 0;
    always @(posedge clk_sys)
        if (ddram_accept && (cm_valid || um_valid))
            mem_owner_user <= um_valid;
    assign cm_ready           = ddram_accept && cm_valid;
    assign um_ready           = ddram_accept && um_valid;
    assign cm_done            = ddram_dout_ready && !mem_owner_user;
    assign um_done            = ddram_dout_ready && mem_owner_user;
    assign ddram_addr         = um_valid ? um_addr : cm_addr;
    assign ddram_din          = um_valid ? um_data : cm_data;
    assign ddram_be           = um_valid ? um_be : cm_be;
    assign ddram_wr           = (um_valid && um_write) || (cm_valid && cm_write);
    assign ddram_rd           = (um_valid && !um_write) || (cm_valid && !cm_write);
    assign flash_busy         = flash_issued || code_pending || user_pending;
    assign flash_dirty        = code_dirty || user_dirty;
    assign flash_dirty_sector = user_dirty ? {1'b0, user_dirty_sector} : code_dirty_sector;
    assign sdram_addr         = wb_adr[24:0];
    assign sdram_din          = wb_dat_o;
    assign sdram_be           = wb_sel;
    assign sdram_we           = ram_hit && wb_we && mem_req;
    assign sdram_req          = ram_hit && mem_req;
    wire flash_error = (code_rsp && code_err) || (user_rsp && user_err);
    wire mem_ack = ram_hit ? sdram_ack : flash_hit ? (flash_response && !flash_error) : 1'b0;
    // Register board/decode faults so Wishbone STB suppression on ERR cannot
    // form a combinational loop. No invalid access is acknowledged as success.
    reg  invalid_response = 0;
    always @(posedge clk_sys) begin
        if (core_reset) invalid_response <= 0;
        else
            invalid_response<=!invalid_response && (((dma_claim && dma_bad) || (!dma_claim && brd_claim && brd_ready && brd_unmodeled)) ||
                                              (mem_req && !ram_hit && !flash_hit));
    end
    wire lcd_write_collision = dma_lcd_valid && wb_cyc && wb_stb && wb_we && pa == 32'h0c121208;
    assign wb_ack=(core_reset || lcd_write_collision) ? 1'b0 : dma_claim ? !dma_bad : brd_claim ? (brd_ready && !brd_unmodeled) : mem_ack;
    assign wb_dat_i=dma_claim ? dma_reg_data : brd_claim ? brd_dout : flash_hit ? (user_rsp ? user_data : code_data) : sdram_dout;
    assign wb_err = !core_reset && (invalid_response || flash_error);


    ngage_diagnostics diagnostics (
        .clk(clk_sys),
        .cold_reset(cold_reset),
        .freeze_trace(debug_freeze_trace),
        .fault(!core_reset && ((dma_claim && dma_bad) ||
            (!dma_claim && brd_claim && brd_ready && brd_unmodeled) ||
            (mem_req && !ram_hit && !flash_hit) || flash_error)),
        .fault_address(wb_adr),
        .fault_is_fetch(wb_code),
        .fault_reason(flash_error ? 3'd3 : (mem_req && !ram_hit && !flash_hit) ? 3'd2 : 3'd1),
        .trace_valid(board_trace_valid || lcd_unsupported_valid),
        .trace_lost(board_trace_valid && lcd_unsupported_valid),
        .trace_addr(lcd_unsupported_valid ? 32'h0c121208 : board_trace_addr),
        .trace_data(lcd_unsupported_valid ? lcd_unsupported_data : board_trace_data),
        .trace_sel(lcd_unsupported_valid ? 4'hf : board_trace_sel),
        .read_word(debug_read_word),
        .read_data(debug_read_data),
        .fault_seen(debug_fault_seen)
    );

    wire unused_unmodeled = brd_unmodeled;
endmodule
