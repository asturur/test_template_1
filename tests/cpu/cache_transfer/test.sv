`timescale 1ns/1ps
module test;
 logic clk=0;always #5 clk=~clk;
 logic reset=1,start=0,ack=0,err=0;logic [31:0] va=32'h8123401f,ra=32'h1234501f,rdata=0;
 logic [1:0] dirty=0;logic [255:0] line;wire busy,done,error,valid,write;
 wire [255:0] result;wire [31:0] addr,wdata;
 arm920_cache_transfer dut(.clk(clk),.reset(reset),.start(start),.victim_address(va),.victim_dirty(dirty),.victim_line(line),.refill_address(ra),.busy(busy),.done(done),.error(error),.refill_line(result),.bus_valid(valid),.bus_write(write),.bus_address(addr),.bus_wdata(wdata),.bus_ack(ack),.bus_error(err),.bus_rdata(rdata));
 task automatic tick;begin @(posedge clk);#1;@(negedge clk);end endtask
 task automatic launch(input logic [1:0] d);begin dirty=d;start=1;tick();start=0;end endtask
 task automatic beat(input logic wr,input logic [31:0] a,input logic [31:0] data);
  begin
   if(!valid || write!==wr || addr!==a || (wr && wdata!==data)) $fatal(1,"bad request write=%b addr=%h data=%h expected %b %h %h",write,addr,wdata,wr,a,data);
   tick();if(!valid || write!==wr || addr!==a || (wr && wdata!==data))$fatal(1,"request changed during wait");
   rdata=data;ack=1;tick();ack=0;
  end
 endtask
 integer n;
 initial begin
  line=0;for(n=0;n<8;n=n+1)line[n*32+:32]=32'haabb0000+n;
  tick();reset=0;tick();
  launch(2'b11);
  for(n=0;n<8;n=n+1)beat(1,32'h81234000+4*n,32'haabb0000+n);
  for(n=0;n<8;n=n+1)beat(0,32'h12345000+4*n,32'h12340000+n);
  if(!done || error || busy)$fatal(1,"missing successful completion");
  for(n=0;n<8;n=n+1)if(result[n*32+:32]!==32'h12340000+n)$fatal(1,"bad refill word %0d",n);
  tick();launch(2'b10);
  for(n=4;n<8;n=n+1)beat(1,32'h81234000+4*n,32'haabb0000+n);
  if(!valid || write || addr!==32'h12345000)$fatal(1,"upper-half sequence");
  err=1;tick();err=0;if(!done || !error || busy)$fatal(1,"refill error not reported");
  tick();launch(2'b01);err=1;tick();err=0;
  if(!done || !error || busy)$fatal(1,"writeback error not reported");
  tick();launch(0);if(write || addr!==32'h12345000)$fatal(1,"clean victim must refill directly");
  $display("PASS: cache transfer dirty halves, bus waits, refill and errors");$finish;
 end
endmodule
