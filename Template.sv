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
	"F0,BIN,Load ROM (core.bin);",
	"-;",
	"RE,Save C: drive;",
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
wire  [15:0] joystick_0;

// ioctl (HPS data loading: boot ROMs from games/NGage/)
// boot.rom  = core.bin (18.6MB, main firmware)  → ioctl_index[7:6]=00
// boot1.rom = extension.bin (2.3MB)             → ioctl_index[7:6]=01
// boot2.rom = cdrive image (4MB LFFS)           → ioctl_index[7:6]=10
wire        ioctl_download;
wire        ioctl_wr;
wire [26:0] ioctl_addr;
wire [15:0] ioctl_dout;
wire  [7:0] ioctl_index;
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
	.ioctl_upload_req(save_cdrive_req),
	.ioctl_upload_index(8'h80),          // index[7:6]=10 = boot2.rom (C:)
	.ioctl_din(save_din),
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

wire reset = RESET | status[0] | buttons[1] | ~pll_locked | ioctl_download;

///////////////////////   C: DRIVE SAVE   ////////////////////////////

// "Save C: drive" OSD button (status bit E = 14) triggers upload
wire save_cdrive_btn = status[14];
reg  save_cdrive_btn_d;
reg  save_cdrive_req;
wire ioctl_upload;
wire ioctl_rd;

always @(posedge clk_sys) begin
	save_cdrive_btn_d <= save_cdrive_btn;
	if (save_cdrive_btn && !save_cdrive_btn_d)
		save_cdrive_req <= 1;
	else if (ioctl_upload)
		save_cdrive_req <= 0;
end

// During upload: read C: drive data from DDR3 and feed to ioctl_din
// The HPS drives ioctl_rd pulses; we respond with ioctl_din from DDR3.
// C: drive is at DDR3 word offset 0x500000 (0x1400000 >> 2), 4MB.
// TODO: wire DDR3 read port for upload (needs arbitration with CPU reads).
// For now: stub data.
wire [15:0] save_din = 16'hFFFF;  // TODO: DDR3 readback

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

///////////////////////   DDR3 (ROM flash)   /////////////////////

// DDR3 carries the ROM images (read-only from CPU; HPS writes via ioctl).
// Layout in DDR3 word address space:
//   boot.rom  (index[7:6]=00) → offset 0x000000 (CS0 flash, 8MB)
//   boot1.rom (index[7:6]=01) → offset 0x200000 (CS1/extension, 4MB)
//   boot2.rom (index[7:6]=10) → offset 0x350000 (C: drive image, 4MB)
// DDR3 word address = byte address >> 2 (32-bit words)

assign DDRAM_CLK      = clk_sys;
assign DDRAM_BURSTCNT = 8'd1;

// Boot ROM base offsets in DDR3 (word addresses)
// CS0=0, CS1=0x800000>>2=0x200000, C:=0x1400000>>2=0x350000 (adjusted)
reg [27:0] rom_base;
always @(*) case (ioctl_index[7:6])
	2'b00: rom_base = 28'h0000000;   // CS0 main firmware
	2'b01: rom_base = 28'h0200000;   // CS1 extension
	2'b10: rom_base = 28'h0500000;   // C: drive (0x1400000 >> 2)
	2'b11: rom_base = 28'h0700000;   // spare
endcase

// PSX-style 16→32 bit word assembly: collect two ioctl_wr pulses
wire rom_download = ioctl_download && (ioctl_index[5:0] == 6'd0);

reg [27:0] dl_addr;
reg [31:0] dl_data;
reg        dl_wr;

always @(posedge clk_sys) begin
	dl_wr <= 0;
	if (rom_download && ioctl_wr) begin
		if (~ioctl_addr[1]) begin
			// Low halfword: latch data and compute address
			dl_data[15:0] <= ioctl_dout;
			dl_addr       <= rom_base + ioctl_addr[26:2];
		end else begin
			// High halfword: complete the 32-bit word, trigger write
			dl_data[31:16] <= ioctl_dout;
			dl_wr          <= 1;
		end
	end
end

assign ioctl_wait = dl_wr;   // backpressure while DDR3 write in flight

// DDR3 arbitration: download (ioctl) vs CPU flash reads.
// During download the CPU is in reset so no conflict.
// During run: core drives DDR3 reads, ioctl is idle.
wire [27:0] core_ddr_addr;
wire        core_ddr_rd;
wire [31:0] core_ddr_dout;
wire        core_ddr_ready;

assign DDRAM_ADDR = ioctl_download ? dl_addr : core_ddr_addr;
assign DDRAM_DIN  = dl_data;
assign DDRAM_BE   = ioctl_download ? 4'b1111 : 4'b1111;
assign DDRAM_RD   = ioctl_download ? 1'b0    : core_ddr_rd;
assign DDRAM_WE   = dl_wr;

assign core_ddr_dout  = DDRAM_DOUT[31:0];   // low 32 bits of 64-bit DDR3 read
assign core_ddr_ready = DDRAM_DOUT_READY;

///////////////////////   CORE   /////////////////////////////////

wire        core_ce_pix;
wire        core_hsync, core_vsync, core_hblank, core_vblank;
wire [11:0] core_rgb;

ngage_mister core (
	.clk_sys       (clk_sys),
	.reset         (reset),

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
	.keys          (joystick_0)
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
assign LED_USER = act_cnt[26] ? act_cnt[25:18] > act_cnt[7:0] : act_cnt[25:18] <= act_cnt[7:0];

endmodule
