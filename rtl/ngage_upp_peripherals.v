/*  UPP-side behavioral peripherals, migrated from the C++ reference
    model (scratch/boot-v15-nosprobe/boot_profile.cpp). Wishbone-slave view:
    external fixtures retain live responses; the internal CPU snapshots each
    local response and its one-hot owner before returning data. Registered state
    uses a request authorization window; each device checks its own ownership,
    readiness and supported operation before applying side effects. Unsupported
    selected accesses raise unmodeled for the CPU response/diagnostics only.

    Device 1 (2026-10-31): the LCD transport at 0x0c121200/204/208 - the
    header/control/data registers the boot logo travels through.

    Device 2: GPIO/keypad/system-control latch banks.  Extended 2026-11-01
    to cover all the NOS-phase GPIO ranges the authentic run uses:
    0x0c150000-0x05ff (original), 0x0c150800-0x08ff (FBUS port),
    0x0c120c00-0x0c1f (ICU-adjacent), 0x0c14f000-0x0c14f0ff,
    0x0c100000-0x0c10ffff, 0x0c148000-0x0c14801f, 0x0c142000/14a/14b/14c,
    plus the upload RAMs 0x0c030000-0x0c03ffff and 0x0c06ff00-0x0c06ffff.
    Quirk bits: euart1 TX-idle 0x0c150514 bit 2, FBUS TX drained
    0x0c150504 |=0x1D0, 0x0c150568 bits 1+2, MBUS strobe 0x0c15021c
    self-clears, GSM strap 0x0c150002 bit 22.

    Device 3 (2026-10-31): ideal-clock block.

    Device 4 (2026-11-01): NOS peripheral block 0x0c004000-0x0c004fff
    and ASIC ROM stub page 0x0c000000-0x0c000fff.

    Device 5 (2026-11-01): 0x0d space peripherals + trace sink.

    Device 6 (2026-11-01): free-running counter 0x0c150112 + window 0x0c150114.

    Selected byte/halfword/word widths are accepted; unsupported combinations fault.

    Regional latch RAMs have a registered read: ready follows the first
    sampled address (held until acknowledgement). Their writes and register
    devices remain immediately ready. Sparse-register transactions use a
    separate staged lookup and ready/commit handshake. The arrays were once
    combinational, forcing ~525K GPIO registers instead of Cyclone V BRAM.
*/

