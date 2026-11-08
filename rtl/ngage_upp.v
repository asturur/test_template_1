// D100 UPP chip boundary. The MiSTer instantiation includes the ARM and
// peripheral logic; external-bus mode is retained for focused board tests.
// Active bus, CBUS and ADSP ports are transaction-level migration interfaces,
// not the schematic's multiplexed electrical pin timings.
module ngage_upp #(
    parameter INTERNAL_CPU     = 0,
              SIMIF_ENABLE     = 0,
              KEYPAD_ENABLE    = 0,
              LCD_DMA_ENABLE   = 0,
              LCD_QUEUE_ENABLE = 0
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
    output wire        bus_access,
    output wire        bus_code,
    output wire [31:0] bus_adr,
    output wire [31:0] bus_din,
    output wire [ 3:0] bus_sel,
    input  wire        dma_mem_ack,
    input  wire [31:0] dma_mem_data,
    output wire        dma_mem_req,
    output wire [24:0] dma_mem_addr,
    output wire        lcd_write_valid,
    input  wire        lcd_sink_ready,
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
    generate
        if (INTERNAL_CPU) begin : cpu_inside
            wire master_cyc, master_stb, master_we, master_code;
            wire master_ack, master_error;
            wire [31:0] master_address, master_data, master_read_data;
            wire [3:0] master_sel;
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
            // A transaction-level UPP boundary, not the physical phone bus.
            // LOCK bypasses the beat pipeline and remains asserted through
            // response/idle bubbles between the two halves of an atomic SWP.
            ngage_upp_bus_bridge bridge (
                .clk             (clk),
                .reset           (rst),
                .master_cyc      (master_cyc),
                .master_stb      (master_stb),
                .master_we       (master_we),
                .master_code     (master_code),
                .master_address  (master_address),
                .master_data     (master_data),
                .master_sel      (master_sel),
                .master_ack      (master_ack),
                .master_error    (master_error),
                .master_read_data(master_read_data),
                .bus_cyc         (bus_cyc),
                .bus_stb         (bus_stb),
                .bus_we          (bus_we),
                .bus_code        (bus_code),
                .bus_address     (bus_adr),
                .bus_data        (bus_din),
                .bus_sel         (bus_sel),
                .bus_ack         (cpu_ack),
                .bus_error       (cpu_err),
                .bus_read_data   (cpu_rdata)
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
    wire internal_dma_irq;
    generate
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
    endgenerate
    ngage_upp_peripherals #(
        .REGISTER_RESPONSES(INTERNAL_CPU),
        .LCD_QUEUE_ENABLE  (LCD_QUEUE_ENABLE),
        .SIMIF_ENABLE      (SIMIF_ENABLE),
        .KEYPAD_ENABLE     (KEYPAD_ENABLE)
    ) peripherals (
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
        .lcd_write_valid     (lcd_write_valid),
        .lcd_sink_ready      (lcd_sink_ready)
    );
endmodule

// One outstanding classic Wishbone beat. Both request fields and the returned
// response cross registers: decode/ACK cannot feed the next CPU address in
// the same cycle. Every external access adds request and response latency;
// cached execution and the model's elapsed-time clocks are not slowed.
module ngage_upp_bus_bridge (
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
    output reg         bus_we,
    output reg         bus_code,
    output reg  [31:0] bus_address,
    output reg  [31:0] bus_data,
    output reg  [ 3:0] bus_sel,
    input  wire        bus_ack,
    input  wire        bus_error,
    input  wire [31:0] bus_read_data
);
    localparam IDLE = 2'd0, ACTIVE = 2'd1, RESPONSE = 2'd2;
    reg [1:0] state;
    reg       response_error;
    // CYC withdrawal cancels an unfinished beat. STB/fields are held from the
    // captured request until termination. Upstream response must not depend
    // on master STB: ZAP may suppress STB combinationally on an error.
    assign bus_cyc      = !reset && state == ACTIVE && master_cyc;
    assign bus_stb      = bus_cyc;
    assign master_ack   = !reset && state == RESPONSE && !response_error;
    assign master_error = !reset && state == RESPONSE && response_error;
    always @(posedge clk) begin
        if (reset) begin
            state            <= IDLE;
            response_error   <= 0;
            master_read_data <= 0;
            bus_we           <= 0;
            bus_code         <= 0;
            bus_address      <= 0;
            bus_data         <= 0;
            bus_sel          <= 0;
        end else begin
            case (state)
                IDLE:
                if (master_cyc && master_stb) begin
                    bus_we      <= master_we;
                    bus_code    <= master_code;
                    bus_address <= master_address;
                    bus_data    <= master_data;
                    bus_sel     <= master_sel;
                    state       <= ACTIVE;
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
endmodule
