`timescale 1ns/1ps
module tb;
 reg clk=0,reset=1,req=0,commit=0,we=0,periodic=0;
 reg [31:0] addr=0,din=0;reg [3:0] sel=15;
 wire claim,bad;wire [31:0] dout;
 always #5 clk=~clk;
 ngage_icu_extra dut(clk,reset,req,commit,we,periodic,addr,din,sel,claim,bad,dout);
 task write_word;input [31:0] a,d;begin @(negedge clk);addr=a;din=d;req=1;we=1;commit=1;#1;if(!claim||bad)$fatal(1,"write %h",a);@(negedge clk);req=0;commit=0;end endtask
 task read_word;input [31:0] a,d;begin @(negedge clk);addr=a;req=1;we=0;#1;if(!claim||bad||dout!==d)$fatal(1,"read %h = %h",a,dout);req=0;end endtask
 initial begin
  repeat(2)@(negedge clk);reset=0;
  addr=32'h0c120040;req=1;#1;if(claim)$fatal(1,"low bank before timer");req=0;
  periodic=1;write_word(32'h0c120040,32'h11223344);write_word(32'h0c120340,32'h55667788);write_word(32'h0c120600,32'h99aabbcc);
  read_word(32'h0c120040,32'h11223344);read_word(32'h0c120340,32'h55667788);read_word(32'h0c120600,32'h99aabbcc);
  @(negedge clk);addr=32'h0c120348;din=2;req=1;we=1;commit=1;#1;if(!claim||!bad)$fatal(1,"DMA start must fail");
  @(negedge clk);addr=32'h0c120600;sel=3;#1;if(!bad)$fatal(1,"bad width");
  req=0;commit=0;sel=15;read_word(32'h0c120348,0);
  $display("PASS ICU and epbus independent latches, unsupported DMA and widths");$finish;
 end
endmodule
