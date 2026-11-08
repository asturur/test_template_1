`timescale 1ns/1ps
module tb;
 reg clk=0,reset=1,cold_reset=1,cyc=0,stb=0,we=0;
 reg [31:0] adr=0,din=0; reg [3:0] sel=15;
 wire claim,fallback,ack,err,irq,fiq,init_done,trace_valid;
 wire [31:0] dout,trace_addr,trace_data;wire [3:0] trace_sel;
 always #5 clk=~clk;
 ngage_board_sim dut(clk,reset,cold_reset,cyc,stb,we,adr,din,sel,claim,fallback,ack,err,dout,irq,fiq,init_done,trace_valid,trace_addr,trace_data,trace_sel);
 integer n,waits;
 task transfer;
 input write_op;input [31:0] address,value;input [3:0] lanes;input expected_error;input [31:0] expected_data;
 begin
  @(negedge clk);cyc=1;stb=1;we=write_op;adr=address;din=value;sel=lanes;waits=0;#1;
  while(!ack && !err)begin @(negedge clk);#1;waits=waits+1;if(waits>16)$fatal(1,"device handshake timeout");end
  if(err!==expected_error || (!write_op && !expected_error && dout!==expected_data))$fatal(1,"board sparse result %h",address);
  @(negedge clk);cyc=0;stb=0;@(negedge clk);
 end endtask
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
  @(negedge clk);cyc=0;stb=0;@(negedge clk);
  // Sparse wait is selected-device local; cancel before commit and switch to upload.
  cyc=1;stb=1;we=1;adr=32'h0d000220;din=32'hffffffff;sel=15;
  @(negedge clk);adr=32'h0c030220;din=32'h12345678;#1;
  if(!ack || err)$fatal(1,"CAM stalled unrelated upload");
  @(negedge clk);cyc=0;stb=0;
  transfer(0,32'h0d000220,0,15,0,0);
  for(n=0;n<64;n=n+1)transfer(1,32'h0d000220+(n<<16),n+1,15,0,0);
  transfer(1,32'h0dff0220,32'hffffffff,15,1,0);
  // Trace sink remains immediate and successful even with a full CAM.
  transfer(1,32'h0de00000,32'h41,1,0,0);
  if(waits!=0)$fatal(1,"CAM stalled trace sink");
  transfer(1,32'h0def0000,32'h12345678,15,0,0);
  if(waits!=0)$fatal(1,"CAM stalled word trace sink");
  reset=1;@(negedge clk);reset=0;
  transfer(0,32'h0d000220,0,15,0,1);
  transfer(1,32'h0d000220,32'habcd0000,12,0,0);
  transfer(0,32'h0d000220,0,15,0,32'habcd0001);
  $display("PASS board sparse waits, cancel, overflow, trace exclusion and warm retention");
  $display("PASS board adapter ownership and warm/cold RAM reset");$finish;
 end
endmodule
