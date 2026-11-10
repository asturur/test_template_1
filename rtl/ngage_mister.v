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
    parameter UEM_POWERUP_STATUS = 2,
              DIRECT_SDRAM       = 1,
              SYS_CLK_HZ         = 104000000,
              TIMER_CLK_DIV      = 1,
              NOS_TICK_HZ        = 1000
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
    input  wire [31:0] diagnostic_status,
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
    input  wire        sdram_accept,

    // DDR3 port (ROM + C: drive — mostly read, HPS-loaded)
    output wire [31:0] ddram_addr,
    output wire        ddram_rd,
    output wire        ddram_fetch,
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
    wire fast_ram_req, fast_ram_we, fast_ram_code, fast_ram_pending, fast_ram_response;
    wire [31:0] fast_ram_address, fast_ram_data;
    wire [3:0] fast_ram_be;
    wire irq_line, fiq_line;

    // Keep the CPU in reset until any accepted flash transaction has drained.
    // Command state is cleared while draining; pending command setup alone must
    // not prevent release. Cold reset cancels controller state with the transport.
    wire code_idle, user_idle;
    // Assert cancellation immediately, but release only on a clock edge after
    // both flash engines have drained. The registered output, rather than a
    // live OR of loader/readiness flags, drives the phone reset tree. Quartus
    // may replicate this register near consumers instead of routing one
    // combinational reset enable across every chip/cache metadata bank.
    wire reset_request = reset || cold_reset;
    (* maxfan = 128, preserve *)reg  reset_drain = 1'b1;
    always @(posedge clk_sys or posedge reset_request) begin
        if (reset_request) reset_drain <= 1'b1;
        else if (reset_drain && code_idle && user_idle) reset_drain <= 1'b0;
    end
    wire core_reset = reset_drain;

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

    wire [31:0] cpu_pc, cpu_cpsr, cpu_instruction;
    wire cpu_fetch;
    wire raw_ce, raw_hsync, raw_vsync, raw_hblank, raw_vblank;
    wire [11:0] raw_rgb;
    wire [8:0] video_x, video_y;
    ngage_board #(
        .SYS_CLK_HZ        (SYS_CLK_HZ),
        .TIMER_CLK_DIV     (TIMER_CLK_DIV),
        .NOS_TICK_HZ       (NOS_TICK_HZ),
        .INTERNAL_CPU      (1),
        .DIRECT_SDRAM      (DIRECT_SDRAM),
        .SIMIF_ENABLE      (1),
        .KEYPAD_ENABLE     (1),
        .LCD_ENABLE        (1),
        .LCD_DMA_ENABLE    (1),
        .UEM_POWERUP_STATUS(UEM_POWERUP_STATUS)
    ) board (
        .debug_pc             (cpu_pc),
        .debug_cpsr           (cpu_cpsr),
        .debug_instruction    (cpu_instruction),
        .debug_fetch          (cpu_fetch),
        .video_x              (video_x),
        .video_y              (video_y),
        .diagnostic_video     (diagnostic_video),
        .diagnostic_status    (diagnostic_status[7:0]),
        .save_state           (save_state),
        .ram_accept           (DIRECT_SDRAM && sdram_accept),
        .ram_ack              (sdram_ack),
        .ram_rdata            (sdram_dout),
        .ram_req              (fast_ram_req),
        .ram_we               (fast_ram_we),
        .ram_code             (fast_ram_code),
        .ram_address          (fast_ram_address),
        .ram_wdata            (fast_ram_data),
        .ram_be               (fast_ram_be),
        .ram_pending          (fast_ram_pending),
        .ram_response         (fast_ram_response),
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
        .video_ce             (raw_ce),
        .video_hsync          (raw_hsync),
        .video_vsync          (raw_vsync),
        .video_hblank         (raw_hblank),
        .video_vblank         (raw_vblank),
        .video_rgb            (raw_rgb),
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
    wire       flash_hit = rom_hit || cdrive_hit || pmm_hit;
    // NOR/SDRAM regions are disjoint from all UPP/DMA register windows.
    // Capture their owner once per held bridge request. Their launch/return
    // paths must not traverse the aggregate peripheral claim/priority tree.
    // The bridge holds address, data and lanes until termination and inserts
    // a request-low gap; retain this owner through the entire response.
    reg        memory_owner_valid = 0;
    reg  [3:0] memory_owner = 0;  // {PMM, C:, code NOR, SDRAM}
    always @(posedge clk_sys) begin
        if (core_reset || !wb_cyc || !wb_stb) begin
            memory_owner_valid <= 0;
            memory_owner       <= 0;
        end else if (!memory_owner_valid) begin
            memory_owner_valid <= 1;
            memory_owner       <= {pmm_hit, cdrive_hit, rom_hit, (ram_hit && !DIRECT_SDRAM)};
        end
    end
    wire memory_owned = memory_owner_valid && (|memory_owner);
    wire memory_req = wb_cyc && wb_stb && memory_owned;
    wire unclaimed_req = wb_cyc && wb_stb && memory_owner_valid &&
                         !(|memory_owner) && !brd_claim && !dma_claim;
    // Keep the observation bit's original meaning: an access not routed to a
    // board register, including unmapped accesses reported as decode faults.
    wire mem_req = memory_req || unclaimed_req;
    reg flash_issued = 0;
    wire code_ready,code_rsp,code_err,cm_valid,cm_write,cm_ready,cm_done,code_dirty,code_pending;
    wire [31:0] code_data, cm_addr, cm_data;
    wire [ 3:0] cm_be;
    wire [13:0] code_dirty_sector;
    wire user_ready,user_rsp,user_err,um_valid,um_write,um_ready,um_done,user_dirty,user_pending;
    wire [31:0] user_data, um_addr, um_data;
    wire [ 3:0] um_be;
    wire [12:0] user_dirty_sector;
    wire        flash_start = memory_req && (|memory_owner[3:1]) && !flash_issued && !core_reset;
    wire        flash_response = code_rsp || user_rsp;
    always @(posedge clk_sys) begin
        if (core_reset) flash_issued <= 0;
        else begin
            if (flash_start && (memory_owner[2] ? user_ready : code_ready)) flash_issued <= 1;
            if (flash_response) flash_issued <= 0;
        end
    end
    // Preserve instruction/data ownership while the flash controller issues
    // its later backing request. File/literal reads never allocate ROM lines.
    reg flash_fetch = 0;
    always @(posedge clk_sys) begin
        if (core_reset) flash_fetch <= 0;
        else if (flash_start && !memory_owner[2] && code_ready) flash_fetch <= wb_code && !wb_we;
    end
    assign ddram_fetch = cm_valid && !cm_write && !um_valid && flash_fetch;
    ngage_codeflash code_flash (
        .clk         (clk_sys),
        .reset       (core_reset),
        .cold_reset  (cold_reset),
        .req_valid   (flash_start && !memory_owner[2]),
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
        .req_valid   (flash_start && memory_owner[2]),
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
    assign sdram_addr         = DIRECT_SDRAM ? fast_ram_address[24:0] : wb_adr[24:0];
    assign sdram_din          = DIRECT_SDRAM ? fast_ram_data : wb_dat_o;
    assign sdram_be           = DIRECT_SDRAM ? fast_ram_be : wb_sel;
    assign sdram_we           = DIRECT_SDRAM ? fast_ram_we : memory_owner[0] && wb_we && memory_req;
    assign sdram_req          = DIRECT_SDRAM ? fast_ram_req : memory_owner[0] && memory_req;
    wire flash_error = (code_rsp && code_err) || (user_rsp && user_err);
    wire mem_ack = memory_owner[0] ? sdram_ack : (flash_response && !flash_error);
    // Register board/decode faults so Wishbone STB suppression on ERR cannot
    // form a combinational loop. No invalid access is acknowledged as success.
    wire board_fault = !memory_owned && ((dma_claim && dma_bad) ||
                       (!dma_claim && brd_claim && brd_ready && brd_unmodeled));
    reg invalid_response = 0;
    always @(posedge clk_sys) begin
        if (core_reset) invalid_response <= 0;
        else invalid_response <= !invalid_response && (board_fault || unclaimed_req);
    end
    wire lcd_write_collision = dma_lcd_valid && wb_cyc && wb_stb && wb_we && pa == 32'h0c121208;
    assign wb_ack = core_reset ? 1'b0 : memory_owned ? mem_ack :
                    lcd_write_collision ? 1'b0 : dma_claim ? !dma_bad :
                    brd_claim ? (brd_ready && !brd_unmodeled) : 1'b0;
    assign wb_dat_i = memory_owned ? (memory_owner[0] ? sdram_dout :
                                     memory_owner[2] ? user_data : code_data) :
                     dma_claim ? dma_reg_data : brd_dout;
    assign wb_err = !core_reset && (invalid_response || flash_error);


    wire       diagnostic_fault = !core_reset && (board_fault || unclaimed_req || flash_error);
    wire [2:0] diagnostic_reason = flash_error ? 3'd3 : unclaimed_req ? 3'd2 : 3'd1;
    // Observe admission in a separate pipeline: the RAM grant drives only
    // this one event FF, not a wide diagnostic packet's clock enables.
    reg        ram_sample_valid = 0;
    reg [31:0] ram_sample_address = 0, ram_sample_data = 0;
    reg [3:0] ram_sample_be = 0;
    reg ram_sample_write = 0, ram_sample_code = 0;
    reg [31:0] ram_observed_address = 0, ram_observed_data = 0;
    reg [3:0] ram_observed_be = 0;
    reg ram_observed_write = 0, ram_observed_code = 0;
    always @(posedge clk_sys) begin
        ram_sample_valid   <= !core_reset && fast_ram_req && sdram_accept;
        ram_sample_address <= fast_ram_address;
        ram_sample_data    <= fast_ram_data;
        ram_sample_be      <= fast_ram_be;
        ram_sample_write   <= fast_ram_we;
        ram_sample_code    <= fast_ram_code;
        if (ram_sample_valid) begin
            ram_observed_address <= ram_sample_address;
            ram_observed_data    <= ram_sample_data;
            ram_observed_be      <= ram_sample_be;
            ram_observed_write   <= ram_sample_write;
            ram_observed_code    <= ram_sample_code;
        end
    end
    // Slow faults retain their own payload even while a RAM event is visible.
    wire observe_ram = DIRECT_SDRAM && (fast_ram_req || fast_ram_pending) && !diagnostic_fault;
    wire [31:0] observed_address = observe_ram ?
        (fast_ram_pending ? (ram_sample_valid ? ram_sample_address : ram_observed_address) : fast_ram_address) : wb_adr;
    wire [31:0] observed_data = observe_ram ?
        (fast_ram_pending ? (ram_sample_valid ? ram_sample_data : ram_observed_data) : fast_ram_data) : wb_dat_o;
    wire [3:0] observed_be = observe_ram ?
        (fast_ram_pending ? (ram_sample_valid ? ram_sample_be : ram_observed_be) : fast_ram_be) : wb_sel;
    wire observed_write = observe_ram ?
        (fast_ram_pending ? (ram_sample_valid ? ram_sample_write : ram_observed_write) : fast_ram_we) : wb_we;
    wire observed_code = observe_ram ?
        (fast_ram_pending ? (ram_sample_valid ? ram_sample_code : ram_observed_code) : fast_ram_code) : wb_code;
    wire observed_active = observe_ram || (wb_cyc && wb_stb);
    wire observed_ack = observe_ram ? fast_ram_response : wb_ack;
    wire observed_error = !observe_ram && wb_err;
    wire [31:0] cpu_flags = {
        23'b0,
        flash_busy,
        flash_hit,
        ram_hit || observe_ram,
        mem_req || observe_ram,
        brd_ready,
        brd_claim,
        fiq_line,
        irq_line,
        core_reset
    };
    wire [31:0] bus_flags = {
        21'b0,
        observed_be,
        bus_lock,
        observed_error,
        observed_ack,
        observed_code,
        observed_write,
        observed_active,
        observed_active
    };
    wire [31:0] fault_flags = {
        15'b0,
        1'b1,
        1'b0,
        diagnostic_reason,
        2'b0,
        flash_error,
        mem_req,
        flash_hit,
        ram_hit,
        brd_unmodeled,
        brd_ready,
        dma_claim,
        brd_claim,
        wb_code,
        wb_we
    };
    wire [767:0] diagnostic_values;
    wire [98:0] panic_report;
    ngage_debug_monitor monitor (
        .clk           (clk_sys),
        .cold_reset    (cold_reset),
        .cpu_reset     (core_reset),
        .pc            (cpu_pc),
        .cpsr          (cpu_cpsr),
        .instruction   (cpu_instruction),
        .fetch         (cpu_fetch),
        .bus_active    (observed_active),
        .bus_ack       (observed_ack),
        .bus_error     (observed_error),
        .bus_address   (observed_address),
        .bus_write_data(observed_data),
        .bus_read_data (observe_ram ? sdram_dout : wb_dat_i),
        .bus_write     (observed_write),
        .bus_flags     (bus_flags),
        .fault         (diagnostic_fault && !wb_code),
        .fault_flags   (fault_flags),
        .fault_reason  (diagnostic_reason),
        .boot_flags    (diagnostic_status),
        .cpu_flags     (cpu_flags),
        .keys          (keys),
        .values        (diagnostic_values)
    );
    ngage_debug_video debug_video (
        .panic_report(panic_report),
        .clk         (clk_sys),
        .diagnostic  (diagnostic_video),
        .values      (diagnostic_values),
        .x           (video_x),
        .y           (video_y),
        .ce_in       (raw_ce),
        .hsync_in    (raw_hsync),
        .vsync_in    (raw_vsync),
        .hblank_in   (raw_hblank),
        .vblank_in   (raw_vblank),
        .rgb_in      (raw_rgb),
        .ce_out      (ce_pix),
        .hsync_out   (hsync),
        .vsync_out   (vsync),
        .hblank_out  (hblank),
        .vblank_out  (vblank),
        .rgb_out     (rgb444)
    );
    wire panic_trace = board_trace_valid && (board_trace_addr == 32'h0c0047f0 ||
                       board_trace_addr == 32'h0c0047f4 || board_trace_addr == 32'h0c0047f8);
    wire lcd_trace_selected = lcd_unsupported_valid && !panic_trace;
    ngage_diagnostics diagnostics (
        .panic_report  (panic_report),
        .clk           (clk_sys),
        .cold_reset    (cold_reset),
        .freeze_trace  (debug_freeze_trace),
        .fault         (diagnostic_fault),
        .fault_address (wb_adr),
        .fault_is_fetch(wb_code),
        .fault_reason  (diagnostic_reason),
        .trace_valid   (board_trace_valid || lcd_unsupported_valid),
        .trace_lost    (board_trace_valid && lcd_unsupported_valid),
        .trace_addr    (lcd_trace_selected ? 32'h0c121208 : board_trace_addr),
        .trace_data    (lcd_trace_selected ? lcd_unsupported_data : board_trace_data),
        .trace_sel     (lcd_trace_selected ? 4'hf : board_trace_sel),
        .read_word     (debug_read_word),
        .read_data     (debug_read_data),
        .fault_seen    (debug_fault_seen)
    );

    wire unused_unmodeled = brd_unmodeled;
endmodule
