// D100 UPP chip boundary. The MiSTer instantiation includes the ARM and
// peripheral logic; external-bus mode is retained for focused board tests.
// Active bus, CBUS and ADSP ports are transaction-level migration interfaces,
// not the schematic's multiplexed electrical pin timings.
module ngage_upp #(
    parameter LINE_REFILL      = 0,
              INTERNAL_CPU     = 0,
              DIRECT_SDRAM     = 0,
              SIMIF_ENABLE     = 0,
              KEYPAD_ENABLE    = 0,
              GENERAL_DMA      = 0,
              MMC_ENABLE       = GENERAL_DMA,
              MMC_CLK_DIV      = 4,
              MMC_TIMEOUT_LOG2 = 23,
              LCD_DMA_ENABLE   = 0,
              LCD_QUEUE_ENABLE = 0,
              SYS_CLK_HZ       = 104000000,
              TIMER_CLK_DIV    = 1,
              NOS_TICK_HZ      = 1000
) (

    output wire        mmc_prefetch_stop,
    output wire        mmc_clk,
    output wire        mmc_cmd_o,
    output wire        mmc_cmd_oe,
    output wire        mmc_dat_o,
    output wire        mmc_dat_oe,
    input  wire        mmc_cmd_i,
    input  wire        mmc_dat_i,
    output wire        line_req,
    output wire [31:0] line_addr,
    input  wire        line_ready,
    input  wire        line_reject,
    input  wire        line_valid,
    input  wire [63:0] line_data,
    input  wire        line_wide,
    input  wire        line_last,
    input  wire        line_error,
    input  wire        clk,
    input  wire        rst,
    input  wire        init_rst,
    input  wire        ext_cyc,
    input  wire        ext_stb,
    input  wire        ext_we,
    input  wire        ext_commit,
    input  wire [31:0] ext_adr,
    input  wire [31:0] ext_din,
    input  wire [ 3:0] ext_sel,
    input  wire        cpu_ack,
    input  wire        cpu_err,
    input  wire [31:0] cpu_rdata,
    output wire        cpu_lock,
    output wire        bus_cyc,
    output wire        bus_stb,
    output wire        bus_we,
    output wire        bus_access,
    output wire        bus_code,
    output wire [31:0] bus_adr,
    output wire [31:0] bus_din,
    output wire [ 3:0] bus_sel,
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
    input  wire        dma_local_waiting,
    output wire        dma_local_ready,
    input  wire        dma_local_write,
    input  wire [31:0] dma_local_addr,
    input  wire [31:0] dma_local_data,
    input  wire [ 3:0] dma_local_be,
    output wire        dma_local_done,
    output wire        dma_local_error,
    output wire [31:0] dma_local_rdata,
    output wire        lcd_fast_valid,
    output wire [31:0] lcd_fast_data,
    input  wire        lcd_fast_ready,
    input  wire        lcd_fast_error,
    output wire        lcd_transport_ready,
    output wire        lcd_write_valid,
    output wire        lcd_write_dma,
    output wire        lcd_local_reserved,
    input  wire        lcd_queue_empty,
    input  wire        lcd_pixel_mode,
    input  wire        lcd_sink_ready,
    output wire        lcd_dma_claim,
    output wire        lcd_dma_ready,
    output wire        lcd_dma_bad,
    output wire [31:0] lcd_dma_reg_data,
    output wire        lcd_dma_valid,
    output wire        lcd_dma_full,
    output wire [14:0] lcd_dma_addr,
    output wire [31:0] lcd_dma_data,
    input  wire [25:0] keys,
    input  wire        sim_present,
    input  wire        card_rx_valid,
    input  wire        card_tx_will_emit,
    input  wire        card_overflow,
    input  wire [ 7:0] card_rx_data,
    input  wire [ 6:0] card_available,
    input  wire        card_busy,
    output wire        card_tx_valid,
    output wire        card_rx_pop,
    output wire [ 7:0] card_tx_data,
    input  wire        cfg_lcd,
    input  wire        cfg_keypad,
    input  wire        cfg_clocks,
    input  wire        dma_irq_pending,
    input  wire        sim_fiq_pending,
    output wire        dma_irq_clear,
    output wire        claim,
    output wire        ready,
    output wire        unmodeled,
    output wire        irq,
    output wire        fiq,
    output wire        init_done,
    output wire [31:0] dout,
    output wire        trace_valid,
    output wire [31:0] trace_addr,
    output wire [31:0] trace_data,
    output wire [ 3:0] trace_sel,
    input  wire        cbus_claim,
    input  wire        cbus_bad,
    input  wire        cbus_irq,
    input  wire [31:0] cbus_data,
    input  wire [15:0] route2a,
    input  wire [15:0] route2c,
    input  wire [15:0] route3b,
    input  wire        cbus8d_written,
    output wire        uem_periodic,
    output wire        uem_irq_clear,
    input  wire        mdi_claim,
    input  wire        mdi_bad,
    input  wire [31:0] mdi_data,
    input  wire [15:0] mdi_events,
    output wire        adsp_tick,
    output wire [31:0] debug_pc,
    output wire [31:0] debug_cpsr,
    output wire [31:0] debug_instruction,
    output wire        debug_fetch

);
    wire peripheral_response_pending;
    wire lcd_route_ready, lcd_waiting;
    wire mmc_rx_ready, mmc_tx_ready, mmc_route_ready, mmc_read_waiting, mmc_write_waiting;
    generate
        if (INTERNAL_CPU) begin : cpu_inside
            wire master_cyc, master_stb, master_we, master_code;
            wire master_ack, master_error;
            wire [31:0] master_address, master_data, master_read_data;
            wire [3:0] master_sel;
            ngage_cpu #(
                .LINE_REFILL(LINE_REFILL)
            ) cpu (
                .line_req   (line_req),
                .line_addr  (line_addr),
                .line_ready (line_ready),
                .line_reject(line_reject),
                .line_valid (line_valid),
                .line_data  (line_data),
                .line_wide  (line_wide),
                .line_last  (line_last),
                .line_error (line_error),

                .debug_pc         (debug_pc),
                .debug_cpsr       (debug_cpsr),
                .debug_instruction(debug_instruction),
                .debug_fetch      (debug_fetch),
                .clk              (clk),
                .reset            (rst),
                .irq              (irq),
                .fiq              (fiq),
                .wb_lock          (cpu_lock),
                .wb_cyc           (master_cyc),
                .wb_stb           (master_stb),
                .wb_code          (master_code),
                .wb_address       (master_address),
                .wb_write         (master_we),
                .wb_write_data    (master_data),
                .wb_byte_enable   (master_sel),
                .wb_cycle_type    (),
                .wb_burst_type    (),
                .wb_ack           (master_ack),
                .wb_read_data     (master_read_data),
                .wb_error         (master_error)
            );
            wire slow_master_cyc, slow_master_stb;
            wire slow_ack, slow_error, slow_idle;
            wire [31:0] slow_read_data;
            wire cpu_bus_cyc, cpu_bus_stb, cpu_bus_we, cpu_bus_code;
            wire [31:0] cpu_bus_adr, cpu_bus_din;
            wire [3:0] cpu_bus_sel;
            reg dma_local_active = 0, dma_local_gap = 0, prefer_dma = 0;
            reg dma_write;
            reg lcd_reserved = 0;
            reg mmc_reserved = 0;
            wire mmc_waiting = (mmc_read_waiting && mmc_rx_ready) || (mmc_write_waiting && mmc_tx_ready);
            assign mmc_route_ready = mmc_reserved && !cpu_lock && slow_idle;
            // Grant queue capacity on a registered CPU-idle/response boundary.
            // CPU cancellation decode never feeds its own arbitration grant.
            assign lcd_route_ready = lcd_reserved && !cpu_lock && lcd_queue_empty && slow_idle;
            wire dma_bus_active = dma_local_active;
            assign lcd_local_reserved = lcd_reserved;
            reg [31:0] dma_addr, dma_data;
            reg  [3:0] dma_be;
            wire       dma_lcd = GENERAL_DMA && dma_write && dma_addr == 32'h0c121208;
            assign lcd_write_dma = dma_bus_active && dma_lcd;

            wire lcd_destination = cfg_lcd && dma_local_addr == 32'h0c121208;
            wire mmc_destination = MMC_ENABLE && dma_local_addr == 32'h0c120624;
            wire endpoint_ready = (!lcd_destination || (lcd_sink_ready && !lcd_dma_valid && (!GENERAL_DMA || lcd_queue_empty))) &&
                (!mmc_destination || (mmc_reserved && (dma_local_write ? mmc_tx_ready : mmc_rx_ready)));
            assign dma_local_ready = !rst && init_done && slow_idle && !cpu_lock &&
                !dma_local_active && !dma_local_gap && endpoint_ready && (prefer_dma || !slow_master_stb || lcd_reserved || mmc_reserved);
            wire dma_take = dma_local_valid && dma_local_ready;
            // Captured local packets and registered endpoint reservations own
            // admission. Live cancelable engine valid must not exclude the
            // CPU that decodes the cancellation itself.
            wire block_cpu = (dma_local_waiting && dma_local_ready) || dma_local_active || dma_local_gap || ((lcd_reserved || mmc_reserved) && !cpu_lock);
