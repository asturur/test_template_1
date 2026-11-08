`timescale 1ns/1ps
module test;
 reg clk=0;always #5 clk=~clk;
 reg sd=1,sc=0;
 reg reset=1,rv=0,wb=0,refill=0,store=0,inv=0,lock=0,rr=1;
 reg [31:0] mva=0,pa=0,mask=0;reg [255:0] refill_line=0,store_line=0;
 reg [5:0] lock_in=0;wire hit,rvalid,vvalid,need,ready;wire [5:0] way,lock_base;
 wire [1:0] dirty;wire [31:0] victim_pa;wire [255:0] rline;
 arm920_cache_bank dut(.clk(clk),.reset(reset),.mva(mva),.lookup_segment_select(8'b1 << mva[7:5]),.hit(hit),.hit_way(way),
  .read_victim(rv),.read_valid(rvalid),.read_line(rline),.victim_valid(vvalid),.victim_dirty(dirty),
  .victim_physical_line(victim_pa),.needs_writeback(need),.writeback_done(wb),
  .refill(refill),.refill_physical(pa),.refill_line(refill_line),.refill_ready(ready),
  .store(store),.store_dirty(sd),.store_enable(mask),.store_line(store_line),.invalidate_all(inv),
  .lock_write(lock),.lock_base_in(lock_in),.lock_base(lock_base),.round_robin(rr),.scan_segment(3'b0),.scan_way(6'b0),.scan_valid(),.scan_dirty(),.scan_physical_line(),.scan_clean(sc),.scan_invalidate(1'b0),.scan_read(1'b0));
 task automatic tick;begin @(posedge clk);#1;@(negedge clk);end endtask
 // Drain commit, fresh tag read, compare and data read before observing.
 task automatic settle;begin repeat(4) tick();end endtask
 integer n;
 initial begin
  tick();reset=0;tick();
  for(n=0;n<64;n=n+1) begin
   mva=n<<8;pa=32'h80000000+(n<<8);refill_line={8{32'h10000000+n}};settle();#1;
   if(!ready || hit || need)$fatal(1,"unexpected blocked fill %0d",n);
   refill=1;tick();refill=0;settle();
  end
  // A store request on a miss must neither dirty metadata nor write the
  // encoded default way. Write-hit qualification is now local to the bank.
  mva=64<<8;settle();store=1;mask=1;store_line={256{1'b1}};tick();store=0;mask=0;
  for(n=0;n<64;n=n+1)begin
   mva=n<<8;settle();
   if(!hit || dut.tags.hit_dirty!==0 || rline!=={8{32'h10000000+n}})$fatal(1,"miss store changed way %0d",n);
  end
  // An empty byte mask is not a dirtying operation, including a valid hit.
  mva=0;settle();store=1;mask=0;tick();store=0;tick();
  if(dut.tags.hit_dirty!==0)$fatal(1,"empty store dirtied a line");
  mva=0;settle();#1;if(!hit)$fatal(1,"first line missing");
  store=1;mask=1;store_line=0;store_line[7:0]=8'h7a;tick();store=0;mask=0;
  rv=0;settle();if(!rvalid || rline[7:0]!==8'h7a)$fatal(1,"hit data missing");
  mva=64<<8;pa=32'h90000000;refill_line={8{32'hdeadbeef}};settle();#1;
  if(!need || ready || victim_pa!==32'h80000000 || dirty!==2'b01)$fatal(1,"dirty victim not protected");
  rv=1;refill=1;tick();
  if(!rvalid || rline[7:0]!==8'h7a || hit || ready)$fatal(1,"stalled victim read changed");
  tick();if(!need || ready)$fatal(1,"writeback stall not retained");
  wb=1;#1;if(!ready)$fatal(1,"ack did not allow refill");tick();wb=0;refill=0;rv=0;settle();#1;
  if(!hit || need)$fatal(1,"replacement did not install");
  tick();if(!rvalid || rline!=={8{32'hdeadbeef}})$fatal(1,"refill data mismatch");
  mva=0;settle();#1;if(hit)$fatal(1,"old line still valid");
  // A captured store owns its address, payload and byte mask through commit.
  mva=64<<8;settle();store=1;mask=32'h00000006;
  store_line={8{32'h12345678}};tick();store=0;mask=0;
  mva=32'h20;store_line=0;settle();mva=64<<8;settle();
  if(rline[31:0]!==32'hde3456ef || dut.tags.hit_dirty!==1)
   $fatal(1,"store record lost transaction identity");
  // Indexed clean cancels a pending store, including its data half.
  store=1;mask=1;store_line=0;tick();store=0;sc=1;tick();sc=0;settle();
  if(rline[31:0]!==32'hde3456ef || dut.tags.hit_dirty!==0)
   $fatal(1,"maintenance failed to cancel pending store");
  // Write-through merges bytes without dirtying; upper-half dirty is independent.
  sd=0;store=1;mask=1;store_line={8{32'h000000aa}};tick();store=0;settle();
  if(rline[31:0]!==32'hde3456aa || dut.tags.hit_dirty!==0)
   $fatal(1,"write-through publication");
  sd=1;mva=(64<<8)|16;settle();store=1;mask=32'h00030000;
  store_line={8{32'h0000abcd}};tick();store=0;settle();
  if(rline[143:128]!==16'habcd || dut.tags.hit_dirty!==2)
   $fatal(1,"upper half store publication");
  // Reset/invalidation discard records that have been accepted but not committed.
  mva=32'h20;pa=32'h90000020;settle();refill=1;tick();refill=0;
  inv=1;tick();inv=0;settle();if(hit)$fatal(1,"invalidate published pending fill");
  refill=1;tick();refill=0;reset=1;tick();reset=0;settle();
  if(hit || vvalid)$fatal(1,"reset published pending fill");
  $display("PASS: associative bank holds dirty victim until acknowledged and refills");$finish;
 end
endmodule
