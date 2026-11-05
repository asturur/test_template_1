//============================================================================
//
//  N-Gage MiSTer core — Template.sv (emu module)
//  104 MHz CPU + SDRAM, DDR3 for ROM/flash, BRAM framebuffer
//
//============================================================================

module emu
(
	`include "sys/emu_ports.vh"
);

///////// Default values for ports not used in this core /////////

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;

assign VGA_SL = 0;
assign VGA_F1 = 0;
assign VGA_SCALER  = 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

assign AUDIO_S = 0;
assign AUDIO_L = 0;
assign AUDIO_R = 0;
assign AUDIO_MIX = 0;

assign LED_DISK = 0;
assign LED_POWER = 0;
assign BUTTONS = 0;

//////////////////////////////////////////////////////////////////

wire [1:0] ar = status[122:121];

assign VIDEO_ARX = (!ar) ? 12'd4 : (ar - 1'd1);
assign VIDEO_ARY = (!ar) ? 12'd3 : 12'd0;

`include "build_id.v"
localparam CONF_STR = {
	"NGage;;",
	"-;",
	"O[122:121],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"-;",
	"F0,NGB,Load firmware bundle;",
	"S0,NGA,Mount working save;",
	"T[14],Flush working save;",
	"-;",
	"-;",
	"T[0],Reset;",
	"R[0],Reset and close OSD;",
	"v,0;",
	"V,v",`BUILD_DATE
};

wire forced_scandoubler;
wire   [1:0] buttons;
wire [127:0] status;
wire  [10:0] ps2_key;
wire  [31:0] joystick_0;

// One validated versioned bundle (core, extension, C: and PMM).
wire        ioctl_download;
wire        ioctl_wr;
wire [26:0] ioctl_addr;
wire [15:0] ioctl_dout;
wire [15:0] ioctl_index;
wire        ioctl_wait;

hps_io #(.CONF_STR(CONF_STR), .WIDE(1)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),
	.gamma_bus(),

	.forced_scandoubler(forced_scandoubler),

	.buttons(buttons),
	.status(status),
	.status_menumask(0),

	.ps2_key(ps2_key),
	.joystick_0(joystick_0),

	.ioctl_download(ioctl_download),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_index(ioctl_index),
	.ioctl_wait(ioctl_wait),
 .img_mounted(img_mounted), .img_readonly(img_readonly), .img_size(img_size),
 .sd_lba(sd_lba), .sd_blk_cnt(sd_blk_cnt), .sd_rd(sd_rd), .sd_wr(sd_wr), .sd_ack(sd_ack),
 .sd_buff_addr(sd_buff_addr), .sd_buff_dout(sd_buff_dout), .sd_buff_din(sd_buff_din), .sd_buff_wr(sd_buff_wr),

	// C: drive save (upload DDR3 → SD card)
	.ioctl_upload(ioctl_upload),
	.ioctl_upload_req(1'b0),
	.ioctl_upload_index(8'h00),
	.ioctl_din(16'hffff),
	.ioctl_rd(ioctl_rd)
);

///////////////////////   CLOCKS   ///////////////////////////////

wire clk_sys;          // 104 MHz — CPU, bus, board devices, SDRAM logic
wire clk_sdram;        // 104 MHz −90° — SDRAM chip clock pin
wire pll_locked;

pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_sys),
	.outclk_1(clk_sdram),
	.locked(pll_locked)
);

// Keep the phone CPU held during transport bring-up. SDRAM and board
// initialization are not yet safe to boot (milestone 2 and later).
wire transport_reset = ~pll_locked;
wire phone_reset;
ngage_reset_gate phone_reset_gate(.clk(clk_sys), .cold_reset(transport_reset),
 .reset_request(RESET | status[0] | buttons[1]), .block_reset(save_saving || save_busy), .phone_reset(phone_reset));
wire reset = phone_reset | !loader_valid | !sdram_scrub_done | !save_mounted | 1'b1;
wire ioctl_upload, ioctl_rd;
wire [0:0] img_mounted,sd_rd,sd_wr,sd_ack;
wire img_readonly;wire [63:0] img_size;
wire [31:0] sd_lba[1];wire [5:0] sd_blk_cnt[1];
wire [12:0] sd_buff_addr;wire [15:0] sd_buff_dout;wire [15:0] sd_buff_din[1];wire sd_buff_wr;
assign sd_blk_cnt[0]=0;

///////////////////////   SDRAM   ////////////////////////////////

// SDRAM: phone RAM 16MB at PA 0x0a000000, split across BA0 (low 8MB)
// and BA1 (high 8MB). AW=22 matches DE10 SDRAM geometry (8MB/bank).
// 104 MHz system clock, phase-shifted copy to SDRAM chip pin.
assign SDRAM_CLK = clk_sdram;

// CPU → SDRAM address/data decode
// ngage_mister outputs: sdram_addr[24:0], sdram_din[31:0], sdram_be[3:0],
//                       sdram_we, sdram_req
// Phone PA bit 23 (= sdram_addr[23]) selects BA0 vs BA1.
wire [24:0] cpu_sdram_addr;
wire [31:0] cpu_sdram_din;
wire [3:0]  cpu_sdram_be;
wire        cpu_sdram_we;
wire        cpu_sdram_req;
// No competing phone-memory master is wired yet. Future DMA arbitration must
// preserve the CPU bus reservation while this signal is asserted.
wire        cpu_bus_lock;

// The adapter owns an entire 32-bit access, including both halfwords.
// Cold-start RAM scrub proceeds while the phone CPU remains held in reset.
wire [21:0] sdram_haddr;
wire [15:0] sdram_wdata, sdram_dout_16;
wire [1:0] sdram_dsn;
wire [3:0] sdram_rd_banks, sdram_wr_banks, sdram_ack_banks, sdram_rdy_banks;
wire sdram_init, sdram_rfsh, sdram_scrub_done, sdram_ack;
wire [31:0] sdram_dout;
wire mem_req, mem_we, mem_ack;
wire [24:0] mem_addr;
wire [31:0] mem_wdata, mem_rdata;
wire [3:0] mem_be;
// LCD DMA has not been migrated yet; it must connect to the second port.
ngage_sdram_arbiter ram_arbiter (
 .clk(clk_sys), .reset(phone_reset), .cpu_lock(cpu_bus_lock),
 .cpu_req(cpu_sdram_req), .cpu_we(cpu_sdram_we), .cpu_addr(cpu_sdram_addr),
 .cpu_data(cpu_sdram_din), .cpu_be(cpu_sdram_be), .cpu_ack(sdram_ack), .cpu_rdata(sdram_dout),
 .dma_req(1'b0), .dma_we(1'b0), .dma_addr(25'b0), .dma_data(32'b0), .dma_be(4'b0),
 .dma_ack(), .dma_rdata(), .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr),
 .mem_data(mem_wdata), .mem_be(mem_be), .mem_ack(mem_ack), .mem_rdata(mem_rdata)
);
ngage_sdram_adapter phone_sdram (
 .clk(clk_sys), .rst(transport_reset), .phone_reset(phone_reset), .init(sdram_init),
 .req(mem_req), .we(mem_we), .addr(mem_addr),
 .din(mem_wdata), .be(mem_be), .ack(mem_ack), .dout(mem_rdata),
 .scrub_done(sdram_scrub_done), .ba_addr(sdram_haddr), .ba_din(sdram_wdata),
 .ba_dsn(sdram_dsn), .rd(sdram_rd_banks), .wr(sdram_wr_banks),
 .ba_ack(sdram_ack_banks), .ba_rdy(sdram_rdy_banks), .ba_dout(sdram_dout_16), .rfsh(sdram_rfsh)
);

jtframe_sdram64 #(
    .AW       (22),
    .HF       (1),        // 104 MHz > 66 MHz → HF mode
    .BA0_LEN  (16),       // 16-bit single reads
    .BA1_LEN  (16),
    .BA2_LEN  (16),
    .BA3_LEN  (16),
    .PROG_LEN (16),       // must match BA_LEN to avoid state vector overflow
    .BA0_WEN  (1),        // phone RAM is read+write
    .BA1_WEN  (1),
    .BA2_WEN  (0),
    .BA3_WEN  (0)
) sdram_ctrl (
    .rst        (transport_reset),
    .clk        (clk_sys),
    .init       (sdram_init),

    // BA0: phone RAM low 8MB
    .ba0_addr   (sdram_haddr),
    .ba0_din    (sdram_wdata),
    .ba0_dsn    (sdram_dsn),

    // BA1: phone RAM high 8MB
    .ba1_addr   (sdram_haddr),
    .ba1_din    (sdram_wdata),
    .ba1_dsn    (sdram_dsn),

    // BA2/BA3: unused
    .ba2_addr   (22'd0),
    .ba2_din    (16'd0),
    .ba2_dsn    (2'b11),
    .ba3_addr   (22'd0),
    .ba3_din    (16'd0),
    .ba3_dsn    (2'b11),

    .rd         (sdram_rd_banks),
    .wr         (sdram_wr_banks),
    .rfsh       (sdram_rfsh),

    .ack        (sdram_ack_banks),
    .dst        (),
    .dok        (),
    .rdy        (sdram_rdy_banks),
    .dout       (sdram_dout_16),

    // programming port (unused — ROM goes via DDR3)
    .prog_en    (1'b0),
    .prog_addr  (22'd0),
    .prog_rd    (1'b0),
    .prog_wr    (1'b0),
    .prog_din   (16'd0),
    .prog_dsn   (2'b11),
    .prog_ba    (2'd0),
    .prog_dst   (),
    .prog_dok   (),
    .prog_rdy   (),
    .prog_ack   (),

    // SDRAM chip pins
    .sdram_dq   (SDRAM_DQ),
    .sdram_a    (SDRAM_A),
    .sdram_dqml (SDRAM_DQML),
    .sdram_dqmh (SDRAM_DQMH),
    .sdram_ba   (SDRAM_BA),
    .sdram_nwe  (SDRAM_nWE),
    .sdram_ncas (SDRAM_nCAS),
    .sdram_nras (SDRAM_nRAS),
    .sdram_ncs  (SDRAM_nCS),
    .sdram_cke  (SDRAM_CKE)
);

///////////////////////   DDR3 bundle transport   ////////////////
// 0x30000000 is a candidate Main DDR reservation; hardware use is
// prohibited until checked against the installed Main/Linux memory map.
assign DDRAM_CLK = clk_sys;
assign DDRAM_BURSTCNT = 8'd1;
wire loader_valid, loader_failed, loader_known_firmware;
wire [1:0] loader_profile;
wire load_req, load_ready, load_done;
wire [31:0] load_addr, load_data;
wire [3:0] load_be;
wire save_mounted,save_saving,save_saved,save_error,save_busy;
// Do not replace backing memory while a save is mounted or being processed.
wire bundle_download = ioctl_download && ioctl_index == 0 && !save_mounted && !save_busy && !save_error;
reg blocked_load=0;
always @(posedge clk_sys) begin
 if(transport_reset) blocked_load<=0;
 else if(ioctl_download && ioctl_index==0 && !bundle_download) blocked_load<=1;
 else if(bundle_download) blocked_load<=0;
end
ngage_loader loader (
 .clk(clk_sys), .reset(transport_reset), .download(bundle_download),
 .wr(ioctl_wr), .addr(ioctl_addr), .data(ioctl_dout), .wait_req(ioctl_wait),
 .valid(loader_valid), .failed(loader_failed),
 .mem_valid(load_req), .mem_ready(load_ready), .mem_addr(load_addr),
 .mem_data(load_data), .mem_be(load_be), .mem_done(load_done),
 .image_profile(loader_profile), .known_firmware(loader_known_firmware)
);
wire [31:0] core_ddr_addr;
wire core_ddr_rd, core_ddr_wr;
wire [31:0] core_ddr_din;
wire [3:0] core_ddr_be;
wire flash_dirty,flash_busy;
wire [13:0] flash_dirty_sector;
wire [31:0] core_ddr_dout;
wire core_ddr_ready;
wire arb_valid, arb_ready, arb_write, arb_rsp;
wire [31:0] arb_addr, arb_data, arb_rdata;
wire [3:0] arb_be;
wire core_accept;
// Flash modules retain a request until core_accept, and drain accepted
// operations across phone reset. Do not gate their backing traffic on reset.
// The first arbiter shares the loader and save engine; the second shares
// their registered transaction stream with the phone while honoring SWP lock.
wire save_mem_valid,save_mem_ready,save_mem_write,save_mem_done;
wire [31:0] save_mem_addr,save_mem_data,save_mem_rdata;wire [3:0] save_mem_be;
wire aux_valid,aux_ready,aux_write,aux_done;wire [31:0] aux_addr,aux_data,aux_rdata;wire [3:0] aux_be;
ngage_ddr_arbiter auxiliary_arbiter (
 .clk(clk_sys), .reset(transport_reset), .cpu_lock(1'b0),
 .l_valid(load_req), .l_ready(load_ready), .l_addr(load_addr), .l_data(load_data), .l_be(load_be), .l_done(load_done), .l_write(1'b1), .l_rdata(),
 .c_valid(save_mem_valid), .c_ready(save_mem_ready), .c_write(save_mem_write), .c_addr(save_mem_addr), .c_data(save_mem_data), .c_be(save_mem_be), .c_done(save_mem_done), .c_rdata(save_mem_rdata),
 .req_valid(aux_valid), .req_ready(aux_ready), .req_write(aux_write), .req_addr(aux_addr), .req_data(aux_data), .req_be(aux_be), .rsp_valid(aux_done), .rsp_data(aux_rdata)
);
ngage_ddr_arbiter ddr_arbiter (
 .clk(clk_sys), .reset(transport_reset), .cpu_lock(cpu_bus_lock && !reset),
 .l_valid(aux_valid), .l_ready(aux_ready), .l_addr(aux_addr), .l_data(aux_data), .l_be(aux_be), .l_done(aux_done), .l_write(aux_write), .l_rdata(aux_rdata),
 .c_valid(core_ddr_rd || core_ddr_wr), .c_ready(core_accept), .c_write(core_ddr_wr),
 .c_addr(core_ddr_addr), .c_data(core_ddr_din), .c_be(core_ddr_be), .c_done(core_ddr_ready), .c_rdata(core_ddr_dout),
 .req_valid(arb_valid), .req_ready(arb_ready), .req_write(arb_write),
 .req_addr(arb_addr), .req_data(arb_data), .req_be(arb_be), .rsp_valid(arb_rsp), .rsp_data(arb_rdata)
);
ngage_ddr_adapter ddr_adapter (
 .clk(clk_sys), .reset(transport_reset), .req_valid(arb_valid), .req_ready(arb_ready),
 .req_write(arb_write), .req_addr(arb_addr), .req_wdata(arb_data), .req_be(arb_be),
 .rsp_valid(arb_rsp), .rsp_data(arb_rdata), .ddr_addr(DDRAM_ADDR), .ddr_din(DDRAM_DIN),
 .ddr_be(DDRAM_BE), .ddr_rd(DDRAM_RD), .ddr_we(DDRAM_WE), .ddr_busy(DDRAM_BUSY),
 .ddr_dout(DDRAM_DOUT), .ddr_dout_ready(DDRAM_DOUT_READY)
);

// Only the audited stock core/extension are currently supported. The loader
// verifies their CRCs; these SHA values bind the mounted save header to that
// profile but are not computed in FPGA (CRC is not cryptographic identity).
reg flush_prev=0;
always @(posedge clk_sys) flush_prev<=status[14];
ngage_save_manager saves (
 .clk(clk_sys), .reset(transport_reset), .mount(img_mounted[0]), .readonly_image(img_readonly), .image_size(img_size),
 .bundle_verified(loader_valid && loader_known_firmware && !ioctl_download), .profile(loader_profile),
 .core_sha_le(256'h24b589715a8ddf962b0d8974aec0651f1d3ab9a83888b524f481fff5cd2e8bbe),
 .extension_sha_le(256'hf36c44302d1797f385c9f33f5c4f1e2b37247652ee21fc6408f00dc9390b6ecb),
 .dirty_valid(flash_dirty), .dirty_sector(flash_dirty_sector), .flush_start(status[14] && !flush_prev),
 .mounted(save_mounted), .saving(save_saving), .saved(save_saved), .error(save_error), .busy(save_busy),
 .mem_valid(save_mem_valid), .mem_ready(save_mem_ready), .mem_write(save_mem_write), .mem_addr(save_mem_addr),
 .mem_data(save_mem_data), .mem_be(save_mem_be), .mem_done(save_mem_done), .mem_rdata(save_mem_rdata),
 .sd_lba(sd_lba[0]), .sd_rd(sd_rd[0]), .sd_wr(sd_wr[0]), .sd_ack(sd_ack[0]),
 .hps_addr(sd_buff_addr), .hps_dout(sd_buff_dout), .hps_we(sd_buff_wr), .hps_din(sd_buff_din[0]), .flash_quiescent(!flash_busy)
);

///////////////////////   CORE   /////////////////////////////////

wire        core_ce_pix;
wire        core_hsync, core_vsync, core_hblank, core_vblank;
wire [11:0] core_rgb;

ngage_mister core (
	.clk_sys       (clk_sys),
	.reset         (reset),
	.bus_lock      (cpu_bus_lock),

	// SDRAM (phone RAM)
	.sdram_addr    (cpu_sdram_addr),
	.sdram_din     (cpu_sdram_din),
	.sdram_dout    (sdram_dout),
	.sdram_be      (cpu_sdram_be),
	.sdram_we      (cpu_sdram_we),
	.sdram_req     (cpu_sdram_req),
	.sdram_ack     (sdram_ack),

	// DDR3 (flash reads)
	.ddram_addr    (core_ddr_addr),
	.ddram_rd      (core_ddr_rd),
	.ddram_wr      (core_ddr_wr),
	.ddram_din     (core_ddr_din),
	.ddram_be      (core_ddr_be),
	.ddram_dout    (core_ddr_dout),
	.ddram_dout_ready(core_ddr_ready),
	.ddram_accept (core_accept),
	.flash_dirty (flash_dirty),
	.flash_dirty_sector (flash_dirty_sector),
	.flash_busy (flash_busy),

	// video
	.ce_pix        (core_ce_pix),
	.hsync         (core_hsync),
	.vsync         (core_vsync),
	.hblank        (core_hblank),
	.vblank        (core_vblank),
	.rgb444        (core_rgb),

	// keys
	.keys          (joystick_0[15:0])
);

///////////////////////   VIDEO   ////////////////////////////////

// 176×208 at ~60Hz, centered by the MiSTer scaler.
// The framebuffer lives in BRAM inside ngage_board (filled by LCD DMA).

assign CLK_VIDEO = clk_sys;
assign CE_PIXEL  = core_ce_pix;

assign VGA_DE = ~(core_hblank | core_vblank);
assign VGA_HS = core_hsync;
assign VGA_VS = core_vsync;
// RGB444 → RGB888: expand 4-bit nibbles to 8-bit ({n,n} = ×17)
assign VGA_R  = {core_rgb[11:8], core_rgb[11:8]};
assign VGA_G  = {core_rgb[ 7:4], core_rgb[ 7:4]};
assign VGA_B  = {core_rgb[ 3:0], core_rgb[ 3:0]};

///////////////////////   LED   //////////////////////////////////

reg [26:0] act_cnt;
always @(posedge clk_sys) act_cnt <= act_cnt + 1'd1;
assign LED_USER = (loader_failed || save_error || blocked_load) ? act_cnt[22] : (bundle_download || save_saving || save_busy) ? act_cnt[25] : (save_mounted && save_saved);

endmodule
