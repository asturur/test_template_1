`timescale 1ns/1ps
module test;
 logic clk=0;always #5 clk=~clk;
 logic reset=1,start=0,clean=0,invalidate=0,all=0,ack=0,err=0,seed=0,store=0;
 logic [31:0] mva=0,pa=32'h80001000;wire busy,done,error,sread,sv,sc,si,bv;
 wire [5:0] sw,way,lock;wire [2:0] ss;wire [1:0] sd,vd;wire [31:0] spa,ba,bd,vpa;wire [255:0] line;
 wire hit,vvalid,need,ready,rvalid;
 arm920_cache_maintenance ctl(.clk(clk),.reset(reset),.start(start),.clean(clean),.invalidate(invalidate),.all(all),.index_way(6'b0),.index_segment(3'b0),.busy(busy),.done(done),.error(error),.scan_read(sread),.scan_way(sw),.scan_segment(ss),.scan_valid(sv),.scan_dirty(sd),.scan_physical_line(spa),.scan_line(line),.scan_clean(sc),.scan_invalidate(si),.bus_valid(bv),.bus_address(ba),.bus_wdata(bd),.bus_ack(ack),.bus_error(err));
 arm920_cache_bank bank(.clk(clk),.reset(reset),.mva(mva),.lookup_segment_select(8'b1 << mva[7:5]),.hit(hit),.hit_way(way),.read_victim(1'b0),.read_valid(rvalid),.read_line(line),.victim_valid(vvalid),.victim_dirty(vd),.victim_physical_line(vpa),.needs_writeback(need),.writeback_done(1'b0),.refill(seed && !store),.refill_physical(pa),.refill_line({8{32'h11111111}}),.refill_ready(ready),.store(seed && store),.store_dirty(1'b1),.store_enable(32'hf),.store_line({224'b0,32'hdeadbeef}),.invalidate_all(1'b0),.lock_write(1'b0),.lock_base_in(6'b0),.lock_base(lock),.round_robin(1'b1),.scan_read(sread),.scan_segment(ss),.scan_way(sw),.scan_valid(sv),.scan_dirty(sd),.scan_physical_line(spa),.scan_clean(sc),.scan_invalidate(si));
 task automatic tick;begin @(posedge clk);#1;@(negedge clk);end endtask
 task automatic launch(input logic cl,input logic inv,input logic every);begin clean=cl;invalidate=inv;all=every;start=1;tick();start=0;end endtask
 initial begin #300000;$fatal(1,"timeout");end
 integer count;
 initial begin
  tick();reset=0;repeat(3)tick();seed=1;tick();seed=0;repeat(4)tick();
  seed=1;store=1;tick();seed=0;store=0;repeat(4)tick();#1;
  if(!hit)$fatal(1,"setup missing line");
  launch(1,1,0);wait(bv);#1;
  if(ba!==32'h80001000 || bd!==32'hdeadbeef)$fatal(1,"bad clean address/data");
  err=1;tick();err=0;if(!done || !error || !hit)$fatal(1,"failed clean lost line");
  launch(1,0,0);count=0;
  while(!done)begin
   if(bv)begin if(ba!==32'h80001000+4*count)$fatal(1,"bad clean beat");ack=1;count=count+1;end
   tick();ack=0;
  end
  if(error || count!=4 || !hit)$fatal(1,"clean should keep line");
  launch(1,0,0);count=0;while(!done)begin if(bv)count=count+1;tick();end
  if(count!=0)$fatal(1,"clean did not clear dirty bit");
  launch(0,1,1);while(!done)tick();if(hit)$fatal(1,"invalidate all failed");
  $display("PASS: indexed clean, error retention and invalidate all");$finish;
 end
endmodule
