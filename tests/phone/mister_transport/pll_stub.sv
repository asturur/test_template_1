// Elaboration-only substitute for Intel's unavailable PLL simulation library.
// This is not a clock or timing model and is never included in files.qip.
module pll(input refclk,input rst,output outclk_0,output outclk_1,output locked);
assign outclk_0=refclk; assign outclk_1=refclk; assign locked=!rst;
endmodule
