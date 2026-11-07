module tb;
parameter SECTORS=16;
reg clk=0;always #5 clk=~clk;reg reset=1,dv=0,start=0,accept=0,done=0,ok=1,abort_flush=0;reg [3:0] di=0;wire flushing,error,init,valid;wire [3:0] index;
ngage_dirty_tracker #(.SECTORS(SECTORS),.AW(4)) dut(clk,reset,dv,di,start,flushing,error,init,valid,accept,index,done,ok,abort_flush);
task tick;begin @(posedge clk);#1;end endtask
task mark(input [3:0] n);begin @(negedge clk);di=n;dv=1;tick();@(negedge clk);dv=0;end endtask
task begin_flush;begin @(negedge clk);start=1;tick();@(negedge clk);start=0;end endtask
task offer(input [3:0] n);integer k;begin k=0;while(!valid && k<100)begin tick();k=k+1;end if(!valid||index!=n)$fatal(1,"wrong sector %d expected %d",index,n);@(negedge clk);accept=1;tick();@(negedge clk);accept=0;end endtask
task finish_sector(input bit success);begin @(negedge clk);ok=success;done=1;tick();@(negedge clk);done=0;end endtask
initial begin
 tick();reset=0;wait(init);mark(2);mark(7);begin_flush();offer(2);mark(2);finish_sector(1);offer(7);finish_sector(1);offer(2);finish_sector(1);wait(!flushing);
 mark(2);begin_flush();offer(2);finish_sector(0);if(!error)$fatal(1,"failure not reported");
 begin_flush();offer(2); // mark on same cycle as completion
 @(negedge clk);di=2;dv=1;done=1;ok=1;tick();@(negedge clk);dv=0;done=0;offer(2);finish_sector(1);wait(!flushing);
 mark(5);begin_flush();offer(5);@(negedge clk);abort_flush=1;tick();@(negedge clk);abort_flush=0;
 if(flushing || !error)$fatal(1,"abort not reported");begin_flush();offer(5);finish_sector(1);wait(!flushing);
 begin_flush();wait(!flushing);if(valid || error)$fatal(1,"clean scan failure");
 // Clear on B and mark another sector on A in the same cycle.
 mark(2);begin_flush();offer(2);
 @(negedge clk);di=7;dv=1;done=1;ok=1;tick();@(negedge clk);dv=0;done=0;
 offer(7);finish_sector(1);wait(!flushing);
 // Forward a mark coincident with the scan RAM read itself.
 begin_flush();wait(dut.state==4 && dut.cursor==3);
 @(negedge clk);di=3;dv=1;tick();@(negedge clk);dv=0;
 offer(3);finish_sector(1);wait(!flushing);
 mark(SECTORS-1);begin_flush();offer(SECTORS-1);finish_sector(1);wait(!flushing);
 if(SECTORS<16)begin mark(15);begin_flush();wait(!flushing);if(valid)$fatal(1,"out-of-range mark");end
 $display("PASS dirty sectors, concurrent writes and failed-flush retry");$finish;
end
initial begin #200000;$fatal(1,"dirty tracker timeout state=%d cursor=%d flushing=%b valid=%b",dut.state,dut.cursor,flushing,valid);end
endmodule
