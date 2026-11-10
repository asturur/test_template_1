module tb;
reg clk=0; always #5 clk=~clk;
reg reset=1, download=0, wr=0; wire ready, done; reg [26:0] addr=0; reg [15:0] data=0;
wire wait_req, valid, failed, mem_valid; wire [31:0] ma,md; wire [3:0] be;
ngage_loader #(.CORE_LEN(4),.EXT_LEN(4),.C_LEN(4),.PMM_LEN(4)) dut
(clk,reset,download,wr,addr,data,wait_req,valid,failed,mem_valid,ready,ma,md,be,done);
reg [15:0] words[0:71]; integer i, writes=0; reg [31:0] saved_addr; reg [3:0] saved_be; reg [31:0] saved_data;
function automatic [31:0] crcbyte(input [31:0] c,input [7:0] b);
reg [31:0] x; integer n; begin x=c^b; for(n=0;n<8;n=n+1) x=(x>>1)^(32'hedb88320 & {32{x[0]}}); crcbyte=x; end endfunction
function automatic [31:0] crc4(input [15:0] x,input [15:0] y);
reg [31:0] c; begin c=crcbyte(32'hffffffff,x[7:0]);c=crcbyte(c,x[15:8]);c=crcbyte(c,y[7:0]);c=crcbyte(c,y[15:8]);crc4=c^32'hffffffff;end endfunction
task put32(input integer idx,input [31:0] v); begin words[idx]=v[15:0];words[idx+1]=v[31:16];end endtask
task tick; begin @(posedge clk); #1; end endtask
wire [28:0] ddr_addr; wire [63:0] ddr_din; wire [7:0] ddr_be; wire ddr_rd,ddr_we;
wire [31:0] unused_read; reg [63:0] mem [0:3]; reg [63:0] fake_out=0; reg fake_ready=0; reg busy=0;
integer cycles=0, k, slot;
wire av, ar, aw, rsp; wire [31:0] aa, ad, rv; wire [3:0] ab;
ngage_ddr_arbiter arb(.clk(clk),.reset(reset),.cpu_lock(1'b0),.l_valid(mem_valid),.l_ready(ready),.l_addr(ma),.l_data(md),.l_be(be),.l_done(done),.c_valid(1'b0),.c_ready(),.c_write(1'b0),.c_addr(32'b0),.c_data(32'b0),.c_be(4'b0),.c_done(),.c_rdata(),.req_valid(av),.req_ready(ar),.req_write(aw),.req_addr(aa),.req_data(ad),.req_be(ab),.rsp_valid(rsp),.rsp_data(rv),.l_write(1'b1),.l_rdata());
ngage_ddr_adapter adapter(.clk(clk),.reset(reset),.req_valid(av),.req_ready(ar),.req_write(aw),.req_addr(aa),.req_wdata(ad),.req_be(ab),.rsp_valid(rsp),.rsp_data(rv),.ddr_addr(ddr_addr),.ddr_din(ddr_din),.ddr_be(ddr_be),.ddr_rd(ddr_rd),.ddr_we(ddr_we),.ddr_busy(busy),.ddr_dout(fake_out),.ddr_dout_ready(fake_ready),.req_fetch(1'b0),.ddr_burstcount());
always @(posedge clk) begin
 cycles<=cycles+1; busy<= (cycles%5 < 3);
 if(ddr_we && !busy) begin
   case(ddr_addr)
   (32'h30000000 >> 3): slot=0;
   (32'h311c0000 >> 3): slot=1;
   (32'h31400000 >> 3): slot=2;
   (32'h31800000 >> 3): slot=3;
   default: $fatal(1,"bad DDR target %x",ddr_addr);
   endcase
   for(k=0;k<8;k=k+1) if(ddr_be[k]) mem[slot][k*8 +:8] <= ddr_din[k*8 +:8];
   saved_addr<=ma;saved_data<=md;saved_be<=be;writes<=writes+1;
 end
end
task setup; reg [31:0] c; begin
 for(i=0;i<72;i=i+1) words[i]=0;
 words[0]=16'h474e;words[1]=16'h4741;words[2]=16'h4245;words[3]=16'h0031;
 put32(4,1);put32(6,1);put32(8,4);put32(10,128);
 put32(12,0);put32(14,4);put32(18,32'h11c0000);put32(20,4);
 put32(24,32'h1400000);put32(26,4);put32(30,32'h1800000);put32(32,4);
 for(i=64;i<72;i=i+1) words[i]=16'h1000+i;
 c=crc4(words[64],words[65]);put32(16,c);c=crc4(words[66],words[67]);put32(22,c);
 c=crc4(words[68],words[69]);put32(28,c);c=crc4(words[70],words[71]);put32(34,c);
end endtask
task start; begin @(negedge clk);download=1;tick(); end endtask
task send(input integer n,input integer a); begin
 while(wait_req) tick(); @(negedge clk);addr=a;data=words[n];wr=1;tick();@(negedge clk);wr=0;
end endtask
task finish_dl; begin @(negedge clk);download=0; repeat(5) tick(); end endtask
initial begin
 tick();reset=0;tick();setup();start();
 for(i=0;i<72;i=i+1) send(i,2*i);
 finish_dl(); if(!valid || failed || writes!=8) $fatal(1,"valid bundle failed valid=%d failed=%d writes=%d pos=%d section=%d spos=%d",valid,failed,writes,dut.position,dut.section,dut.section_pos);
 if(mem[0][31:0]!=32'h10411040 || mem[1][31:0]!=32'h10431042 ||
    mem[2][31:0]!=32'h10451044 || mem[3][31:0]!=32'h10471046) $fatal(1,"DDR readback mismatch");
 if(saved_addr!=32'h31800000 || saved_be!=4'b1100 || saved_data!=32'h10471047) $fatal(1,"last lane");
 start();for(i=0;i<71;i=i+1) send(i,2*i);finish_dl();if(valid || !failed) $fatal(1,"short bundle accepted");
 setup();words[64]=words[64]^1;start();for(i=0;i<72;i=i+1) send(i,2*i);finish_dl();if(valid || !failed) $fatal(1,"bad crc accepted");
 setup();start();for(i=0;i<10;i=i+1) send(i,2*i);send(10,18);finish_dl();if(valid || !failed) $fatal(1,"duplicate accepted");
 setup();words[18]=16'h1234;start();for(i=0;i<64;i=i+1) send(i,2*i);finish_dl();if(valid || !failed) $fatal(1,"bad offset accepted");
 setup();start();for(i=0;i<72;i=i+1) send(i,2*i);send(71,144);finish_dl();if(valid || !failed) $fatal(1,"oversized bundle accepted");
 setup();start();for(i=0;i<10;i=i+1) send(i,2*i);send(10,22);finish_dl();if(valid || !failed) $fatal(1,"address hole accepted");
 $display("PASS integrated loader and fake DDR");$finish;
end
endmodule
