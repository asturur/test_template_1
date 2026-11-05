`timescale 1ns/1ps
module test;
 logic clk=0;always #5 clk=~clk;
 logic reset=1,start=0,ack=0,err=0,seed=0,store=0;
 logic [31:0] mva=0,pa=0,memdata=0;wire [31:0] bm,bpa,baddr,bdata,vpa;wire [255:0] bline,rline;
 wire busy,done,error,rv,fill,wb,ready,hit,valid,need,read_valid,bvalid,bwrite;wire [1:0] dirty;wire [5:0] way,lock;
 wire [31:0] selected_mva=seed ? mva : bm;
 arm920_cache_refill ctl(.clk(clk),.reset(reset),.start(start),.request_mva(mva),.request_physical(pa),.busy(busy),.done(done),.error(error),.bank_mva(bm),.bank_hit(hit),.bank_victim_valid(valid),.bank_victim_dirty(dirty),.bank_victim_physical(vpa),.bank_read_line(rline),.bank_read_victim(rv),.bank_refill(fill),.bank_writeback_done(wb),.bank_refill_physical(bpa),.bank_refill_line(bline),.bank_refill_ready(ready),.bus_valid(bvalid),.bus_write(bwrite),.bus_address(baddr),.bus_wdata(bdata),.bus_ack(ack),.bus_error(err),.bus_rdata(memdata));
 arm920_cache_bank bank(.clk(clk),.reset(reset),.mva(selected_mva),.hit(hit),.hit_way(way),.read_victim(rv),.read_valid(read_valid),.read_line(rline),.victim_valid(valid),.victim_dirty(dirty),.victim_physical_line(vpa),.needs_writeback(need),.writeback_done(wb),.refill(seed ? !store : fill),.refill_physical(seed ? pa : bpa),.refill_line(seed ? {8{32'h10101010}} : bline),.refill_ready(ready),.store(seed && store),.store_dirty(1'b1),.store_enable(32'hf),.store_line({224'b0,32'hdeadbeef}),.invalidate_all(1'b0),.lock_write(1'b0),.lock_base_in(6'b0),.lock_base(lock),.round_robin(1'b1));
 task automatic tick;begin @(posedge clk);#1;@(negedge clk);end endtask
 integer n,beats;
 initial begin #100000; $fatal(1,"test timed out"); end
 initial begin
  tick();reset=0;tick();seed=1;
  for(n=0;n<64;n=n+1)begin mva=n<<8;pa=32'h80000000+(n<<8);tick();end
  mva=0;store=1;tick();store=0;seed=0;
  mva=64<<8;pa=32'h90000000;start=1;tick();start=0;
  wait(bvalid);#1;if(!bwrite || baddr!==32'h80000000 || bdata!==32'hdeadbeef)$fatal(1,"first victim beat");
  err=1;tick();err=0;while(!done)tick();if(!error)$fatal(1,"error missing");
  seed=1;mva=0;#1;if(!hit)$fatal(1,"error discarded dirty victim");seed=0;
  // Complete write-back, then fail the first refill beat. The original dirty
  // line must remain available because installation never committed.
  mva=64<<8;start=1;tick();start=0;beats=0;
  while(beats<4)begin
   if(bvalid)begin
    if(!bwrite || baddr!==32'h80000000+4*beats)$fatal(1,"first writeback beat %0d",beats);
    ack=1;beats=beats+1;
   end else ack=0;
   tick();ack=0;
  end
  if(!bvalid || bwrite)$fatal(1,"expected refill after writeback");
  err=1;tick();err=0;while(!done)tick();if(!error)$fatal(1,"refill error missing");
  seed=1;mva=0;#1;if(!hit)$fatal(1,"refill error discarded victim");seed=0;
  mva=64<<8;start=1;tick();start=0;beats=0;
  while(!done)begin
   if(bvalid)begin
    if(beats<4)begin
     if(!bwrite || baddr!==32'h80000000+4*beats || (beats==0 && bdata!==32'hdeadbeef))$fatal(1,"writeback beat %0d",beats);
    end else begin
     if(bwrite || baddr!==32'h90000000+4*(beats-4))$fatal(1,"refill beat %0d",beats);
     memdata=32'hfa000000+beats-4;
    end
    ack=1;beats=beats+1;
   end else ack=0;
   tick();ack=0;
  end
  if(error || beats!=12)$fatal(1,"bad completion %0d",beats);
  seed=1;mva=64<<8;#1;if(!hit)$fatal(1,"new line missing");tick();if(rline[31:0]!==32'hfa000000)$fatal(1,"new data missing");
  mva=0;#1;if(hit)$fatal(1,"victim still present");
  $display("PASS: cache bank replacement survives bus error and retries dirty victim");$finish;
 end
endmodule
