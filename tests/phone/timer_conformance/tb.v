`timescale 1ns/1ps
// Programmable timer/ICU ownership. The former staged C++ oracle deliberately
// retained fixed delays and boot whitelists and is no longer a hardware oracle.
module tb;
reg clk=0;always #5 clk=~clk;
reg reset=1,req=0,commit=0,we=0,uem=0;
reg [31:0] addr=0,din=0;
wire tc,tb,ic,ib,irq,fiq,rearm;wire [31:0] td,id;wire [5:0] pending;
wire [95:0] clear;
wire [95:0] irq_sources={90'd0,pending}|{94'd0,uem,1'b0};
wire [95:0] fiq_sources={90'd0,pending};
integer cycles=0,cases=0;
always @(posedge clk)cycles=cycles+1;
ngage_timers timers(clk,reset,req,commit,we,addr,din,4'hf,1'b0,tc,tb,td,
 ,,,rearm,,1'b0,pending);
ngage_icu icu(clk,reset,req,commit,we,addr,din,4'hf,irq_sources,fiq_sources,
 ic,ib,id,irq,fiq,clear,rearm);
task tick;begin @(posedge clk);#1;end endtask
task wr(input [31:0] a,input [31:0] d);begin
 @(negedge clk);req=1;commit=1;we=1;addr=a;din=d;#1;
 if((!tc&&!ic)||(tc?tb:ib))$fatal(1,"write rejected %h",a);
 tick();@(negedge clk);req=0;commit=0;we=0;
end endtask
task rd(input [31:0] a,input [31:0] expected);begin
 @(negedge clk);req=1;commit=0;we=0;addr=a;#1;
 if((!tc&&!ic)||(tc?tb:ib)||(tc?td:id)!==expected)
  $fatal(1,"read%h got%h expected%h",a,tc?td:id,expected);
 cases=cases+1;@(negedge clk);req=0;
end endtask
task check(input condition,input [255:0] name);begin
 if(!condition)$fatal(1,"%s cycle%0d",name,cycles);cases=cases+1;
end endtask
initial begin
 tick();@(negedge clk);reset=0;
 // Masked IRQ1 expiry remains pending, including across mask-clear writes.
 wr('h0c120a30,30);wr('h0c120a24,1);repeat(31)tick();
 check(!irq&&pending[1],"masked timer pending");rd('h0c120110,2);
 wr('h0c120108,2);check(irq,"unmask existing event");rd('h0c120114,2);
 wr('h0c12010c,2);check(!irq&&pending[1],"mask is not timer ACK");
 wr('h0c120108,2);uem=1;wr('h0c120a28,1);
 check(irq&&!pending[1],"timer ACK preserves shared UEM");rd('h0c120110,2);
 uem=0;#1;check(!irq,"shared producer release");
 // Timer0 reload does not alter IRQ enables. A stopped/ACKed timer alone
 // releases its level; the original periodic reload need not be a magic value.
 wr('h0c120108,1);wr('h0c120a04,2);wr('h0c120a18,64);rd('h0c120108,3);
 wr('h0c120a10,64);repeat(65)tick();check(irq&&pending[0],"ordinary timer0 expiry");
 wr('h0c120a04,0);wr('h0c120a08,0);check(!irq,"timer0 stop ACK");
 // A masked timer3 must not steal current from enabled timer4 in either plane.
 wr('h0c120a70,25);wr('h0c120a64,1);wr('h0c120a90,25);wr('h0c120a84,1);
 wr('h0c1201c8,16);repeat(26)tick();check(fiq,"enabled timer4 FIQ");
 rd('h0c1201d0,24);rd('h0c1201d4,5);
 wr('h0c120a88,1);check(!fiq&&pending[3],"timer4 ACK preserves masked timer3");
 wr('h0c1201c8,8);check(fiq,"timer3 unmask");rd('h0c1201d4,4);
 wr('h0c1201cc,8);check(!fiq&&pending[3],"FIQ mask retains producer");
 wr('h0c1201c8,8);wr('h0c120a68,0);check(!fiq&&!pending[3],"timer3 explicit ACK");
 $display("PASS programmable timer ICU ownership cases=%0d cycles=%0d",cases,cycles);$finish;
end
endmodule
