`timescale 1ns/1ps
module tb;
 reg clk=0,reset=1,cold_reset=1,cyc=0,stb=0,we=0;
 reg [31:0] adr=0,din=0; reg [3:0] sel=15;
 wire claim,fallback,ack,err,irq,fiq,init_done,trace_valid;
 wire [31:0] dout,trace_addr,trace_data;wire [3:0] trace_sel;
 always #5 clk=~clk;
 ngage_board_sim dut(clk,reset,cold_reset,cyc,stb,we,adr,din,sel,claim,fallback,ack,err,dout,irq,fiq,init_done,trace_valid,trace_addr,trace_data,trace_sel);
 initial begin
  repeat(2) @(negedge clk); cold_reset=0; wait(init_done); @(negedge clk); reset=0;
  cyc=1;stb=1;adr=32'h0c150420;sel=3;we=1;din=7; #1;
  if(!claim || fallback || !ack || err) $fatal(1,"owned transaction");
  @(negedge clk); cyc=0;stb=0; #1;
  cyc=1;stb=1;adr=32'h0c150420;sel=5; #1;
  if(!claim || fallback || ack || !err) $fatal(1,"claimed invalid transaction");
  cyc=1;stb=1;adr=32'h40000000;sel=15; #1;
  if(claim || !fallback || ack || err) $fatal(1,"fallback transaction");
  @(negedge clk);cyc=1;stb=1;we=1;adr=32'h0c030220;din=32'h12345678;sel=15;
  #1;if(!ack) $fatal(1,"upload RAM write"); @(negedge clk);cyc=0;stb=0;
  reset=1;@(negedge clk);reset=0;
  cyc=1;stb=1;we=0;adr=32'h0c030220;wait(ack);#1;if(dout!==32'h12345678)$fatal(1,"warm reset lost RAM");
  @(negedge clk);cyc=0;stb=0;reset=1;cold_reset=1;
  @(negedge clk);cold_reset=0;wait(init_done);@(negedge clk);reset=0;
  cyc=1;stb=1;we=0;adr=32'h0c030220;wait(ack);#1;if(dout!==0)$fatal(1,"cold reset did not clear RAM");
  $display("PASS board adapter ownership and warm/cold RAM reset");$finish;
 end
endmodule
