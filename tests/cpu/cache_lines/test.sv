`timescale 1ns/1ps
module test;
 reg clk=0;always #5 clk=~clk;
 reg [2:0] rs=0,ws=0;reg [5:0] rw=0,ww=0;reg [31:0] wen=0;reg [255:0] data=0;wire [255:0] out;
 arm920_cache_lines dut(.clk(clk),.read_segment(rs),.read_way(rw),.read_line(out),
  .write_segment(ws),.write_way(ww),.write_enable(wen),.write_line(data));
 task automatic tick;begin @(posedge clk);#1;@(negedge clk);end endtask
 reg [255:0] a,b,expected;
 initial begin
  for(integer i=0;i<32;i=i+1) begin a[i*8+:8]=i;b[i*8+:8]=8'h80+i;end
  ww=5;ws=3;data=a;wen='1;tick();wen=0;
  ww=6;ws=3;data=b;wen='1;tick();wen=0;
  rw=5;rs=3;tick();if(out!==a)$fatal(1,"line A mismatch");
  rw=6;tick();if(out!==b)$fatal(1,"line B mismatch");
  ww=5;ws=3;data='1;wen=32'h80010001;tick();wen=0;
  expected=a;expected[7:0]=8'hff;expected[16*8+:8]=8'hff;expected[31*8+:8]=8'hff;
  rw=5;tick();if(out!==expected)$fatal(1,"byte update mismatch");
  rw=6;tick();if(out!==b)$fatal(1,"neighbor overwritten");
  ww=5;ws=4;data=b;wen='1;tick();wen=0;
  rw=5;rs=3;tick();if(out!==expected)$fatal(1,"segment isolation failed");
  rs=4;tick();if(out!==b)$fatal(1,"second segment mismatch");
  $display("PASS: cache lines, byte masks and way/segment isolation");$finish;
 end
endmodule
