`timescale 1ns/1ps
module test;
 logic clk=0;always #5 clk=~clk;
 logic reset=1,req=0,wr=0,en=1,c=1,b=0,allow=1,inject_error=0;
 logic [31:0] mva=0,pa=0,wd=0;logic [3:0] ben=4'hf;
 logic mv=0,mc=0,mi=0,ma=0,mb=0; logic [31:0] mad=0;wire mr,md,me;
 wire ready,rv,re,bv,bw,empty,buferr;wire [31:0] rd,ba,bd;wire [3:0] bs;
 logic [31:0] mem[0:1023];integer writes=0,n;
 wire ack=bv && allow && !inject_error;wire [31:0] br=mem[ba[11:2]];
 arm920_cache_access dut(.clk(clk),.reset(reset),.discard_refill(1'b0),.req_valid(req),.req_ready(ready),.req_mva(mva),.req_physical(pa),.req_write(wr),.req_cache_enable(en),.req_cacheable(c),.req_bufferable(b),.req_wdata(wd),.req_byte_enable(ben),.response_valid(rv),.response_error(re),.response_data(rd),.write_buffer_empty(empty),.write_buffer_error(buferr),.fast_lookup_enable(1'b0),.fast_lookup_address(32'b0),.fast_lookup_valid(),.fast_lookup_checked(),.fast_lookup_line(),.invalidate_all(1'b0),.lock_write(1'b0),.lock_base_in(6'b0),.round_robin(1'b1),.maint_valid(mv),.maint_clean(mc),.maint_invalidate(mi),.maint_all(ma),.maint_by_mva(mb),.maint_address(mad),.maint_way(0),.maint_segment(0),.maint_ready(mr),.maint_done(md),.maint_error(me),.bus_valid(bv),.bus_write(bw),.bus_address(ba),.bus_wdata(bd),.bus_byte_enable(bs),.bus_ack(ack),.bus_error(bv && inject_error),.bus_rdata(br));
 always @(posedge clk) if(!reset && ack && bw)begin
  writes<=writes+1;for(integer k=0;k<4;k=k+1)if(bs[k])mem[ba[11:2]][k*8+:8]<=bd[k*8+:8];
 end
 task automatic tick;begin @(posedge clk);#1;@(negedge clk);end endtask
 task automatic begin_req(input logic write_op,input logic cacheable,input logic bufferable,input logic [31:0] a,input logic [31:0] d);begin
  if(!ready)$fatal(1,"request not ready");wr=write_op;c=cacheable;b=bufferable;mva=a;pa=a;wd=d;req=1;tick();req=0;
 end endtask
 task automatic finish_req;begin while(!rv)tick();if(re)$fatal(1,"unexpected error");end endtask
 initial begin #100000;$fatal(1,"timeout");end
 initial begin
  for(n=0;n<1024;n=n+1)mem[n]=0;
  tick();reset=0;tick();
  begin_req(0,1,0,32'h100,0);finish_req();
  allow=0;begin_req(1,1,0,32'h100,32'h12345678);finish_req();
  if(empty || mem['h40]!==0 || writes!=0)$fatal(1,"write-through did not complete asynchronously");
  begin_req(0,1,0,32'h100,0);finish_req();
  if(rd!==32'h12345678 || empty)$fatal(1,"cache hit did not run while buffer stalled");
  begin_req(0,1,0,32'h180,0);
  repeat(8)begin tick();if(rv)$fatal(1,"cache linefill passed buffered write");end
  allow=1;finish_req();if(rd!==0 || !empty)$fatal(1,"ordered linefill failed");
  allow=0;begin_req(1,1,0,32'h100,32'h12345679);finish_req();
  begin_req(0,0,0,32'h100,0);
  repeat(8)begin tick();if(rv)$fatal(1,"uncached load passed buffered write");end
  allow=1;finish_req();if(rd!==32'h12345679 || !empty)$fatal(1,"ordered uncached load failed");
  // A different word in the same replacement line must wait for the
  // earlier buffered store, otherwise the new cache line becomes stale.
  allow=0;begin_req(1,0,1,32'h3a4,32'ha1b2c3d4);finish_req();
  // Use a different virtual line that aliases the buffered physical line.
  if(!ready)$fatal(1,"alias request not ready");
  wr=0;c=1;b=1;mva=32'h3c0;pa=32'h3a0;req=1;tick();req=0;
  repeat(12)begin tick();if(rv)$fatal(1,"overlapping linefill passed pending store");end
  if(!dut.buffer_line_hazard)$fatal(1,"overlapping line not detected");
  allow=1;finish_req();
  if(!ready)$fatal(1,"alias hit not ready");
  wr=0;c=1;b=1;mva=32'h3c4;pa=32'h3a4;req=1;tick();req=0;finish_req();
  if(rd!==32'ha1b2c3d4)$fatal(1,"linefill returned stale buffered word");
  allow=0;
  for(n=0;n<4;n=n+1)begin begin_req(1,0,1,32'h200+32*n,32'hab000000+n);finish_req();end
  if(empty || dut.buffer_entries!=4)$fatal(1,"four writes not buffered");
  begin_req(1,0,1,32'h280,32'hab000004);
  repeat(8)begin tick();if(rv)$fatal(1,"full buffer did not stall fifth store");end
  allow=1;finish_req();while(!empty)tick();
  for(n=0;n<5;n=n+1)if(mem['h80+8*n]!==32'hab000000+n)$fatal(1,"buffered ordering n=%0d",n);
  // Buffered errors retry without losing the accepted write or reporting an abort.
  inject_error=1;begin_req(1,0,1,32'h300,32'hfeedbeef);finish_req();
  repeat(5)tick();if(empty || mem['hc0]!==0)$fatal(1,"failed buffered beat was lost");
  // The unrelated refill and pending write both encounter errors; neither
  // may report a CPU abort or lose the buffered store when the bus recovers.
  mem['hd0]=32'h01234567;begin_req(0,1,1,32'h340,0);
  repeat(15)begin tick();if(rv)$fatal(1,"cacheable refill reported abort");end
  inject_error=0;finish_req();if(rd!==32'h01234567)$fatal(1,"refill retry failed");
  while(!empty)tick();if(mem['hc0]!==32'hfeedbeef)$fatal(1,"buffer retry failed");
  // Cleaning a dirty line must finish when its writeback enters the buffer,
  // even while the external bus is blocked. A subsequent drain makes it visible.
  begin_req(1,1,1,32'h340,32'hc001d00d);finish_req();
  allow=0;mb=1;mad=32'h340;mc=1;
  while(!mr)tick();mv=1;tick();mv=0;
  repeat(30)begin tick();if(md)break;end
  if(!md || me || empty || mem['hd0]!==32'h01234567)
   $fatal(1,"dirty clean did not complete into stalled write buffer");
  while(!ready)tick();
  begin_req(0,1,1,32'h340,0);finish_req();
  if(rd!==32'hc001d00d || empty)$fatal(1,"cached hit did not overlap pending clean");
  inject_error=1;allow=1;repeat(5)tick();
  if(empty || mem['hd0]!==32'h01234567)$fatal(1,"failed clean beat was discarded");
  inject_error=0;while(!empty)tick();
  if(mem['hd0]!==32'hc001d00d)$fatal(1,"dirty clean writeback lost data");
  mb=0;mc=0;
  // Noncached/nonbuffered reads can report an external abort.
  inject_error=1;begin_req(0,0,0,32'h380,0);while(!rv)tick();
  if(!re)$fatal(1,"uncached bus abort not reported");inject_error=0;
  $display("PASS: asynchronous buffering, ordering, backpressure and bus-error behavior");$finish;
 end
endmodule
