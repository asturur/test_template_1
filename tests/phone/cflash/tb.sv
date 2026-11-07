module tb;
reg clk=0;always #5 clk=~clk;
reg reset=1,valid=0,write_op=0;reg [21:0] off=0;reg [31:0] data=0;reg [3:0] be=15;
wire ready,rsp,err,mv,mw,dirty;wire [31:0] result,ma,md;wire [3:0] mb;wire [12:0] ds;
reg done=0;reg [31:0] mr=0;reg [31:0] mem[0:1048575];integer writes=0,dirty_events=0;reg sector0_seen=0,sector1_seen=0;
ngage_cflash dut(clk,reset,1'b0,valid,ready,write_op,off,data,be,rsp,err,result,mv,1'b1,mw,ma,md,mb,done,mr,dirty,ds,,);
always @(posedge clk) begin
 done<=0;
 if(mv) begin
  if(ma<32'h31400000 || ma>=32'h31800000) $fatal(1,"backing out of range");
  mr<=mem[(ma-32'h31400000)>>2];
  if(mw) begin
   if(mb[0]) mem[(ma-32'h31400000)>>2][7:0]<=md[7:0];
   if(mb[1]) mem[(ma-32'h31400000)>>2][15:8]<=md[15:8];
   if(mb[2]) mem[(ma-32'h31400000)>>2][23:16]<=md[23:16];
   if(mb[3]) mem[(ma-32'h31400000)>>2][31:24]<=md[31:24];
   writes<=writes+1;
  end
  done<=1;
 end
 if(dirty)begin dirty_events<=dirty_events+1;if(ds==0)sector0_seen<=1;if(ds==1)sector1_seen<=1;end
end
task tick;begin @(posedge clk);#1;end endtask
task transaction(input bit w,input [21:0] a,input [15:0] v,input [3:0] mask,input bit expected_error);
integer n;begin
 while(!ready) tick();@(negedge clk);valid=1;write_op=w;off=a;be=mask;data=(mask==12)?{v,16'b0}:{16'b0,v};tick();@(negedge clk);valid=0;
 n=0;while(!rsp && n<100000)begin tick();n=n+1;end
 if(!rsp || err!==expected_error) $fatal(1,"flash response offset=%h rsp=%b err=%b",a,rsp,err);
end endtask
task cmd(input [21:0] a,input [15:0] v);begin transaction(1,a,v,a[1]?12:3,0);end endtask
task unlock;begin cmd(22'haaa,16'haa);cmd(22'h554,16'h55);end endtask
task program_half(input [21:0] a,input [15:0] v);begin unlock();cmd(22'haaa,16'ha0);cmd(a,v);end endtask
task erase_start(input [21:0] a);begin unlock();cmd(22'haaa,16'h80);unlock();cmd(a,16'h30);end endtask
integer i;
initial begin
 for(i=0;i<1048576;i=i+1)mem[i]=32'hffffffff;
 tick();reset=0;tick();
 program_half(22'h100,16'h0060);transaction(0,22'h100,0,15,0);if(result!==32'hffff0060)$fatal(1,"program 60");
 program_half(22'h102,16'h00f0);transaction(0,22'h100,0,15,0);if(result!==32'h00f00060)$fatal(1,"program f0");
 program_half(22'h1fe,16'habcd);program_half(22'h200,16'h1234);repeat(3)tick();
 if(mem[22'h1fc>>2]!==32'habcdffff || mem[22'h200>>2]!==32'hffff1234 || !sector0_seen || !sector1_seen)$fatal(1,"cross-sector halfword program/dirty");
 program_half(22'h100,16'hffff);transaction(0,22'h100,0,15,0);if(result!==32'h00f0ffff)$fatal(1,"software first-program semantics");
 unlock();cmd(22'haaa,16'h90);transaction(0,0,0,3,0);if(result!==1)$fatal(1,"manufacturer");transaction(0,2,0,12,0);if(result!==32'h257e0000)$fatal(1,"device id");cmd(0,16'hf0);
 transaction(1,22'h000120,16'h1234,1,1);
 mem[22'h010000>>2]=32'h12345678;mem[22'h01fffc>>2]=32'habcdef01;mem[22'h020000>>2]=32'h76543210;
 erase_start(22'h010000);transaction(0,22'h010000,0,3,0);if(result!==8)$fatal(1,"erase busy");
 transaction(0,22'h010000,0,3,0);if(result!==32'h0000ffff)$fatal(1,"erase completed read");
 if(mem[22'h010000>>2]!==32'hffffffff || mem[22'h01fffc>>2]!==32'hffffffff || mem[22'h020000>>2]!==32'h76543210)$fatal(1,"64k erase range");
 mem[22'h1f8000>>2]=0;mem[22'h1fbffc>>2]=0;mem[22'h1fc000>>2]=32'h12345678;
 erase_start(22'h1f8000);cmd(22'h1f8000,16'hb0);
 if(mem[22'h1f8000>>2]!==32'hffffffff || mem[22'h1fbffc>>2]!==32'hffffffff || mem[22'h1fc000>>2]!==32'h12345678)$fatal(1,"16k suspend/erase range");
 // A reset after accepted erase must finish the backing writes before clearing state.
 mem[22'h3fc000>>2]=0;erase_start(22'h3fc000);@(negedge clk);reset=1;
 i=0;while((dut.erase_pending || dut.state!=0) && i<100000) begin @(negedge clk);i=i+1;end
 if(dut.erase_pending || mem[22'h3fc000>>2]!==32'hffffffff) $fatal(1,"reset lost accepted erase");
 reset=0;tick();
 // Reset while an accepted program is waiting for its backing write.
 unlock();cmd(22'haaa,16'ha0);
 @(negedge clk);valid=1;write_op=1;off=22'h300;be=3;data=32'h00001234;
 tick();@(negedge clk);valid=0;
 wait(mv && mw);@(negedge clk);reset=1;
 i=0;while(dut.state!=0 && i<1000)begin @(negedge clk);i=i+1;end
 if(dut.state!=0 || mem[22'h300>>2]!==32'hffff1234)$fatal(1,"reset lost accepted program");
 reset=0;repeat(2)tick();
 if(writes<6 || dirty_events==0)$fatal(1,"missing committed writes");
 $display("PASS C: flash commands, program, 64K/16K erase and dirty events");$finish;
end
endmodule
