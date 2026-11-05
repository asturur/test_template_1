// Simulation bus adapter. The caller must dispatch to the C++ model only
// when fallback is asserted; claimed requests are owned exclusively here.
module ngage_board_sim(
 input wire clk, reset, cold_reset,
 input wire cyc, stb, we, input wire [31:0] adr, din, input wire [3:0] sel,
 output wire claim, fallback, ack, err, output wire [31:0] dout,
 output wire irq, fiq, init_done, trace_valid,
 output wire [31:0] trace_addr, trace_data, output wire [3:0] trace_sel
);
 wire ready, bad;
 assign fallback = cyc && stb && !claim;
 assign ack = claim && ready && !bad;
 assign err = claim && ready && bad;
 ngage_board board(.clk(clk),.rst(reset),.init_rst(cold_reset),
  .cyc(cyc),.stb(stb),.we(we),.adr(adr),.din(din),.sel(sel),.commit(ack),
  .cfg_lcd(1'b1),.cfg_keypad(1'b1),.cfg_clocks(1'b1),
  .claim(claim),.ready(ready),.dout(dout),.unmodeled(bad),
  .irq(irq),.fiq(fiq),.init_done(init_done),.trace_valid(trace_valid),
  .trace_addr(trace_addr),.trace_data(trace_data),.trace_sel(trace_sel));
endmodule
