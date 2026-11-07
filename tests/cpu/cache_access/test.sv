`timescale 1ns/1ps
module test;
 logic fast=0;logic [31:0] fast_addr=0;wire fv;wire [31:0] fc;wire [255:0] fl;
 logic clk=0;always #5 clk=~clk;
 logic reset=1,req=0,wr=0,en=1,c=1,b=1,inv=0,lock=0,rr=1,allow=1,allow_reads=1,hold_after_refill=0;
 logic mv=0,mc=0,mi=0,ma=0,mb=0;logic [31:0] mad=0;logic [5:0] mw=0;logic [2:0] ms=0;wire mr,md,me;
 logic [31:0] mva=0,pa=0,wd=0;logic [3:0] ben=4'hf;
 wire ready,rv,re,bv,bw,wbempty,wberror;wire [31:0] rd,ba,bd;wire [3:0] bs;
 logic [31:0] mem[0:32767];integer reads=0,writes=0,n;
 logic prev_blocked=0,prev_we;logic [31:0] prev_addr,prev_data;logic [3:0] prev_sel;
 wire [31:0] br=mem[ba[16:2]];
 arm920_cache_access dut(.clk(clk),.reset(reset),.req_valid(req),.req_ready(ready),.req_mva(mva),.req_physical(pa),.req_write(wr),.req_cache_enable(en),.req_cacheable(c),.req_bufferable(b),.req_wdata(wd),.req_byte_enable(ben),.response_valid(rv),.response_error(re),.response_data(rd),.write_buffer_empty(wbempty),.write_buffer_error(wberror),.fast_lookup_enable(fast),.fast_lookup_address(fast_addr),.fast_lookup_valid(fv),.fast_lookup_checked(fc),.fast_lookup_line(fl),.invalidate_all(inv),.lock_write(lock),.lock_base_in(6'b0),.round_robin(rr),.maint_valid(mv),.maint_clean(mc),.maint_invalidate(mi),.maint_all(ma),.maint_by_mva(mb),.maint_address(mad),.maint_way(mw),.maint_segment(ms),.maint_ready(mr),.maint_done(md),.maint_error(me),.bus_valid(bv),.bus_write(bw),.bus_address(ba),.bus_wdata(bd),.bus_byte_enable(bs),.bus_ack(bv && (bw ? allow : allow_reads)),.bus_error(1'b0),.bus_rdata(br));
 always @(posedge clk) begin
  if(reset) prev_blocked<=0;
  else begin
   if(prev_blocked && (!bv || bw!==prev_we || ba!==prev_addr || bd!==prev_data || bs!==prev_sel))
    $fatal(1,"bus request changed before acknowledgement");
   prev_blocked<=bv && !(bw ? allow : allow_reads);
   if(bv)begin prev_we<=bw;prev_addr<=ba;prev_data<=bd;prev_sel<=bs;end
  end
 end
 always @(posedge clk) if(!reset && bv && (bw ? allow : allow_reads)) begin
  if(bw)begin writes<=writes+1;for(integer k=0;k<4;k=k+1)if(bs[k])mem[ba[16:2]][k*8+:8]<=bd[k*8+:8];end
  else begin reads<=reads+1;if(hold_after_refill)allow<=0;end
 end
 task automatic tick;begin @(posedge clk);#1;@(negedge clk);end endtask
 task automatic access(input logic write_op,input logic [31:0] a,input logic [31:0] data,input logic [3:0] mask,input logic bufferable,output logic [31:0] result);
  begin
   if(!ready)$fatal(1,"request not ready");mva=a;pa=32'h80000000+a;wd=data;ben=mask;b=bufferable;wr=write_op;req=1;tick();req=0;
   while(!rv)tick();if(re)$fatal(1,"unexpected access error");result=rd;
   // Existing data checks observe external memory after buffered stores drain.
   while(!wbempty)tick();
  end
 endtask
 logic [31:0] result;integer r0,w0;
 initial begin
  #200000;$fatal(1,"timeout");
 end
 initial begin
  for(n=0;n<32768;n=n+1)mem[n]=0;
  tick();reset=0;tick();
  access(1,32'h100,32'h12345678,4'hf,1,result);
  if(writes!=1 || reads!=0 || mem['h40]!==32'h12345678)$fatal(1,"write miss allocated or failed");
  mem['h40]=32'h11112222;
  access(0,32'h100,0,4'hf,1,result);
  if(result!==32'h11112222 || reads!=8)$fatal(1,"read miss failed result=%h reads=%0d",result,reads);
  r0=reads;w0=writes;
  access(1,32'h100,32'habcdef12,4'hf,1,result);
  access(0,32'h100,0,4'hf,1,result);
  if(result!==32'habcdef12 || reads!=r0 || writes!=w0 || mem['h40]!==32'h11112222)$fatal(1,"write-back hit");
  access(0,32'h4100,0,4'hf,1,result);
  if(writes!=w0 || reads!=r0+8)$fatal(1,"unnecessary conflicting eviction");
  access(0,32'h100,0,4'hf,1,result);
  if(result!==32'habcdef12 || reads!=r0+8)$fatal(1,"associative hit lost");
  // Clean by MVA affects only the selected dirty line.
  access(1,32'h4100,32'hcafebabe,4'hf,1,result);
  mc=1;ma=0;mb=1;mad=32'h100;mv=1;tick();mv=0;while(!md)tick();if(me)$fatal(1,"MVA clean failed");while(!wbempty)tick();tick();
  if(mem['h40]!==32'habcdef12 || mem['h1040]!==0)$fatal(1,"MVA clean affected wrong line");
  // The second line is way 1, segment 0. Indexed invalidate discards it.
  mc=0;mi=1;mb=0;mw=1;ms=0;mv=1;tick();mv=0;while(!md)tick();tick();
  r0=reads;access(0,32'h4100,0,4'hf,1,result);
  if(result!==0 || reads!=r0+8)$fatal(1,"indexed invalidate failed");
  mc=0;mi=1;mb=1;mad=32'h7f00;w0=writes;mv=1;tick();mv=0;
  while(!md)tick();tick();if(writes!=w0)$fatal(1,"missing MVA should do no write-back");
  mc=0;mi=0;mb=0;mw=0;
  // Fresh line, read then write-through: cached and external values must agree.
  access(0,32'h200,0,4'hf,0,result);w0=writes;
  access(1,32'h200,32'h56789abc,4'hf,0,result);
  access(0,32'h200,0,4'hf,0,result);
  if(result!==32'h56789abc || mem['h80]!==32'h56789abc || writes!=w0+1)$fatal(1,"write-through hit");
  // A write-through miss goes straight to the bus, with no fill.
  r0=reads;w0=writes;access(1,32'h300,32'h98765432,4'hf,0,result);
  if(reads!=r0 || writes!=w0+1 || mem['hc0]!==32'h98765432)$fatal(1,"write-through miss");
  // Whole-cache clean writes back the dirty WB line and leaves it resident.
  mc=1;ma=1;mv=1;tick();mv=0;while(!md)tick();if(me)$fatal(1,"clean all failed");tick();
  if(mem['h40]!==32'habcdef12)$fatal(1,"clean all lost dirty data");
  r0=reads;access(0,32'h100,0,4'hf,1,result);
  if(result!==32'habcdef12 || reads!=r0)$fatal(1,"clean invalidated line");
  mc=0;mi=1;mv=1;tick();mv=0;while(!md)tick();tick();
  r0=reads;access(0,32'h100,0,4'hf,1,result);
  if(result!==32'habcdef12 || reads!=r0+8)$fatal(1,"invalidate all failed");
  // Fill all 64 ways in one segment, then require an actual dirty eviction.
  mc=0;mi=1;ma=1;mv=1;tick();mv=0;while(!md)tick();tick();
  for(n=0;n<65;n=n+1)mem[(n<<8)>>2]=32'h01000000+n;
  access(0,0,0,4'hf,1,result);
  access(1,0,32'hdeadbeef,4'hf,1,result);
  access(1,16,32'hfaceb00c,4'hf,1,result);
  for(n=1;n<64;n=n+1)begin
   access(0,n<<8,0,4'hf,1,result);
   if(result!==32'h01000000+n)$fatal(1,"wrong way value %0d",n);
  end
  w0=writes;allow=0;allow_reads=0;mva=64<<8;pa=32'h80000000+mva;wr=0;req=1;tick();req=0;
  repeat(30)tick();
  if(wbempty || dut.buffer_entries!=2 || rv)$fatal(1,"dirty victim was not queued while memory stalled");
  hold_after_refill=1;allow=1;allow_reads=1;while(!rv)tick();result=rd;
  if(wbempty)$fatal(1,"dirty replacement waited for all writebacks before linefill");
  $display("OVERLAP: replacement completed after %0d of 8 writeback words",writes-w0);
  hold_after_refill=0;allow=1;while(!wbempty)tick();
  if(writes!=w0+8 || mem[0]!==32'hdeadbeef || mem[4]!==32'hfaceb00c || result!==32'h01000040)$fatal(1,"dirty 65th-way eviction");
  // Prime both streaming slots, then alternate them every cycle.
  access(0,32'h20,0,4'hf,1,result);
  fast=1;fast_addr=32'h20;mva=32'h20;repeat(5)tick();
  if(!fv || fl[31:0]!==0)$fatal(1,"fast lookup prime");
  fast_addr=32'h4000;mva=32'h4000;repeat(5)tick();
  for(n=0;n<12;n=n+1)begin
   mva=n[0] ? 32'h20 : 32'h4000;fast_addr=mva;#1;
   if(!fv || fc!==mva || fl[31:0]!==(n[0] ? 0 : 32'h01000040))
    $fatal(1,"stream address/data alignment");
   tick();
  end
  access(1,32'h20,32'hcafe1234,4'hf,1,result);
  fast_addr=32'h20;mva=32'h20;
  repeat(6)begin
   #1;if(fv && fl[31:0]!==32'hcafe1234)$fatal(1,"stale stream after store");tick();
  end
  if(!fv)$fatal(1,"stream did not recover after store");
  inv=1;#1;if(fv)$fatal(1,"stream survived invalidation");tick();inv=0;
  repeat(6)begin tick();if(fv)$fatal(1,"pending fast lookup survived invalidation");end
  reset=1;tick();reset=0;repeat(6)begin tick();if(fv)$fatal(1,"pending fast lookup survived reset");end
  $display("PASS: serialized associative accesses, WB/WT hits, maintenance and 65th-way eviction");$finish;
 end
endmodule
