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

// ioctl (HPS data loading: ROM, extension, C: image)
wire        ioctl_download;
wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire [15:0] ioctl_dout;
wire  [7:0] ioctl_index;

hps_io #(.CONF_STR(CONF_STR)) hps_io
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
	.ioctl_index(ioctl_index)
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

wire reset = RESET | status[0] | buttons[1] | ~pll_locked;

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
// Layout: CS0 at 0, CS1 at 0x800000, CS2 at 0xC00000, C: at 0x1400000

// During download: HPS writes to DDR3 via ioctl
// During run: CPU reads flash through the core's PA decode

assign DDRAM_CLK      = clk_sys;
assign DDRAM_BURSTCNT = 8'd1;

// TODO: arbitrate ioctl writes (download) vs CPU reads (run).
// For now, stub — ROM loading path only.
assign DDRAM_ADDR = ioctl_download ? {3'd0, ioctl_addr} : 28'd0;
assign DDRAM_DIN  = {16'd0, ioctl_dout};
assign DDRAM_BE   = ioctl_download ? 4'b0011 : 4'b0000;
assign DDRAM_RD   = 1'b0;
assign DDRAM_WE   = ioctl_download && ioctl_wr;

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
