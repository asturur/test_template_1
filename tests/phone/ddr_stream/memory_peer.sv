// Independent byte-addressed physical peer. BUSY and read gaps vary; first
// response may coincide with command acceptance. No client-interface knowledge.
module memory_peer # (parameter SEED=1) (
 input wire clk,input wire [28:0] address,input wire [63:0] data,
 input wire [7:0] mask,count,input wire rd,wr,
 output wire busy,output wire ready,output reg [63:0] q,
 input wire hold_busy,input wire hold_data
);
 reg [7:0] bytes[0:8191];reg [31:0] rng=SEED;
 integer pending=0,next_address=0,reads=0,writes=0,beats=0;
 wire first=rd&&!busy;
 wire early=first&&rng[3];
 wire later=pending!=0&&rng[4]&&!hold_data;
 assign busy=hold_busy||rng[1:0]==0;
 assign ready=early||later;
 integer j;
 always @* begin
  q=0;
  for(integer k=0;k<8;k=k+1)q[k*8+:8]=bytes[((early?address*8:next_address)+k)&8191];
 end
 initial for(integer k=0;k<8192;k=k+1)bytes[k]=(k*43)^(k>>7)^8'hc5;
 always @(posedge clk)begin
  rng<={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
  if(first)begin
   if(pending!=0||count<1||count>64)$fatal(1,"overlapping/invalid physical read");
   pending<=count-(early?1:0);next_address<=address*8+(early?8:0);reads<=reads+1;
  end else if(later)begin pending<=pending-1;next_address<=next_address+8;end
  if(ready)beats<=beats+1;
  if(wr&&!busy)begin
   if(count!=1||rd)$fatal(1,"physical write burst/overlap");
   for(j=0;j<8;j=j+1)if(mask[j])bytes[((address*8)+j)&8191]<=data[j*8+:8];writes<=writes+1;
  end
 end
endmodule
