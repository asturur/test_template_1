// D100 UPP chip boundary. The MiSTer instantiation includes the ARM and
// peripheral logic; external-bus mode is retained for focused board tests.
// Active bus, CBUS and ADSP ports are transaction-level migration interfaces,
// not the schematic's multiplexed electrical pin timings.
module ngage_upp #(
    parameter INTERNAL_CPU   = 0,
              SIMIF_ENABLE   = 0,
              KEYPAD_ENABLE  = 0,
              LCD_DMA_ENABLE = 0
) (
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
    output wire        bus_commit,
    output wire        bus_code,
    output wire [31:0] bus_adr,
    output wire [31:0] bus_din,
    output wire [ 3:0] bus_sel,
    input  wire        dma_mem_ack,
    input  wire [31:0] dma_mem_data,
    output wire        dma_mem_req,
    output wire [24:0] dma_mem_addr,
    output wire        lcd_dma_claim,
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
    generate
        if (INTERNAL_CPU) begin : cpu_inside
            ngage_cpu cpu (
                .debug_pc         (debug_pc),
                .debug_cpsr       (debug_cpsr),
                .debug_instruction(debug_instruction),
                .debug_fetch      (debug_fetch),
                .clk              (clk),
                .reset            (rst),
                .irq              (irq),
                .fiq              (fiq),
                .wb_lock          (cpu_lock),
                .wb_cyc           (bus_cyc),
                .wb_stb           (bus_stb),
                .wb_code          (bus_code),
                .wb_address       (bus_adr),
                .wb_write         (bus_we),
                .wb_write_data    (bus_din),
                .wb_byte_enable   (bus_sel),
                .wb_cycle_type    (),
                .wb_burst_type    (),
                .wb_ack           (cpu_ack),
                .wb_read_data     (cpu_rdata),
                .wb_error         (cpu_err)
            );
            assign bus_commit = cpu_ack;
        end else begin : external_master
            assign debug_pc          = 0;
            assign debug_cpsr        = 0;
            assign debug_instruction = 0;
            assign debug_fetch       = 0;
            assign cpu_lock          = 1'b0;
            assign bus_code          = 1'b0;
            assign bus_cyc           = ext_cyc;
            assign bus_stb           = ext_stb;
            assign bus_we            = ext_we;
            assign bus_adr           = ext_adr;
            assign bus_din           = ext_din;
            assign bus_sel           = ext_sel;
            assign bus_commit        = ext_commit;
        end
    endgenerate
    wire internal_dma_irq;
    generate
        if (LCD_DMA_ENABLE) begin : lcd_dma_enabled
            ngage_lcd_dma lcd_dma (
                .clk           (clk),
                .reset         (rst),
                .req           (bus_cyc && bus_stb),
                .commit        (bus_commit),
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
                .irq_pending   (internal_dma_irq),
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
    endgenerate
    ngage_upp_peripherals #(
        .SIMIF_ENABLE (SIMIF_ENABLE),
        .KEYPAD_ENABLE(KEYPAD_ENABLE)
    ) peripherals (
        .keys             (keys),
        .sim_present      (sim_present),
        .card_rx_valid    (card_rx_valid),
        .card_tx_will_emit(card_tx_will_emit),
        .card_overflow    (card_overflow),
        .card_rx_data     (card_rx_data),
        .card_available   (card_available),
        .card_tx_valid    (card_tx_valid),
        .card_rx_pop      (card_rx_pop),
        .card_tx_data     (card_tx_data),
        .rst              (rst),
        .init_rst         (init_rst),
        .clk              (clk),
        .cyc              (bus_cyc),
        .stb              (bus_stb),
        .adr              (bus_adr),
        .we               (bus_we),
        .din              (bus_din),
        .sel              (bus_sel),
        .commit           (bus_commit),
        .cfg_lcd          (cfg_lcd),
        .cfg_keypad       (cfg_keypad),
        .cfg_clocks       (cfg_clocks),
        .dma_irq_pending  (dma_irq_pending || internal_dma_irq),
        .sim_fiq_pending  (sim_fiq_pending),
        .dma_irq_clear    (dma_irq_clear),
        .claim            (claim),
        .ready            (ready),
        .dout             (dout),
        .unmodeled        (unmodeled),
        .irq              (irq),
        .fiq              (fiq),
        .init_done        (init_done),
        .trace_valid      (trace_valid),
        .trace_addr       (trace_addr),
        .trace_data       (trace_data),
        .trace_sel        (trace_sel),
        .cbus_claim       (cbus_claim),
        .cbus_bad         (cbus_bad),
        .cbus_irq         (cbus_irq),
        .cbus_data        (cbus_data),
        .route2a          (route2a),
        .route2c          (route2c),
        .route3b          (route3b),
        .cbus8d_written   (cbus8d_written),
        .uem_periodic     (uem_periodic),
        .uem_irq_clear    (uem_irq_clear),
        .mdi_claim        (mdi_claim),
        .mdi_bad          (mdi_bad),
        .mdi_data         (mdi_data),
        .mdi_events       (mdi_events),
        .adsp_tick        (adsp_tick)
    );
endmodule
