// Staged ICU configuration, DMA programming latches, and epbus clock bank.
// Starting LCD DMA requires a real engine and is rejected rather than
// acknowledging a transfer that did not occur.
module ngage_icu_extra(
 input wire clk, reset, req, commit, we, periodic_active,
 input wire [31:0] addr, din, input wire [3:0] sel,
 output reg claim, bad, output reg [31:0] dout
);
 wire [31:0] a={addr[31:2],2'b00};
 wire low=periodic_active && a>=32'h0c120040 && a<32'h0c120100 &&
          a!=32'h0c120050 && a!=32'h0c120064 && a!=32'h0c120068 && a!=32'h0c120074;
 wire dma=a>=32'h0c120300 && a<32'h0c120400;
 wire epbus=a>=32'h0c120600 && a<32'h0c120700;
 reg [31:0] low_regs[0:47],dma_regs[0:63],epbus_regs[0:63];
 integer i;
 always @* begin
  claim=req && (low || dma || epbus);
  bad=claim && (sel!=4'hf || (dma && a==32'h0c120348 && we && din==2));
  dout=0;
  if(claim && !bad)begin
   if(low)dout=low_regs[(a-32'h0c120040)>>2];
   else if(dma)dout=dma_regs[a[7:2]];
   else dout=epbus_regs[a[7:2]];
  end
 end
 always @(posedge clk)begin
  if(reset)begin
   for(i=0;i<48;i=i+1)low_regs[i]<=0;
   for(i=0;i<64;i=i+1)begin dma_regs[i]<=0;epbus_regs[i]<=0;end
  end else if(commit && claim && !bad && we)begin
   if(low)low_regs[(a-32'h0c120040)>>2]<=din;
   else if(dma)dma_regs[a[7:2]]<=din;
   else epbus_regs[a[7:2]]<=din;
  end
 end
endmodule
