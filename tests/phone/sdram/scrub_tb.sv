`timescale 1ns/1ps
// Full-size scrub address/byte-enable coverage with an idealized halfword
// responder. Real controller and timing are separately covered by tb.sv.
module tb;
reg clk=0;always #5 clk=~clk;
reg rst=1, phone_reset=1, init=0; wire ack,done; wire [31:0] dout; wire [21:0] ba;wire [15:0] wd;wire [1:0] dsn;wire [3:0] rd,wr;wire rfsh;
reg [3:0] rdy=0;wire [3:0] take=rd|wr;
ngage_sdram_adapter adapter(clk,rst,phone_reset,init,1'b0,1'b0,25'b0,32'b0,4'b0,ack,dout,done,ba,wd,dsn,rd,wr,take,rdy,16'b0,rfsh);
integer count=0, refreshes=0;
always @(posedge clk) begin
 rdy<=take;
 if(!rst && |wr) begin
  if(wr !== (count < 4194304 ? 4'b0001 : 4'b0010) || ba !== (count % 4194304) || wd!==0 || dsn!==0)
   $fatal(1,"scrub write %0d bank=%b address=%h data=%h mask=%b",count,wr,ba,wd,dsn);
  count<=count+1;
 end
 if(rfsh) refreshes<=refreshes+1;
 if(ack) $fatal(1,"CPU response during scrub");
end
initial begin
 repeat(3) @(negedge clk);rst=0;wait(done);@(negedge clk);
 if(count!=8388608 || refreshes==0) $fatal(1,"scrub size/refresh count=%0d refresh=%0d",count,refreshes);
 $display("PASS full 16 MiB cold scrub: %0d halfwords, %0d scheduled refresh pulses",count,refreshes);$finish;
end
endmodule
