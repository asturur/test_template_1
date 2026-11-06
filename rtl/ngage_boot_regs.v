// Boot-controller latches and executable scratch. A byte is readable only
// after the firmware wrote it, except the documented zero-reset 0x08000040.
module ngage_boot_regs(input wire clk,input wire reset,input wire req,input wire commit,input wire we,
 input wire [31:0] addr,input wire [31:0] din,input wire [3:0] sel,
 output reg claim,output reg bad,output reg [31:0] dout);
 reg [31:0] values[0:10],scratch[0:44];reg [3:0] valid[0:10],scratch_valid[0:44];
 integer index,i;reg boot_hit,scratch_hit;
 wire [31:0] a={addr[31:2],2'b00};
 wire [31:0] mask={{8{sel[3]}},{8{sel[2]}},{8{sel[1]}},{8{sel[0]}}};
 always @* begin
  index=0;boot_hit=0;scratch_hit=0;claim=0;bad=0;dout=0;
  case(a)
   32'h08000000:begin boot_hit=1;index=0;end
   32'h08000004:begin boot_hit=1;index=1;end
   32'h08000008:begin boot_hit=1;index=2;end
   32'h08000010:begin boot_hit=1;index=3;end
   32'h08000014:begin boot_hit=1;index=4;end
   32'h08000018:begin boot_hit=1;index=5;end
   32'h08000040:begin boot_hit=1;index=6;end
   32'h0c120014:begin boot_hit=1;index=7;end
   32'h0c120018:begin boot_hit=1;index=8;end
   32'h0c120034:begin boot_hit=1;index=9;end
   32'h0c120038:begin boot_hit=1;index=10;end
   default:if(a>=32'h0c004748 && a<32'h0c0047fc)begin scratch_hit=1;index=(a-32'h0c004748)>>2;end
  endcase
  claim=req && (boot_hit||scratch_hit);
  if(claim)begin
   if(boot_hit)begin dout=values[index] & mask;if(!we && (valid[index]&sel)!=sel)bad=1;end
   else begin dout=scratch[index];if(!we && (scratch_valid[index]&sel)!=sel)bad=1;end
  end
 end
 always @(posedge clk)begin
  if(reset)begin
   for(i=0;i<11;i=i+1)begin values[i]<=0;valid[i]<=i==6?4'hf:0;end
   for(i=0;i<45;i=i+1)begin scratch[i]<=0;scratch_valid[i]<=0;end
  end else if(commit && claim && !bad && we)begin
   if(boot_hit)begin values[index]<=(values[index]&~mask)|(din&mask);valid[index]<=valid[index]|sel;end
   else begin scratch[index]<=(scratch[index]&~mask)|(din&mask);scratch_valid[index]<=scratch_valid[index]|sel;end
  end
 end
endmodule
