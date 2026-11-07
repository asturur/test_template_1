`timescale 1ns/1ps
module test;
 reg clk=0,reset=1,fill=0,write_hit=0,invalidate_line=0,invalidate_all=0,clean_hit=0,lock_write=0,rr=1;
 reg [31:0] mva=0,pa=0;reg [5:0] lock_in=0;
 wire hit,vvalid;wire [5:0] hit_way,vway,lock_base;wire [1:0] hd,vd;wire [31:0] hp,vp;
 always #5 clk=~clk;
 arm920_cache_tags dut(.clk(clk),.reset(reset),.mva(mva),.hit(hit),.hit_way(hit_way),.hit_dirty(hd),.hit_physical_line(hp),
 .victim_way(vway),.victim_valid(vvalid),.victim_dirty(vd),.victim_physical_line(vp),.fill(fill),.fill_physical(pa),
 .write_hit(write_hit),.invalidate_line(invalidate_line),.invalidate_all(invalidate_all),.clean_hit(clean_hit),
 .lock_write(lock_write),.lock_base_in(lock_in),.lock_base(lock_base),.round_robin(rr),.scan_segment(3'b0),.scan_way(6'b0),.scan_valid(),.scan_dirty(),.scan_physical_line(),.scan_clean(1'b0),.scan_invalidate(1'b0));
 task automatic tick;begin @(posedge clk);#1;@(negedge clk);end endtask
 integer n;
 initial begin
  tick();reset=0;tick();
  // 64 distinct tags in the same segment must coexist in round-robin mode.
  for(n=0;n<64;n=n+1) begin
   mva=n<<8;pa=32'h80000000+(n<<8);tick();tick();#1;
   if(hit || vway!==n || vvalid) $fatal(1,"allocation n=%0d hit=%b victim=%d valid=%b",n,hit,vway,vvalid);
   fill=1;tick();fill=0;tick();
  end
  for(n=0;n<64;n=n+1) begin
   mva=n<<8;tick();tick();#1;
   if(!hit || hit_way!==n || hp!==(32'h80000000+(n<<8))) $fatal(1,"lookup n=%0d hit=%b way=%d PA=%h",n,hit,hit_way,hp);
  end
  // A different segment has independent tags and its own victim counter.
  mva=32'h20;pa=32'ha0000020;tick();tick();#1;
  if(hit || vway!==0 || vvalid) $fatal(1,"segment isolation before fill");
  fill=1;tick();fill=0;mva=0;tick();tick();#1;
  if(!hit || hit_way!==0) $fatal(1,"segment allocation clobbered another segment");
  mva=0;tick();write_hit=1;tick();write_hit=0;mva=16;tick();write_hit=1;tick();write_hit=0;tick();tick();#1;
  if(hd!==2'b11) $fatal(1,"dirty halves %b",hd);
  mva=64<<8;tick();tick();#1;
  if(hit || vway!==0 || !vvalid || vd!==2'b11 || vp!==32'h80000000) $fatal(1,"victim data incorrect");
  // Caller may fill only once it has dealt with the dirty victim.
  fill=1;pa=32'h90000000;tick();fill=0;tick();tick();#1;
  if(!hit || hit_way!==0 || hd!==0) $fatal(1,"replacement missing");
  clean_hit=1;tick();clean_hit=0;invalidate_line=1;tick();invalidate_line=0;tick();tick();#1;
  if(hit) $fatal(1,"single invalidate failed");
  lock_in=6'd3;lock_write=1;tick();lock_write=0;mva=32'h1020;tick();tick();#1;
  if(lock_base!==3 || vway!==3) $fatal(1,"lockdown victim base");
  invalidate_all=1;tick();invalidate_all=0;mva=32'h100;tick();tick();#1;
  if(hit || lock_base!==3) $fatal(1,"invalidate must clear lines but preserve lockdown");
  lock_in=63;lock_write=1;tick();lock_write=0;tick();tick();#1;
  if(vway!==63) $fatal(1,"round-robin lockdown at final way");
  fill=1;pa=32'h90000100;tick();fill=0;mva=32'h200;tick();tick();#1;
  if(vway!==63) $fatal(1,"round-robin must wrap to lockdown base");
  rr=0;tick();tick();#1;if(vway!==63) $fatal(1,"random victim must respect lockdown base");
  lock_in=6'd4;lock_write=1;tick();lock_write=0;tick();tick();#1;
  if(vway!==4)$fatal(1,"random mode must use the explicitly written victim first");
  $display("PASS: 64-way tags, dirty halves, physical victim and lockdown");$finish;
 end
endmodule
