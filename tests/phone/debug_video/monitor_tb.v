`timescale 1ns/1ps
module tb;
 reg clk=0,cold=1,reset=1,fetch=0,active=0,ack=0,err=0,wr=0,fault=0;
 reg [31:0] pc=32'h12345678,cpsr=32'h600000d3,op=32'he3a00001,addr=32'h08000000,wd=32'h7037f800,rd=32'h11223344;
 reg [31:0] flags=32'h12001;reg [2:0] reason=2;
 wire [767:0] data;
 always #5 clk=~clk;
 ngage_debug_monitor dut(clk,cold,reset,pc,cpsr,op,fetch,active,ack,err,wr,addr,wd,rd,32'hf43,fault,flags,reason,32'h1f,32'h21,27'h123,data);
 task tick;begin @(posedge clk);#1;@(negedge clk);end endtask
 initial begin
  tick();cold=0;tick();if(data[4*32+:32]!==0)$fatal(1,"cycles advanced in Hold");
  reset=0;fetch=1;active=1;wr=1;repeat(5)tick();fetch=0;active=0;tick();
  if(data[5*32+:32]!==5 || data[13*32+:32]!==5 || data[12*32+:32]!==5)$fatal(1,"fetch/wait counters");
  if(data[1*32+:32]!==pc || data[2*32+:32]!==op)$fatal(1,"last accepted fetch pair");
  active=1;ack=1;tick();ack=0;active=0;addr=0;wd=0;tick();
  if(data[10*32+:32]!==1 || data[14*32+:32]!==32'h08000000 || data[15*32+:32]!==32'h7037f800)$fatal(1,"last write transfer alignment");
  addr=32'h08000000;wd=32'h7037f800;fault=1;err=1;active=1;tick();
  // Back-to-back faults have different PC/address/data/flags/reason. The first
  // record must remain coherent even when Hold arrives on its processing edge.
  pc=32'habcdef00;addr=32'hffffffff;wd=0;flags=32'h55;reason=3;reset=1;tick();
  fault=0;err=0;active=0;tick();
  if(data[16*32+:32]!==32'h08000000 || data[17*32+:32]!==32'h12345678 || data[18*32+:32]!==32'h7037f800 || data[19*32+:32]!==32'h12001 || data[20*32+:32]!==2)$fatal(1,"pipelined first-fault context");
  if(data[11*32+:32]!==1)$fatal(1,"Hold discarded or duplicated accepted error");
  // Cold reset discards an event still in the input stage.
  cold=1;tick();cold=0;reset=0;fault=1;wr=0;addr=32'h87654321;pc=32'h11112222;rd=32'h76543210;flags=7;reason=1;tick();
  cold=1;tick();cold=0;fault=0;tick();
  if(data[16*32+:32]!==0 || data[11*32+:32]!==0)$fatal(1,"cold reset did not flush pending history");
  // Read faults choose read data at sampling time, not the following request.
  fault=1;active=1;tick();fault=0;active=0;rd=0;addr=0;pc=0;flags=0;reason=0;tick();
  if(data[16*32+:32]!==32'h87654321 || data[17*32+:32]!==32'h11112222 || data[18*32+:32]!==32'h76543210 || data[19*32+:32]!==7 || data[20*32+:32]!==1)$fatal(1,"read fault fields skewed");
  $display("PASS pipelined diagnostic monitor: counters, coherent write/read fault records, back-to-back events, Hold and cold flush");$finish;
 end
endmodule
