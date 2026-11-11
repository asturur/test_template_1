// Phone board transaction-level composition. UPP external pin buses are not
// yet bit-accurate; temporary CBUS/ADSP transactions are explicitly named.
module ngage_board #(
    parameter LINE_REFILL        = 0,
              INTERNAL_CPU       = 0,
              DIRECT_SDRAM       = 0,
              SIMIF_ENABLE       = 0,
              KEYPAD_ENABLE      = 0,
              LCD_ENABLE         = 0,
              GENERAL_DMA        = 0,
              MMC_ENABLE         = GENERAL_DMA,
              MMC_CLK_DIV        = 4,
              MMC_TIMEOUT_LOG2   = 23,
              LCD_DMA_ENABLE     = 0,
              UEM_POWERUP_STATUS = 1,
              SYS_CLK_HZ         = 104000000,
              TIMER_CLK_DIV      = 1,
              NOS_TICK_HZ        = 1000
) (

    input  wire        mmc_img_mounted,
    input  wire        mmc_img_readonly,
    input  wire [63:0] mmc_img_size,
    input  tri0        mmc_card_reset,
    output wire [31:0] mmc_sd_lba,
    output wire [ 5:0] mmc_sd_blk_cnt,
    output wire        mmc_sd_rd,
    output wire        mmc_sd_wr,
    input  wire        mmc_sd_ack,
    input  wire [12:0] mmc_sd_buff_addr,
    input  wire [15:0] mmc_sd_buff_dout,
    output wire [15:0] mmc_sd_buff_din,
    input  wire        mmc_sd_buff_wr,
    output wire        mmc_present,
    output wire        mmc_write_protected,
    output wire        mmc_active,
    output wire        line_req,
    output wire [31:0] line_addr,
    input  wire        line_ready,
    input  wire        line_reject,
    input  wire        line_valid,
    input  wire [63:0] line_data,
    input  wire        line_wide,
    input  wire        line_last,
    input  wire        line_error,
    input  wire        rst,
    input  wire        init_rst,
    input  wire        clk,
    // CPU wishbone request (held stable while pending)
    input  wire        cyc,
    input  wire        stb,
    input  wire [31:0] adr,
    input  wire        we,
    input  wire [31:0] din,
    input  wire [ 3:0] sel,
    input  wire        commit,                 // harness acknowledges this cycle
    // configuration (from the harness command line)
    input  wire [26:0] keys,
    input  wire        sim_present,
    input  wire        diagnostic_video,
    input  wire [ 7:0] diagnostic_status,
    input  wire [ 2:0] save_state,
    // Dedicated transaction-level SDRAM interface, not physical pin timing.
    input  wire        ram_accept,
    input  wire        ram_ack,
    input  wire [31:0] ram_rdata,
    output wire        ram_req,
    output wire        ram_we,
    output wire        ram_code,
    output wire [31:0] ram_address,
    output wire [31:0] ram_wdata,
    output wire [ 3:0] ram_be,
    output wire        ram_pending,
    output wire        ram_response,
    input  wire        dma_mem_accept,
    input  wire        dma_mem_ack,
    input  wire [31:0] dma_mem_data,
    output wire        dma_mem_req,
    output wire [24:0] dma_mem_addr,
    output wire [ 7:0] dma_error_pending,
    output wire        dma_cmd_valid,
    input  wire        dma_cmd_ready,
    output wire        dma_cmd_write,
    output wire [31:0] dma_cmd_addr,
    output wire [31:0] dma_cmd_data,
    output wire [ 3:0] dma_cmd_be,
    input  wire        dma_rsp_valid,
    input  wire        dma_rsp_error,
    input  wire [31:0] dma_rsp_data,
    input  wire        dma_local_valid,
    output wire        dma_local_ready,
    input  wire        dma_local_write,
    input  wire [31:0] dma_local_addr,
    input  wire [31:0] dma_local_data,
    input  wire [ 3:0] dma_local_be,
    output wire        dma_local_done,
    output wire        dma_local_error,
    output wire [31:0] dma_local_rdata,
    output wire        lcd_dma_claim,
    output wire        lcd_dma_bad,
    output wire [31:0] lcd_dma_reg_data,
    output wire        lcd_dma_valid,
    output wire        lcd_dma_full,
    output wire [14:0] lcd_dma_addr,
    output wire [31:0] lcd_dma_data,
    output wire        lcd_unsupported,
    output wire        lcd_unsupported_valid,
    output wire [31:0] lcd_unsupported_data,
    output wire        video_ce,
    output wire        video_hsync,
    output wire        video_vsync,
    output wire        video_hblank,
    output wire        video_vblank,
    output wire [11:0] video_rgb,
    input  wire        cfg_lcd,                // lcd-probe option
    input  wire        cfg_keypad,             // keypad-gpio option
    input  wire        cfg_clocks,             // ideal-clocks option
    input  wire        dma_irq_pending,
    input  wire        sim_fiq_pending,
    output wire        dma_irq_clear,
    // service
    output wire        claim,
    output wire        ready,                  // dout valid / access may be acknowledged
    output wire [31:0] dout,
    output wire        unmodeled,
    output wire        irq,
    output wire        fiq,
    output wire        init_done,
    output wire        trace_valid,
    output wire [31:0] trace_addr,
    output wire [31:0] trace_data,
    output wire [ 3:0] trace_sel,
    // Internal-CPU mode is used by the MiSTer top. External mode preserves
    // the transaction interface used by focused board tests.
    input  wire        cpu_ack,
    input  wire        cpu_err,
    input  wire [31:0] cpu_rdata,
    output wire        cpu_lock,
    output wire        bus_cyc,
    output wire        bus_stb,
    output wire        bus_we,
    output wire        bus_code,
    output wire [31:0] bus_adr,
    output wire [31:0] bus_din,
    output wire [ 3:0] bus_sel,
    output wire [ 8:0] video_x,
    output wire [ 8:0] video_y,
    output wire [31:0] debug_pc,
    output wire [31:0] debug_cpsr,
    output wire [31:0] debug_instruction,
    output wire        debug_fetch

);
    // Named transaction shortcut: the physical D550/AMA-WD2 path remains
    // unimplemented. These resolved CLK/CMD/DAT0 levels model no pin timing,
    // open-drain arbitration or electrical behavior.
    wire mmc_clk, host_cmd_o, host_cmd_oe, host_dat_o, host_dat_oe;
    wire mmc_prefetch_stop;
    wire card_cmd_o, card_cmd_oe, card_dat_o, card_dat_oe;
    wire mmc_cmd_line = host_cmd_oe ? host_cmd_o : card_cmd_oe ? card_cmd_o : 1'b1;
    wire mmc_dat_line = host_dat_oe ? host_dat_o : card_dat_oe ? card_dat_o : 1'b1;
    generate
        if (MMC_ENABLE) begin : mmc_shortcut
            ngage_mmc_card card (
                .clk            (clk),
                .reset          (rst || mmc_card_reset),
                .mmc_clk        (mmc_clk),
                .cmd_i          (mmc_cmd_line),
                .cmd_o          (card_cmd_o),
                .cmd_oe         (card_cmd_oe),
                .dat_i          (mmc_dat_line),
                .dat_o          (card_dat_o),
                .dat_oe         (card_dat_oe),
                // Internal prefetch optimization; not a physical D550/AMA pin.
                .stop_queued    (mmc_prefetch_stop),
                .present        (mmc_present),
                .write_protected(mmc_write_protected),
                .active         (mmc_active),
                .img_mounted    (mmc_img_mounted),
                .img_readonly   (mmc_img_readonly),
                .img_size       (mmc_img_size),
                .sd_lba         (mmc_sd_lba),
                .sd_blk_cnt     (mmc_sd_blk_cnt),
                .sd_rd          (mmc_sd_rd),
                .sd_wr          (mmc_sd_wr),
                .sd_ack         (mmc_sd_ack),
                .sd_buff_addr   (mmc_sd_buff_addr),
                .sd_buff_dout   (mmc_sd_buff_dout),
                .sd_buff_din    (mmc_sd_buff_din),
                .sd_buff_wr     (mmc_sd_buff_wr)
            );
        end else begin : no_mmc
            assign card_cmd_o          = 1;
            assign card_cmd_oe         = 0;
            assign card_dat_o          = 1;
            assign card_dat_oe         = 0;
            assign mmc_present         = 0;
            assign mmc_write_protected = 0;
            assign mmc_active          = 0;
            assign mmc_sd_lba          = 0;
            assign mmc_sd_blk_cnt      = 0;
            assign mmc_sd_rd           = 0;
            assign mmc_sd_wr           = 0;
            assign mmc_sd_buff_din     = 0;
        end
    endgenerate
    wire card_rx_valid, card_tx_will_emit, card_overflow, card_tx_valid, card_rx_pop, card_busy;
    wire [7:0] card_rx_data, card_tx_data;
    wire [6:0] card_available;
    generate
        if (SIMIF_ENABLE) begin : test_card
            ngage_test_sim #(
                .CLOCK_DIV(SYS_CLK_HZ / 3250000)
            ) card (
                .clk         (clk),
                .reset       (rst),
                .tx_valid    (card_tx_valid),
                .tx_data     (card_tx_data),
                .rx_pop      (card_rx_pop),
                .rx_valid    (card_rx_valid),
                .rx_data     (card_rx_data),
                .overflow    (card_overflow),
                .available   (card_available),
                .tx_will_emit(card_tx_will_emit),
                .busy        (card_busy)
            );
        end else begin : no_test_card
            assign card_rx_valid     = 0;
            assign card_tx_will_emit = 0;
            assign card_overflow     = 0;
            assign card_rx_data      = 0;
            assign card_available    = 0;
            assign card_busy         = 0;
        end
    endgenerate
    wire cbus_claim, cbus_bad, cbus_irq, uem_periodic, uem_irq_clear, cbus8d_written;
    wire [31:0] cbus_data, mdi_data;
    wire [15:0] route2a, route2c, route3b, mdi_events;
    wire mdi_claim, mdi_bad, adsp_tick;
    wire [31:0] aligned_addr = {bus_adr[31:2], 2'b00};
    wire bus_access, lcd_write_valid, lcd_sink_ready;
    wire lcd_fast_valid, lcd_fast_ready, lcd_fast_error;
    wire [31:0] lcd_fast_data;
    wire lcd_local_reserved, lcd_transport_ready;
    wire lcd_write_dma, lcd_dma_retire, lcd_dma_pixel, lcd_queue_empty, lcd_pixel_mode;
    // Display-controller connection is a transaction-level LCD bus hypothesis.
    generate
        if (LCD_ENABLE) begin : display
            wire queued_valid, queued_dma, queue_ready;
            wire cpu_lcd_write = bus_cyc && bus_stb && bus_we &&
                (aligned_addr == 32'h0c121200 || aligned_addr == 32'h0c121204 || aligned_addr == 32'h0c121208);
            // The optimized read stream joins the same ordered command queue.
            // CPU commands already accepted by UPP precede it; a later command
            // cannot overtake an accepted pixel. Pixel position is the panel's
            // decoded window/cursor, never the source memory address.
            assign lcd_sink_ready = queue_ready;
            assign lcd_fast_ready = queue_ready && lcd_queue_empty && !cpu_lcd_write && !lcd_local_reserved;
            assign lcd_fast_error = !lcd_pixel_mode || !lcd_transport_ready;
            wire fast_enqueue = lcd_fast_valid && lcd_fast_ready && !lcd_fast_error;
            assign lcd_dma_retire = queued_valid && queued_dma;
            wire [31:0] queued_addr, queued_data;
            reg panel_dma_valid = 0, panel_dma_full = 0;
            reg [14:0] panel_dma_addr;
            reg [31:0] panel_dma_data;
            // Both streams cross the same edge. Holding only CPU commands
            // behind raw DMA would let later pixels overtake an accepted write.
            always @(posedge clk) begin
                panel_dma_valid <= !rst && lcd_dma_valid;
                panel_dma_full  <= !rst && lcd_dma_full;
                panel_dma_addr  <= lcd_dma_addr;
                panel_dma_data  <= lcd_dma_data;
            end
            ngage_lcd_bus_queue command_queue (
                .clk      (clk),
                .reset    (rst),
                .hold     (1'b0),
                .in_valid (lcd_write_valid || fast_enqueue),
                .in_dma   (lcd_write_dma || fast_enqueue),
                .out_dma  (queued_dma),
                .empty    (lcd_queue_empty),
                .in_ready (queue_ready),
                .in_addr  (fast_enqueue ? 32'h0c121208 : aligned_addr),
                .in_data  (fast_enqueue ? lcd_fast_data : bus_din),
                .out_valid(queued_valid),
                .out_addr (queued_addr),
                .out_data (queued_data)
            );
            ngage_lcd_display #(
                .PIXEL_DIV(SYS_CLK_HZ / 6500000)
            ) lcd (
                .clk              (clk),
                .reset            (rst),
                .diagnostic       (diagnostic_video),
                .status           (diagnostic_status),
                .save_state       (save_state),
                .write_valid      (queued_valid),
                .pixel_commit     (lcd_dma_pixel),
                .pixel_mode       (lcd_pixel_mode),
                .write_addr       (queued_addr),
                .write_data       (queued_data),
                .dma_valid        (panel_dma_valid),
                .dma_frame_full   (panel_dma_full),
                .dma_word_addr    (panel_dma_addr),
                .dma_data         (panel_dma_data),
                .raster_x         (video_x),
                .raster_y         (video_y),
                .ce_pix           (video_ce),
                .hsync            (video_hsync),
                .vsync            (video_vsync),
                .hblank           (video_hblank),
                .vblank           (video_vblank),
                .rgb              (video_rgb),
                .frame_complete   (),
                .incomplete       (),
                .unsupported      (lcd_unsupported),
                .unsupported_valid(lcd_unsupported_valid),
                .unsupported_data (lcd_unsupported_data)
            );
        end else begin : display_disabled
            assign lcd_fast_ready        = 1;
            assign lcd_fast_error        = 1;
            assign lcd_queue_empty       = 1;
            assign lcd_pixel_mode        = 0;
            assign lcd_dma_retire        = 0;
            assign lcd_dma_pixel         = 0;
            assign lcd_sink_ready        = 1;
            assign lcd_unsupported       = 0;
            assign lcd_unsupported_valid = 0;
            assign lcd_unsupported_data  = 0;
            assign video_x               = 0;
            assign video_y               = 0;
            assign video_ce              = 0;
            assign video_hsync           = 0;
            assign video_vsync           = 0;
            assign video_hblank          = 0;
            assign video_vblank          = 0;
            assign video_rgb             = 0;
        end
    endgenerate
    ngage_upp #(
        .LINE_REFILL     (LINE_REFILL),
        .SYS_CLK_HZ      (SYS_CLK_HZ),
        .TIMER_CLK_DIV   (TIMER_CLK_DIV),
        .NOS_TICK_HZ     (NOS_TICK_HZ),
        .INTERNAL_CPU    (INTERNAL_CPU),
        .DIRECT_SDRAM    (DIRECT_SDRAM),
        .SIMIF_ENABLE    (SIMIF_ENABLE),
        .KEYPAD_ENABLE   (KEYPAD_ENABLE),
        .LCD_DMA_ENABLE  (LCD_DMA_ENABLE),
        .GENERAL_DMA     (GENERAL_DMA),
        .MMC_ENABLE      (MMC_ENABLE),
        .MMC_CLK_DIV     (MMC_CLK_DIV),
        .MMC_TIMEOUT_LOG2(MMC_TIMEOUT_LOG2),
        .LCD_QUEUE_ENABLE(LCD_ENABLE)
    ) upp (
        .mmc_prefetch_stop(mmc_prefetch_stop),
        .mmc_clk          (mmc_clk),
        .mmc_cmd_o        (host_cmd_o),
        .mmc_cmd_oe       (host_cmd_oe),
        .mmc_cmd_i        (mmc_cmd_line),
        .mmc_dat_o        (host_dat_o),
        .mmc_dat_oe       (host_dat_oe),
        .mmc_dat_i        (mmc_dat_line),
        .line_req         (line_req),
        .line_addr        (line_addr),
        .line_ready       (line_ready),
        .line_reject      (line_reject),
        .line_valid       (line_valid),
        .line_data        (line_data),
        .line_wide        (line_wide),
        .line_last        (line_last),
        .line_error       (line_error),

        .debug_pc           (debug_pc),
        .debug_cpsr         (debug_cpsr),
        .debug_instruction  (debug_instruction),
        .debug_fetch        (debug_fetch),
        .ram_accept         (ram_accept),
        .ram_ack            (ram_ack),
        .ram_rdata          (ram_rdata),
        .ram_req            (ram_req),
        .ram_we             (ram_we),
        .ram_code           (ram_code),
        .ram_address        (ram_address),
        .ram_wdata          (ram_wdata),
        .ram_be             (ram_be),
        .ram_pending        (ram_pending),
        .ram_response       (ram_response),
        .dma_mem_accept     (dma_mem_accept),
        .dma_mem_ack        (dma_mem_ack),
        .dma_mem_data       (dma_mem_data),
        .dma_mem_req        (dma_mem_req),
        .dma_mem_addr       (dma_mem_addr),
        .dma_error_pending  (dma_error_pending),
        .dma_cmd_valid      (dma_cmd_valid),
        .dma_cmd_ready      (dma_cmd_ready),
        .dma_cmd_write      (dma_cmd_write),
        .dma_cmd_addr       (dma_cmd_addr),
        .dma_cmd_data       (dma_cmd_data),
        .dma_cmd_be         (dma_cmd_be),
        .dma_rsp_valid      (dma_rsp_valid),
        .dma_rsp_error      (dma_rsp_error),
        .dma_rsp_data       (dma_rsp_data),
        .dma_local_valid    (dma_local_valid),
        .dma_local_ready    (dma_local_ready),
        .dma_local_write    (dma_local_write),
        .dma_local_addr     (dma_local_addr),
        .dma_local_data     (dma_local_data),
        .dma_local_be       (dma_local_be),
        .dma_local_done     (dma_local_done),
        .dma_local_error    (dma_local_error),
        .dma_local_rdata    (dma_local_rdata),
        .lcd_fast_valid     (lcd_fast_valid),
        .lcd_fast_data      (lcd_fast_data),
        .lcd_fast_ready     (lcd_fast_ready),
        .lcd_fast_error     (lcd_fast_error),
        .lcd_transport_ready(lcd_transport_ready),
        .lcd_write_valid    (lcd_write_valid),
        .lcd_write_dma      (lcd_write_dma),
        .lcd_local_reserved (lcd_local_reserved),
        .lcd_queue_empty    (lcd_queue_empty),
        .lcd_pixel_mode     (lcd_pixel_mode),
        .lcd_sink_ready     (lcd_sink_ready),
        .lcd_dma_claim      (lcd_dma_claim),
        .lcd_dma_bad        (lcd_dma_bad),
        .lcd_dma_reg_data   (lcd_dma_reg_data),
        .lcd_dma_valid      (lcd_dma_valid),
        .lcd_dma_full       (lcd_dma_full),
        .lcd_dma_addr       (lcd_dma_addr),
        .lcd_dma_data       (lcd_dma_data),
        .keys               (keys[25:0]),
        .sim_present        (sim_present),
        .card_rx_valid      (card_rx_valid),
        .card_tx_will_emit  (card_tx_will_emit),
        .card_overflow      (card_overflow),
        .card_rx_data       (card_rx_data),
        .card_available     (card_available),
        .card_busy          (card_busy),
        .card_tx_valid      (card_tx_valid),
        .card_rx_pop        (card_rx_pop),
        .card_tx_data       (card_tx_data),
        .rst                (rst),
        .init_rst           (init_rst),
        .clk                (clk),
        .ext_cyc            (cyc),
        .ext_stb            (stb),
        .ext_adr            (adr),
        .ext_we             (we),
        .ext_din            (din),
        .ext_sel            (sel),
        .ext_commit         (commit),
        .cpu_ack            (cpu_ack),
        .cpu_err            (cpu_err),
        .cpu_rdata          (cpu_rdata),
        .cpu_lock           (cpu_lock),
        .bus_cyc            (bus_cyc),
        .bus_stb            (bus_stb),
        .bus_code           (bus_code),
        .bus_adr            (bus_adr),
        .bus_we             (bus_we),
        .bus_din            (bus_din),
        .bus_sel            (bus_sel),
        .bus_access         (bus_access),
        .cfg_lcd            (cfg_lcd),
        .cfg_keypad         (cfg_keypad),
        .cfg_clocks         (cfg_clocks),
        .dma_irq_pending    (dma_irq_pending),
        .sim_fiq_pending    (sim_fiq_pending),
        .dma_irq_clear      (dma_irq_clear),
        .claim              (claim),
        .ready              (ready),
        .dout               (dout),
        .unmodeled          (unmodeled),
        .irq                (irq),
        .fiq                (fiq),
        .init_done          (init_done),
        .trace_valid        (trace_valid),
        .trace_addr         (trace_addr),
        .trace_data         (trace_data),
        .trace_sel          (trace_sel),
        .cbus_claim         (cbus_claim),
        .cbus_bad           (cbus_bad),
        .cbus_irq           (cbus_irq),
        .cbus_data          (cbus_data),
        .route2a            (route2a),
        .route2c            (route2c),
        .route3b            (route3b),
        .cbus8d_written     (cbus8d_written),
        .uem_periodic       (uem_periodic),
        .uem_irq_clear      (uem_irq_clear),
        .mdi_claim          (mdi_claim),
        .mdi_bad            (mdi_bad),
        .mdi_data           (mdi_data),
        .mdi_events         (mdi_events),
        .adsp_tick          (adsp_tick)
    );
    ngage_uem #(
        .SYS_CLK_HZ      (SYS_CLK_HZ),
        .POWER_KEY_ENABLE(KEYPAD_ENABLE),
        .POWERUP_STATUS  (UEM_POWERUP_STATUS)
    ) uem (
        .pwronx         (!keys[26]),
        .clk            (clk),
        .reset          (rst),
        .req            (bus_cyc && bus_stb),
        .commit         (bus_access),
        .we             (bus_we),
        .addr           (aligned_addr),
        .din            (bus_din),
        .sel            (bus_sel),
        .kernel_periodic(uem_periodic),
        .clear_irq      (uem_irq_clear),
        .claim          (cbus_claim),
        .bad            (cbus_bad),
        .dout           (cbus_data),
        .uem_int        (cbus_irq),
        .route2a        (route2a),
        .route2c        (route2c),
        .route3b        (route3b),
        .cbus8d_written (cbus8d_written)
    );
    ngage_adsp adsp (
        .clk            (clk),
        .reset          (rst),
        .tick           (adsp_tick),
        .periodic_active(1'b1),
        .req            (bus_cyc && bus_stb),
        .commit         (bus_access),
        .we             (bus_we),
        .addr           (aligned_addr),
        .din            (bus_din),
        .sel            (bus_sel),
        .claim          (mdi_claim),
        .bad            (mdi_bad),
        .dout           (mdi_data),
        .irq_events     (mdi_events)
    );
    // Physical radio components are explicitly unimplemented and disconnected.
    // A future pin-accurate controller must replace these disabled connections.
    ngage_lrb2 lrb2 (
        .resetx           (1'b0),
        .sleepx           (1'b0),
        .sysclk           (1'b0),
        .slpclk           (1'b0),
        .cbusclk          (1'b0),
        .cenx             (1'b1),
        .cbusdata_i       (1'b0),
        .cbusdata_o       (),
        .cbusdata_oe      (),
        .gpp_i            (4'b0),
        .gpp_o            (),
        .gpp_oe           (),
        .model_implemented()
    );
    ngage_mjoelner gsm_rf (
        .resetx           (1'b0),
        .rfbusclk         (1'b0),
        .rfbusenx         (1'b1),
        .rfbusda_i        (1'b0),
        .rfbusda_o        (),
        .rfbusda_oe       (),
        .model_implemented()
    );
endmodule

// Transaction-level board buffer, not a claim about physical panel pin timing.
// Validation qualifies only capture. Panel decoding/BRAM writes see registered
// address/data/valid. A consumer hold retains a packet without dropping it.
module ngage_lcd_bus_queue (
    input  wire        clk,
    input  wire        reset,
    input  wire        hold,
    input  wire        in_valid,
    input  wire        in_dma,
    output reg         out_dma,
    output wire        empty,
    output wire        in_ready,
    input  wire [31:0] in_addr,
    input  wire [31:0] in_data,
    output wire        out_valid,
    output reg  [31:0] out_addr,
    output reg  [31:0] out_data
);
    reg pending = 0;
    assign empty     = !pending;
    assign in_ready  = !reset && (!pending || !hold);
    assign out_valid = !reset && pending && !hold;
    always @(posedge clk) begin
        if (reset) pending <= 0;
        else if (in_ready) begin
            pending  <= in_valid;
            // Payload sampling is independent of late validation. Only the
            // pending bit records whether these fields form a real command.
            out_dma  <= in_dma;
            out_addr <= in_addr;
            out_data <= in_data;
        end
    end
endmodule
