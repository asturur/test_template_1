`timescale 1ns/1ps
module tb;
parameter STREAM_TRANSPORT=1;
reg clk=0;always #5 clk=~clk;
reg reset=1,request=0,data_valid=0;reg [63:0] physical_data=0;
wire accept,complete,beat_valid,beat_last,rd,wr;
wire [63:0] beat,wd;wire [31:0] word_data;wire [28:0] address;wire [7:0] mask,count;
reg [63:0] expected[4];integer seen=0,completions=0,cycle=0,physical_seen=0,first_physical=-1,first_logical=-1;
ngage_ddr_adapter #(.STREAM_TRANSPORT(STREAM_TRANSPORT),.LINE_REFILL(1),.ROM_CACHE(1)) dut(
 .clk(clk),.reset(reset),.req_valid(request),.req_ready(accept),.req_write(1'b0),.req_addr(32'h30001000),.req_wdata(32'b0),.req_be(4'hf),.req_fetch(1'b1),.req_line(1'b1),
 .rsp_valid(complete),.rsp_data(word_data),.rsp_beat_valid(beat_valid),.rsp_beat_data(beat),.rsp_beat_last(beat_last),
 .ddr_addr(address),.ddr_din(wd),.ddr_be(mask),.ddr_rd(rd),.ddr_we(wr),.ddr_busy(1'b0),.ddr_dout(physical_data),.ddr_dout_ready(data_valid),.ddr_burstcount(count));
always @(posedge clk)begin
 cycle=cycle+1;
 if(data_valid)begin if(physical_seen==0)first_physical=cycle;physical_seen=physical_seen+1;end
 if(beat_valid)begin
  if(seen==0)first_logical=cycle;
  if(seen>=4||beat!==expected[seen]||beat_last!==(seen==3))$fatal(1,"incremental adapter beat mismatch %d",seen);
  seen<=seen+1;
 end
 if(complete)begin
  if(physical_seen!=4||seen+(beat_valid?1:0)!=4)$fatal(1,"line completed before full staged fill");completions<=completions+1;
 end
end
task offer(input [63:0] marker);begin
 @(negedge clk);while(!accept)@(negedge clk);
 for(integer k=0;k<4;k=k+1)expected[k]=marker+k;
 seen=0;physical_seen=0;first_physical=-1;first_logical=-1;request=1;@(negedge clk);request=0;wait(rd);@(posedge clk);if(count!=4)$fatal(1,"line read count");@(negedge clk);
end endtask
task send(input [63:0] value);begin @(negedge clk);physical_data=value;data_valid=1;@(negedge clk);data_valid=0;end endtask
initial begin
 repeat(3)@(negedge clk);reset=0;
 offer(64'h123456789abc0000);send(expected[0]);wait(seen==1);
 if(first_logical-first_physical!=1)$fatal(1,"adapter added a first-beat cycle: physical%d logical%d",first_physical,first_logical);
 $display("METRIC adapter mode=%s count=4 delayed_tail first_consume=%0d",STREAM_TRANSPORT?"overlap":"legacy",first_logical-first_physical);
 repeat(20)begin @(negedge clk);if(complete||accept)$fatal(1,"prefix prematurely released ownership/completed fill");end
 if(dut.line_port.backend.rsp_line[0+:64]!==expected[0])$fatal(1,"first bytes not staged while physical tail waits");
 for(integer k=1;k<4;k=k+1)send(expected[k]);wait(complete);@(negedge clk);@(negedge clk);
 offer(64'hbad0000000000000);send(expected[0]);wait(seen==1);
 @(negedge clk);reset=1;@(negedge clk);reset=0;
 for(integer k=1;k<4;k=k+1)send(expected[k]);
 while(!accept)begin @(negedge clk);if(complete||beat_valid)$fatal(1,"canceled line tail escaped");end
 if(seen!=1)$fatal(1,"canceled prefix count changed");
 offer(64'hcafe000000000000);for(integer k=0;k<4;k=k+1)send(expected[k]);wait(complete);@(negedge clk);@(negedge clk);
 if(completions!=2)$fatal(1,"success/cancel completion count");
 $display("PASS D1 adapter overlap: prefix copied during delayed physical tail, ownership/full-line completion retained, prefix cancel drains, fresh fill correct");$finish;
end
initial begin #500000;$fatal(1,"adapter overlap timeout seen%0d",seen);end
endmodule
