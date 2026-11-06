// D550 audio DSP model boundary. Only the existing synthetic MDI ring is
// modeled: this is not a DSP implementation or the physical AMA-WD2 bus.
module ngage_adsp(
 input wire clk,reset,tick,periodic_active,req,commit,we,
 input wire [31:0] addr,din,input wire [3:0] sel,
 output wire claim,bad,output wire [31:0] dout,output wire [15:0] irq_events
);
 ngage_mdi_stub mdi(.clk(clk),.reset(reset),.tick(tick),.periodic_active(periodic_active),
  .req(req),.commit(commit),.we(we),.addr(addr),.din(din),.sel(sel),
  .claim(claim),.bad(bad),.dout(dout),.irq_events(irq_events));
endmodule
