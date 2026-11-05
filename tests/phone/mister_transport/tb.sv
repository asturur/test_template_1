module tb;
reg clk=0; always #5 clk=~clk;
reg reset=1, valid=0, wr=0, busy=0, ready=0;
reg [31:0] addr=0, data=0; reg [3:0] be=0; reg [63:0] dout=0;
wire req_ready, rsp, rd, we; wire [31:0] result; wire [28:0] da; wire [63:0] din; wire [7:0] db;
ngage_ddr_adapter dut(clk,reset,valid,req_ready,wr,addr,data,be,rsp,result,da,din,db,rd,we,busy,dout,ready);
task tick; begin @(posedge clk); #1; end endtask
task send(input bit w,input [31:0] a,input [3:0] m); begin
 while(!req_ready) tick(); @(negedge clk); valid=1; wr=w; addr=a; be=m; data=32'h12345678; tick(); @(negedge clk); valid=0;
end endtask
integer lane, mask;
initial begin
 tick(); reset=0; tick();
 for(lane=0;lane<2;lane=lane+1) for(mask=0;mask<16;mask=mask+1) begin
   busy=1; send(1,32'h30000000+4*lane,mask); tick();
   if(!we || rd || db !== (lane ? mask<<4 : mask) || da !== 29'h6000000 || din !== 64'h1234567812345678) $fatal(1,"write lanes");
   tick(); if(!we) $fatal(1,"command not held");
   busy=0; tick(); if(!rsp || we) $fatal(1,"write acceptance"); tick(); if(rsp) $fatal(1,"duplicate response");
 end
 send(0,32'h30000004,15); tick(); if(rd || req_ready) $fatal(1,"read acceptance");
 repeat(3) tick(); dout=64'hcafebabe_deadbeef; ready=1; tick(); ready=0;
 if(!rsp || result!==32'hcafebabe) $fatal(1,"delayed read"); tick();
 send(0,32'h30000000,15); tick(); reset=1; tick(); reset=0; tick();
 if(req_ready || rsp) $fatal(1,"reset did not drain read");
 ready=1; tick(); ready=0; if(rsp || !req_ready) $fatal(1,"stale response leaked");
 send(0,32'h30000000,15); tick(); dout=64'h12345678_abcdef01; ready=1; tick(); ready=0;
 if(!rsp || result!==32'habcdef01) $fatal(1,"post-reset read");
 $display("PASS DDR transport"); $finish;
end
endmodule
