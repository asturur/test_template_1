module tb;
reg clk=0;always #5 clk=~clk;reg reset=1,v=0,w=0;reg [31:0] a=0,d=0;reg [3:0] be=15;
wire ready,rsp,err,mv,mw,dirty;wire [31:0] q,ma,md;wire [3:0] mb;wire [13:0] ds;
reg done=0;reg [31:0] mr=0;reg [31:0] pmm[0:16383];integer marks=0;
ngage_codeflash dut(clk,reset,v,ready,w,a,d,be,rsp,err,q,mv,1'b1,mw,ma,md,mb,done,mr,dirty,ds,);
always @(posedge clk)begin
 done<=0;
 if(mv)begin
  done<=1;
  if(ma>=32'h31800000 && ma<32'h31810000)begin
   mr<=pmm[(ma-32'h31800000)>>2];
   if(mw)begin
    if(mb[0])pmm[(ma-32'h31800000)>>2][7:0]<=md[7:0];
    if(mb[1])pmm[(ma-32'h31800000)>>2][15:8]<=md[15:8];
    if(mb[2])pmm[(ma-32'h31800000)>>2][23:16]<=md[23:16];
    if(mb[3])pmm[(ma-32'h31800000)>>2][31:24]<=md[31:24];
   end
  end else begin if(mw)$fatal(1,"unexpected code write");mr<=32'h12345678;end
 end
 if(dirty)begin if(ds<8192 || ds>=8320)$fatal(1,"bad dirty sector");marks<=marks+1;end
end
task tick;begin @(posedge clk);#1;end endtask
task xfer(input bit write_op,input [31:0] address,input [15:0] value,input [3:0] mask,input bit expected_error);
integer n;begin
 while(!ready)tick();@(negedge clk);v=1;w=write_op;a=address;be=mask;d=mask==12?{value,16'b0}:{16'b0,value};tick();@(negedge clk);v=0;
 n=0;while(!rsp && n<100)begin tick();n=n+1;end
 if(!rsp || err!==expected_error)$fatal(1,"response address=%h rsp=%b err=%b",address,rsp,err);
end endtask
task cmd(input [31:0] address,input [15:0] value);begin xfer(1,address,value,address[1]?12:3,0);end endtask
integer i;reg [31:0] before0,before2;
initial begin
 for(i=0;i<16384;i=i+1)pmm[i]=32'hffffffff;
 tick();reset=0;tick();
 xfer(0,32'h0027ee60,0,15,0);before0=q;xfer(0,32'h04000000,0,15,0);before2=q;
 cmd(32'h007f0000,16'h60);
 xfer(0,32'h0027ee60,0,15,0);if(q!==before0)$fatal(1,"status leaked across banks");
 xfer(0,32'h04000000,0,15,0);if(q!==before2)$fatal(1,"status leaked across chips");
 xfer(0,32'h007f0000,0,3,0);if(q!==1)$fatal(1,"lock status");cmd(0,16'hf0);
 cmd(32'h007f003e,16'h40);cmd(32'h007f003e,16'h60);
 xfer(0,32'h007f003c,0,3,0);if(q!==32'h80)$fatal(1,"program status");cmd(0,16'hf0);
 xfer(0,32'h007f003e,0,12,0);if(q!==32'h0060ffff)$fatal(1,"program data 60 %h",q);
 cmd(32'h007f003e,16'h40);cmd(32'h007f003e,16'hf0);cmd(0,16'hf0);
 xfer(0,32'h007f003e,0,12,0);if(q!==32'h0060ffff)$fatal(1,"program data f0 and NOR AND %h",q);
 cmd(32'h00000aaa,16'haa);cmd(32'h00000554,16'h55);cmd(32'h00000aaa,16'h90);
 xfer(0,0,0,3,0);if(q!==1)$fatal(1,"identify vendor");xfer(0,2,0,12,0);if(q!==32'h257e0000)$fatal(1,"identify device");
 xfer(0,8,0,3,1);cmd(0,16'hf0);
 cmd(32'h04000aaa,16'haa);cmd(32'h04000554,16'h55);cmd(32'h04000aaa,16'h90);
 xfer(0,32'h04000000,0,3,0);if(q!==1)$fatal(1,"chip2 identify");
 xfer(0,0,0,15,0);if(q!==32'h12345678)$fatal(1,"chip2 mode leaked");cmd(32'h04000000,16'hf0);
 cmd(32'h00000aaa,16'haa);cmd(32'h00000554,16'h55);cmd(32'h00000aaa,16'hc0);
 xfer(0,0,0,15,0);if(q!==32'h12345678)$fatal(1,"burst command changed array");
 xfer(1,32'h007f0000,0,15,1);xfer(0,32'h02400000,0,15,1);
 if(marks!=1)$fatal(1,"dirty count %d",marks);
 $display("PASS code-flash identification, bank scope, PMM program and NOR AND");$finish;
end
endmodule
