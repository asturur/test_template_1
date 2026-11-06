`timescale 1ns/1ps
module tb;
reg resetx=0,clock=0;reg [3:0] gpp_i=0;
wire btd,bt_oe,bt_impl,rfd,rf_oe,rf_impl;wire [3:0] gpp_o,gpp_oe;
ngage_lrb2 bt(.resetx(resetx),.sleepx(resetx),.sysclk(clock),.slpclk(clock),
 .cbusclk(clock),.cenx(resetx),.cbusdata_i(clock),.cbusdata_o(btd),.cbusdata_oe(bt_oe),
 .gpp_i(gpp_i),.gpp_o(gpp_o),.gpp_oe(gpp_oe),.model_implemented(bt_impl));
ngage_mjoelner rf(.resetx(resetx),.rfbusclk(clock),.rfbusenx(resetx),.rfbusda_i(clock),
 .rfbusda_o(rfd),.rfbusda_oe(rf_oe),.model_implemented(rf_impl));
initial begin
 repeat(4)begin #1;resetx=~resetx;clock=~clock;gpp_i=~gpp_i;#1;
  if(bt_oe!==0 || gpp_oe!==0 || rf_oe!==0 || bt_impl!==0 || rf_impl!==0)begin
   $display("FAIL unimplemented radio boundary drives a signal");$finish;
  end
 end
 $display("PASS unimplemented radio components stay non-driving");$finish;
end
endmodule
