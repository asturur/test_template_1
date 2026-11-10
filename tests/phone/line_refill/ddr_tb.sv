`timescale 1ns/1ps
module tb;
reg clk=0,reset=1,req=0,isline=0,write_op=0;always #5 clk=~clk;
wire ready,done,bv,bl,rd,wr;wire [31:0] q;wire [63:0] beat,wd;wire [28:0] a;wire [7:0] be,burst;
reg busy=0,dv=0;reg [63:0] dq=0;integer commands=0,seen=0,j;
ngage_ddr_adapter #(.LINE_REFILL(1),.ROM_CACHE(1)) dut(
 .clk(clk),.reset(reset),.req_valid(req),.req_ready(ready),.req_write(write_op),.req_addr(32'h30001000),.req_wdata(32'h12345678),.req_be(4'hf),.req_fetch(1'b1),
 .req_line(isline),.rsp_valid(done),.rsp_data(q),.rsp_beat_valid(bv),.rsp_beat_data(beat),.rsp_beat_last(bl),
 .ddr_addr(a),.ddr_din(wd),.ddr_be(be),.ddr_rd(rd),.ddr_we(wr),.ddr_busy(busy),.ddr_dout(dq),.ddr_dout_ready(dv),.ddr_burstcount(burst));
always @(posedge clk)begin
 if(rd && !busy)commands<=commands+1;
 if(bv)begin
  if(beat!==64'h1122334455660000+seen || bl!==(seen==3))$fatal(1,"bad beat %0d %h",seen,beat);
  seen<=seen+1;
 end
end
task offer;input line;begin @(negedge clk);req=1;isline=line;wait(ready);@(negedge clk);req=0;end endtask
task send;input [63:0] value;begin @(negedge clk);dq=value;dv=1;@(negedge clk);dv=0;end endtask
initial begin
 repeat(2)@(negedge clk);reset=0;offer(1);wait(rd);@(posedge clk);if(burst!=4)$fatal(1,"not a line burst");
 @(negedge clk);busy=1;
 for(j=0;j<4;j=j+1)begin repeat(j+1)@(negedge clk);send(64'h1122334455660000+j);end
 @(negedge clk);busy=0;repeat(2)@(negedge clk);
 if(seen!=4 || commands!=1)$fatal(1,"line transactions %d beats %d",commands,seen);
 // Accepted reads drain reset; a fresh packet cannot consume an old beat.
 offer(1);wait(rd);@(posedge clk);@(negedge clk);busy=1;reset=1;
 repeat(2)@(negedge clk);reset=0;
 for(j=0;j<4;j=j+1)send(64'hdeadbeef);
 @(negedge clk);busy=0;repeat(2)@(negedge clk);
 if(seen!=4 || done)$fatal(1,"reset leaked response");
 // A normal immutable-ROM request still allocates/hits the historical 1KiB buffer.
 offer(0);wait(rd);@(posedge clk);if(burst!=1)$fatal(1,"word burst changed");@(negedge clk);busy=1;
 send(64'hcafef00d13579bdf);wait(done);if(q!==32'h13579bdf)$fatal(1,"word value");
 @(negedge clk);busy=0;repeat(2)@(negedge clk);j=commands;
 offer(0);wait(done);if(q!==32'h13579bdf || commands!=j)$fatal(1,"normal cache hit failed");
 $display("PASS DDR line stream, one four-beat command, reset drain and normal ROM cache");$finish;
end
initial begin #500000;$fatal(1,"timeout commands=%d seen=%d active=%b owner=%b rawstate=%d cache=%d normal=%d rd=%b ready=%b",commands,seen,dut.active,dut.owner_line,dut.line_port.backend.state,dut.word_port.cached.cache.state,dut.word_port.cached.backend.state,rd,ready);end
endmodule