module ngage_upp_peripherals #(
    parameter GENERAL_DMA        = 0,
              MMC_ENABLE         = 0,
              MMC_CLK_DIV        = 4,
              MMC_TIMEOUT_LOG2   = 23,
              SIMIF_ENABLE       = 0,
              KEYPAD_ENABLE      = 0,
              LCD_QUEUE_ENABLE   = 0,
              REGISTER_RESPONSES = 0,
              SYS_CLK_HZ         = 104000000,
              TIMER_CLK_DIV      = 1,
              NOS_TICK_HZ        = 1000
) (
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
    input  wire        commit,                // authorize local access checks this cycle
    // configuration (from the harness command line)
    input  wire        cfg_lcd,               // lcd-probe option
    input  wire        cfg_keypad,            // keypad-gpio option
    input  wire        cfg_clocks,            // ideal-clocks option
    input  wire        dma_irq_pending,
    input  wire [ 7:0] general_dma_irq,
    input  wire        sim_fiq_pending,
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
    output wire        dma_irq_clear,
    // service
    output reg         claim,
    output wire        ready,                 // dout valid / access may be acknowledged
    output reg  [31:0] dout,
    output reg         unmodeled,
    output wire        irq,
    output wire        fiq,
    output reg         init_done,
    output wire        trace_valid,
    output wire [31:0] trace_addr,
    output wire [31:0] trace_data,
    output wire [ 3:0] trace_sel,
    // Temporary transaction-level inter-chip interface. These signals are
    // not the physical serial CBUS or AMA-WD2 pins; see chip-inventory.md.
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
    // Transaction-level AMA serial bytes; electrical/baud timing is unmodeled.
    output wire        adsp_receive_enabled,
    output wire        adsp_tx_valid,
    input  wire        adsp_tx_ready,
    output wire [ 7:0] adsp_tx_data,
    input  wire        adsp_rx_valid,
    output wire        adsp_rx_ready,
    input  wire [ 7:0] adsp_rx_data,
    input  wire        mdi_claim,
    input  wire        mdi_bad,
    input  wire        mdi_ready,
    input  wire [31:0] mdi_data,
    input  wire [15:0] mdi_events,
    output wire        adsp_tick,
    output wire        lcd_transport_ready,
    output wire        lcd_write_valid,
    input  wire        lcd_sink_ready,
    input  wire        lcd_dma_access,
    input  wire        lcd_pixel_mode,
    input  wire        dma_shadow_claim,
    input  wire        lcd_direct_collision,
    output wire        mmc_clk,
    output wire        mmc_cmd_o,
    output wire        mmc_cmd_oe,
    output wire        mmc_dat_o,
    output wire        mmc_dat_oe,
    input  wire        mmc_cmd_i,
    input  wire        mmc_dat_i,
    output wire        mmc_rx_ready,
    output wire        mmc_tx_ready,
    output wire        mmc_prefetch_stop,
    output wire        response_pending
);

    wire extra_ready;
    wire icu_ready, timer_ready;
    wire local_access = commit && init_done && cyc && stb && !response_pending;
    wire uart_claim, uart_bad, uart_ready, uart_fiq;
    wire [31:0] uart_data;
    ngage_upp_euart euart1 (
        .clk            (clk),
        .reset          (rst),
        .req            (cyc && stb && cfg_keypad),
        .commit         (local_access),
        .we             (we),
        .addr           (adr),
        .din            (din),
        .sel            (sel),
        .claim          (uart_claim),
        .bad            (uart_bad),
        .ready          (uart_ready),
        .dout           (uart_data),
        .irq_pending    (uart_fiq),
        .tx_valid       (adsp_tx_valid),
        .tx_ready       (adsp_tx_ready),
        .tx_data        (adsp_tx_data),
        .rx_valid       (adsp_rx_valid),
        .rx_ready       (adsp_rx_ready),
        .rx_data        (adsp_rx_data),
        .receive_enabled(adsp_receive_enabled)
    );

    // Native host owns this register window before the generic storage bank.
    // Storage bits are retained; FIFO side effects occur once on admission.
    wire mmc_claim = MMC_ENABLE && cyc && stb && adr[31:6] == (32'h0c120600 >> 6);
    wire mmc_fifo = adr[5:2] == 4'h9;
    wire mmc_bad = mmc_claim && (sel == 0 || (!mmc_fifo && (sel != 15 || adr[1:0] != 0)));
    wire [31:0] mmc_mask, mmc_data;
    wire       mmc_busy;
    wire [3:0] mmc_irq;
    // Donor internal prefetch optimization: a queued final command remains
    // command-busy through its preceding block and NRC/card busy. This is
    // not a phone pin or a modeled D550/AMA-WD2 signal.
    assign mmc_prefetch_stop = MMC_ENABLE && !mmc_irq[2];
    wire mmc_storage = mmc_mask != 32'hffffffff;
    wire mmc_accept = local_access && mmc_claim && !mmc_bad && !mmc_busy &&
        (!mmc_storage || extra_ready);
    generate
        if (MMC_ENABLE) begin : mmc_enabled
            ngage_mmc_host #(
                .DIV         (MMC_CLK_DIV),
                .TIMEOUT_LOG2(MMC_TIMEOUT_LOG2)
            ) host (
                .clk     (clk),
                .reset   (rst),
                .acc     (mmc_claim),
                .we      (we),
                .wr      (mmc_accept && we),
                .rd      (mmc_accept && !we),
                .off     ({adr[5:2], 2'b00}),
                .be      (sel),
                .wdata   (din),
                .rmask   (mmc_mask),
                .rdata   (mmc_data),
                .busy    (mmc_busy),
                .rx_ready(mmc_rx_ready),
                .tx_ready(mmc_tx_ready),
                .irq     (mmc_irq),
                .mmc_clk (mmc_clk),
                .cmd_o   (mmc_cmd_o),
                .cmd_oe  (mmc_cmd_oe),
                .cmd_i   (mmc_cmd_i),
                .dat_o   (mmc_dat_o),
                .dat_oe  (mmc_dat_oe),
                .dat_i   (mmc_dat_i)
            );
        end else begin : mmc_disabled
            assign mmc_mask     = 0;
            assign mmc_data     = 0;
            assign mmc_busy     = 0;
            assign mmc_irq      = 0;
            assign mmc_rx_ready = 0;
            assign mmc_tx_ready = 0;
            assign mmc_clk      = 0;
            assign mmc_cmd_o    = 1;
            assign mmc_cmd_oe   = 0;
            assign mmc_dat_o    = 1;
            assign mmc_dat_oe   = 0;
        end
    endgenerate
    wire simif_claim, simif_bad, simif_irq;

    wire        sim_access = local_access && (!simif_claim || (!card_busy && !card_overflow));
    wire [31:0] simif_data;
    generate
        if (SIMIF_ENABLE) begin : simif_enabled
            ngage_simif simif (
                .clk              (clk),
                .reset            (rst),
                .present          (sim_present),
                .req              (cyc && stb),
                .commit           (sim_access),
                .we               (we),
                .addr             (adr),
                .din              (din),
                .sel              (sel),
                .claim            (simif_claim),
                .bad              (simif_bad),
                .dout             (simif_data),
                .fiq_pending      (simif_irq),
                .card_tx_valid    (card_tx_valid),
                .card_tx_data     (card_tx_data),
                .card_rx_valid    (card_rx_valid),
                .card_rx_data     (card_rx_data),
                .card_available   (card_available),
                .card_tx_will_emit(card_tx_will_emit),
                .card_rx_pop      (card_rx_pop)
            );
        end else begin : simif_disabled
            assign simif_claim   = 0;
            assign simif_bad     = 0;
            assign simif_data    = 0;
            assign simif_irq     = 0;
            assign card_tx_valid = 0;
            assign card_tx_data  = 0;
            assign card_rx_pop   = 0;
        end
    endgenerate
    wire [31:0] a = {adr[31:2], 2'b00};
    wire [31:0] wmask = {{8{sel[3]}}, {8{sel[2]}}, {8{sel[1]}}, {8{sel[0]}}};

    // Dedicated ownership for the modeled ICU and timer registers. Other
    // sources remain low until their actual device models are connected.
    wire icu_claim, icu_bad, timer_claim, timer_bad, nos_claim, nos_bad,
        nos_pending, periodic_active, boot_claim, boot_bad, trace_claim, trace_bad,
        nos_tick, gpio_loop_claim, gpio_loop_bad, extra_claim, extra_bad;
    wire genio1_level, boot_ready;
    wire [31:0] icu_data, timer_data, nos_data, boot_data, gpio_loop_data, extra_data;
    wire sysc74_seen;

    wire [95:0] irq_clear;
    wire timer0_pending, unit1_pending, unit60_pending, timer0_rearm;
    wire [5:0] timer_pending;
    wire keypad_irq;
    wire [95:0] legacy_irq_sources = {
        64'b0,
        6'b0,
        (nos_pending || keypad_irq),
        17'b0,
        dma_irq_pending,
        1'b0,
        timer_pending[5:2],
        (timer_pending[1] || cbus_irq),
        timer_pending[0]
    };
    wire [95:0] irq_sources = legacy_irq_sources |
        (GENERAL_DMA ? {82'd0, general_dma_irq, 6'd0} : 96'd0) |
    // DataRdy/source22 is a donor hypothesis: deliberately not asserted.
    {71'd0, mmc_irq[3], mmc_irq[2], 1'b0, mmc_irq[0], 21'd0};
    // NEM-4's FiqTimer0..5 and IrqTimer0..5 name tables identify the same
    // six timer levels on independently enabled planes (50322fe8/503236c0).
    wire [95:0] fiq_sources = {
        64'b0, 5'b0, (sim_fiq_pending || simif_irq || uart_fiq), 20'b0, timer_pending
    };
    assign dma_irq_clear = irq_clear[7];
    assign uem_irq_clear = irq_clear[1];
    assign uem_periodic  = periodic_active;
    assign adsp_tick     = nos_tick;
    wire dma_selector = GENERAL_DMA && (a == 32'h0c120064 || a == 32'h0c120068);
    // UPP owns one MMIO access at a time, so the passive timer and ICU
    // words share one64x32 M10K without arbitration; reads sample for one clock.
    wire [31:0] icu_live_data, timer_live_data;
    wire passive_icu = icu_claim && !icu_bad && a >= 32'h0c120100 &&
        a < 32'h0c1201c0 && a[5:3] == 0;
    wire timer_high = a[4:2] == 1 || a[4:2] == 2;
    wire timer_status = a[4:2] == 2;
    wire [3:0] timer_high_index = {a[7:5], timer_status};
    wire [5:0] timer_status_clear;
    wire passive_timer = timer_claim && !timer_bad &&
        (timer_high || a[4:2] == 0 || a[4:2] == 3 || a[4:2] == 5 || a[4:2] == 7);
    wire [1:0] timer_word = a[4:2] == 0 ? 2'd0 : a[4:2] == 3 ? 2'd1 : a[4:2] == 5 ? 2'd2 : 2'd3;
    // Rows0..23: timer spares;24..29: ICU configuration;32..43: timer high bits.
    wire [5:0] passive_address = passive_timer ?
        (timer_high ? {2'b10, a[7:5], timer_status} : {1'b0, a[7:5], timer_word}) :
        {3'b011, a[7:6], a[2]};
    wire passive_selected = passive_icu || passive_timer;
    wire passive_read = passive_selected && !we;
    wire passive_write = passive_selected && we && local_access && !rst;
    wire [31:0] passive_q;
    reg [29:0] passive_valid = 0;
    reg [11:0] timer_high_valid = 0;
    integer timer_valid_index;
    reg passive_pending = 0, passive_word_valid = 0;
    reg [5:0] passive_sample_address;
    ngage_bram #(
        .AW         (6),
        .DW         (32),
        .READ_ONLY_B(1)
    ) passive_words (
        .clk   (clk),
        .addr_a(passive_address),
        .addr_b(passive_address),
        .data_a(din),
        .data_b(32'b0),
        .we_a  (passive_write),
        .we_b  (1'b0),
        .q_a   (),
        .q_b   (passive_q)
    );
    wire passive_ready = !passive_read ||
        (passive_pending && passive_sample_address == passive_address);
    // Live validity masks an already sampled status word on expiry/count rewrite.
    wire high_selected = passive_timer && timer_high;
    wire [31:0] passive_data = passive_word_valid &&
        (!high_selected || timer_high_valid[timer_high_index]) ? passive_q : 32'b0;
    assign icu_data = passive_icu ? passive_data : icu_live_data;
    assign timer_data = !passive_timer ? timer_live_data :
        a[4:2] == 1 ? {passive_data[31:2], timer_live_data[1:0]} :
        a[4:2] == 2 ? {passive_data[31:1], timer_live_data[0]} : passive_data;
    always @(posedge clk) begin
        if (rst) begin
            passive_valid          <= 0;
            timer_high_valid       <= 0;
            passive_pending        <= 0;
            passive_word_valid     <= 0;
            passive_sample_address <= 0;
        end else begin
            if (passive_write) begin
                if (high_selected) timer_high_valid[timer_high_index] <= 1;
                else passive_valid[passive_address[4:0]] <= 1;
            end
            // Expiry overrides a coincident software status write, as in the live timer.
            for (
                timer_valid_index = 0;
                timer_valid_index < 6;
                timer_valid_index = timer_valid_index + 1
            ) begin
                if (timer_status_clear[timer_valid_index])
                    timer_high_valid[2*timer_valid_index+1] <= 0;
            end
            passive_pending <= passive_read;
            passive_word_valid     <= passive_read && (high_selected ? timer_high_valid[timer_high_index] : passive_valid[passive_address[4:0]]);
            passive_sample_address <= passive_address;
        end
    end
    ngage_icu #(
        .PASSIVE_STORAGE(0)
    ) icu (
        .clk         (clk),
        .reset       (rst),
        .req         (cyc && stb && !dma_selector),
        .commit      (local_access && !dma_selector),
        .we          (we),
        .addr        (a),
        .din         (din),
        .sel         (sel),
        .irq_pending (irq_sources),
        .fiq_pending (fiq_sources),
        .claim       (icu_claim),
        .bad         (icu_bad),
        .dout        (icu_live_data),
        .irq         (irq),
        .fiq         (fiq),
        .irq_clear   (irq_clear),
        .timer0_rearm(timer0_rearm),
        .ready       (icu_ready)
    );
    ngage_timers #(
        .CLOCK_DIV      (TIMER_CLK_DIV),
        .PASSIVE_STORAGE(0)
    ) timers (
        .clk            (clk),
        .reset          (rst),
        .req            (cyc && stb),
        .commit         (local_access),
        .we             (we),
        .addr           (a),
        .din            (din),
        .sel            (sel),
        // Masking the shared line must not acknowledge the timer producer.
        .clear_unit1    (1'b0),
        .claim          (timer_claim),
        .bad            (timer_bad),
        .dout           (timer_live_data),
        .timer0_pending (timer0_pending),
        .unit1_pending  (unit1_pending),
        .unit60_pending (unit60_pending),
        .timer0_rearm   (timer0_rearm),
        .periodic_active(periodic_active),
        .sysc74_seen    (sysc74_seen),
        .pending_sources(timer_pending),
        .ready          (timer_ready),
        .status_clear   (timer_status_clear)
    );
    localparam integer FAST_TICK_DIV = (SYS_CLK_HZ + 16384) / 32768;
    ngage_nos_io #(
        .TICK_DIV(SYS_CLK_HZ / NOS_TICK_HZ),
        .FAST_DIV(FAST_TICK_DIV)
    ) nos_timer (
        .clk       (clk),
        .reset     (rst),
        .req       (cyc && stb),
        .commit    (local_access),
        .we        (we),
        .addr      (a),
        .din       (din),
        .sel       (sel),
        .claim     (nos_claim),
        .bad       (nos_bad),
        .dout      (nos_data),
        .irq       (nos_pending),
        .event_bits(mdi_events),
        .nos_tick  (nos_tick)
    );
    ngage_gpio_loopback gpio_loop (
        .clk         (clk),
        .reset       (rst),
        .req         (cyc && stb),
        .commit      (local_access),
        .we          (we),
        .addr        (a),
        .din         (din),
        .sel         (sel),
        .route2a     (route2a),
        .route2c     (route2c),
        .route3b     (route3b),
        .claim       (gpio_loop_claim),
        .bad         (gpio_loop_bad),
        .dout        (gpio_loop_data),
        .genio1_level(genio1_level)
    );
    ngage_boot_regs boot_regs (
        .clk   (clk),
        .reset (rst),
        .req   (cyc && stb),
        .commit(local_access),
        .we    (we),
        .addr  (a),
        .din   (din),
        .sel   (sel),
        .claim (boot_claim),
        .bad   (boot_bad),
        .dout  (boot_data),
        .ready (boot_ready)
    );
    ngage_icu_extra extra_regs (
        .clk(clk),
        .reset(rst),
        .req(cyc && stb),
        .commit         (local_access && !dma_shadow_claim &&
                         (!mmc_claim || (!mmc_fifo && !mmc_bad && !mmc_busy))),
        .we(we),
        .periodic_active(periodic_active),
        .addr(a),
        .din(din),
        .sel(sel),
        .claim(extra_claim),
        .bad(extra_bad),
        .dout(extra_data),
        .cbus8d_written(cbus8d_written),
        .sysc74_seen(sysc74_seen),
        .ready(extra_ready)
    );
    ngage_trace_sink trace_sink (
        .clk        (clk),
        .reset      (rst),
        .req        (cyc && stb),
        .commit     (local_access),
        .we         (we),
        .addr       (a),
        .din        (din),
        .sel        (sel),
        .claim      (trace_claim),
        .bad        (trace_bad),
        .trace_valid(trace_valid),
        .trace_addr (trace_addr),
        .trace_data (trace_data),
        .trace_sel  (trace_sel)
    );

    // ---- device 1: LCD transport ------------------------------------------------
    wire lcd_hit = cfg_lcd && (a == 32'h0c12_1200 || a == 32'h0c12_1204 || a == 32'h0c12_1208);

    reg        lcd_bad;
    reg [31:0] lcd_read_data;
    reg ctl_written, hdr_written;
    reg [31:0] ctl, hdr;
    assign lcd_transport_ready = cfg_lcd && ctl_written && ctl == 1 && hdr_written;

    wire hdr_ok = din == 32'h4f30_0000 || din == 32'h4920_0000 ||
              din == 32'h0920_0000 || din[31:16] == 16'h0924 ||
              din[31:16] == 16'h8924 || din[31:16] == 16'h0214 ||
              din == 32'h0780_0000 || din[31:16] == 16'h0784;

    // ---- device 2: GPIO/keypad/system-control latch family ----------------------
    // All ranges that the C++ keypad_regs_ map covers, including the NOS-phase
    // extensions added on 2026-10-31/11-01.
    wire gpio_hit = cfg_keypad && (
    // original GPIO banks
    (a[31:12] == 20'h0c150 && (
    // 0x0c150000-0x05ff minus 0x420/0x424: the UEM control bus (CBUS)
    // is served by the separate UEM transaction-level model.
    (a[11:0] < 12'h600 && a[11:3] != 9'h084) ||
        (a[11:0] >= 12'h800 && a[11:0] < 12'h900)  // FBUS port 0x800-0x8ff
    )) ||
    // ICU-adjacent
    (a[31:8] == 24'h0c120c && a[7:0] < 8'h20) ||
    // 0x0c14fxxx
    (a[31:8] == 24'h0c14f0) ||
    // clock-unit siblings
    (a[31:12] == 20'h0c148 && a[11:0] < 12'h020) ||
    (a[31:12] == 20'h0c142 && a[11:0] < 12'h020) ||
    (a[31:12] == 20'h0c14a && a[11:0] < 12'h020) ||
    (a[31:12] == 20'h0c14b && a[11:0] < 12'h020) ||
    (a[31:12] == 20'h0c14c && a[11:0] < 12'h020) ||
    // 0x0c10xxxx peripheral block
    (a[31:16] == 16'h0c10) ||
    // upload RAMs
    (a[31:16] == 16'h0c03) || (a[31:8] == 24'h0c06ff) ||
    // clock reg 0x0c120034
    a == 32'h0c12_0034);

    // Separate storage for each large address window: the old low-16-bit
    // index aliased upload RAM, NOS RAM and GPIO at the same offsets.
    wire upload_hit = a[31:16] == 16'h0c03;
    wire nosmem_hit = a[31:16] == 16'h0c10;
    wire gpio15_hit = a[31:12] == 20'h0c150;
    wire aux_hit = gpio_hit && !upload_hit && !nosmem_hit && !gpio15_hit;
    wire [11:0] aux_index = a[31:16]==16'h0c14 ? {2'b00,a[15:12],a[7:2]} :
                         a[31:16]==16'h0c12 ? (a[11:8]==4'hc ? {6'b010000,a[7:2]} : 12'h440) :
                         {6'b100000,a[7:2]};
    wire [31:0] upload_q, nosmem_q, gpio15_q, aux_q;
    wire [31:0] gpr_q=upload_hit?upload_q:nosmem_hit?nosmem_q:gpio15_hit?gpio15_q:aux_q;
    reg [14:0] init_index = 0;
    wire clearing = !init_done;
    always @(posedge clk) begin
        if (init_rst) begin
            init_index <= 0;
            init_done  <= 0;
        end else if (!init_done) begin
            if (init_index == 15'd16383) init_done <= 1;
            else init_index <= init_index + 1'b1;
        end
    end

    // ---- device 3: ideal-clock block -------------------------------------------
    wire clk_hit = cfg_clocks && (a == 32'h0c12_0004 || a == 32'h0c12_0008 ||
                              a == 32'h0c12_0020 || a == 32'h0c14_9000);

    reg [31:0] ctlv, cmdv, pllv;
    reg [3:0] ctlw, cmdw, pllw;

    // ---- device 4: NOS peripheral 0x0c004xxx + ASIC ROM stub -------------------
    wire nos4k_hit = cfg_keypad && ((a[31:12] == 20'h0c004) ||  // comm RAM shared block
    (a[31:12] == 20'h0c000)  // ASIC ROM stub page (reads only)
    );

    wire [31:0] nos4k_q;  // 4KB for 0x0c004xxx

    // ---- device 5: 0x0d space (peripherals + trace sink) -----------------------
    wire d_space_hit = cfg_keypad && (a[31:24] == 8'h0d);

    wire [31:0] d_q;
    wire d_full, d_ready;

    // ---- block-RAM latch arrays ------------------------------------------------
    wire req = cyc && stb;
    wire d_selected = d_space_hit && req && !trace_claim;
    wire valid_lanes = sel == 1 || sel == 2 || sel == 4 || sel == 8 ||
                       sel == 3 || sel == 12 || sel == 15;
    // Regional ownership: only genuine overlaps qualify each RAM's writes.
    // In particular upload0c03 and aux0c06ff do not depend on boot/scratch
    // comparisons. Dedicated response priority and snooped side effects below
    // remain unchanged; see docs/peripheral-ownership.md for the overlap map.
    wire upload_selected = cfg_keypad && upload_hit;
    wire nosmem_selected = cfg_keypad && nosmem_hit && !mdi_claim;
    wire gpio15_selected = gpio_hit && gpio15_hit && !simif_claim && !uart_claim && !gpio_loop_claim && !nos_claim;
    wire aux06_selected = cfg_keypad && a[31:8] == 24'h0c06ff;
    wire aux12_selected = gpio_hit && a[31:16] == 16'h0c12 && !boot_claim;
    wire aux14_selected = gpio_hit && a[31:16] == 16'h0c14 && !mdi_claim;
    wire aux_selected = aux06_selected || aux12_selected || aux14_selected;
    wire gpio_selected = upload_selected || nosmem_selected || gpio15_selected || aux_selected;
    wire ram_write = local_access && we && valid_lanes;
    wire nos4k_ram = nos4k_hit && !boot_claim && a[31:12] == 20'h0c004;
    // NOS4K retains its existing unrestricted byte-mask write semantics.
    wire nos4k_write = local_access && we && nos4k_ram;

    ngage_bram_be #(
        .AW(14)
    ) upload_ram (
        .clk  (clk),
        .raddr(a[15:2]),
        .rdata(upload_q),
        .waddr(clearing ? init_index[13:0] : a[15:2]),
        .we   (clearing ? 4'hf : ((upload_selected && ram_write) ? sel : 4'd0)),
        .wdata(clearing ? 32'b0 : din)
    );
    ngage_bram_be #(
        .AW(14)
    ) nosmem_ram (
        .clk  (clk),
        .raddr(a[15:2]),
        .rdata(nosmem_q),
        .waddr(clearing ? init_index[13:0] : a[15:2]),
        .we   (clearing ? 4'hf : ((nosmem_selected && ram_write) ? sel : 4'd0)),
        .wdata(clearing ? 32'b0 : din)
    );
    ngage_bram_be #(
        .AW(10)
    ) gpio15_ram (
        .clk  (clk),
        .raddr(a[11:2]),
        .rdata(gpio15_q),
        .waddr(clearing ? init_index[9:0] : a[11:2]),
        .we   (clearing ? 4'hf : ((gpio15_selected && ram_write) ? sel : 4'd0)),
        .wdata(clearing ? 32'b0 : din)
    );
    ngage_bram_be #(
        .AW(12)
    ) aux_ram (
        .clk  (clk),
        .raddr(aux_index),
        .rdata(aux_q),
        .waddr(clearing ? init_index[11:0] : aux_index),
        .we   (clearing ? 4'hf : ((aux_selected && ram_write) ? sel : 4'd0)),
        .wdata(clearing ? 32'b0 : din)
    );
    ngage_bram_be #(
        .AW(10)
    ) nos4k_ram_i (
        .clk  (clk),
        .raddr(a[11:2]),
        .rdata(nos4k_q),
        .waddr(clearing ? init_index[9:0] : a[11:2]),
        .we   (clearing ? 4'hf : (nos4k_write ? sel : 4'd0)),
        .wdata(clearing ? 32'b0 : din)
    );
    ngage_sparse_regs #(
        .ENTRIES(64)
    ) d_regs (
        .clk       (clk),
        .cold_reset(init_rst),
        .reset     (rst),
        .req       (d_selected),
        .commit    (local_access),
        .we        (we),
        .addr      (a),
        .din       (din),
        .sel       (sel),
        .dout      (d_q),
        .full      (d_full),
        .ready     (d_ready)
    );

    // A RAM-backed read is ready once the RAM has sampled this request's
    // address on a previous edge; cleared on every ack so the next request
    // (even to the same address, e.g. after a write) re-reads.
    reg rd_vld;
    reg [31:0] rd_adr;
    wire ram_read = !we && ((gpio_hit && !simif_claim && !uart_claim && !nos_claim && !mdi_claim && !gpio_loop_claim && !boot_claim) || nos4k_ram);
    // A committed card event is captured at system speed and serviced on its
    // slower enable. Hold the next SIMIF access until card state is current.
    // Only LCD writes wait for their panel command buffer. Legacy standalone
    // fixtures without a display keep their original immediate contract.
    wire lcd_can_accept = (!LCD_QUEUE_ENABLE || lcd_sink_ready) && !lcd_direct_collision;
    wire local_ready = init_done && (!uart_claim || uart_ready) && (!extra_claim || (mmc_claim && !mmc_storage) || extra_ready) &&
        (!boot_claim || boot_ready) && (!mdi_claim || mdi_ready) &&
        (!icu_claim || icu_bad || icu_ready) && (!timer_claim || timer_bad || timer_ready) && passive_ready &&
        (!mmc_claim || mmc_bad || !mmc_busy) && (!(lcd_hit && we) || lcd_can_accept) && (!d_selected || d_ready) && (!SIMIF_ENABLE || !simif_claim || !card_busy) &&
                   (!ram_read || (rd_vld && rd_adr == a));

    always @(posedge clk) begin
        if (rst || (local_access && ready) || !req) rd_vld <= 1'b0;
        else begin
            rd_vld <= 1'b1;
            rd_adr <= a;
        end
    end

    // ---- device 6: free-running counter ----------------------------------------
    reg [31:0] fcnt;  // approximately 32.768 kHz, rounded host-clock divisor
    reg [11:0] fcnt_div;

    wire gpio_access = local_access && gpio_selected && valid_lanes &&
                       (we || (rd_vld && rd_adr == a));
    // Keypad configuration/status overlays share accepted transactions with
    // GPIO loopback and NOS. Each owner retains its independent state.
    wire keypad_access = gpio_access ||
                         (local_access && valid_lanes && nos_claim && !nos_bad &&
                          we && a == 32'h0c150100) ||
                         (local_access && valid_lanes && gpio_loop_claim &&
                          !gpio_loop_bad && we);
    wire [31:0] keypad_dout;
    reg [31:0] gpio_data, clock_data;
    reg gpio_bad, clock_bad;
    wire [31:0] dout_unkeyed = gpio_loop_claim ? gpio_loop_data : nos_claim ? nos_data : gpio_data;
    generate
        if (KEYPAD_ENABLE) begin : keypad_enabled
            ngage_keypad keypad (
                .clk          (clk),
                .reset        (rst),
                .keys         (keys),
                .req          (cyc && stb),
                .commit       (keypad_access),
                .we           (we),
                .addr         (a),
                .din          (din),
                .sel          (sel),
                .base         (dout_unkeyed),
                .genio1_driven(route2a[3]),
                .genio1_level (genio1_level),
                .value        (keypad_dout),
                .irq          (keypad_irq)
            );
        end else begin : keypad_disabled
            assign keypad_dout = dout_unkeyed;
            assign keypad_irq  = 1'b0;
        end
    endgenerate

    // Local data cones are independent of the global ownership priority.
    // Only GPIO/NOS/loopback share the keypad overlay, which belongs to that
    // address family. No SIM/boot/timer path traverses this overlay or a chain
    // of all device data muxes.
    always @* begin
        clock_data = 0;
        clock_bad  = 0;
        if (a == 32'h0c12_0020) begin
            if (we || ctlw != 4'hf) clock_bad = 1'b1;
            else
                case (ctlv)
                    32'd12: clock_data = 32'h0400_0000;
                    32'h27:
                    if (cmdw == 4'hf && cmdv == 32'd1) clock_data = 32'h0800_0000;
                    else clock_bad = 1'b1;
                    32'd3:
                    if (pllw == 4'hf && pllv == 32'h2210) clock_data = 32'h0800_0000;
                    else clock_bad = 1'b1;
                    32'h20, 32'h40: clock_data = 32'h0600_0000;
                    default: clock_bad = 1'b1;
                endcase
        end else if (!we) begin
            case (a)
                32'h0c12_0004: begin
                    clock_data = ctlv;
                    if ((ctlw & sel) != sel) clock_bad = 1'b1;
                end
                32'h0c12_0008: begin
                    clock_data = cmdv;
                    if ((cmdw & sel) != sel) clock_bad = 1'b1;
                end
                default: begin
                    clock_data = pllv;
                    if ((pllw & sel) != sel || pllv != 32'h2210) clock_bad = 1'b1;
                    else clock_data = pllv | 32'd1;
                end
            endcase
        end
    end
    always @* begin
        gpio_data = 0;
        gpio_bad  = 0;
        if (!(sel == 1 || sel == 2 || sel == 4 || sel == 8 || sel == 3 || sel == 12 || sel == 15))
            gpio_bad = 1'b1;
        gpio_data = gpr_q & wmask;
        // ---- quirk bits on reads ----
        // FBUS TX drained (0x0c150504 bits 4,6,7,8 = 0x1D0)
        if (a == 32'h0c15_0504 && !we) gpio_data = gpio_data | (32'h1d0 & wmask);
        // FBUS TX empty (0x0c150568 bits 1+2 in upper halfword = 0x60000)
        if (a == 32'h0c15_0568 && !we) gpio_data = gpio_data | (32'h6_0000 & wmask);
        // MBUS strobe self-clear: low halfword reads 0
        if (a == 32'h0c15_021c && !we) gpio_data = gpio_data & 32'hffff_0000;
        // GSM system-type strap (0x0c150000 bit 22)
        if (a == 32'h0c15_0000 && !we) gpio_data = gpio_data | (32'h0040_0000 & wmask);
        // Staged self-test hypothesis: UPP register-version bit.
        if (a == 32'h0c14_b000 && !we) gpio_data = gpio_data | (32'h80 & wmask);
        // clock-unit 0x0c148000 lock bit 0
        if (a == 32'h0c14_8000 && !we) gpio_data = gpio_data | (32'h1 & wmask);
        // free-running counter 0x0c150110 upper halfword = counter
        if (a == 32'h0c15_0110 && !we)
            gpio_data = (gpio_data & 32'h0000_ffff) | {fcnt[15:0], 16'd0};
        // window constant 0x0c150114: reads 0x0080 if never written
        if (a == 32'h0c15_0114 && !we && gpr_q[15:0] == 16'd0)
            gpio_data = (gpio_data & 32'hffff_0000) | 16'h0080;
    end

    // Decode priority once into a one-hot owner. Claims may depend on lanes,
    // direction and device state; an address-only owner cache is not valid.
    reg [15:0] selected_owner;
    wire [15:0] result_owner, result_bad;
    always @* begin
        selected_owner = 0;
        if (mmc_claim) selected_owner[15] = 1;
        else if (simif_claim) selected_owner[0] = 1;
        else if (extra_claim) selected_owner[1] = 1;
        else if (gpio_loop_claim) selected_owner[2] = 1;
        else if (mdi_claim) selected_owner[3] = 1;
        else if (trace_claim) selected_owner[4] = 1;
        else if (boot_claim) selected_owner[5] = 1;
        else if (icu_claim) selected_owner[6] = 1;
        else if (timer_claim) selected_owner[7] = 1;
        else if (nos_claim) selected_owner[8] = 1;
        else if (cbus_claim) selected_owner[9] = 1;
        else if (nos4k_hit && req) selected_owner[10] = 1;
        else if (d_space_hit && req) selected_owner[11] = 1;
        else if (clk_hit && req) selected_owner[12] = 1;
        else if ((uart_claim || gpio_hit) && req) selected_owner[13] = 1;
        else if (lcd_hit && req) selected_owner[14] = 1;
        claim = response_pending ? (|result_owner && req) : |selected_owner;
    end
    wire [511:0] local_data = {
        (mmc_data & mmc_mask) | (extra_data & ~mmc_mask),
        lcd_read_data,
        uart_claim ? uart_data : keypad_dout,
        clock_data,
        d_q & wmask,
        (a[31:12] == 20'h0c000 ? (we ? 32'b0 : 32'h47704770) : nos4k_q & wmask),
        cbus_data,
        keypad_dout,
        timer_data,
        icu_data,
        boot_data,
        32'b0,
        mdi_data,
        keypad_dout,
        extra_data,
        simif_data | (uart_claim ? uart_data : 32'b0)
    };
    wire [15:0] local_bad = {
        mmc_bad,
        lcd_bad,
        uart_claim ? uart_bad : gpio_bad,
        clock_bad,
        d_full,
        (a[31:12] == 20'h0c000 && we),
        cbus_bad,
        nos_bad,
        timer_bad,
        icu_bad,
        boot_bad,
        trace_bad,
        mdi_bad,
        gpio_loop_bad,
        extra_bad,
        (simif_bad || card_overflow || (uart_claim && uart_bad))
    };
    wire [511:0] result_data;
    generate
        if (REGISTER_RESPONSES) begin : registered_response
            reg valid;
            genvar local_lane;
            for (local_lane = 0; local_lane < 16; local_lane = local_lane + 1) begin : local_results
                reg [31:0] data;
                reg owner, error;
                always @(posedge clk) begin
                    if (!rst && req && !valid) begin
                        data  <= local_data[local_lane*32+:32];
                        owner <= selected_owner[local_lane];
                        error <= local_bad[local_lane];
                    end
                end
                assign result_data[local_lane*32+:32] = data;
                assign result_owner[local_lane]       = owner;
                assign result_bad[local_lane]         = error;
            end
            // The UPP request record is already stable across this edge.
            // Each device's data/error and ownership cross the same edge as
            // its authorized effects. Held requests cannot repeat effects.
            always @(posedge clk) begin
                if (rst || !req) valid <= 0;
                else if (!valid) begin
                    // Payload registers are local, never enabled by aggregate
                    // ready/error. Only the completion bit uses readiness.
                    if (claim && local_ready && commit) valid <= 1;
                end
            end
            assign response_pending = valid;
            assign ready            = valid && req;
        end else begin : immediate_response
            assign response_pending = 0;
            assign ready            = local_ready;
            assign result_owner     = selected_owner;
            assign result_bad       = local_bad;
            assign result_data      = local_data;
        end
    endgenerate
    // Constant slices and a balanced return tree keep each registered local
    // result separate through elaboration and avoid a procedural mux chain.
    wire [31:0] response_tree[0:30];
    genvar response_lane;
    generate
        for (
            response_lane = 0; response_lane < 16; response_lane = response_lane + 1
        ) begin : response_leaves
            assign response_tree[15+response_lane] =
                result_data[response_lane*32+:32] & {32{result_owner[response_lane]}};
        end
        for (
            response_lane = 0; response_lane < 15; response_lane = response_lane + 1
        ) begin : response_nodes
            assign response_tree[response_lane] = response_tree[2*response_lane+1] |
                                                  response_tree[2*response_lane+2];
        end
    endgenerate
    always @* begin
        dout      = response_tree[0];
        unmodeled = |(result_owner & result_bad);
    end

    always @* begin
        lcd_bad       = 0;
        lcd_read_data = 0;
        if (lcd_hit && req) begin
            if (sel != 4'hf) lcd_bad = 1'b1;
            if (GENERAL_DMA && lcd_dma_access && a == 32'h0c121208 && !lcd_pixel_mode) lcd_bad = 1;
            else if (a == 32'h0c12_1204 && we) begin
                if (din != 32'd1 && din != 32'd2) lcd_bad = 1'b1;
            end else if (!ctl_written || ctl != 32'd1) begin
                lcd_bad = 1'b1;
            end else if (a == 32'h0c12_1200 && we) begin
                if (!hdr_ok) lcd_bad = 1'b1;
            end else if (a == 32'h0c12_1204 && !we) begin
                lcd_read_data = 32'd4;
            end else if (a == 32'h0c12_1200 && !we) begin
                if (hdr_written && hdr == 32'h4920_0000) lcd_read_data = 32'h4000_0000;
                else lcd_bad = 1'b1;
            end else if (a == 32'h0c12_1208 && we) begin
                if (!hdr_written) lcd_bad = 1'b1;
            end else if (a == 32'h0c12_1208 && !we) begin
                if (!(hdr_written && hdr[31:16] == 16'h0784)) lcd_bad = 1'b1;
            end
        end
    end
    assign lcd_write_valid = local_access && lcd_hit && we && !lcd_bad && lcd_can_accept;

    // ---- registered state -------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            ctl_written <= 1'b0;
            hdr_written <= 1'b0;
            ctl         <= 32'd0;
            hdr         <= 32'd0;
            ctlv        <= 32'd0;
            cmdv        <= 32'd0;
            pllv        <= 32'd0;
            ctlw        <= 4'd0;
            cmdw        <= 4'd0;
            pllw        <= 4'd0;
            fcnt        <= 32'd0;
            fcnt_div    <= 12'd0;
        end else begin
            // Keep the approximate wall-time tick independent of CPU frequency.
            if (fcnt_div == FAST_TICK_DIV - 1) begin
                fcnt_div <= 12'd0;
                fcnt     <= fcnt + 32'd1;
            end else fcnt_div <= fcnt_div + 12'd1;

            if (clk_hit && local_access && we) begin
                case (a)
                    32'h0c12_0004: begin
                        ctlv <= (ctlv & ~wmask) | (din & wmask);
                        ctlw <= ctlw | sel;
                    end
                    32'h0c12_0008: begin
                        cmdv <= (cmdv & ~wmask) | (din & wmask);
                        cmdw <= cmdw | sel;
                    end
                    default: begin
                        pllv <= (pllv & ~wmask) | (din & wmask);
                        pllw <= pllw | sel;
                    end
                endcase
            end

            if (lcd_write_valid) begin
                if (a == 32'h0c12_1204) begin
                    ctl         <= din;
                    ctl_written <= 1'b1;
                    if (din == 32'd2) hdr_written <= 1'b0;
                end else if (a == 32'h0c12_1200) begin
                    hdr         <= din;
                    hdr_written <= 1'b1;
                end
            end
        end
    end

endmodule
