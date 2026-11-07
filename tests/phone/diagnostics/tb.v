`timescale 1ns/1ps
module tb;
reg clk=0,cold=1,fault=0,fetch=0,tv=0;reg [31:0] fa=0,ta=0,td=0;reg [2:0] reason=0;reg [3:0] sel=0;reg [10:0] ra=0;wire [15:0] data;wire seen;integer i;
always #5 clk=~clk;
ngage_diagnostics dut(.clk(clk),.cold_reset(cold),.freeze_trace(1'b0),.fault(fault),.fault_is_fetch(fetch),.fault_address(fa),.fault_reason(reason),.trace_valid(tv),.trace_lost(1'b0),.trace_addr(ta),.trace_data(td),.trace_sel(sel),.read_word(ra),.read_data(data),.fault_seen(seen));
task check;input [10:0] index;input [15:0] expected;begin @(negedge clk);ra=index;@(negedge clk);#1;if(data!==expected)begin $display("FAIL debug word %d got %h want %h",index,data,expected);$finish;end end endtask
initial begin
 repeat(2)@(negedge clk);cold=0;
 @(negedge clk);fault=1;fetch=1;fa=32'h0c0047e4;reason=1;@(negedge clk);fault=0;fetch=0;
 if(seen)begin $display("FAIL speculative fetch reported as data fault");$finish;end
 check(393,'h47e4);check(394,'h0c00);check(395,9);
 @(negedge clk);fault=1;fa=32'h12345678;reason=3;@(negedge clk);fa=32'hffffffff;reason=1;@(negedge clk);fault=0;
 check(8,0);check(0,'h4e47);check(2,'h5678);check(3,'h1234);check(4,'hb);
 for(i=0;i<65;i=i+1)begin @(negedge clk);tv=1;ta=i;td=i+100;sel=4'h3;end
 @(negedge clk);tv=0;check(5,64);check(6,1);check(7,1);check(8,64);check(10,164);check(12,3);
 // A pending fault must not survive a cold reset; opposite fault kinds on
 // consecutive clocks must retain their independently sampled address/reason.
 @(negedge clk);cold=1;@(negedge clk);cold=0;fault=1;fetch=1;fa=32'h00112233;reason=2;
 @(negedge clk);fetch=0;fa=32'h44556677;reason=3;
 @(negedge clk);fault=0;fa=0;reason=0;
 check(393,'h2233);check(394,'h0011);check(395,10);
 check(2,'h6677);check(3,'h4455);check(4,11);
 @(negedge clk);cold=1;@(negedge clk);cold=0;fault=1;fa=32'hdeadbeef;
 @(negedge clk);cold=1;fault=0;@(negedge clk);cold=0;
 check(4,0);check(395,0);
 $display("PASS pipelined diagnostic readout: coherent back-to-back fetch/data faults, cold flush, wrap and sticky history");$finish;
end
endmodule
