// N-Gage PLL: 50 MHz in → 104 MHz system clock + 104 MHz SDRAM clock (−90°)
// Generated wrapper for Quartus altera_pll megafunction

`timescale 1 ps / 1 ps
module pll (
	input  wire  refclk,     //  50 MHz reference
	input  wire  rst,        //  reset
	output wire  outclk_0,   //  104 MHz system (CPU, bus, board devices)
	output wire  outclk_1,   //  104 MHz SDRAM chip clock (−90° phase)
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
