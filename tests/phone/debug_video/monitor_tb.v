`timescale 1ns/1ps
module tb;
 reg clk=0,cold=1,reset=1,fetch=0,active=0,ack=0,err=0,wr=0,fault=0;
 reg [31:0] pc=32'h12345678,cpsr=32'h600000d3,op=32'he3a00001,addr=32'h08000000,wd=32'h7037f800,rd=32'h11223344;
 wire [767:0] data;
 always #5 clk=~clk;
 ngage_debug_monitor dut(clk,cold,reset,pc,cpsr,op,fetch,active,ack,err,wr,addr,wd,rd,32'hf43,fault,32'h12001,3'd2,32'h1f,32'h21,27'h123,data);
 task tick;begin @(posedge clk);#1;@(negedge clk);end endtask
 initial begin
  tick();cold=0;tick();if(data[4*32+:32]!==0)$fatal(1,"cycles advanced in Hold");
  reset=0;fetch=1;active=1;wr=1;repeat(5)tick();fetch=0;
  if(data[5*32+:32]!==5 || data[13*32+:32]!==5 || data[12*32+:32]!==5)$fatal(1,"fetch/wait counters");
  if(data[1*32+:32]!==pc || data[2*32+:32]!==op)$fatal(1,"last accepted fetch pair");
  ack=1;tick();ack=0;
  if(data[10*32+:32]!==1 || data[14*32+:32]!==addr || data[15*32+:32]!==wd)$fatal(1,"last write transfer");
  fault=1;err=1;tick();fault=0;err=0;active=0;
  if(data[16*32+:32]!==addr || data[17*32+:32]!==pc || data[18*32+:32]!==wd || data[20*32+:32]!==2)$fatal(1,"fault context");
  pc=0;addr=32'hffffffff;wd=0;fault=1;tick();fault=0;reset=1;tick();
  if(data[16*32+:32]!==32'h08000000 || data[17*32+:32]!==32'h12345678)$fatal(1,"sticky context overwritten/reset");
  cold=1;tick();if(data[16*32+:32]!==0 || data[11*32+:32]!==0)$fatal(1,"cold reset history");
  $display("PASS diagnostic monitor counters, fetch pair, wait and sticky fault context");$finish;
 end
endmodule
