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

// SDRAM active during run; directly driven by the core at 104 MHz.
// Phone RAM = 16MB at PA 0x0a000000.
// The −90° phase-shifted clock goes to the SDRAM chip.
assign SDRAM_CLK = clk_sdram;
assign SDRAM_CKE = 1'b1;

// TODO: SDRAM controller instantiation here.
// Candidates: jtframe_sdram, or a simple single-port controller.
// The N-Gage needs only one master (CPU) for the phone's 16MB RAM.
// No video refresh from SDRAM (framebuffer is in BRAM).

// Directly connect SDRAM pins to the controller (stub for now)
wire [31:0] sdram_dout;
wire        sdram_ack;

// Stub: SDRAM not yet connected — directly drives 'Z
assign SDRAM_DQ   = 16'hZZZZ;
assign SDRAM_A    = 13'd0;
assign SDRAM_BA   = 2'd0;
assign SDRAM_DQML = 1'b1;
assign SDRAM_DQMH = 1'b1;
assign SDRAM_nWE  = 1'b1;
assign SDRAM_nCAS = 1'b1;
assign SDRAM_nRAS = 1'b1;
assign SDRAM_nCS  = 1'b1;

assign sdram_dout = 32'd0;
assign sdram_ack  = 1'b0;

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

// TODO: arbitrate download writes vs CPU reads during run.
// During download the CPU is in reset so no conflict.
assign DDRAM_ADDR = dl_addr;
assign DDRAM_DIN  = dl_data;
assign DDRAM_BE   = 4'b1111;
assign DDRAM_RD   = 1'b0;       // TODO: CPU flash reads
assign DDRAM_WE   = dl_wr;

///////////////////////   CORE   /////////////////////////////////

// TODO: instantiate ngage_mister with:
//   - clk_sys (104 MHz)
//   - SDRAM port (phone RAM)
//   - DDR3 port (flash reads, after ioctl arbitration)
//   - video out
//   - keys from joystick_0

///////////////////////   VIDEO   ////////////////////////////////

// 176×208 at ~60Hz, centered by the MiSTer scaler.
// The framebuffer lives in BRAM inside ngage_board (filled by LCD DMA).
// For now: blank output.

assign CLK_VIDEO = clk_sys;
assign CE_PIXEL  = 1'b0;

assign VGA_DE = 1'b0;
assign VGA_HS = 1'b0;
assign VGA_VS = 1'b0;
assign VGA_G  = 8'd0;
assign VGA_R  = 8'd0;
assign VGA_B  = 8'd0;

///////////////////////   LED   //////////////////////////////////

reg [26:0] act_cnt;
always @(posedge clk_sys) act_cnt <= act_cnt + 1'd1;
assign LED_USER = act_cnt[26] ? act_cnt[25:18] > act_cnt[7:0] : act_cnt[25:18] <= act_cnt[7:0];

endmodule
