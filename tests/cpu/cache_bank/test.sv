`timescale 1ns/1ps
module test;
 reg clk=0;always #5 clk=~clk;
 reg reset=1,rv=0,wb=0,refill=0,store=0,inv=0,lock=0,rr=1;
 reg [31:0] mva=0,pa=0,mask=0;reg [255:0] refill_line=0,store_line=0;
 reg [5:0] lock_in=0;wire hit,rvalid,vvalid,need,ready;wire [5:0] way,lock_base;
 wire [1:0] dirty;wire [31:0] victim_pa;wire [255:0] rline;
 arm920_cache_bank dut(.clk(clk),.reset(reset),.mva(mva),.hit(hit),.hit_way(way),
  .read_victim(rv),.read_valid(rvalid),.read_line(rline),.victim_valid(vvalid),.victim_dirty(dirty),
  .victim_physical_line(victim_pa),.needs_writeback(need),.writeback_done(wb),
  .refill(refill),.refill_physical(pa),.refill_line(refill_line),.refill_ready(ready),
  .store(store),.store_dirty(1'b1),.store_enable(mask),.store_line(store_line),.invalidate_all(inv),
  .lock_write(lock),.lock_base_in(lock_in),.lock_base(lock_base),.round_robin(rr),.scan_segment(3'b0),.scan_way(6'b0),.scan_valid(),.scan_dirty(),.scan_physical_line(),.scan_clean(1'b0),.scan_invalidate(1'b0),.scan_read(1'b0));
 task automatic tick;begin @(posedge clk);#1;@(negedge clk);end endtask
 integer n;
 initial begin
  tick();reset=0;tick();
  for(n=0;n<64;n=n+1) begin
   mva=n<<8;pa=32'h80000000+(n<<8);refill_line={8{32'h10000000+n}};tick();#1;
   if(!ready || hit || need)$fatal(1,"unexpected blocked fill %0d",n);
   refill=1;tick();refill=0;tick();
  end
  mva=0;tick();#1;if(!hit)$fatal(1,"first line missing");
  store=1;mask=1;store_line=0;store_line[7:0]=8'h7a;tick();store=0;mask=0;
  rv=0;tick();if(!rvalid || rline[7:0]!==8'h7a)$fatal(1,"hit data missing");
  mva=64<<8;pa=32'h90000000;refill_line={8{32'hdeadbeef}};tick();#1;
  if(!need || ready || victim_pa!==32'h80000000 || dirty!==2'b01)$fatal(1,"dirty victim not protected");
  rv=1;refill=1;tick();
  if(!rvalid || rline[7:0]!==8'h7a || hit || ready)$fatal(1,"stalled victim read changed");
  tick();if(!need || ready)$fatal(1,"writeback stall not retained");
  wb=1;#1;if(!ready)$fatal(1,"ack did not allow refill");tick();wb=0;refill=0;rv=0;tick();#1;
  if(!hit || need)$fatal(1,"replacement did not install");
  tick();if(!rvalid || rline!=={8{32'hdeadbeef}})$fatal(1,"refill data mismatch");
  mva=0;tick();#1;if(hit)$fatal(1,"old line still valid");
  $display("PASS: associative bank holds dirty victim until acknowledged and refills");$finish;
 end
endmodule
