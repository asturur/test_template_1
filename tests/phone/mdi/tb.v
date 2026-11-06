`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;reg reset=1,slow_tick=0,periodic=1,req=0,commit=0,we=0;reg [31:0] addr=0,din=0;reg [3:0] sel=15;
wire claim,bad;wire [31:0] dout;wire [15:0] events;reg [15:0] sampled_events;
always @(posedge clk) sampled_events<=events;
ngage_mdi_stub #(.ANNOUNCE_TICKS(20)) dut(clk,reset,slow_tick,periodic,req,commit,we,addr,din,sel,claim,bad,dout,events);
task tick;begin @(posedge clk);#1;end endtask
task wr;input [31:0] a,d;input [3:0] b;begin @(negedge clk);req=1;we=1;commit=1;addr=a;din=d;sel=b;#1;if(!claim||bad)$fatal(1,"decode");tick();@(negedge clk);req=0;commit=0;end endtask
task beat;begin @(negedge clk);slow_tick=1;tick();@(negedge clk);slow_tick=0;end endtask
task rd;input [31:0] a,expected;begin @(negedge clk);req=1;we=0;addr=a;sel=15;#1;if(!claim||bad||dout!==expected)$fatal(1,"read %h got %h expected %h",a,dout,expected);@(negedge clk);req=0;end endtask
initial begin
 tick();reset=0;
 // Stalled reads must not mark ring pointers as initialized.
 @(negedge clk);req=1;we=0;commit=0;addr='h0c1003e8;sel=15;repeat(3)tick();
 if(dut.pointers_seen)$fatal(1,"stalled read changed pointer state");
 commit=1;tick();if(!dut.pointers_seen)$fatal(1,"committed read did not set pointer state");
 @(negedge clk);req=0;commit=0;
 wr('h0c14b004,'h500,15);wr('h0c1003e8,'h00000002,15);wr('h0c1003ec,0,15);
 beat();if(!sampled_events[9])$fatal(1,"M2D not consumed");rd('h0c1003e8,'h00020002);
 repeat(19)beat();if(sampled_events[10])$fatal(1,"early announcement");beat();if(!sampled_events[10])$fatal(1,"missing announcement");
 rd('h0c1001f4,'h7cd00000);rd('h0c1001f8,'h04000001);rd('h0c1003ec,4);beat();if(sampled_events[10])$fatal(1,"repeated announcement");
 @(negedge clk);req=1;we=1;commit=0;addr='h0c1003e8;din=0;sel=15;tick();req=0;rd('h0c1003e8,'h00020002);
 wr('h0c1003e8,3,3);
 @(negedge clk);slow_tick=1;req=1;we=1;commit=1;addr='h0c1003e8;sel=12;din='hbeef0000;tick();
 if(!sampled_events[9])$fatal(1,"simultaneous consumption event");
 @(negedge clk);slow_tick=0;req=0;commit=0;rd('h0c1003e8,'h00030003);
 $display("PASS staged MDI ring announcement and consumption");$finish;
end
endmodule
