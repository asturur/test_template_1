`timescale 1ns/1ps
module tb;
reg clk=0,reset=1,start=0;always #5 clk=~clk;
reg [31:0] target=32'h00321000;reg [1:0] dirty=0;
wire busy,done,error,bv,bw,lr;wire [31:0] ba,bd,la;wire [255:0] result;
reg ack=0,berr=0,ready=0,reject=0,valid=0,wide=0,last=0,lerror=0;
reg [63:0] data=0;reg [31:0] q=0;integer j,k,writes;
arm920_cache_transfer #(.LINE_REFILL(1)) dut(
 .clk(clk),.reset(reset),.start(start),.victim_address(32'h0a000040),.victim_dirty(dirty),.victim_line({8{32'h12345678}}),.refill_address(target),
 .busy(busy),.done(done),.error(error),.refill_line(result),.bus_valid(bv),.bus_write(bw),.bus_address(ba),.bus_wdata(bd),.bus_ack(ack),.bus_error(berr),.bus_rdata(q),
 .line_req(lr),.line_addr(la),.line_ready(ready),.line_reject(reject),.line_valid(valid),.line_data(data),.line_wide(wide),.line_last(last),.line_error(lerror));
task begin_read;begin @(negedge clk);start=1;@(negedge clk);start=0;end endtask
task accept_line;begin wait(lr);@(negedge clk);if(la!==target || bv)$fatal(1,"bad line offer");ready=1;@(negedge clk);ready=0;end endtask
task beat;input [63:0] d;input w,l;begin
 @(negedge clk);data=d;wide=w;last=l;valid=1;@(negedge clk);valid=0;last=0;data='hx;
end endtask
initial begin
 repeat(3)@(negedge clk);reset=0;
 begin_read();accept_line();
 for(j=0;j<16;j=j+1)begin beat(j+16'h8000,0,j==15);end
 if(!done || error)$fatal(1,"halfword stream failed");
 for(j=0;j<16;j=j+1)if(result[j*16+:16]!==16'h8000+j)$fatal(1,"halfword order");
 @(negedge clk);begin_read();accept_line();
 for(j=0;j<4;j=j+1)begin
  data=0;for(k=0;k<4;k=k+1)data[k*16+:16]=j*4+k;
  beat(data,1,j==3);
 end
 if(!done || error)$fatal(1,"wide stream failed");
 for(j=0;j<16;j=j+1)if(result[j*16+:16]!==j)$fatal(1,"wide order");
 @(negedge clk);begin_read();accept_line();
 @(negedge clk);reject=1;@(negedge clk);reject=0;
 for(j=0;j<8;j=j+1)begin
  wait(bv);@(negedge clk);if(bw || ba!==target+4*j)$fatal(1,"fallback address");q=j;ack=1;
  @(negedge clk);ack=0;
 end
 if(!done || error)$fatal(1,"fallback completion");
 @(negedge clk);dirty=1;begin_read();writes=0;
 while(!lr)begin
  @(negedge clk);ack=bv;
  if(bv)begin if(!bw || bd!==32'h12345678)$fatal(1,"writeback");writes=writes+1;end
 end
 ack=0;if(writes!=4)$fatal(1,"writeback length %d",writes);
 accept_line();lerror=1;beat(0,1,1);lerror=0;
 if(!done || !error)$fatal(1,"line error lost");
 @(negedge clk);dirty=0;begin_read();accept_line();beat(0,1,0);
 reset=1;@(negedge clk);reset=0;repeat(2)@(negedge clk);
 if(busy || done || lr || bv)$fatal(1,"reset did not cancel requester");
 $display("PASS line refill 16/64-bit streams, stalls, fallback, dirty writeback, error, reset");$finish;
end
initial begin #200000;$fatal(1,"timeout");end
endmodule
