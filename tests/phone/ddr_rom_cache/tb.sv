`timescale 1ns/1ps
module tb;
parameter LINE_BITS=64,CACHE_BYTES=1024;
reg clk=0,reset=1,valid=0,write_op=0,busy=0,ready=0,hold_response=0,fetch=1;
always #5 clk=~clk;
reg [31:0] address=0,wdata=0;reg [3:0] mask=15;
wire [7:0] burst;wire accept,rsp,rd,wr;wire [31:0] q;wire [28:0] da;wire [63:0] wd;wire [7:0] be;
reg [63:0] rdata=0,memory[0:2047];reg [10:0] pending_addr;integer pending=0,pending_beats=0,reads=0,writes=0,i,n,latency,hit_latency;
ngage_ddr_adapter #(.ROM_CACHE(1),.ROM_CACHE_BITS(LINE_BITS),.ROM_CACHE_BYTES(CACHE_BYTES)) dut(
 .ddr_burstcount(burst),.req_fetch(fetch),.clk(clk),.reset(reset),.req_valid(valid),.req_ready(accept),.req_write(write_op),.req_addr(address),.req_wdata(wdata),.req_be(mask),
 .rsp_valid(rsp),.rsp_data(q),.ddr_addr(da),.ddr_din(wd),.ddr_be(be),.ddr_rd(rd),.ddr_we(wr),.ddr_busy(busy),.ddr_dout(rdata),.ddr_dout_ready(ready));
always @(posedge clk) begin
 ready<=0;
 if(rd && !busy)begin
  if(pending!=0)$fatal(1,"overlapping DDR read");
  pending_addr<=da[10:0];pending_beats<=burst;pending<=3+reads%5;reads<=reads+1;
 end
 if(pending!=0 && !hold_response)begin
  pending<=pending-1;
  if(pending==1)begin
   rdata<=memory[pending_addr];ready<=1;
   if(pending_beats>1)begin pending<=1;pending_beats<=pending_beats-1;pending_addr<=pending_addr+1'b1;end
  end
 end
 if(wr && !busy)begin
  for(integer j=0;j<8;j=j+1)if(be[j])memory[da[10:0]][j*8+:8]<=wd[j*8+:8];
  writes<=writes+1;
 end
end
task transact(input bit w,input [31:0] a,input [31:0] data,input [3:0] bytes,input [31:0] expected,input integer misses);
 integer before_reads;begin
 @(negedge clk);while(!accept)@(negedge clk);
 address=a;wdata=data;mask=bytes;write_op=w;valid=1;before_reads=reads;
 // The producer may change its pins immediately after acceptance.
 @(negedge clk);valid=0;address=32'hdeadbeec;wdata=~data;mask=0;write_op=~w;n=0;
 while(!rsp && n<200)begin @(negedge clk);n=n+1;end
 if(!rsp)$fatal(1,"request timeout %h state%0d",a,dut.cached.cache.state);
 if(!w && q!==expected)$fatal(1,"read %h got%h want%h",a,q,expected);
 if(reads-before_reads!=misses)$fatal(1,"unexpected DDR reads at%h got%0d want%0d",a,reads-before_reads,misses);
 latency=n;@(negedge clk);if(rsp)$fatal(1,"duplicate completion");
 end endtask
// Start the next request while the previous response pulse is still visible.
// This stresses lookup ownership with no inserted idle cycle and a new index,
// a conflicting tag, a returning tag and the other word of the same line.
task tight_read(input [31:0] a,input [31:0] expected);
 begin
 while(!accept)@(negedge clk);
 address=a;valid=1;write_op=0;mask=15;
 @(negedge clk);valid=0;address=32'hdeadbeec;n=0;
 while(!rsp && n<200)begin @(negedge clk);n=n+1;end
 if(!rsp || q!==expected)$fatal(1,"tight read %h got%h want%h",a,q,expected);
 end endtask
task abort_at(input integer stage);begin
 @(negedge clk);reset=1;@(negedge clk);reset=0;
 while(pending!=0)@(negedge clk);
 @(negedge clk);valid=1;write_op=0;address=32'h30000040;
 @(negedge clk);valid=0;
 wait(dut.cached.cache.state==stage);
 @(negedge clk);reset=1;@(negedge clk);reset=0;
 repeat(25)begin @(negedge clk);if(rsp)$fatal(1,"stale completion after reset stage%0d",stage);end
 transact(0,32'h30000040,0,15,32'h10000010,1);
 end endtask
initial begin
 for(i=0;i<2048;i=i+1)memory[i]={32'h10000001+32'd2*i,32'h10000000+32'd2*i};
 repeat(3)@(negedge clk);reset=0;
 transact(0,32'h30000000,0,15,32'h10000000,1);
 transact(0,32'h30000004,0,15,32'h10000001,0);hit_latency=latency;
 if(hit_latency!=1)$fatal(1,"resident hit latency %0d expected1",hit_latency);
 for(i=0;i<32;i=i+1)begin
  transact(0,32'h30000000,0,15,32'h10000000,0);
  transact(0,32'h30000004,0,15,32'h10000001,0);
 end
 for(i=0;i<8;i=i+1)begin
  tight_read(32'h30000000,32'h10000000);
  tight_read(32'h30000040,32'h10000010);
  tight_read(32'h30000000+CACHE_BYTES,32'h10000000+CACHE_BYTES/4);
  tight_read(32'h30000000,32'h10000000);
  tight_read(32'h30000004,32'h10000001);
 end
 @(negedge clk);
 transact(0,32'h30000000+CACHE_BYTES,0,15,32'h10000000+CACHE_BYTES/4,1);
 transact(0,32'h30000000,0,15,32'h10000000,1);
 // ROM data/literal/file reads bypass and do not evict instruction lines.
 fetch=0;
 transact(0,32'h30000000+CACHE_BYTES,0,15,32'h10000000+CACHE_BYTES/4,1);
 transact(0,32'h30000000+CACHE_BYTES,0,15,32'h10000000+CACHE_BYTES/4,1);
 fetch=1;transact(0,32'h30000000,0,15,32'h10000000,0);
 // Sequential new lines, both lanes and short gaps expose stale tag/data.
 for(i=0;i<32;i=i+1)begin
  transact(0,32'h30001000+i*8,0,15,32'h10000400+i*2,(i%(LINE_BITS/64)==0)?1:0);
  transact(0,32'h30001004+i*8,0,15,32'h10000401+i*2,0);
 end
 // Firmware reload writes invalidate the raw cache, including partner word.
 transact(1,32'h30000004,32'h89abcdef,15,0,0);
 transact(0,32'h30000004,0,15,32'h89abcdef,1);
 transact(1,32'h30000004,32'h11223344,5,0,0);
 transact(0,32'h30000004,0,15,32'h8922cd44,1);
 // Mutable C:/PMM and guard are never cached.
 transact(0,32'h31800000,0,15,32'h10000000,1);
 transact(0,32'h31800000,0,15,32'h10000000,1);
 transact(0,32'h313f0000,0,15,32'h10000000,1);
 transact(0,32'h313f0000,0,15,32'h10000000,1);
 abort_at(1);abort_at(2);abort_at(3);abort_at(4);abort_at(5);
 // Reset during accepted DDR read; queue a new address before stale reply.
 @(negedge clk);reset=1;@(negedge clk);reset=0;hold_response=1;
 valid=1;write_op=0;address=32'h30000080;@(negedge clk);valid=0;
 wait(pending!=0);@(negedge clk);reset=1;@(negedge clk);reset=0;
 address=32'h30000088;valid=1;@(negedge clk);valid=0;
 repeat(8)begin @(negedge clk);if(rsp)$fatal(1,"response before drain");end
 hold_response=0;n=0;while(!rsp && n<200)begin @(negedge clk);n=n+1;end
 if(!rsp || q!==32'h10000022)$fatal(1,"late response poisoned next request %h",q);
 if(LINE_BITS>64)begin
  // Cancel after the first physical beat; remaining beats must drain before
  // the next miss may use the same DDR response channel.
  @(negedge clk);reset=1;@(negedge clk);reset=0;
  repeat(3)@(negedge clk);
  valid=1;write_op=0;address=32'h30000100;
  @(negedge clk);valid=0;
  wait(ready);@(negedge clk);hold_response=1;
  @(negedge clk);reset=1;
  @(negedge clk);reset=0;valid=1;address=32'h30000148;
  @(negedge clk);valid=0;
  repeat(4)begin @(negedge clk);if(rsp)$fatal(1,"partial burst escaped reset");end
  hold_response=0;n=0;while(!rsp && n<200)begin @(negedge clk);n=n+1;end
  if(!rsp || q!==32'h10000052)$fatal(1,"partial burst poisoned new fill %h",q);
 end
 $display("PASS DDR ROM cache: lane/reuse/conflict/masked reload/bypass/reset stages/stale drain, hit latency=%0d clocks",hit_latency);$finish;
end
initial begin #200000;$fatal(1,"timeout");end
endmodule
