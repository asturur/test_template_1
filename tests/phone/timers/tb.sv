`timescale 1ns/1ps
// Public-register checks. No firmware values, internal timer state, or boot delays.
module tb;
parameter integer DIV=1;
reg clk=0; always #5 clk=~clk;
reg reset=1,req=0,commit=0,we=0,clear1=0;
reg [31:0] addr=0,din=0;reg [3:0] sel=15;
wire claim,bad,p0,p1,p60,rearm,periodic;wire [31:0] dout;wire [5:0] pending;
integer cycles=0, cases=0,n,k,first,last,elapsed;reg [31:0] saved;
always @(posedge clk) cycles=cycles+1;
ngage_timers #(.CLOCK_DIV(DIV)) dut(clk,reset,req,commit,we,addr,din,sel,clear1,
 claim,bad,dout,p0,p1,p60,rearm,periodic,1'b0,pending);
task tick;begin @(posedge clk);#1;end endtask
task fresh;begin @(negedge clk);reset=1;req=0;commit=0;we=0;tick();@(negedge clk);reset=0;end endtask
task wr(input integer unit_no,input integer off,input [31:0] value);begin
 @(negedge clk);req=1;we=1;commit=1;addr=32'h0c120a00+32*unit_no+off;din=value;#1;
 if(!claim||bad)$fatal(1,"write rejected %h=%h",addr,din);
 tick();@(negedge clk);req=0;commit=0;we=0;
end endtask
task read_count(input integer unit_no);begin
 addr=32'h0c120a10+32*unit_no;req=1;we=0;#1;
 if(!claim||bad)$fatal(1,"read rejected");saved=dout;req=0;
end endtask
task check(input condition,input [255:0] name);begin
 if(!condition)$fatal(1,"DIV%0d %s cycle%0d",DIV,name,cycles);cases=cases+1;
end endtask
initial begin
 fresh();
 // All six timers accept arbitrary values and expose live descending counts.
 for(n=0;n<6;n=n+1)begin
  wr(n,16,1000+n);read_count(n);check(saved==1000+n,"stopped load readback");
  wr(n,4,1);read_count(n);saved=saved;
  begin : live
   reg [31:0] before_count;before_count=saved;
   repeat(10*DIV)tick();read_count(n);
   check(saved==before_count-10,"live count");
  end
  wr(n,4,0);read_count(n);
  begin : stopped
   reg [31:0] before_count;before_count=saved;
   repeat(9*DIV)tick();read_count(n);check(saved==before_count,"stop retains count");
  end
 end
 fresh();
 // One-shot expiry and reprogram after expiry; ACK accepts either ISR value.
 wr(1,16,11);wr(1,4,1);
 elapsed=0;while(!p1 && elapsed<12*DIV)begin tick();elapsed=elapsed+1;end
 check(p1,"oneshot expiry");read_count(1);check(saved==0,"oneshot stops zero");
 wr(1,8,1);check(!p1,"ACK one");wr(1,16,23);
 repeat(12*DIV)tick();check(!p1,"rearm not premature");
 repeat(12*DIV)tick();check(p1,"oneshot count rearm");
 // Completion status resets for a new deadline, while an older IRQ event
 // remains owned by the explicit ACK. This is required by repeated original
 // timer2 polling and must not become an implicit producer acknowledgement.
 wr(1,16,100);check(p1,"reprogram retains pending IRQ");
 addr=32'h0c120a28;req=1;we=0;#1;check(dout==0,"new deadline clears completion");req=0;
 wr(1,8,0);check(!p1,"ACK zero");
 fresh();
 // NEM-4 medint: reload390, count390, ctrl2, repeated ACK0. ACK does
 // not substitute a constant delay and leaves the running phase intact.
 wr(3,24,390);wr(3,16,390);wr(3,4,2);
 repeat(128*DIV)tick();check(!p60,"390 has no fixed128 expiry");
 elapsed=0;while(!p60 && elapsed<391*DIV)begin tick();elapsed=elapsed+1;end
 check(p60,"390 expiry");first=cycles;wr(3,8,0);check(!p60,"FIQ ACK");
 while(!p60 && cycles-first<391*DIV)tick();check(cycles-first==390*DIV,"programmed reload period");
 wr(3,4,0);wr(3,8,0);repeat(400*DIV)tick();check(!p60,"stop cancels periodic deadline");
 fresh();
 // All counters advance in parallel, rather than sharing a serial counter.
 for(n=0;n<6;n=n+1)begin wr(n,24,50);wr(n,16,50);wr(n,4,2);end
 repeat(51*DIV)tick();check(pending==6'b111111,"six parallel producers");
 for(n=0;n<6;n=n+1)wr(n,4,0);
 for(n=0;n<6;n=n+1)begin wr(n,8,0);check(!pending[n],"independent producer ACK");end
 fresh();
 // Zero is a 32-bit wrap, not immediate expiry; no invented zero-load event.
 wr(2,16,0);wr(2,4,1);repeat(3*DIV)tick();read_count(2);
 check(saved>32'hfffffff0 && !pending[2],"zero count rollover");
 wr(2,4,0);wr(2,16,4);wr(2,4,1);wr(2,16,100);
 repeat(10*DIV)tick();check(!pending[2],"reprogram cancels old deadline");
 fresh();
 // Align an ACK to the expiry edge: a new event survives ACK. This explicit
 // digital policy is retained from our prior model; board edge order unmeasured.
 wr(0,16,10);wr(0,4,1);
 wait(dut.g_timer[0].count==1);@(negedge clk);
 while(dut.divider!=DIV-1)@(negedge clk);
 req=1;we=1;commit=1;addr=32'h0c120a08;din=0;tick();check(p0,"expiry dominates same-edge ACK");
 @(negedge clk);req=0;we=0;commit=0;wr(0,8,0);check(!p0,"later ACK clears expiry");
 wr(0,16,64);check(!rearm,"reload has no ICU mask authority");
 @(negedge clk);addr=32'h0c120a08;din=1;req=1;we=1;commit=0;tick();check(!p0,"uncommitted no effect");
 sel=3;commit=1;#1;check(bad,"partial width rejected");tick();
 sel=15;addr=32'h0c120a09;#1;check(bad,"unaligned rejected");
 $display("PASS programmable six timers DIV=%0d cases=%0d cycles=%0d",DIV,cases,cycles);$finish;
end
initial begin #2000000;$fatal(1,"timeout");end
endmodule
