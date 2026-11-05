`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;reg reset=1,req=0,commit=0,we=0;reg [31:0] addr=0,din=0;reg [3:0] sel=15;reg [15:0] a=0,c=0,b=0;wire claim,bad;wire [31:0] dout;
ngage_gpio_loopback dut(clk,reset,req,commit,we,addr,din,sel,a,c,b,claim,bad,dout);
task tick;begin @(posedge clk);#1;end endtask
task wr;input [31:0] x,y;input [3:0] z;begin @(negedge clk);req=1;we=1;commit=1;addr=x;din=y;sel=z;tick();@(negedge clk);req=0;commit=0;end endtask
task read_mask;input [31:0] x,m,v;begin @(negedge clk);req=1;we=0;addr=x;sel=15;#1;if(!claim||bad||(dout&m)!==v)$fatal(1,"read %h got %h",x,dout);@(negedge clk);req=0;end endtask
initial begin
 tick();reset=0;tick();a=8;b='h400;c='h20;
 wr('h0c150200,'h00050000,12);read_mask('h0c150208,'h000a0000,'h000a0000);
 wr('h0c150204,'h00000001,3);read_mask('h0c150208,'h000a0000,'h00080000);
 wr('h0c150204,'h00050000,12);read_mask('h0c15020c,2,2);
 wr('h0c150208,1,3);read_mask('h0c15020c,2,0);
 wr('h0c15021c,'h0080ffff,15);read_mask('h0c15021c,'h00c0ffff,'h00c00000);
 @(negedge clk);req=1;we=1;commit=0;addr='h0c150200;din='h00010000;sel=12;tick();req=0;read_mask('h0c150208,'h00020000,0);
 $display("PASS GPIO set/clear and UEM routed loopbacks");$finish;
end
endmodule
