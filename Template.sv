//============================================================================
//
//  N-Gage MiSTer core — Template.sv (emu module)
//  78 MHz CPU + SDRAM, DDR3 for ROM/flash, BRAM framebuffer
//
//============================================================================

module emu (
    `include "sys/emu_ports.vh"
);

    ///////// Default values for ports not used in this core /////////

    assign ADC_BUS                        = 'Z;
    assign USER_OUT                       = '1;
    assign {UART_RTS, UART_TXD, UART_DTR} = 0;
    assign {SD_SCK, SD_MOSI, SD_CS}       = 'Z;

    assign VGA_SL         = 0;
    assign VGA_F1         = 0;
    assign VGA_SCALER     = 0;
    assign VGA_DISABLE    = 0;
    assign HDMI_FREEZE    = 0;
    assign HDMI_BLACKOUT  = 0;
    assign HDMI_BOB_DEINT = 0;

    assign AUDIO_S   = 0;
    assign AUDIO_L   = 0;
    assign AUDIO_R   = 0;
    assign AUDIO_MIX = 0;

    assign LED_DISK  = 0;
    assign LED_POWER = 0;
    assign BUTTONS   = 0;

    //////////////////////////////////////////////////////////////////

    wire [1:0] ar = status[122:121];

    assign VIDEO_ARX = (ar == 2'b00) ? (status[17] ? 13'd11 : 13'd4) : ({11'b0, ar} - 13'd1);
    assign VIDEO_ARY = (ar == 2'b00) ? (status[17] ? 13'd13 : 13'd3) : 13'd0;

    `include "build_id.v"
    localparam CONF_STR = {
        "ngage1;;",
        "-;",
        "O[122:121],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
        "-;",
        // "P1,Firmware;",
        // "P1F1,ROM,Load MCU service firmware;",
        // "P1F2,ROM,Load PPM service firmware;",
        // "P1O[19],NOS Compatibility,Off,On;",
        // "D0P1F3,NGO,Load NOS Compatibility;",
        // "P1O[20],Bluetooth Compatibility,Off,On;",
        // "D1P1F4,NGO,Load Bluetooth Compatibility;",
        "S0,VHD,Mount C: raw image;",
        "S1,VHD,Mount PMM raw image;",
        "S2,MMC,Mount MMC card (read only);",
        "S3,NGD,Mount diagnostic disk;",
        "T[14],Flush C:/PMM images;",
        "D2O[21],Background save,Off,On;",
        "O[16],CPU mode,Hold,Run;",
        "O[17],Display,Diagnostic,Phone;",
        "T[18],Export diagnostics;",
        "-;",
        "-;",
        "T[0],Reset;",
        "R[0],Reset and close OSD;",
        "J1,OK,Clear,End,Menu,Left soft,Right soft,Send,Power,",
        "Music,Radio,Shift,Star,Hash,1,2,3,4,5,6,7,8,9,0;",
        "v,0;",
        "V,v",
        `BUILD_DATE
    };

    wire         forced_scandoubler;
    wire [  1:0] buttons;
    wire [127:0] status;
    wire [ 10:0] ps2_key;
    wire [ 31:0] joystick_0;

    // Original MCU/PPM service containers; C:/PMM restore from the mounted NGA.
    wire        ioctl_download;
    wire        ioctl_wr;
    wire [26:0] ioctl_addr;
    wire [15:0] ioctl_dout;
    wire [15:0] ioctl_index;
    wire        ioctl_wait;

    hps_io #(
        .CONF_STR(CONF_STR),
        .WIDE    (1),
        .VDNUM   (4)
    ) hps_io (
        .clk_sys  (clk_sys),
        .HPS_BUS  (HPS_BUS),
        .EXT_BUS  (),
        .gamma_bus(),

        .forced_scandoubler(forced_scandoubler),

        .buttons(buttons),
        .status(status),
        .status_menumask({
            13'b0,
            D3_BULK_PERSISTENCE == 0,
            bt_applied || bt_busy || overlay_busy,
            overlay_applied || overlay_busy || bt_busy
        }),

        .ps2_key   (ps2_key),
        .joystick_0(joystick_0),

        .ioctl_download(ioctl_download),
        .ioctl_wr      (ioctl_wr),
        .ioctl_addr    (ioctl_addr),
        .ioctl_dout    (ioctl_dout),
        .ioctl_index   (ioctl_index),
        .ioctl_wait    (ioctl_wait),
        .img_mounted   (img_mounted),
        .img_readonly  (img_readonly),
        .img_size      (img_size),
        .sd_lba        (sd_lba),
        .sd_blk_cnt    (sd_blk_cnt),
        .sd_rd         (sd_rd),
        .sd_wr         (sd_wr),
        .sd_ack        (sd_ack),
        .sd_buff_addr  (sd_buff_addr),
        .sd_buff_dout  (sd_buff_dout),
        .sd_buff_din   (sd_buff_din),
        .sd_buff_wr    (sd_buff_wr),

        // C: drive save (upload DDR3 → SD card)
        .ioctl_upload      (ioctl_upload),
        .ioctl_upload_req  (1'b0),
        .ioctl_upload_index(8'h00),
        .ioctl_din         (16'hffff),
        .ioctl_rd          (ioctl_rd)
    );

    ///////////////////////   CLOCKS   ///////////////////////////////

    localparam integer SYS_CLK_HZ = 78000000;
    wire clk_sys;  // 78 MHz — CPU, bus, board devices, SDRAM logic
    wire pll_locked;

    pll pll (
        .refclk  (CLK_50M),
        .rst     (0),
        .outclk_0(clk_sys),
        .outclk_1(),
        .locked  (pll_locked)
    );

    // Default to CPU Hold; a deliberate OSD selection releases it only after
    // loader, save, SDRAM scrub and board initialization gates are satisfied.
    wire transport_reset = ~pll_locked;
    wire phone_reset, phone_reset_pending;
    ngage_reset_gate phone_reset_gate (
        .clk          (clk_sys),
        .cold_reset   (transport_reset),
        .reset_request(RESET | status[0] | buttons[1]),
        .block_reset  (save_saving || save_busy),
        .reset_pending(phone_reset_pending),
        .phone_reset  (phone_reset)
    );
    wire reset = phone_reset | !loader_valid | !sdram_scrub_done | !board_init_done | !save_mounted
        | !status[16] | !overlay_ready | !bt_ready;
    wire ioctl_upload, ioctl_rd, board_init_done;
    wire [3:0] img_mounted, sd_rd, sd_wr, sd_ack;
    wire        img_readonly;
    wire [63:0] img_size;
    wire [31:0] sd_lba       [4];
    wire [ 5:0] sd_blk_cnt   [4];
    wire [12:0] sd_buff_addr;
    wire [15:0] sd_buff_dout;
    wire [15:0] sd_buff_din  [4];
    wire        sd_buff_wr;
    assign sd_blk_cnt[0] = 0;
    assign sd_blk_cnt[1] = 0;
    assign sd_blk_cnt[3] = 0;
    // S2 is dedicated to MMC. Backing ownership survives guest/CPU-Hold reset;
    // global hps_io buffer strobes are qualified inside the MMC adapter.
    wire mmc_card_reset, mmc_img_mounted, mmc_img_readonly;
    wire [63:0] mmc_img_size;
    wire [31:0] mmc_sd_lba;
    wire [ 5:0] mmc_sd_blk_cnt;
    wire mmc_sd_rd, mmc_sd_wr, mmc_sd_ack, mmc_sd_buff_wr;
    wire [12:0] mmc_sd_buff_addr;
    wire [15:0] mmc_sd_buff_dout, mmc_sd_buff_din;
    wire mmc_present, mmc_write_protected, mmc_active, mmc_hps_busy, mmc_hps_fault;

    ngage_mmc_hps mmc_backing (
        .clk              (clk_sys),
        .init_reset       (transport_reset),
        .guest_reset      (dma_reset),
        .hps_img_mounted  (img_mounted[2]),
        .hps_img_readonly (img_readonly),
        .hps_img_size     (img_size),
        .card_reset       (mmc_card_reset),
        .card_img_mounted (mmc_img_mounted),
        .card_img_readonly(mmc_img_readonly),
        .card_img_size    (mmc_img_size),
        .card_sd_lba      (mmc_sd_lba),
        .card_sd_blk_cnt  (mmc_sd_blk_cnt),
        .card_sd_rd       (mmc_sd_rd),
        .card_sd_wr       (mmc_sd_wr),
        .card_sd_ack      (mmc_sd_ack),
        .card_sd_buff_addr(mmc_sd_buff_addr),
        .card_sd_buff_dout(mmc_sd_buff_dout),
        .card_sd_buff_din (mmc_sd_buff_din),
        .card_sd_buff_wr  (mmc_sd_buff_wr),
        .hps_sd_lba       (sd_lba[2]),
        .hps_sd_blk_cnt   (sd_blk_cnt[2]),
        .hps_sd_rd        (sd_rd[2]),
        .hps_sd_wr        (sd_wr[2]),
        .hps_sd_ack       (sd_ack[2]),
        .hps_buff_addr    (sd_buff_addr),
        .hps_buff_dout    (sd_buff_dout),
        .hps_buff_wr      (sd_buff_wr),
        .hps_buff_din     (sd_buff_din[2]),
        .busy             (mmc_hps_busy),
        .fault            (mmc_hps_fault)
    );

    ///////////////////////   SDRAM   ////////////////////////////////

    // SDRAM: phone RAM 16MB at PA 0x0a000000, split across BA0 (low 8MB)
    // and BA1 (high 8MB). AW=22 matches DE10 SDRAM geometry (8MB/bank).
    // 78 MHz system clock, inverted DDIO output to SDRAM chip pin.
    // Forward the 78 MHz system clock through the output IO register. The
    // inverted pin clock is paired with falling-edge read capture in sdram_ctrl.
    ngage_sdram_clock sdram_clock (
        .clk      (clk_sys),
        .sdram_clk(SDRAM_CLK)
    );

    // CPU → SDRAM address/data decode
    // ngage_mister outputs: sdram_addr[24:0], sdram_din[31:0], sdram_be[3:0],
    //                       sdram_we, sdram_req
    // Phone PA bit 23 (= sdram_addr[23]) selects BA0 vs BA1.
    wire [24:0] cpu_sdram_addr;
    wire [31:0] cpu_sdram_din;
    wire [ 3:0] cpu_sdram_be;
    wire        cpu_sdram_we;
    wire        cpu_sdram_req;
    // Retain the CPU bus reservation across the read and write of an atomic swap.
    wire        cpu_bus_lock;

    // The adapter owns an entire 32-bit access, including both halfwords.
    // Cold-start RAM scrub proceeds while the phone CPU remains held in reset.
    wire [21:0] sdram_haddr;
    wire [15:0] sdram_wdata, sdram_dout_16;
    wire [1:0] sdram_dsn;
    wire [3:0] sdram_rd_banks, sdram_wr_banks, sdram_ack_banks, sdram_rdy_banks;
    wire sdram_init, sdram_rfsh, sdram_scrub_done, sdram_ack, cpu_sdram_accept;
    wire [31:0] sdram_dout;
    wire mem_req, mem_we, mem_ack;
    wire [7:0] dma_error_pending;
    wire dma_cmd_valid, dma_cmd_ready, dma_cmd_write;
    wire [31:0] dma_cmd_addr, dma_cmd_data;
    wire [ 3:0] dma_cmd_be;
    wire [31:0] dma_rsp_data;
    wire        dma_reset;
    wire lcd_dma_req, lcd_dma_accept, lcd_dma_ack;
    wire [24:0] lcd_dma_addr;
    wire [31:0] lcd_dma_rdata;
    wire dma_ram_req, dma_ram_write, dma_ram_ack, dma_error, dma_response;
    wire [24:0] dma_ram_addr;
    wire [31:0] dma_ram_data, dma_ram_rdata;
    wire [3:0] dma_ram_be;
    wire shared_dma_req, shared_dma_write, shared_dma_accept, shared_dma_ack;
    wire [24:0] shared_dma_addr;
    wire [31:0] shared_dma_data, shared_dma_rdata;
    wire [3:0] shared_dma_be;
    wire dma_local_valid, dma_local_waiting, dma_local_ready, dma_local_write, dma_local_done, dma_local_error;
    wire [31:0] dma_local_addr, dma_local_data, dma_local_rdata;
    wire [ 3:0] dma_local_be;
    wire [24:0] mem_addr;
    wire [31:0] mem_wdata, mem_rdata;
    wire [3:0] mem_be;
    // One captured route serves all eight guest-programmed DMA channels.
    ngage_dma_route dma_route (
        .clk          (clk_sys),
        .reset        (dma_reset || transport_reset),
        .cpu_lock     (cpu_bus_lock),
        .cmd_valid    (dma_cmd_valid),
        .cmd_ready    (dma_cmd_ready),
        .cmd_write    (dma_cmd_write),
        .cmd_addr     (dma_cmd_addr),
        .cmd_data     (dma_cmd_data),
        .cmd_be       (dma_cmd_be),
        .rsp_valid    (dma_response),
        .rsp_error    (dma_error),
        .rsp_data     (dma_rsp_data),
        .ram_req      (dma_ram_req),
        .ram_write    (dma_ram_write),
        .ram_addr     (dma_ram_addr),
        .ram_data     (dma_ram_data),
        .ram_be       (dma_ram_be),
        .ram_ack      (dma_ram_ack),
        .ram_rdata    (dma_ram_rdata),
        .local_valid  (dma_local_valid),
        .local_waiting(dma_local_waiting),
        .local_ready  (dma_local_ready),
        .local_write  (dma_local_write),
        .local_addr   (dma_local_addr),
        .local_data   (dma_local_data),
        .local_be     (dma_local_be),
        .local_done   (dma_local_done),
        .local_error  (dma_local_error),
        .local_rdata  (dma_local_rdata)
    );
    // No extra request pipeline for the fast reader. Capture only the outer
    // grant's owner; completed words alternate between LCD and general DMA.
    ngage_dma_ram_mux dma_ram_mux (
        .clk       (clk_sys),
        .reset     (dma_reset || transport_reset),
        .lcd_req   (lcd_dma_req),
        .lcd_addr  (lcd_dma_addr),
        .lcd_accept(lcd_dma_accept),
        .lcd_ack   (lcd_dma_ack),
        .lcd_rdata (lcd_dma_rdata),
        .dma_req   (dma_ram_req),
        .dma_write (dma_ram_write),
        .dma_addr  (dma_ram_addr),
        .dma_data  (dma_ram_data),
        .dma_be    (dma_ram_be),
        .dma_ack   (dma_ram_ack),
        .dma_rdata (dma_ram_rdata),
        .mem_req   (shared_dma_req),
        .mem_write (shared_dma_write),
        .mem_addr  (shared_dma_addr),
        .mem_data  (shared_dma_data),
        .mem_be    (shared_dma_be),
        .mem_accept(shared_dma_accept),
        .mem_ack   (shared_dma_ack),
        .mem_rdata (shared_dma_rdata)
    );

    // Both DMA paths share SDRAM with the CPU and respect atomic CPU locks.
    ngage_sdram_arbiter ram_arbiter (
        .clk       (clk_sys),
        .reset     (dma_reset || transport_reset),
        .cpu_lock  (cpu_bus_lock),
        .cpu_req   (cpu_sdram_req),
        .cpu_we    (cpu_sdram_we),
        .cpu_addr  (cpu_sdram_addr),
        .cpu_data  (cpu_sdram_din),
        .cpu_be    (cpu_sdram_be),
        .cpu_ack   (sdram_ack),
        .cpu_accept(cpu_sdram_accept),
        .cpu_rdata (sdram_dout),
        .dma_req   (shared_dma_req),
        .dma_we    (shared_dma_write),
        .dma_addr  (shared_dma_addr),
        .dma_data  (shared_dma_data),
        .dma_be    (shared_dma_be),
        .dma_ack   (shared_dma_ack),
        .dma_accept(shared_dma_accept),
        .dma_rdata (shared_dma_rdata),
        .mem_req   (mem_req),
        .mem_we    (mem_we),
        .mem_addr  (mem_addr),
        .mem_data  (mem_wdata),
        .mem_be    (mem_be),
        .mem_ack   (mem_ack),
        .mem_rdata (mem_rdata)
    );
    wire [3:0] sdram_dst_banks;
    wire ram_line_req, ram_line_ready, ram_line_valid, ram_line_last;
    wire [24:0] ram_line_addr;
    wire [15:0] ram_line_data;
    wire [ 1:0] sdram_line_banks;

    ngage_sdram_adapter #(
        .LINE_REFILL   (1),
        .REFRESH_PERIOD((64'd6800 * SYS_CLK_HZ) / 104000000)
    ) phone_sdram (
        .line_req   (ram_line_req && !cpu_bus_lock),
        .line_addr  (ram_line_addr),
        .line_ready (ram_line_ready),
        .line_valid (ram_line_valid),
        .line_data  (ram_line_data),
        .line_last  (ram_line_last),
        .ba_line    (sdram_line_banks),
        .clk        (clk_sys),
        .rst        (transport_reset),
        .phone_reset(dma_reset || transport_reset),
        .init       (sdram_init),
        .req        (mem_req),
        .we         (mem_we),
        .addr       (mem_addr),
        .din        (mem_wdata),
        .be         (mem_be),
        .ack        (mem_ack),
        .dout       (mem_rdata),
        .scrub_done (sdram_scrub_done),
        .ba_addr    (sdram_haddr),
        .ba_din     (sdram_wdata),
        .ba_dsn     (sdram_dsn),
        .rd         (sdram_rd_banks),
        .wr         (sdram_wr_banks),
        .ba_ack     (sdram_ack_banks),
        .ba_dst     (sdram_dst_banks),
        .ba_rdy     (sdram_rdy_banks),
        .ba_dout    (sdram_dout_16),
        .rfsh       (sdram_rfsh)
    );

    jtframe_sdram64 #(
        .SHORT_READS         (1),
        .DYNAMIC_LINE        (1),
        .AW                  (22),
        .HF                  (1),    // 78 MHz > 66 MHz → HF mode
        .READ_CAPTURE_NEGEDGE(1),    // paired with the inverted DDIO pin clock
        .BA0_LEN             (128),  // BL8: two reads fill one 32-byte ARM line
        .BA1_LEN             (128),
        .BA2_LEN             (16),
        .BA3_LEN             (16),
        .PROG_LEN            (16),   // unused programming port; no longer than physical burst
        .BA0_WEN             (1),    // phone RAM is read+write
        .BA1_WEN             (1),
        .BA2_WEN             (0),
        .BA3_WEN             (0)
    ) sdram_ctrl (
        .line_read(sdram_line_banks),
        .rst      (transport_reset),
        .clk      (clk_sys),
        .init     (sdram_init),

        // BA0: phone RAM low 8MB
        .ba0_addr(sdram_haddr),
        .ba0_din (sdram_wdata),
        .ba0_dsn (sdram_dsn),

        // BA1: phone RAM high 8MB
        .ba1_addr(sdram_haddr),
        .ba1_din (sdram_wdata),
        .ba1_dsn (sdram_dsn),

        // BA2/BA3: unused
        .ba2_addr(22'd0),
        .ba2_din (16'd0),
        .ba2_dsn (2'b11),
        .ba3_addr(22'd0),
        .ba3_din (16'd0),
        .ba3_dsn (2'b11),

        .rd  (sdram_rd_banks),
        .wr  (sdram_wr_banks),
        .rfsh(sdram_rfsh),

        .ack (sdram_ack_banks),
        .dst (sdram_dst_banks),
        .dok (),
        .rdy (sdram_rdy_banks),
        .dout(sdram_dout_16),

        // programming port (unused — ROM goes via DDR3)
        .prog_en  (1'b0),
        .prog_addr(22'd0),
        .prog_rd  (1'b0),
        .prog_wr  (1'b0),
        .prog_din (16'd0),
        .prog_dsn (2'b11),
        .prog_ba  (2'd0),
        .prog_dst (),
        .prog_dok (),
        .prog_rdy (),
        .prog_ack (),

        // SDRAM chip pins
        .sdram_dq  (SDRAM_DQ),
        .sdram_a   (SDRAM_A),
        .sdram_dqml(SDRAM_DQML),
        .sdram_dqmh(SDRAM_DQMH),
        .sdram_ba  (SDRAM_BA),
        .sdram_nwe (SDRAM_nWE),
        .sdram_ncas(SDRAM_nCAS),
        .sdram_nras(SDRAM_nRAS),
        .sdram_ncs (SDRAM_nCS),
        .sdram_cke (SDRAM_CKE)
    );

    ///////////////////////   DDR3 firmware transport   ////////////////
    // Installed Linux reserves0x1ff00000..0x3fffffff (2026-11-12 SSH audit).
    // Core ROM/C:/PMM occupy0x30000000..0x3180ffff. Diagnostics use the unused
    // ROM/C: guard at0x313f0000 (text ring and two1KiB snapshots); no new span.
    assign DDRAM_CLK = clk_sys;
    // DDR burst count is owned by the ROM-cache/backend transaction.
    wire loader_valid, loader_failed, loader_known_firmware;
    wire overlay_ready, overlay_loaded, overlay_applied, overlay_busy;
    wire [3:0] overlay_error;
    wire bt_ready, bt_loaded, bt_applied, bt_busy, bt_wait;
    wire [3:0] bt_error;
    wire bt_req, bt_mem_ready, bt_done, bt_write;
    wire [31:0] bt_addr, bt_data, bt_rdata;
    wire any_compatibility = status[19] || status[20];
    wire service_wait, overlay_wait;
    wire overlay_req, overlay_mem_ready, overlay_done, overlay_write;
    wire [31:0] overlay_addr, overlay_data, overlay_rdata;
    wire [1:0] loader_profile;
    wire load_req, load_ready, load_done;
    wire [31:0] load_addr, load_data;
    wire [3:0] load_be;
    wire snapshot_valid, snapshot_ready, snapshot_write, snapshot_done;
    wire [31:0] snapshot_addr, snapshot_data, snapshot_rdata;
    wire text_valid, text_ready, text_write, text_done, runtime_char_valid;
    wire [31:0] text_addr, text_data, text_rdata, text_dropped;
    wire [7:0] runtime_char_data;
    wire telemetry_valid, telemetry_ready, telemetry_write, telemetry_done;
    wire [31:0] telemetry_addr, telemetry_data, telemetry_rdata;
    wire         telemetry_capture;
    wire [ 10:0] telemetry_word;
    wire [767:0] diagnostic_values;
    wire service_valid, service_ready, service_write, service_done;
    wire [31:0] service_addr, service_data, service_rdata;
    wire [3:0] service_be;
    ngage_ddr_arbiter diagnostic_arbiter (
        .clk           (clk_sys),
        .reset         (transport_reset),
        .cpu_lock      (1'b0),
        .l_bulk        (1'b0),
        .c_bulk        (1'b0),
        .req_bulk      (),
        .c_line        (1'b0),
        .req_line      (),
        .rsp_beat_valid(1'b0),
        .rsp_beat_data (64'b0),
        .rsp_beat_last (1'b0),
        .c_beat_valid  (),
        .c_beat_data   (),
        .c_beat_last   (),
        .l_valid       (snapshot_valid),
        .l_ready       (snapshot_ready),
        .l_write       (snapshot_write),
        .l_addr        (snapshot_addr),
        .l_data        (snapshot_data),
        .l_be          (4'hf),
        .l_done        (snapshot_done),
        .l_rdata       (snapshot_rdata),
        .c_valid       (text_valid),
        .c_ready       (text_ready),
        .c_write       (text_write),
        .c_addr        (text_addr),
        .c_data        (text_data),
        .c_be          (4'hf),
        .c_done        (text_done),
        .c_rdata       (text_rdata),
        .req_valid     (telemetry_valid),
        .req_ready     (telemetry_ready),
        .req_write     (telemetry_write),
        .req_addr      (telemetry_addr),
        .req_data      (telemetry_data),
        .req_be        (),
        .rsp_valid     (telemetry_done),
        .rsp_data      (telemetry_rdata)
    );
    ngage_diag_loader_port diagnostics_port (
        .clk       (clk_sys),
        .reset     (transport_reset),
        .load_valid(load_req),
        .load_ready(load_ready),
        .load_addr (load_addr),
        .load_data (load_data),
        .load_be   (load_be),
        .load_done (load_done),
        .diag_valid(telemetry_valid),
        .diag_ready(telemetry_ready),
        .diag_write(telemetry_write),
        .diag_addr (telemetry_addr),
        .diag_data (telemetry_data),
        .diag_done (telemetry_done),
        .diag_rdata(telemetry_rdata),
        .mem_valid (service_valid),
        .mem_ready (service_ready),
        .mem_write (service_write),
        .mem_addr  (service_addr),
        .mem_data  (service_data),
        .mem_be    (service_be),
        .mem_done  (service_done),
        .mem_rdata (service_rdata)
    );

    wire save_mounted, save_saving, save_saved, save_error, save_busy;
    // Do not replace backing memory while a save is mounted or being processed.
    wire bundle_download, blocked_load;
    // Main uses 00/40 for boot.rom/boot1.rom; F1/F2 are manual selectors.
    wire firmware_request = ioctl_download && (ioctl_index == 0 || ioctl_index == 16'h40 ||
                                               ioctl_index == 1 || ioctl_index == 2);
    wire firmware_ppm = ioctl_index == 16'h40 || ioctl_index == 2;
    ngage_bundle_gate bundle_gate (
        .clk         (clk_sys),
        .reset       (transport_reset),
        .request     (firmware_request),
        .save_mounted(save_mounted),
        .save_busy   (save_busy),
        .save_error  (save_error),
        .download    (bundle_download),
        .blocked     (blocked_load)
    );
    ngage_service_loader loader (
        .clk           (clk_sys),
        .reset         (transport_reset),
        .download      (bundle_download),
        .ppm           (firmware_ppm),
        .wr            (ioctl_wr),
        .addr          (ioctl_addr),
        .data          (ioctl_dout),
        .wait_req      (service_wait),
        .valid         (loader_valid),
        .failed        (loader_failed),
        .mem_valid     (load_req),
        .mem_ready     (load_ready),
        .mem_addr      (load_addr),
        .mem_data      (load_data),
        .mem_be        (load_be),
        .mem_done      (load_done),
        .failure_reason()
    );
    wire firmware_aux_valid, firmware_aux_ready, firmware_aux_write, firmware_aux_done;
    wire [31:0] firmware_aux_addr, firmware_aux_data, firmware_aux_rdata;
    wire [3:0] firmware_aux_be;
`ifdef NGAGE_COMPAT_OVERLAYS
    // Stock Main autoloads boot2.rom at index80, potentially before boot.rom.
    // The NOS package stages independently and applies only after both services.
    wire overlay_download = ioctl_download && (ioctl_index == 16'h80 || ioctl_index == 3);
    wire bt_download = ioctl_download && (ioctl_index == 16'hc0 || ioctl_index == 4);
    assign ioctl_wait = firmware_request ? service_wait : overlay_download ? overlay_wait :
                        bt_download ? bt_wait : 1'b0;
    ngage_nos_overlay #(
        .SHARED_CHECKSUM(1)
    ) nos_overlay (
        .clk              (clk_sys),
        .reset            (transport_reset),
        .firmware_valid   (loader_valid),
        .firmware_loading (bundle_download),
        .enabled          (status[19]),
        .checksum_required(any_compatibility),
        .blocked          (save_saving || save_busy),
        .download         (overlay_download),
        .wr               (ioctl_wr),
        .addr             (ioctl_addr),
        .data             (ioctl_dout),
        .wait_req         (overlay_wait),
        .ready            (overlay_ready),
        .loaded           (overlay_loaded),
        .applied          (overlay_applied),
        .busy             (overlay_busy),
        .error            (overlay_error),
        .mem_valid        (overlay_req),
        .mem_ready        (overlay_mem_ready),
        .mem_write        (overlay_write),
        .mem_addr         (overlay_addr),
        .mem_data         (overlay_data),
        .mem_done         (overlay_done),
        .mem_rdata        (overlay_rdata)
    );
    // Independent component and undo table; no NOS enable dependency.
    // boot3.rom (C0) auto-loads; F4 selects Bluetooth_Compatibility.ngo manually.
    ngage_nos_overlay #(
        .OVERLAY_ID     (2),
        .SHARED_CHECKSUM(1)
    ) bluetooth_overlay (
        .clk              (clk_sys),
        .reset            (transport_reset),
        .firmware_valid   (loader_valid),
        .firmware_loading (bundle_download),
        .enabled          (status[20]),
        .checksum_required(any_compatibility),
        .blocked          (save_saving || save_busy),
        .download         (bt_download),
        .wr               (ioctl_wr),
        .addr             (ioctl_addr),
        .data             (ioctl_dout),
        .wait_req         (bt_wait),
        .ready            (bt_ready),
        .loaded           (bt_loaded),
        .applied          (bt_applied),
        .busy             (bt_busy),
        .error            (bt_error),
        .mem_valid        (bt_req),
        .mem_ready        (bt_mem_ready),
        .mem_write        (bt_write),
        .mem_addr         (bt_addr),
        .mem_data         (bt_data),
        .mem_done         (bt_done),
        .mem_rdata        (bt_rdata)
    );
    wire component_req, component_ready, component_write, component_done;
    wire [31:0] component_addr, component_data, component_rdata;
    wire [3:0] component_be;
    ngage_ddr_arbiter component_arbiter (
        .clk      (clk_sys),
        .reset    (transport_reset),
        .cpu_lock (1'b0),
        .l_valid  (overlay_req),
        .l_ready  (overlay_mem_ready),
        .l_write  (overlay_write),
        .l_addr   (overlay_addr),
        .l_data   (overlay_data),
        .l_be     (4'hf),
        .l_done   (overlay_done),
        .l_rdata  (overlay_rdata),
        .c_valid  (bt_req),
        .c_ready  (bt_mem_ready),
        .c_write  (bt_write),
        .c_addr   (bt_addr),
        .c_data   (bt_data),
        .c_be     (4'hf),
        .c_done   (bt_done),
        .c_rdata  (bt_rdata),
        .req_valid(component_req),
        .req_ready(component_ready),
        .req_write(component_write),
        .req_addr (component_addr),
        .req_data (component_data),
        .req_be   (component_be),
        .rsp_valid(component_done),
        .rsp_data (component_rdata)
    );
    ngage_ddr_arbiter firmware_overlay_arbiter (
        .clk      (clk_sys),
        .reset    (transport_reset),
        .cpu_lock (1'b0),
        .l_valid  (service_valid),
        .l_ready  (service_ready),
        .l_write  (service_write),
        .l_addr   (service_addr),
        .l_data   (service_data),
        .l_be     (service_be),
        .l_done   (service_done),
        .l_rdata  (service_rdata),
        .c_valid  (component_req),
        .c_ready  (component_ready),
        .c_write  (component_write),
        .c_addr   (component_addr),
        .c_data   (component_data),
        .c_be     (component_be),
        .c_done   (component_done),
        .c_rdata  (component_rdata),
        .req_valid(firmware_aux_valid),
        .req_ready(firmware_aux_ready),
        .req_write(firmware_aux_write),
        .req_addr (firmware_aux_addr),
        .req_data (firmware_aux_data),
        .req_be   (firmware_aux_be),
        .rsp_valid(firmware_aux_done),
        .rsp_data (firmware_aux_rdata)
    );
`else
    // Fit profile: ignore boot2/boot3 downloads and saved overlay selections.
    // MCU/PPM loading remains active; no overlay can hold CPU release or saving.
    assign ioctl_wait         = firmware_request && service_wait;
    assign overlay_ready      = 1'b1;
    assign bt_ready           = 1'b1;
    assign overlay_loaded     = 1'b0;
    assign overlay_applied    = 1'b0;
    assign overlay_busy       = 1'b0;
    assign overlay_error      = 4'b0;
    assign bt_loaded          = 1'b0;
    assign bt_applied         = 1'b0;
    assign bt_busy            = 1'b0;
    assign bt_error           = 4'b0;
    assign firmware_aux_valid = service_valid;
    assign firmware_aux_write = service_write;
    assign firmware_aux_addr  = service_addr;
    assign firmware_aux_data  = service_data;
    assign firmware_aux_be    = service_be;
    assign service_ready      = firmware_aux_ready;
    assign service_done       = firmware_aux_done;
    assign service_rdata      = firmware_aux_rdata;
`endif
    // Service files contain no PMM-seed choice. Both existing NGA profile
    // IDs are accepted only with the same audited firmware hashes.
    assign loader_profile        = 0;
    assign loader_known_firmware = loader_valid;
    wire [31:0] core_ddr_addr;
    wire core_ddr_rd, core_ddr_wr;
    wire [31:0] core_ddr_din;
    wire [ 3:0] core_ddr_be;
    wire flash_dirty, flash_busy;
    wire [13:0] flash_dirty_sector;
    wire [31:0] core_ddr_dout;
    wire        core_ddr_ready;
    wire arb_valid, arb_ready, arb_write, arb_rsp;
    wire [31:0] arb_addr, arb_data, arb_rdata;
    wire [3:0] arb_be;
    wire       core_accept;
    // Flash modules retain a request until core_accept, and drain accepted
    // operations across phone reset. Do not gate their backing traffic on reset.
    // The first arbiter shares the loader and save engine; the second shares
    // their registered transaction stream with the phone while honoring SWP lock.
    localparam D3_BULK_PERSISTENCE = 1;
    wire aux_bulk, arb_bulk, bulk_cancel, bulk_error;
    wire bulk_read_valid, bulk_read_ready, bulk_read_last;
    wire bulk_write_valid, bulk_write_ready, bulk_write_last;
    wire [63:0] bulk_read_data, bulk_write_data;
    wire save_mem_valid, save_mem_ready, save_mem_write, save_mem_done;
    wire [31:0] save_mem_addr, save_mem_data, save_mem_rdata;
    wire [3:0] save_mem_be;
    wire aux_valid, aux_ready, aux_write, aux_done;
    wire [31:0] aux_addr, aux_data, aux_rdata;
    wire [3:0] aux_be;
    ngage_ddr_arbiter auxiliary_arbiter (
        .l_bulk   (1'b0),
        .c_bulk   (D3_BULK_PERSISTENCE != 0),
        .req_bulk (aux_bulk),
        .clk      (clk_sys),
        .reset    (transport_reset),
        .cpu_lock (1'b0),
        .l_valid  (firmware_aux_valid),
        .l_ready  (firmware_aux_ready),
        .l_addr   (firmware_aux_addr),
        .l_data   (firmware_aux_data),
        .l_be     (firmware_aux_be),
        .l_done   (firmware_aux_done),
        .l_write  (firmware_aux_write),
        .l_rdata  (firmware_aux_rdata),
        .c_valid  (save_mem_valid),
        .c_ready  (save_mem_ready),
        .c_write  (save_mem_write),
        .c_addr   (save_mem_addr),
        .c_data   (save_mem_data),
        .c_be     (save_mem_be),
        .c_done   (save_mem_done),
        .c_rdata  (save_mem_rdata),
        .req_valid(aux_valid),
        .req_ready(aux_ready),
        .req_write(aux_write),
        .req_addr (aux_addr),
        .req_data (aux_data),
        .req_be   (aux_be),
        .rsp_valid(aux_done),
        .rsp_data (aux_rdata)
    );
    wire core_ddr_line, arb_line, core_beat_valid, core_beat_last, arb_beat_valid, arb_beat_last;
    wire [63:0] core_beat_data, arb_beat_data;
    ngage_ddr_arbiter ddr_arbiter (
        .l_bulk        (aux_bulk),
        .c_bulk        (1'b0),
        .req_bulk      (arb_bulk),
        .c_line        (core_ddr_line),
        .req_line      (arb_line),
        .rsp_beat_valid(arb_beat_valid),
        .rsp_beat_data (arb_beat_data),
        .rsp_beat_last (arb_beat_last),
        .c_beat_valid  (core_beat_valid),
        .c_beat_data   (core_beat_data),
        .c_beat_last   (core_beat_last),
        .clk           (clk_sys),
        .reset         (transport_reset),
        .cpu_lock      (cpu_bus_lock && !reset),
        .l_valid       (aux_valid),
        .l_ready       (aux_ready),
        .l_addr        (aux_addr),
        .l_data        (aux_data),
        .l_be          (aux_be),
        .l_done        (aux_done),
        .l_write       (aux_write),
        .l_rdata       (aux_rdata),
        .c_valid       (core_ddr_rd || core_ddr_wr),
        .c_ready       (core_accept),
        .c_write       (core_ddr_wr),
        .c_addr        (core_ddr_addr),
        .c_data        (core_ddr_din),
        .c_be          (core_ddr_be),
        .c_done        (core_ddr_ready),
        .c_rdata       (core_ddr_dout),
        .req_valid     (arb_valid),
        .req_ready     (arb_ready),
        .req_write     (arb_write),
        .req_addr      (arb_addr),
        .req_data      (arb_data),
        .req_be        (arb_be),
        .rsp_valid     (arb_rsp),
        .rsp_data      (arb_rdata)
    );
    wire core_ddr_fetch;
    // Integration hardware build: test D1 and the 8 KiB D2 cache together.
    localparam D1_STREAM_TRANSPORT  = 1;
    localparam D2_FLASH_CACHE_BYTES = 8192;
    ngage_ddr_flash_adapter #(
        .FLASH_CACHE_BYTES(D2_FLASH_CACHE_BYTES),
        .BULK_PERSISTENCE (D3_BULK_PERSISTENCE),
        .STREAM_TRANSPORT (D1_STREAM_TRANSPORT),
        // The shared flash cache replaces the old instruction-only ROM cache.
        .ROM_CACHE        (0),
        .LINE_REFILL      (1)
    ) ddr_adapter (
        .req_bulk        (arb_bulk),
        .bulk_cancel     (bulk_cancel),
        .bulk_error      (bulk_error),
        .bulk_read_valid (bulk_read_valid),
        .bulk_read_ready (bulk_read_ready),
        .bulk_read_data  (bulk_read_data),
        .bulk_read_last  (bulk_read_last),
        .bulk_write_valid(bulk_write_valid),
        .bulk_write_ready(bulk_write_ready),
        .bulk_write_data (bulk_write_data),
        .bulk_write_last (bulk_write_last),
        .req_line        (arb_line),
        .rsp_beat_valid  (arb_beat_valid),
        .rsp_beat_data   (arb_beat_data),
        .rsp_beat_last   (arb_beat_last),
        .clk             (clk_sys),
        .reset           (transport_reset),
        .req_fetch       (core_accept && core_ddr_fetch),
        .req_valid       (arb_valid),
        .req_ready       (arb_ready),
        .req_write       (arb_write),
        .req_addr        (arb_addr),
        .req_wdata       (arb_data),
        .req_be          (arb_be),
        .rsp_valid       (arb_rsp),
        .rsp_data        (arb_rdata),
        .ddr_burstcount  (DDRAM_BURSTCNT),
        .ddr_addr        (DDRAM_ADDR),
        .ddr_din         (DDRAM_DIN),
        .ddr_be          (DDRAM_BE),
        .ddr_rd          (DDRAM_RD),
        .ddr_we          (DDRAM_WE),
        .ddr_busy        (DDRAM_BUSY),
        .ddr_dout        (DDRAM_DOUT),
        .ddr_dout_ready  (DDRAM_DOUT_READY)
    );

    // Raw media has no embedded firmware identity. Retain the verified stock
    // firmware gate; host conversion manifests carry the original provenance.
    wire [1:0] save_slot_error;
    reg        flush_prev = 0;
    always @(posedge clk_sys) flush_prev <= status[14];
    ngage_raw_save_manager #(
        .BULK               (D3_BULK_PERSISTENCE),
        .AUTO_QUIET_CYCLES  (SYS_CLK_HZ),
        .AUTO_MAX_AGE_CYCLES(5 * SYS_CLK_HZ),
        .SD_TIMEOUT         (SYS_CLK_HZ)
    ) saves (
        .bulk_cancel     (bulk_cancel),
        .bulk_error      (bulk_error),
        .bulk_read_valid (bulk_read_valid),
        .bulk_read_ready (bulk_read_ready),
        .bulk_read_data  (bulk_read_data),
        .bulk_read_last  (bulk_read_last),
        .bulk_write_valid(bulk_write_valid),
        .bulk_write_ready(bulk_write_ready),
        .bulk_write_data (bulk_write_data),
        .bulk_write_last (bulk_write_last),
        .clk             (clk_sys),
        .reset           (transport_reset),
        .mount           (img_mounted[1:0]),
        .readonly_image  (img_readonly),
        .image_size      (img_size),
        .bundle_verified (loader_valid && loader_known_firmware && !ioctl_download),
        .dirty_valid     (flash_dirty),
        .dirty_sector    (flash_dirty_sector),
        .flush_start     (status[14] && !flush_prev),
        .autosave_enable (status[21]),
        .pause_autosave  (phone_reset_pending || phone_reset || overlay_busy || bt_busy),
        .slot_error      (save_slot_error),
        .mounted         (save_mounted),
        .saving          (save_saving),
        .saved           (save_saved),
        .error           (save_error),
        .busy            (save_busy),
        .mem_valid       (save_mem_valid),
        .mem_ready       (save_mem_ready),
        .mem_write       (save_mem_write),
        .mem_addr        (save_mem_addr),
        .mem_data        (save_mem_data),
        .mem_be          (save_mem_be),
        .mem_done        (save_mem_done),
        .mem_rdata       (save_mem_rdata),
        .sd_lba0         (sd_lba[0]),
        .sd_lba1         (sd_lba[1]),
        .sd_rd           (sd_rd[1:0]),
        .sd_wr           (sd_wr[1:0]),
        .sd_ack          (sd_ack[1:0]),
        .hps_addr        (sd_buff_addr),
        .hps_dout        (sd_buff_dout),
        .hps_we          (sd_buff_wr),
        .hps_din         (sd_buff_din[0]),
        .flash_quiescent (!flash_busy)
    );
    assign sd_buff_din[1] = sd_buff_din[0];

    ///////////////////////   CORE   /////////////////////////////////

    wire core_ce_pix;
    wire core_hsync, core_vsync, core_hblank, core_vblank;
    wire [11:0] core_rgb;

    wire [26:0] phone_keys;
    wire [15:0] debug_read_data;
    wire        debug_fault_seen;
    wire [10:0] debug_word, export_word;
    wire debug_freeze, debug_busy, debug_error, debug_mounted, lcd_unsupported;
    reg debug_trigger_prev = 0;
    always @(posedge clk_sys) debug_trigger_prev <= status[18];
    wire export_trigger = status[18] && !debug_trigger_prev;
    reg  export_pending = 0;
    wire export_start = export_pending && !debug_busy && !telemetry_capture;
    always @(posedge clk_sys) begin
        if (transport_reset) export_pending <= 0;
        else begin
            if (export_start) export_pending <= 0;
            if (export_trigger) export_pending <= 1;
        end
    end
    assign debug_word = telemetry_capture ? telemetry_word : export_word;
    ngage_diag_ddr #(
        .CLOCK_HZ (SYS_CLK_HZ),
        .BUILD_TAG({16'b0, `BUILD_DATE})
    ) telemetry (
        .clk           (clk_sys),
        .reset         (transport_reset),
        .cpu_reset     (dma_reset),
        .allow_capture (!debug_busy && !export_pending && !export_trigger),
        .values        (diagnostic_values),
        .capture_active(telemetry_capture),
        .debug_word    (telemetry_word),
        .debug_data    (debug_read_data),
        .req_valid     (snapshot_valid),
        .req_ready     (snapshot_ready),
        .req_write     (snapshot_write),
        .req_addr      (snapshot_addr),
        .req_data      (snapshot_data),
        .rsp_valid     (snapshot_done),
        .rsp_data      (snapshot_rdata)
    );
    ngage_diag_text_ddr #(
        .CLOCK_HZ(SYS_CLK_HZ)
    ) runtime_text (
        .clk       (clk_sys),
        .reset     (transport_reset),
        .cpu_reset (dma_reset),
        .char_valid(runtime_char_valid),
        .char_data (runtime_char_data),
        .cycles    (diagnostic_values[159:128]),
        .dropped   (text_dropped),
        .req_valid (text_valid),
        .req_ready (text_ready),
        .req_write (text_write),
        .req_addr  (text_addr),
        .req_data  (text_data),
        .rsp_valid (text_done),
        .rsp_data  (text_rdata)
    );
    ngage_diag_export #(
        .TIMEOUT(SYS_CLK_HZ)
    ) debug_export (
        .clk           (clk_sys),
        .reset         (transport_reset),
        .mount         (img_mounted[3]),
        .readonly_image(img_readonly),
        .image_size    (img_size),
        .start         (export_start),
        .mounted       (debug_mounted),
        .busy          (debug_busy),
        .error         (debug_error),
        .done          (),
        .freeze_trace  (debug_freeze),
        .debug_word    (export_word),
        .debug_data    (debug_read_data),
        .sd_lba        (sd_lba[3]),
        .sd_rd         (sd_rd[3]),
        .sd_wr         (sd_wr[3]),
        .sd_ack        (sd_ack[3]),
        .hps_addr      (sd_buff_addr),
        .hps_dout      (sd_buff_dout),
        .hps_we        (sd_buff_wr),
        .hps_din       (sd_buff_din[3])
    );
    reg [1:0] osd_sync = 0;
    always @(posedge clk_sys) osd_sync <= {osd_sync[0], OSD_STATUS};
    ngage_keys key_input (
        .clk     (clk_sys),
        .reset   (transport_reset),
        .inhibit (osd_sync[1]),
        .ps2_key (ps2_key),
        .joystick(joystick_0),
        .keys    (phone_keys)
    );
    // Requested timing experiment: 26 MHz counters and a 64 Hz NOS counter.
    // NOS IRQ deadlines remain firmware-controlled; this is not phone-verified.
    ngage_mister #(
        .LINE_REFILL    (1),
        .DMA_LOCAL      (1),
        .TEST_SIM_ENABLE(0),
        .TIMER_CLK_DIV  (SYS_CLK_HZ / 26000000),
        .NOS_TICK_HZ    (64),
        .SYS_CLK_HZ     (SYS_CLK_HZ)
    ) core (
        .ddram_line(core_ddr_line),
        .ddram_beat_valid(core_beat_valid),
        .ddram_beat_data(core_beat_data),
        .ddram_beat_last(core_beat_last),
        .ram_line_req(ram_line_req),
        .ram_line_addr(ram_line_addr),
        .ram_line_ready(ram_line_ready && !cpu_bus_lock),
        .ram_line_valid(ram_line_valid),
        .ram_line_data(ram_line_data),
        .ram_line_last(ram_line_last),
        .sim_present(1'b0),
        .dma_reset(dma_reset),
        .mmc_card_reset(mmc_card_reset),
        .mmc_img_mounted(mmc_img_mounted),
        .mmc_img_readonly(mmc_img_readonly),
        .mmc_img_size(mmc_img_size),
        .mmc_sd_lba(mmc_sd_lba),
        .mmc_sd_blk_cnt(mmc_sd_blk_cnt),
        .mmc_sd_rd(mmc_sd_rd),
        .mmc_sd_wr(mmc_sd_wr),
        .mmc_sd_ack(mmc_sd_ack),
        .mmc_sd_buff_addr(mmc_sd_buff_addr),
        .mmc_sd_buff_dout(mmc_sd_buff_dout),
        .mmc_sd_buff_din(mmc_sd_buff_din),
        .mmc_sd_buff_wr(mmc_sd_buff_wr),
        .mmc_present(mmc_present),
        .mmc_write_protected(mmc_write_protected),
        .mmc_active(mmc_active),
        .dma_sdram_accept(lcd_dma_accept),
        .dma_sdram_req(lcd_dma_req),
        .dma_sdram_addr(lcd_dma_addr),
        .dma_sdram_ack(lcd_dma_ack),
        .dma_sdram_data(lcd_dma_rdata),
        .dma_error_pending(dma_error_pending),
        .dma_cmd_valid(dma_cmd_valid),
        .dma_cmd_ready(dma_cmd_ready),
        .dma_cmd_write(dma_cmd_write),
        .dma_cmd_addr(dma_cmd_addr),
        .dma_cmd_data(dma_cmd_data),
        .dma_cmd_be(dma_cmd_be),
        .dma_rsp_valid(dma_response),
        .dma_rsp_error(dma_error),
        .dma_rsp_data(dma_rsp_data),
        .dma_local_valid(dma_local_valid),
        .dma_local_waiting(dma_local_waiting),
        .dma_local_ready(dma_local_ready),
        .dma_local_write(dma_local_write),
        .dma_local_addr(dma_local_addr),
        .dma_local_data(dma_local_data),
        .dma_local_be(dma_local_be),
        .dma_local_done(dma_local_done),
        .dma_local_error(dma_local_error),
        .dma_local_rdata(dma_local_rdata),
        .diagnostic_video(!status[17]),
        .save_state(save_error ? 3'd4 : save_saving ? 3'd2 :
                    save_mounted && save_saved ? 3'd3 : save_mounted ? 3'd1 : 3'd0),
        .diagnostic_status({
            save_slot_error,
            (|bt_error),
            bt_busy,
            bt_loaded,
            bt_applied,
            status[20],
            (|overlay_error ? overlay_error : bt_error),
            overlay_busy,
            overlay_loaded,
            overlay_applied,
            status[19],
            loader_known_firmware,
            bundle_download,
            blocked_load,
            save_saving,
            phone_reset,
            save_busy,
            save_error,
            (loader_failed || |overlay_error || |bt_error),
            status[16],
            (debug_error || lcd_unsupported || (|dma_error_pending) || mmc_hps_fault),
            debug_busy,
            debug_fault_seen,
            save_mounted,
            board_init_done,
            sdram_scrub_done,
            loader_valid,
            pll_locked
        }),
        .debug_freeze_trace(debug_freeze || telemetry_capture),
        .debug_read_word(debug_word),
        .debug_read_data(debug_read_data),
        .debug_values(diagnostic_values),
        .debug_char_valid(runtime_char_valid),
        .debug_char_data(runtime_char_data),
        .debug_fault_seen(debug_fault_seen),
        .lcd_unsupported(lcd_unsupported),
        .clk_sys(clk_sys),
        .reset(reset),
        .cold_reset(transport_reset),
        .board_init_done(board_init_done),
        .bus_lock(cpu_bus_lock),

        // SDRAM (phone RAM)
        .sdram_addr  (cpu_sdram_addr),
        .sdram_din   (cpu_sdram_din),
        .sdram_dout  (sdram_dout),
        .sdram_be    (cpu_sdram_be),
        .sdram_we    (cpu_sdram_we),
        .sdram_req   (cpu_sdram_req),
        .sdram_ack   (sdram_ack),
        .sdram_accept(cpu_sdram_accept),

        // DDR3 (flash reads)
        .ddram_addr        (core_ddr_addr),
        .ddram_fetch       (core_ddr_fetch),
        .ddram_rd          (core_ddr_rd),
        .ddram_wr          (core_ddr_wr),
        .ddram_din         (core_ddr_din),
        .ddram_be          (core_ddr_be),
        .ddram_dout        (core_ddr_dout),
        .ddram_dout_ready  (core_ddr_ready),
        .ddram_accept      (core_accept),
        .flash_dirty       (flash_dirty),
        .flash_dirty_sector(flash_dirty_sector),
        .flash_busy        (flash_busy),

        // video
        .ce_pix(core_ce_pix),
        .hsync (core_hsync),
        .vsync (core_vsync),
        .hblank(core_hblank),
        .vblank(core_vblank),
        .rgb444(core_rgb),

        // keys
        .keys(phone_keys)
    );

    ///////////////////////   VIDEO   ////////////////////////////////

    // 320×240 diagnostic raster; 176×208 phone pixels are centered within it.
    // Display-controller framebuffer storage is inside the phone board.

    assign CLK_VIDEO = clk_sys;
    assign CE_PIXEL  = core_ce_pix;

    assign VGA_DE = ~(core_hblank | core_vblank);
    assign VGA_HS = core_hsync;
    assign VGA_VS = core_vsync;
    // RGB444 → RGB888: expand 4-bit nibbles to 8-bit ({n,n} = ×17)
    assign VGA_R  = {core_rgb[11:8], core_rgb[11:8]};
    assign VGA_G  = {core_rgb[7:4], core_rgb[7:4]};
    assign VGA_B  = {core_rgb[3:0], core_rgb[3:0]};

    ///////////////////////   LED   //////////////////////////////////

    reg [26:0] act_cnt;
    always @(posedge clk_sys) act_cnt <= act_cnt + 1'd1;
    assign LED_USER = (loader_failed || save_error || blocked_load || debug_error) ?
        act_cnt[22] : (bundle_download || save_saving || save_busy || debug_busy) ?
        act_cnt[25] : (save_mounted && save_saved);

endmodule
