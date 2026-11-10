`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;
reg reset=1,write_op=0,line_op=0;reg [1:0] valid=0;
reg [31:0] addr=0,data=0;reg [3:0] mask=0;
wire [1:0] req_ready,rsp,beat_valid,beat_last,rd,wr,busy,ready;
wire [31:0] q[2];wire [63:0] beat[2],wd[2],dq[2];wire [28:0] da[2];wire [7:0] be[2],burst[2];
reg [7:0] reference[0:8191];integer counts[2];reg [1:0] completed=0;
reg expected_write=0,expected_line=0;reg [31:0] expected_addr=0;integer ops=0;
function automatic [63:0] expected64(input integer at);
 begin for(integer k=0;k<8;k=k+1)expected64[k*8+:8]=reference[(at+k)&8191];end
endfunction
for(genvar n=0;n<2;n=n+1)begin: ports
 ngage_ddr_adapter #(.STREAM_TRANSPORT(n),.LINE_REFILL(1),.ROM_CACHE(0)) dut(
 .clk(clk),.reset(reset),.req_valid(valid[n]),.req_ready(req_ready[n]),.req_write(write_op),.req_addr(addr),.req_wdata(data),.req_be(mask),.req_fetch(1'b0),.req_line(line_op),
 .rsp_valid(rsp[n]),.rsp_data(q[n]),.rsp_beat_valid(beat_valid[n]),.rsp_beat_data(beat[n]),.rsp_beat_last(beat_last[n]),
 .ddr_addr(da[n]),.ddr_din(wd[n]),.ddr_be(be[n]),.ddr_rd(rd[n]),.ddr_we(wr[n]),.ddr_busy(busy[n]),.ddr_dout(dq[n]),.ddr_dout_ready(ready[n]),.ddr_burstcount(burst[n]));
 memory_peer #(.SEED(32'h81713+n*977)) peer(clk,da[n],wd[n],be[n],burst[n],rd[n],wr[n],busy[n],ready[n],dq[n],1'b0,1'b0);
 always @(posedge clk)begin
  if(beat_valid[n])begin
   if(!expected_line||beat[n]!==expected64(expected_addr+counts[n]*8)||beat_last[n]!==(counts[n]==3))$fatal(1,"line scoreboard client%0d beat%0d got%h",n,counts[n],beat[n]);
   counts[n]<=counts[n]+1;
  end
  if(rsp[n])begin
   if(completed[n])$fatal(1,"duplicate completion");
   if(!expected_write&&!expected_line && q[n]!==scalar_expected[expected_addr[2]*32+:32])$fatal(1,"scalar scoreboard client%0d got%h",n,q[n]);
   completed[n]<=1;
  end
 end
end
// Icarus needs an intermediate for the function-result lane select.
reg [63:0] scalar_expected;
task transaction(input bit w,input bit line,input [31:0] a,input [31:0] d,input [3:0] b);
 integer t;reg [1:0] taken;begin
 @(negedge clk);while(req_ready!=3)@(negedge clk);
 expected_write=w;expected_line=line;expected_addr=a;scalar_expected=expected64(a&32'hfffffff8);
 counts[0]=0;counts[1]=0;completed=0;addr=a;data=d;mask=b;write_op=w;line_op=line;valid=3;taken=0;
 while(taken!=3)begin @(posedge clk);taken=taken|(valid&req_ready);@(negedge clk);valid=~taken;end
 addr=32'hdeadbeec;data=~d;mask=0;write_op=!w;line_op=!line;
 t=0;while(completed!=3)begin @(negedge clk);t=t+1;if(t>1000)$fatal(1,"equivalence timeout");end
 if(line&&(counts[0]!=4||counts[1]!=4))$fatal(1,"line count mismatch");
 if(w)for(integer k=0;k<4;k=k+1)if(b[k])reference[(a+k)&8191]=d[k*8+:8];
 for(integer k=0;k<8192;k=k+1)if(ports[0].peer.bytes[k]!==reference[k]||ports[1].peer.bytes[k]!==reference[k])$fatal(1,"ordered byte-image mismatch%0d",k);
 ops=ops+1;@(negedge clk);
end endtask
initial begin
 for(integer k=0;k<8192;k=k+1)reference[k]=(k*43)^(k>>7)^8'hc5;
 counts[0]=0;counts[1]=0;repeat(3)@(negedge clk);reset=0;
 for(integer k=0;k<128;k=k+1)begin
  transaction(1,0,(k*4)&8191,32'hfab12300+k,k&15);
  transaction(0,0,(k*4)&8191,0,15);
  if(k%4==0)transaction(0,1,(k*32)&8191,0,15);
 end
 for(integer m=0;m<16;m=m+1)for(integer lane=0;lane<2;lane=lane+1)begin
  transaction(1,0,1024+lane*4,32'h9bcdef01^(m*32'h01010101),m);
  transaction(0,0,1024+lane*4,0,15);
 end
 transaction(1,0,8190&~3,32'h76543210,15);transaction(0,0,8190&~3,0,15);
 transaction(0,1,8192-32,0,15);
 $display("PASS D1 cache-disabled legacy/stream ordered byte equivalence: %0d transactions; all scalar lanes/masks, line/sector endpoints, randomized peers and issue-edge data",ops);$finish;
end
initial begin #10000000;$fatal(1,"equivalence timeout");end
endmodule
