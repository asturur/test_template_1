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
wire phone_reset = RESET | status[0] | buttons[1] | ~pll_locked;
wire reset = phone_reset | !loader_valid | 1'b1;
wire ioctl_upload, ioctl_rd;

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

// 32-bit CPU word → two 16-bit SDRAM halfword accesses.
// Phase: 0 = low halfword, 1 = high halfword.
reg         sdram_phase;
reg         sdram_pending;
reg  [31:0] sdram_rdata;       // assembled 32-bit read result
wire        sdram_init;

// Bank select from address bit 23
wire        ba_sel = cpu_sdram_addr[23];

// Halfword address within the 8MB bank (AW=22 = 4M halfwords)
wire [21:0] sdram_haddr = {cpu_sdram_addr[22:2], sdram_phase};

// Write data: select low or high halfword
wire [15:0] sdram_wdata = sdram_phase ? cpu_sdram_din[31:16] : cpu_sdram_din[15:0];

// Write mask (active low for SDRAM): derive from byte enables
wire [1:0]  sdram_dsn = sdram_phase ?
    {~cpu_sdram_be[3], ~cpu_sdram_be[2]} :
    {~cpu_sdram_be[1], ~cpu_sdram_be[0]};

// SDRAM controller read/write strobes
wire [3:0] sdram_rd_banks = sdram_pending && !cpu_sdram_we ?
    (ba_sel ? 4'b0010 : 4'b0001) : 4'b0000;
wire [3:0] sdram_wr_banks = sdram_pending && cpu_sdram_we ?
    (ba_sel ? 4'b0010 : 4'b0001) : 4'b0000;

wire [3:0]  sdram_ack_banks;
wire [3:0]  sdram_rdy_banks;
wire [15:0] sdram_dout_16;

// 32-bit ack to the core: both halfwords done
wire sdram_ack  = sdram_phase && (sdram_ack_banks[0] || sdram_ack_banks[1]);
wire [31:0] sdram_dout = {sdram_dout_16, sdram_rdata[15:0]};

always @(posedge clk_sys) begin
    if (reset || sdram_init) begin
        sdram_phase   <= 0;
        sdram_pending <= 0;
        sdram_rdata   <= 32'd0;
    end else begin
        if (cpu_sdram_req && !sdram_pending) begin
            sdram_pending <= 1;
            sdram_phase   <= 0;
        end
        if (sdram_pending && (sdram_ack_banks[0] || sdram_ack_banks[1])) begin
            if (!sdram_phase) begin
                sdram_rdata[15:0] <= sdram_dout_16;
                sdram_phase <= 1;
            end else begin
                sdram_pending <= 0;
                sdram_phase   <= 0;
            end
        end
    end
end

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
    .rst        (reset),
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
    .rfsh       (1'b0),

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
wire loader_valid, loader_failed;
wire load_req, load_ready, load_done;
wire [31:0] load_addr, load_data;
wire [3:0] load_be;
wire bundle_download = ioctl_download && ioctl_index == 0;
ngage_loader loader (
 .clk(clk_sys), .reset(transport_reset), .download(bundle_download),
 .wr(ioctl_wr), .addr(ioctl_addr), .data(ioctl_dout), .wait_req(ioctl_wait),
 .valid(loader_valid), .failed(loader_failed),
 .mem_valid(load_req), .mem_ready(load_ready), .mem_addr(load_addr),
 .mem_data(load_data), .mem_be(load_be), .mem_done(load_done)
);
wire [31:0] core_ddr_addr;
wire core_ddr_rd;
wire [31:0] core_ddr_dout;
wire core_ddr_ready;
wire arb_valid, arb_ready, arb_write, arb_rsp;
wire [31:0] arb_addr, arb_data, arb_rdata;
wire [3:0] arb_be;
wire core_accept;
reg core_inflight = 0;
// The legacy core presents a level request; accept each request only once.
always @(posedge clk_sys) begin
 if (reset) core_inflight <= 0;
 else if (!core_ddr_rd) core_inflight <= 0;
 else if (core_accept) core_inflight <= 1;
end
ngage_ddr_arbiter ddr_arbiter (
 .clk(clk_sys), .reset(transport_reset), .cpu_lock(cpu_bus_lock && !reset),
 .l_valid(load_req), .l_ready(load_ready), .l_addr(load_addr), .l_data(load_data), .l_be(load_be), .l_done(load_done),
 .c_valid(core_ddr_rd && !core_inflight && !reset), .c_ready(core_accept), .c_write(1'b0),
 .c_addr(core_ddr_addr), .c_data(32'd0), .c_be(4'hf), .c_done(core_ddr_ready), .c_rdata(core_ddr_dout),
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
	.ddram_wr      (),
	.ddram_din     (),
	.ddram_be      (),
	.ddram_dout    (core_ddr_dout),
	.ddram_dout_ready(core_ddr_ready),

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
assign LED_USER = loader_failed ? act_cnt[24] : (bundle_download ? act_cnt[22] : loader_valid);

endmodule
