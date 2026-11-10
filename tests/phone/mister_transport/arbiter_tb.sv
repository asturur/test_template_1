module tb;
reg clk=0; always #5 clk=~clk;
reg reset=1, lock=0, lv=0, cv=0, aready=1, rsp=0; wire lr,cr,ld,cd,av,aw;
wire [31:0] aa,ad,crd; wire [3:0] ab;
ngage_ddr_arbiter dut(.clk(clk),.reset(reset),.cpu_lock(lock),.l_valid(lv),.l_ready(lr),.l_addr(32'h11110000),.l_data(32'h11111111),.l_be(4'hf),.l_done(ld),.c_valid(cv),.c_ready(cr),.c_write(1'b0),.c_addr(32'h22220000),.c_data(32'h22222222),.c_be(4'hf),.c_done(cd),.c_rdata(crd),.req_valid(av),.req_ready(aready),.req_write(aw),.req_addr(aa),.req_data(ad),.req_be(ab),.rsp_valid(rsp),.rsp_data(32'habcdef01),.l_write(1'b1),.l_rdata());
task tick; begin @(posedge clk);#1;end endtask
task complete; begin @(negedge clk);rsp=1;#1;tick();@(negedge clk);rsp=0;tick();end endtask
initial begin
 tick(); reset=0; @(negedge clk); lock=1;lv=1;cv=0;#1;
 if(av || lr) $fatal(1,"lock failed to reserve idle gap");
 cv=1;#1;if(!cr || lr || aa!=32'h22220000) $fatal(1,"cpu not prioritized under lock");tick();
 @(negedge clk);cv=0;#1;if(av || lr) $fatal(1,"granted while outstanding");
 @(negedge clk);rsp=1;#1;if(!cd || ld || crd!=32'habcdef01) $fatal(1,"cpu response routing");tick();
 @(negedge clk);rsp=0;#1;if(av || lr) $fatal(1,"lost lock after response");
 lock=0;#1;if(!lr || cr || aa!=32'h11110000 || !aw) $fatal(1,"loader not granted");tick();
 @(negedge clk);lv=0;cv=1;#1;if(cr) $fatal(1,"two outstanding");
 rsp=1;#1;if(!ld || cd) $fatal(1,"loader response routing");tick();
 @(negedge clk);rsp=0;#1;if(!cr) $fatal(1,"cpu starved");tick();
 @(negedge clk);cv=0;complete();
 $display("PASS DDR arbitration and lock");$finish;
end
endmodule
