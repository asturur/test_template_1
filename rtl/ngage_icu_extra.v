// Staged ICU configuration, DMA programming latches, and epbus clock bank.
// Starting LCD DMA requires a real engine and is rejected rather than
// acknowledging a transfer that did not occur.
module ngage_icu_extra(
 input wire clk, reset, req, commit, we, periodic_active,
 input wire [31:0] addr, din, input wire [3:0] sel,
 output reg claim, bad, output reg [31:0] dout, input wire cbus8d_written, output reg sysc74_seen
);
 wire [31:0] a={addr[31:2],2'b00};
 wire low=periodic_active && a>=32'h0c120040 && a<32'h0c120100 &&
          a!=32'h0c120050 && a!=32'h0c120064 && a!=32'h0c120068 && a!=32'h0c120074;
 wire dma=a>=32'h0c120300 && a<32'h0c120400;
 wire sysc74=a==32'h0c120074;
 wire probe14d=a>=32'h0c14d000 && a<=32'h0c14d010;
 wire epbus=a>=32'h0c120600 && a<32'h0c120700;
 reg [31:0] low_regs[0:47],dma_regs[0:63],epbus_regs[0:63],probe_regs[0:4];
 wire [31:0] mask={{8{sel[3]}},{8{sel[2]}},{8{sel[1]}},{8{sel[0]}}};
 integer i;
 always @* begin
  claim=req && (low || dma || epbus || sysc74 || probe14d);
  bad=claim && ((sysc74 && (!cbus8d_written || sel!=15 || !we || din!=3)) ||
     (probe14d && !sysc74_seen) ||
     (!probe14d && !sysc74 && sel!=15) ||
     (dma && a==32'h0c120348 && we && din==2));
  dout=0;
  if(claim && !bad)begin
   if(low)dout=low_regs[(a-32'h0c120040)>>2];
   else if(dma)dout=dma_regs[a[7:2]];
   else if(epbus)dout=epbus_regs[a[7:2]];
   else if(probe14d)dout=probe_regs[(a-32'h0c14d000)>>2] & mask;
  end
 end
 always @(posedge clk)begin
  if(reset)begin
   sysc74_seen<=0;
   for(i=0;i<5;i=i+1)probe_regs[i]<=0;
   for(i=0;i<48;i=i+1)low_regs[i]<=0;
   for(i=0;i<64;i=i+1)begin dma_regs[i]<=0;epbus_regs[i]<=0;end
  end else if(commit && claim && !bad && we)begin
   if(low)low_regs[(a-32'h0c120040)>>2]<=din;
   else if(dma)dma_regs[a[7:2]]<=din;
   else if(epbus)epbus_regs[a[7:2]]<=din;
   else if(sysc74)sysc74_seen<=1;
   else if(probe14d)probe_regs[(a-32'h0c14d000)>>2]<=
       (probe_regs[(a-32'h0c14d000)>>2]&~mask)|(din&mask);
  end
 end
endmodule
