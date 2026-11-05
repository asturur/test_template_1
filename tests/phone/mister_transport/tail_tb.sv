module tb;
reg clk=0; always #5 clk=~clk;
reg reset=1, download=0, wr=0, ready=1, done=0; reg [26:0] addr=0; reg [15:0] data=0;
wire wait_req, valid, failed, mem_valid; wire [31:0] ma,md; wire [3:0] be;
ngage_loader #(.CORE_LEN(4),.EXT_LEN(4),.C_LEN(4),.PMM_LEN(2)) dut
(clk,reset,download,wr,addr,data,wait_req,valid,failed,mem_valid,ready,ma,md,be,done);
reg [15:0] words[0:71]; integer i, writes=0; reg [31:0] saved_addr; reg [3:0] saved_be; reg [31:0] saved_data;
function automatic [31:0] crcbyte(input [31:0] c,input [7:0] b);
reg [31:0] x; integer n; begin x=c^b; for(n=0;n<8;n=n+1) x=(x>>1)^(32'hedb88320 & {32{x[0]}}); crcbyte=x; end endfunction
function automatic [31:0] crc4(input [15:0] x,input [15:0] y);
reg [31:0] c; begin c=crcbyte(32'hffffffff,x[7:0]);c=crcbyte(c,x[15:8]);c=crcbyte(c,y[7:0]);c=crcbyte(c,y[15:8]);crc4=c^32'hffffffff;end endfunction
task put32(input integer idx,input [31:0] v); begin words[idx]=v[15:0];words[idx+1]=v[31:16];end endtask
task tick; begin @(posedge clk); #1; end endtask
always @(posedge clk) begin
 done<=0;
 if(mem_valid && ready) begin saved_addr<=ma;saved_data<=md;saved_be<=be;done<=1;writes<=writes+1;end
end
task setup; reg [31:0] c; begin
 for(i=0;i<72;i=i+1) words[i]=0;
 words[0]=16'h474e;words[1]=16'h4741;words[2]=16'h4245;words[3]=16'h0031;
 put32(4,1);put32(6,1);put32(8,4);put32(10,128);
 put32(12,0);put32(14,4);put32(18,32'h11c0000);put32(20,4);
 put32(24,32'h1400000);put32(26,4);put32(30,32'h1800000);put32(32,2);
 for(i=64;i<72;i=i+1) words[i]=16'h1000+i;
 c=crc4(words[64],words[65]);put32(16,c);c=crc4(words[66],words[67]);put32(22,c);
 c=crc4(words[68],words[69]);put32(28,c);c=crcbyte(crcbyte(32'hffffffff,words[70][7:0]),words[70][15:8]) ^ 32'hffffffff;put32(34,c);
end endtask
task start; begin @(negedge clk);download=1;tick(); end endtask
task send(input integer n,input integer a); begin
 while(wait_req) tick(); @(negedge clk);addr=a;data=words[n];wr=1;tick();@(negedge clk);wr=0;
end endtask
task finish_dl; begin @(negedge clk);download=0; repeat(5) tick(); end endtask
initial begin
 tick();reset=0;tick();setup();start();
 for(i=0;i<71;i=i+1) send(i,2*i);
 finish_dl();
 if(!valid || failed || writes!=7) $fatal(1,"partial final word failed");
 if(saved_addr!=32'h31800000 || saved_be!=4'b0011 || saved_data!=32'h10461046) $fatal(1,"partial word byte enable");
 $display("PASS loader partial final word");$finish;
end
endmodule