`ifndef ALTERA_RESERVED_QIS
`ifndef SYNTHESIS
            always @(posedge clk) begin
                if (!rst && dma_take && !block_cpu)
                    $fatal(1, "DMA admission failed to exclude the CPU");
            end
`endif
`endif
            assign dma_local_done  = !rst && dma_local_active && (cpu_ack || cpu_err);
            assign dma_local_error = dma_local_done && cpu_err;
            assign dma_local_rdata = cpu_rdata;

            // Use the same UPP device decode and side-effect path for both
            // owners. The direct CPU SDRAM route remains independent.
            // Hold the selected packet before regional decode. Neither owner
            // selection nor its wide address/lane mux crosses device command
            // decode in the same cycle. Fast SDRAM/LCD streams bypass this bus.
            ngage_upp_request_stage request_stage (
                .clk        (clk),
                .reset      (rst),
                .in_cyc     (dma_bus_active || cpu_bus_cyc),
                .in_stb     (dma_bus_active || cpu_bus_stb),
                .in_we      (dma_bus_active ? dma_write : cpu_bus_we),
                .in_code    (!dma_bus_active && cpu_bus_code),
                .in_address (dma_bus_active ? dma_addr : cpu_bus_adr),
                .in_data    (dma_bus_active ? dma_data : cpu_bus_din),
                .in_sel     (dma_bus_active ? dma_be : cpu_bus_sel),
                .out_cyc    (bus_cyc),
                .out_stb    (bus_stb),
                .out_we     (bus_we),
                .out_code   (bus_code),
                .out_address(bus_adr),
                .out_data   (bus_din),
                .out_sel    (bus_sel)
            );

            always @(posedge clk) begin
                if (rst) begin
                    dma_local_active <= 0;
                    lcd_reserved     <= 0;
                    mmc_reserved     <= 0;
                    dma_local_gap    <= 0;
                    prefer_dma       <= 0;
                end else begin
                    // Device response records clear on a sampled request-low
                    // cycle. Leave that cycle before handing the bus back.
                    dma_local_gap <= dma_local_done;
                    if (MMC_ENABLE && !cpu_lock && mmc_waiting && !lcd_reserved &&
                        ((slow_idle && !slow_master_stb) || (!slow_idle && !cpu_bus_cyc)))
                        mmc_reserved <= 1;
                    if (!mmc_waiting || (dma_local_done && dma_addr == 32'h0c120624))
                        mmc_reserved <= 0;
                    if (GENERAL_DMA && !mmc_reserved && !mmc_waiting && !cpu_lock && lcd_waiting && lcd_queue_empty &&
                        ((slow_idle && !slow_master_stb) || (!slow_idle && !cpu_bus_cyc)))
                        lcd_reserved <= 1;
                    if ((dma_local_done && dma_lcd) || !lcd_waiting) lcd_reserved <= 0;
                    if (dma_local_done) dma_local_active <= 0;
                    if (dma_take) begin
                        dma_local_active <= 1;
                        prefer_dma       <= 0;
                        dma_write        <= dma_local_write;
                        dma_addr         <= dma_local_addr;
                        dma_data         <= dma_local_data;
                        dma_be           <= dma_local_be;
                    end else if (slow_idle && slow_master_stb && !block_cpu) prefer_dma <= 1;
                end
            end

            ngage_cpu_memory_route #(
                .DIRECT_SDRAM(DIRECT_SDRAM)
            ) memory_route (
                .clk           (clk),
                .reset         (rst),
                .master_cyc    (master_cyc),
                .master_stb    (master_stb),
                .master_we     (master_we),
                .master_code   (master_code),
                .master_address(master_address),
                .master_data   (master_data),
                .master_sel    (master_sel),
                .master_ack    (master_ack),
                .master_error  (master_error),
                .master_rdata  (master_read_data),
                .slow_cyc      (slow_master_cyc),
                .slow_stb      (slow_master_stb),
                .slow_idle     (slow_idle),
                .slow_ack      (slow_ack),
                .slow_error    (slow_error),
                .slow_rdata    (slow_read_data),
                .ram_req       (ram_req),
                .ram_we        (ram_we),
                .ram_code      (ram_code),
                .ram_address   (ram_address),
                .ram_wdata     (ram_wdata),
                .ram_be        (ram_be),
                .ram_accept    (ram_accept),
                .ram_ack       (ram_ack),
                .ram_rdata     (ram_rdata),
                .ram_pending   (ram_pending),
                .ram_response  (ram_response)
            );
            // A transaction-level UPP boundary, not the physical phone bus.
            // LOCK bypasses the beat pipeline and remains asserted through
            // response/idle bubbles between the two halves of an atomic SWP.
            // ZAP's I/D merger already registers and holds the complete beat.
            // Reuse that request boundary; retain the registered response.
            ngage_upp_bus_bridge #(
                .REGISTERED_MASTER(1)
            ) bridge (
                .clk             (clk),
                .reset           (rst),
                .master_cyc      (slow_master_cyc && !block_cpu),
                .master_stb      (slow_master_stb && !block_cpu),
                .master_we       (master_we),
                .master_code     (master_code),
                .master_address  (master_address),
                .master_data     (master_data),
                .master_sel      (master_sel),
                .master_ack      (slow_ack),
                .master_error    (slow_error),
                .master_read_data(slow_read_data),
                .bus_cyc         (cpu_bus_cyc),
                .bus_stb         (cpu_bus_stb),
                .bus_we          (cpu_bus_we),
                .bus_code        (cpu_bus_code),
                .bus_address     (cpu_bus_adr),
                .bus_data        (cpu_bus_din),
                .bus_sel         (cpu_bus_sel),
                .bus_ack         (cpu_ack && !dma_local_active),
                .bus_error       (cpu_err && !dma_local_active),
                .bus_read_data   (cpu_rdata),
                .idle            (slow_idle)
            );
            // Side effects are qualified by the selected device's own checks.
            // CPU completion/error remains a response, never a shared write enable.
            assign bus_access = bus_cyc && bus_stb && !rst && init_done && !cpu_err &&
                                (!claim || lcd_dma_claim || !peripheral_response_pending);
        end else begin : external_master
            assign debug_pc = 0;
            assign debug_cpsr = 0;
            assign debug_instruction = 0;
            assign debug_fetch = 0;
            assign cpu_lock = 1'b0;
            assign lcd_route_ready = lcd_queue_empty;
            assign mmc_route_ready = 0;
            assign lcd_local_reserved = 0;
            assign lcd_write_dma = 0;
            assign dma_local_ready = 0;
            assign dma_local_done = 0;
            assign dma_local_error = 0;
            assign dma_local_rdata = 0;
            assign ram_req = 0;
            assign ram_we = 0;
            assign ram_code = 0;
            assign ram_address = 0;
            assign ram_wdata = 0;
            assign ram_be = 0;
            assign ram_pending = 0;
            assign ram_response = 0;
            assign bus_code = 1'b0;
            assign bus_cyc = ext_cyc;
            assign bus_stb = ext_stb;
            assign bus_we = ext_we;
            assign bus_adr = ext_adr;
            assign bus_din = ext_din;
            assign bus_sel = ext_sel;
            assign bus_access        = ext_commit &&
                                       (!claim || lcd_dma_claim || !peripheral_response_pending);
        end
    endgenerate
    wire       internal_dma_irq;
    wire [7:0] general_dma_irq;
    wire [7:0] dma_errors, dma_active;
    assign dma_error_pending = dma_errors;
    generate
        if (GENERAL_DMA) begin : general_dma_enabled
            ngage_dma_channels #(
                // Two workers preserve MMC-wait + copy concurrency. LCD has
                // its own native stream; a third worker measured no benefit.
                .ENGINES   (2),
                .PRODUCTION(1)
            ) channels (
                .clk              (clk),
                .reset            (rst),
                .req              (bus_cyc && bus_stb),
                .commit           (bus_access),
                .we               (bus_we),
                .addr             (bus_adr),
                .din              (bus_din),
                .sel              (bus_sel),
                .claim            (lcd_dma_claim),
                .bad              (lcd_dma_bad),
                .dout             (lcd_dma_reg_data),
                .ready            (lcd_dma_ready),
                .irq_pending      (general_dma_irq),
                .error_pending    (dma_errors),
                .active_channels  (dma_active),
                .lcd_mem_req      (dma_mem_req),
                .lcd_mem_addr     (dma_mem_addr),
                .lcd_mem_accept   (dma_mem_accept),
                .lcd_mem_ack      (dma_mem_ack),
                .lcd_mem_data     (dma_mem_data),
                .lcd_pixel_valid  (lcd_fast_valid),
                .lcd_pixel_data   (lcd_fast_data),
                .lcd_pixel_ready  (lcd_fast_ready),
                .lcd_pixel_error  (lcd_fast_error),
                .lcd_waiting      (lcd_waiting),
                .lcd_ready        (lcd_route_ready),
                .lcd_drained      (lcd_queue_empty),
                .mmc_rx_ready     (mmc_rx_ready),
                .mmc_tx_ready     (mmc_tx_ready),
                .mmc_ready        (mmc_route_ready),
                .mmc_read_waiting (mmc_read_waiting),
                .mmc_write_waiting(mmc_write_waiting),
                .source_ready     (8'hff),
                .destination_ready(8'hff),
                .cmd_valid        (dma_cmd_valid),
                .cmd_ready        (dma_cmd_ready),
                .cmd_write        (dma_cmd_write),
                .cmd_addr         (dma_cmd_addr),
                .cmd_data         (dma_cmd_data),
                .cmd_be           (dma_cmd_be),
                .rsp_valid        (dma_rsp_valid),
                .rsp_error        (dma_rsp_error),
                .rsp_data         (dma_rsp_data)
            );
            assign internal_dma_irq = 0;
            assign lcd_dma_valid    = 0;
            assign lcd_dma_full     = 0;
            assign lcd_dma_addr     = 0;
            assign lcd_dma_data     = 0;
        end else begin : legacy_dma
            assign lcd_dma_ready     = 1'b1;
            assign lcd_fast_valid    = 0;
            assign lcd_fast_data     = 0;
            assign lcd_waiting       = 0;
            assign mmc_read_waiting  = 0;
            assign mmc_write_waiting = 0;
            assign general_dma_irq   = 0;
            assign dma_errors        = 0;
            assign dma_active        = 0;
            assign dma_cmd_valid     = 0;
            assign dma_cmd_write     = 0;
            assign dma_cmd_addr      = 0;
            assign dma_cmd_data      = 0;
            assign dma_cmd_be        = 0;
            if (LCD_DMA_ENABLE) begin : lcd_dma_enabled
                wire raw_dma_irq;
                if (LCD_QUEUE_ENABLE) begin : panel_completion
                    reg delayed_irq = 0;
                    always @(posedge clk) begin
                        if (rst) delayed_irq <= 0;
                        else delayed_irq <= raw_dma_irq;
                    end
                    assign internal_dma_irq = delayed_irq;
                end else begin : immediate_completion
                    assign internal_dma_irq = raw_dma_irq;
                end
                ngage_lcd_dma lcd_dma (
                    .clk           (clk),
                    .reset         (rst),
                    .req           (bus_cyc && bus_stb),
                    .commit        (bus_access),
                    .we            (bus_we),
                    .addr          (bus_adr),
                    .din           (bus_din),
                    .sel           (bus_sel),
                    .claim         (lcd_dma_claim),
                    .bad           (lcd_dma_bad),
                    .dout          (lcd_dma_reg_data),
                    .mem_req       (dma_mem_req),
                    .mem_addr      (dma_mem_addr),
                    .mem_ack       (dma_mem_ack),
                    .mem_data      (dma_mem_data),
                    .lcd_valid     (lcd_dma_valid),
                    .lcd_frame_full(lcd_dma_full),
                    .lcd_word_addr (lcd_dma_addr),
                    .lcd_data      (lcd_dma_data),
                    .irq_pending   (raw_dma_irq),
                    .irq_clear     (dma_irq_clear)
                );
            end else begin : lcd_dma_disabled
                assign internal_dma_irq = 0;
                assign lcd_dma_claim    = 0;
                assign lcd_dma_bad      = 0;
                assign lcd_dma_reg_data = 0;
                assign dma_mem_req      = 0;
                assign dma_mem_addr     = 0;
                assign lcd_dma_valid    = 0;
                assign lcd_dma_full     = 0;
                assign lcd_dma_addr     = 0;
                assign lcd_dma_data     = 0;
            end
        end
    endgenerate
    ngage_upp_peripherals #(
        .GENERAL_DMA       (GENERAL_DMA),
        .MMC_ENABLE        (MMC_ENABLE),
        .MMC_CLK_DIV       (MMC_CLK_DIV),
        .MMC_TIMEOUT_LOG2  (MMC_TIMEOUT_LOG2),
        .SYS_CLK_HZ        (SYS_CLK_HZ),
        .TIMER_CLK_DIV     (TIMER_CLK_DIV),
        .NOS_TICK_HZ       (NOS_TICK_HZ),
        .REGISTER_RESPONSES(INTERNAL_CPU),
        .LCD_QUEUE_ENABLE  (LCD_QUEUE_ENABLE),
        .SIMIF_ENABLE      (SIMIF_ENABLE),
        .KEYPAD_ENABLE     (KEYPAD_ENABLE)
    ) peripherals (
        .mmc_prefetch_stop   (mmc_prefetch_stop),
        .mmc_clk             (mmc_clk),
        .mmc_cmd_o           (mmc_cmd_o),
        .mmc_cmd_oe          (mmc_cmd_oe),
        .mmc_cmd_i           (mmc_cmd_i),
        .mmc_dat_o           (mmc_dat_o),
        .mmc_dat_oe          (mmc_dat_oe),
        .mmc_dat_i           (mmc_dat_i),
        .mmc_rx_ready        (mmc_rx_ready),
        .mmc_tx_ready        (mmc_tx_ready),
        .keys                (keys),
        .sim_present         (sim_present),
        .card_rx_valid       (card_rx_valid),
        .card_tx_will_emit   (card_tx_will_emit),
        .card_overflow       (card_overflow),
        .card_rx_data        (card_rx_data),
        .card_available      (card_available),
        .card_busy           (card_busy),
        .card_tx_valid       (card_tx_valid),
        .card_rx_pop         (card_rx_pop),
        .card_tx_data        (card_tx_data),
        .rst                 (rst),
        .init_rst            (init_rst),
        .clk                 (clk),
        .cyc                 (bus_cyc),
        .stb                 (bus_stb),
        .adr                 (bus_adr),
        .we                  (bus_we),
        .din                 (bus_din),
        .sel                 (bus_sel),
        .commit              (bus_access),
        .dma_shadow_claim    (lcd_dma_claim),
        .lcd_direct_collision(lcd_dma_valid && bus_we && bus_adr == 32'h0c121208),
        .response_pending    (peripheral_response_pending),
        .cfg_lcd             (cfg_lcd),
        .cfg_keypad          (cfg_keypad),
        .cfg_clocks          (cfg_clocks),
        .dma_irq_pending     (dma_irq_pending || internal_dma_irq),
        .general_dma_irq     (general_dma_irq),
        .sim_fiq_pending     (sim_fiq_pending),
        .dma_irq_clear       (dma_irq_clear),
        .claim               (claim),
        .ready               (ready),
        .dout                (dout),
        .unmodeled           (unmodeled),
        .irq                 (irq),
        .fiq                 (fiq),
        .init_done           (init_done),
        .trace_valid         (trace_valid),
        .trace_addr          (trace_addr),
        .trace_data          (trace_data),
        .trace_sel           (trace_sel),
        .cbus_claim          (cbus_claim),
        .cbus_bad            (cbus_bad),
        .cbus_irq            (cbus_irq),
        .cbus_data           (cbus_data),
        .route2a             (route2a),
        .route2c             (route2c),
        .route3b             (route3b),
        .cbus8d_written      (cbus8d_written),
        .uem_periodic        (uem_periodic),
        .uem_irq_clear       (uem_irq_clear),
        .mdi_claim           (mdi_claim),
        .mdi_bad             (mdi_bad),
        .mdi_data            (mdi_data),
        .mdi_events          (mdi_events),
        .adsp_tick           (adsp_tick),
        .lcd_transport_ready (lcd_transport_ready),
        .lcd_write_valid     (lcd_write_valid),
        .lcd_sink_ready      (lcd_sink_ready),
        .lcd_dma_access      (GENERAL_DMA && lcd_write_dma),
        .lcd_pixel_mode      (lcd_pixel_mode)
    );
endmodule

// One outstanding classic Wishbone beat. Both request fields and the returned
// response cross registers: decode/ACK cannot feed the next CPU address in
// the same cycle. Every external access adds request and response latency;
// cached execution and the model's elapsed-time clocks are not slowed.
module ngage_upp_bus_bridge #(
    // Only for an upstream registered, held packet (the ZAP I/D merger).
    // Its fields must remain stable until the registered response is consumed,
    // and retire that offer on the response-consumption edge: withdraw STB
    // or replace it with a distinct next transaction on that edge.
    parameter REGISTERED_MASTER = 0
) (
    input  wire        clk,
    input  wire        reset,
    input  wire        master_cyc,
    input  wire        master_stb,
    input  wire        master_we,
    input  wire        master_code,
    input  wire [31:0] master_address,
    input  wire [31:0] master_data,
    input  wire [ 3:0] master_sel,
    output wire        master_ack,
    output wire        master_error,
    output reg  [31:0] master_read_data,
    output wire        bus_cyc,
    output wire        bus_stb,
    output wire        bus_we,
    output wire        bus_code,
    output wire [31:0] bus_address,
    output wire [31:0] bus_data,
    output wire [ 3:0] bus_sel,
    input  wire        bus_ack,
    input  wire        bus_error,
    input  wire [31:0] bus_read_data,
    output wire        idle
);
    localparam IDLE = 2'd0, ACTIVE = 2'd1, RESPONSE = 2'd2;
    reg [1:0] state;
    reg       response_error;
    reg request_we, request_code;
    reg [31:0] request_address, request_data;
    reg  [3:0] request_sel;
    wire       start = state == IDLE && master_cyc && master_stb;
    assign idle         = state == IDLE;
    // CYC withdrawal cancels an unfinished beat. STB/fields are held from the
    // captured request until termination. Upstream response must not depend
    // on master STB: ZAP may suppress STB combinationally on an error.
    // In registered-master mode these fields already come from flip-flops;
    // no translation/arbitration/decode logic is joined across this boundary.
    assign bus_we       = REGISTERED_MASTER ? master_we : request_we;
    assign bus_code     = REGISTERED_MASTER ? master_code : request_code;
    assign bus_address  = REGISTERED_MASTER ? master_address : request_address;
    assign bus_data     = REGISTERED_MASTER ? master_data : request_data;
    assign bus_sel      = REGISTERED_MASTER ? master_sel : request_sel;
    assign bus_cyc      = !reset && master_cyc && (state == ACTIVE || (REGISTERED_MASTER && start));
    assign bus_stb      = bus_cyc;
    assign master_ack   = !reset && state == RESPONSE && !response_error;
    assign master_error = !reset && state == RESPONSE && response_error;
    always @(posedge clk) begin
        if (reset) begin
            state            <= IDLE;
            response_error   <= 0;
            master_read_data <= 0;
            request_we       <= 0;
            request_code     <= 0;
            request_address  <= 0;
            request_data     <= 0;
            request_sel      <= 0;
        end else begin
            case (state)
                IDLE:
                if (master_cyc && master_stb) begin
                    request_we      <= master_we;
                    request_code    <= master_code;
                    request_address <= master_address;
                    request_data    <= master_data;
                    request_sel     <= master_sel;
                    if (REGISTERED_MASTER && (bus_ack || bus_error)) begin
                        master_read_data <= bus_read_data;
                        response_error   <= bus_error;
                        state            <= RESPONSE;
                    end else state <= ACTIVE;
                end
                ACTIVE: begin
                    if (!master_cyc) state <= IDLE;
                    else if (bus_ack || bus_error) begin
                        master_read_data <= bus_read_data;
                        response_error   <= bus_error;
                        state            <= RESPONSE;
                    end
                end
                // CPU consumes the response on this edge. Capture its next
                // registered request on a later edge, never the completed one.
                RESPONSE: state <= IDLE;
                default:  state <= IDLE;
            endcase
        end
    end
    // The specialized path must never silently borrow a changing packet.
    // These observation-only shadow registers disappear from its synthesis.
    // synthesis translate_off
    always @(posedge clk) begin
        if (!reset && REGISTERED_MASTER && state == ACTIVE && master_cyc &&
            {master_we, master_code, master_address, master_data, master_sel} !==
            {request_we, request_code, request_address, request_data, request_sel})
            $fatal(1, "UPP registered master changed an outstanding packet");
    end
    // synthesis translate_on
endmodule


// Route an already translated, registered ZAP merger packet. SDRAM acceptance
// and the route token cross the SAME edge: no peripheral decode/owner stage.
// Arbitration retains the accepted payload, so cancelled reads/writes drain
// without borrowing the next CPU packet or returning a stale completion.
module ngage_cpu_memory_route #(
    parameter DIRECT_SDRAM = 1
) (
    input  wire        clk,
    input  wire        reset,
    input  wire        master_cyc,
    input  wire        master_stb,
    input  wire        master_we,
    input  wire        master_code,
    input  wire [31:0] master_address,
    input  wire [31:0] master_data,
    input  wire [ 3:0] master_sel,
    output wire        master_ack,
    output wire        master_error,
    output wire [31:0] master_rdata,
    output wire        slow_cyc,
    output wire        slow_stb,
    input  wire        slow_idle,
    input  wire        slow_ack,
    input  wire        slow_error,
    input  wire [31:0] slow_rdata,
    output wire        ram_req,
    output wire        ram_we,
    output wire        ram_code,
    output wire [31:0] ram_address,
    output wire [31:0] ram_wdata,
    output wire [ 3:0] ram_be,
    input  wire        ram_accept,
    input  wire        ram_ack,
    input  wire [31:0] ram_rdata,
    output reg         ram_pending = 0,
    output wire        ram_response
);
    // Exactly the 16MiB physical RAM range in ngage_rom_map.
    wire target_ram = DIRECT_SDRAM && master_address[31:24] == 8'h0a;
    reg  cancelled = 0;
    assign ram_req = !reset && target_ram && master_cyc && master_stb && !ram_pending && slow_idle;
    assign ram_address = master_address;
    assign ram_wdata = master_data;
    assign ram_we = master_we;
    assign ram_code = master_code;
    assign ram_be = master_sel;
    assign slow_cyc = !reset && !ram_pending && !target_ram && master_cyc;
    assign slow_stb = slow_cyc && master_stb;
    assign ram_response = !reset && ram_pending && !cancelled && master_cyc && ram_ack;
    assign master_ack = ram_response || (!reset && !ram_pending && slow_ack);
    assign master_error = !reset && !ram_pending && slow_error;
    // ram_ack/data already come from the registered SDRAM response and owner.
    // Keep the cache's completion register; do not forward controller pins.
    assign master_rdata = ram_pending ? ram_rdata : slow_rdata;
    always @(posedge clk) begin
        if (reset) begin
            ram_pending <= 0;
            cancelled   <= 0;
        end else begin
            if (ram_req && ram_accept) begin
                ram_pending <= 1;
                cancelled   <= 0;
            end
            if (ram_pending && !master_cyc) cancelled <= 1;
            if (ram_pending && ram_ack) begin
                ram_pending <= 0;
                cancelled   <= 0;
            end
        end
    end
    // synthesis translate_off
    always @(posedge clk)
        if (!reset) begin
            if (ram_accept && !ram_req) $fatal(1, "RAM admission without CPU offer");
            if (ram_req && slow_stb) $fatal(1, "CPU packet offered to two targets");
            if (ram_response && (slow_ack || slow_error)) $fatal(1, "overlapping CPU responses");
        end
    // synthesis translate_on
