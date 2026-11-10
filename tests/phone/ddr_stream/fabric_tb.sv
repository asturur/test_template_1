`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;
reg reset=1,lock=0,lv=0,cv=0,cw=0,lw=1,cline=0,hold_busy=0;
reg [31:0] la=32'h30000200,ld=32'hdeadbeef,ca=32'h30000400,cd=0;
wire lr,cr,ldone,cdone,av,ar,aw,aline,done,bv,bl,cbv,cbl;
wire [31:0] aa,ad,rdata,lq,cq;wire [3:0] ab;wire [63:0] bd,cb,wd,dq;
wire [28:0] da;wire [7:0] be,burst;wire rd,wr,busy,ready;
integer grants=0,cgrants=0,lgrants=0,completions=0,seen=0,last_grant=-1;
reg outstanding=0,owner=0,held_line=0,held_write=0,fair=0;reg [31:0] held_addr=0,expected_word=0;
reg [7:0] reference[0:8191];
function automatic [63:0] expected64(input integer at);
 begin for(integer k=0;k<8;k=k+1)expected64[k*8+:8]=reference[(at+k)&8191];end
endfunction
reg [63:0] expected_lane;
ngage_ddr_arbiter arb(.clk(clk),.reset(reset),.cpu_lock(lock),
 .l_valid(lv),.l_ready(lr),.l_write(lw),.l_addr(la),.l_data(ld),.l_be(4'hf),.l_done(ldone),.l_rdata(lq),
 .c_valid(cv),.c_ready(cr),.c_write(cw),.c_addr(ca),.c_data(cd),.c_be(4'hf),.c_done(cdone),.c_rdata(cq),
 .c_line(cline),.req_line(aline),.rsp_beat_valid(bv),.rsp_beat_data(bd),.rsp_beat_last(bl),.c_beat_valid(cbv),.c_beat_data(cb),.c_beat_last(cbl),
 .req_valid(av),.req_ready(ar),.req_write(aw),.req_addr(aa),.req_data(ad),.req_be(ab),.rsp_valid(done),.rsp_data(rdata));
ngage_ddr_adapter #(.STREAM_TRANSPORT(1),.LINE_REFILL(1),.ROM_CACHE(1)) adapter(
 .clk(clk),.reset(reset),.req_valid(av),.req_ready(ar),.req_write(aw),.req_addr(aa),.req_wdata(ad),.req_be(ab),.req_fetch(1'b0),.req_line(aline),
 .rsp_valid(done),.rsp_data(rdata),.rsp_beat_valid(bv),.rsp_beat_data(bd),.rsp_beat_last(bl),
 .ddr_addr(da),.ddr_din(wd),.ddr_be(be),.ddr_rd(rd),.ddr_we(wr),.ddr_busy(busy),.ddr_dout(dq),.ddr_dout_ready(ready),.ddr_burstcount(burst));
memory_peer #(.SEED(32'hbc15371)) peer(clk,da,wd,be,burst,rd,wr,busy,ready,dq,hold_busy,1'b0);
always @(posedge clk)begin
 if(reset)begin outstanding<=0;seen<=0;end
 else begin
  if(lock&&lr)$fatal(1,"loader admitted in CPU SWP lock");
  if(cr||lr)begin
   if(outstanding||cr&&lr)$fatal(1,"ownership overlap");
   if(fair&&last_grant!=-1&&last_grant==(cr?1:0))$fatal(1,"continuously pending peer starved");
   last_grant<=cr?1:0;grants<=grants+1;if(cr)cgrants<=cgrants+1;else lgrants<=lgrants+1;
   outstanding<=1;owner<=cr;held_line<=cr&&cline;held_write<=cr?cw:lw;held_addr<=cr?ca:la;seen<=0;
   expected_lane=expected64((cr?ca:la)&32'hfffffff8);expected_word<=((cr?ca:la)&4)?expected_lane[63:32]:expected_lane[31:0];
   if(cr?cw:lw)for(integer k=0;k<4;k=k+1)reference[((cr?ca:la)+k)&8191]=(cr?cd:ld)>>(k*8);
  end
  if(cbv)begin
   if(!outstanding||!owner||!held_line||cb!==expected64(held_addr+seen*8)||cbl!==(seen==3))$fatal(1,"captured line owner/data/last mismatch");seen<=seen+1;
  end
  if(cdone||ldone)begin
   if(!outstanding||cdone!==owner||ldone===owner)$fatal(1,"misrouted/duplicate scalar completion");
   if(!held_write&&!held_line&&(owner?cq:lq)!==expected_word)$fatal(1,"captured scalar readback mismatch");
   if(held_line&&seen+(cbv?1:0)!=4)$fatal(1,"line completion before final beat");
   outstanding<=0;completions<=completions+1;
  end
 end
end
task cpu_offer;begin @(negedge clk);cv=1;do @(posedge clk);while(!cr);@(negedge clk);cv=0;end endtask
task loader_offer;begin @(negedge clk);lv=1;do @(posedge clk);while(!lr);@(negedge clk);lv=0;end endtask
task held_reset(input bit line);integer old_reads;reg [28:0] old_addr;begin
 @(negedge clk);cline=line;cw=0;hold_busy=1;ca=32'h30000600;old_reads=peer.reads;
 cpu_offer();wait(rd);old_addr=da;@(negedge clk);reset=1;
 repeat(4)begin @(negedge clk);if(!rd||da!==old_addr)$fatal(1,"adapter withdrew busy-held command under reset");end
 hold_busy=0;wait(peer.reads==old_reads+1);repeat(2)@(negedge clk);reset=0;
 while(!ar)begin @(negedge clk);if(cdone||ldone||cbv)$fatal(1,"stale reset response");end
 repeat(3)@(negedge clk);cline=0;
end endtask
integer start_c,start_l,start_total,previous_c;
initial begin
 for(integer k=0;k<8192;k=k+1)reference[k]=(k*43)^(k>>7)^8'hc5;
 repeat(3)@(negedge clk);reset=0;while(!ar)@(negedge clk);
 // CPU SWP retains ownership across the read/write idle gap despite loader.
 lock=1;la=32'h30000100;ca=la;lv=1;cw=0;cpu_offer();wait(cdone);repeat(8)begin @(negedge clk);if(lr)$fatal(1,"lost SWP idle reservation");end
 cw=1;cd=32'h13579bdf;cpu_offer();wait(cdone);@(negedge clk);lock=0;
 do @(posedge clk);while(!lr);@(negedge clk);lv=0;wait(ldone);@(negedge clk);
 // Loader reads while the CPU makes no requests (phone-held production seam).
 lw=0;loader_offer();wait(ldone);@(negedge clk);
 // Both owners stay pending. Finite transactions and downstream progress give
 // grant alternation; CPU toggles scalar/line shape only after acceptance.
 start_c=cgrants;start_l=lgrants;start_total=grants;fair=1;last_grant=-1;
 ca=32'h30000400;la=32'h30000200;cw=0;cline=0;cv=1;lv=1;
 previous_c=cgrants;
 while(grants<start_total+24)begin @(negedge clk);if(cgrants!=previous_c)begin cline=!cline;previous_c=cgrants;end end
 cv=0;lv=0;fair=0;while(outstanding)@(negedge clk);
 if(cgrants-start_c!=12||lgrants-start_l!=12)$fatal(1,"fairness grant counts");
 held_reset(0);held_reset(1);
 ca=32'h30000400;cw=0;cpu_offer();wait(cdone);@(negedge clk);
 for(integer k=0;k<8192;k=k+1)if(peer.bytes[k]!==reference[k])$fatal(1,"fabric final byte image mismatch");
 $display("PASS D1 existing arbiter + opt-in adapter: scalar/line captured ownership, 24 alternating grants, finite SWP lock/gap, loader readback, busy-held scalar/line reset drain (%0d grants, %0d completions)",grants,completions);$finish;
end
initial begin #10000000;$fatal(1,"fabric timeout grants%0d completed%0d ready%b",grants,completions,ar);end
endmodule
