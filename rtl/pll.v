// N-Gage PLL: 50 MHz in → 78 MHz system clock + 78 MHz unused second output (−90°)
// Generated wrapper for Quartus altera_pll megafunction

`timescale 1 ps / 1 ps
module pll (
	input  wire  refclk,     //  50 MHz reference
	input  wire  rst,        //  reset
	output wire  outclk_0,   //  78 MHz system (CPU, bus, board devices)
	output wire  outclk_1,   //  unused 78 MHz output (−90° phase)
	output wire  locked      //  PLL locked
);

	pll_0002 pll_inst (
		.refclk   (refclk),
		.rst      (rst),
		.outclk_0 (outclk_0),
		.outclk_1 (outclk_1),
		.locked   (locked)
	);

endmodule