endmodule


// One held request per CYC/STB assertion; the existing CPU response phase and
// DMA gap provide the request-low edge. Cancellation immediately suppresses
// side effects, while an already captured downstream transaction may drain.
module ngage_upp_request_stage (
    input  wire        clk,
    input  wire        reset,
    input  wire        in_cyc,
    input  wire        in_stb,
    input  wire        in_we,
    input  wire        in_code,
    input  wire [31:0] in_address,
    input  wire [31:0] in_data,
    input  wire [ 3:0] in_sel,
    output wire        out_cyc,
    output wire        out_stb,
    output reg         out_we,
    output reg         out_code,
    output reg  [31:0] out_address,
    output reg  [31:0] out_data,
    output reg  [ 3:0] out_sel
);
    reg  valid = 0;
    wire offered = in_cyc && in_stb;
    assign out_cyc = !reset && valid && offered;
    assign out_stb = out_cyc;
    always @(posedge clk) begin
        if (reset) begin
            valid       <= 0;
            out_we      <= 0;
            out_code    <= 0;
            out_address <= 0;
            out_data    <= 0;
            out_sel     <= 0;
        end else if (!offered) valid <= 0;
        else if (!valid) begin
            valid       <= 1;
            out_we      <= in_we;
            out_code    <= in_code;
            out_address <= in_address;
            out_data    <= in_data;
            out_sel     <= in_sel;
        end
    end
endmodule
