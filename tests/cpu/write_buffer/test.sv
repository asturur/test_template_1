`timescale 1ns/1ps
module test;
 logic clk=0;always #5 clk=~clk;
 logic reset=1,push=0,ack=0,err=0,clear=0;
 logic [31:0] pa=0;logic [2:0] words=0;logic [127:0] data=0;logic [15:0] ben=0;
 logic [31:0] query=0;wire hazard;
 wire ready,empty,full,valid,sticky;wire [2:0] entries;wire [31:0] addr,wd;wire [3:0] sel;
 arm920_write_buffer dut(.clk(clk),.reset(reset),.push_valid(push),.push_ready(ready),.push_address(pa),.push_words(words),.push_data(data),.push_byte_enable(ben),.empty(empty),.full(full),.entries(entries),.query_line_address(query),.query_line_pending(hazard),.bus_valid(valid),.bus_address(addr),.bus_data(wd),.bus_byte_enable(sel),.bus_ack(ack),.bus_error(err),.error_latched(sticky),.clear_error(clear));
 task automatic tick;begin @(posedge clk);#1;@(negedge clk);end endtask
 task automatic enqueue(input logic [31:0] base,input integer cnt,input integer id);begin
  pa=base;words=cnt;data=0;ben=0;
  for(integer k=0;k<cnt;k=k+1)begin data[k*32+:32]=id+k;ben[k*4+:4]=k+1;end
  #1;if(!ready)$fatal(1,"unexpected full");push=1;tick();push=0;
 end endtask
 task automatic beat(input logic [31:0] a,input logic [31:0] d,input logic [3:0] m);begin
  while(!valid)tick();
  if(!valid || addr!==a || wd!==d || sel!==m)$fatal(1,"bad beat addr %h data %h mask %h",addr,wd,sel);
  tick();if(!valid || addr!==a || wd!==d || sel!==m)$fatal(1,"bus beat changed while waiting");
  ack=1;tick();ack=0;
 end endtask
 integer n,k,clock_count=0,issue_delay,first_accept,stream_retired=0;
 logic stream_check=0;
 always @(posedge clk)begin
  clock_count++;
  if(stream_check && valid && ack && !err)begin
   if(addr!==32'ha000+32'(stream_retired*4) || wd!==32'(200+stream_retired) || sel!==1)
    $fatal(1,"pipelined stream lost/reordered a beat");
   stream_retired++;
  end
 end
 task automatic stream(input integer total);begin
  stream_retired=0;stream_check=1;ack=1;first_accept=clock_count+1;
  for(integer w=0;w<total;w++)enqueue(32'ha000+32'(w*4),1,200+w);
  while(!empty)tick();ack=0;stream_check=0;
  if(stream_retired!=total)$fatal(1,"stream retired wrong word count");
  $display("WB_STREAM: words=%0d accept_interval=1 first_accept_to_last_ack=%0d",total,clock_count-first_accept);
 end endtask
 initial begin #100000;$fatal(1,"timeout");end
 initial begin
  tick();reset=0;tick();
  for(n=0;n<4;n=n+1)enqueue(32'h1000+32*n,4,16*n);
  if(!full || ready || entries!=4)$fatal(1,"four groups must fill buffer");
  for(n=0;n<4;n=n+1)for(k=0;k<4;k=k+1)beat(32'h1000+32*n+4*k,16*n+k,4'(k+1));
  if(!empty || entries!=0)$fatal(1,"16 words did not drain");
  enqueue(32'h2000,1,42);while(!valid)tick();err=1;tick();err=0;
  if(!sticky || valid || empty)$fatal(1,"error must retain outstanding beat");
  clear=1;tick();clear=0;beat(32'h2000,42,1);
  if(!empty || sticky)$fatal(1,"retry did not drain");
  // Sixteen consecutive single stores use all four address entries.
  for(n=0;n<16;n=n+1)enqueue(32'h2800+4*n,1,100+n);
  if(!full || entries!=4)$fatal(1,"sequential single stores did not group");
  for(n=0;n<16;n=n+1)beat(32'h2800+4*n,100+n,1);
  if(!empty)$fatal(1,"grouped stores did not drain");
  // Full buffer can accept a replacement group on its final completed beat.
  for(n=0;n<4;n=n+1)enqueue(32'h3000+32*n,1,n);
  pa=32'h4000;words=1;data=99;ben=1;push=1;ack=1;#1;
  if(!ready)$fatal(1,"simultaneous pop/push must be accepted");tick();push=0;ack=0;
  if(entries!=4 || addr!==32'h3020)$fatal(1,"simultaneous pop/push corrupted FIFO");
  for(n=1;n<4;n=n+1)beat(32'h3000+32*n,n,1);
  beat(32'h4000,99,1);if(!empty)$fatal(1,"final buffer not empty");
  // Check all entries, including a group spanning a cache-line boundary.
  enqueue(32'h7018,4,70);enqueue(32'h7100,1,80);
  query=32'h7000;#1;if(!hazard)$fatal(1,"missing first-line hazard");
  query=32'h7020;#1;if(!hazard)$fatal(1,"missing crossing-line hazard");
  query=32'h7100;#1;if(!hazard)$fatal(1,"missing later-entry hazard");
  query=32'h7040;#1;if(hazard)$fatal(1,"unrelated line incorrectly overlaps");
  for(k=0;k<4;k=k+1)beat(32'h7018+4*k,70+k,4'(k+1));
  query=32'h7020;#1;if(hazard)$fatal(1,"retired group remains hazardous");
  beat(32'h7100,80,1);
  // An adjacent store arriving on the final beat of its sole group must form
  // a new group rather than append to an entry being retired.
  enqueue(32'h5000,1,11);while(!valid)tick();
  pa=32'h5004;words=1;data=12;ben=1;push=1;ack=1;#1;
  if(!ready)$fatal(1,"retiring adjacent group refused");tick();push=0;ack=0;
  if(entries!=1)$fatal(1,"adjacent retire and push lost entry");
  beat(32'h5004,12,1);if(!empty)$fatal(1,"adjacent group did not drain");
  // Pop the head while extending the distinct tail of a full buffer.
  for(n=0;n<4;n=n+1)enqueue(32'h6000+32*n,1,n);
  pa=32'h6064;words=1;data=33;ben=1;push=1;ack=1;#1;
  if(!ready)$fatal(1,"full buffer should accept tail extension");tick();push=0;ack=0;
  if(entries!=3)$fatal(1,"head pop and tail extension count");
  for(n=1;n<4;n=n+1)beat(32'h6000+32*n,n,1);
  beat(32'h6064,33,1);if(!empty)$fatal(1,"extended tail did not drain");
  // Repeat hazards with the head at every physical ring slot. Stale retired
  // slots must not participate; a four-word group can also wrap address zero.
  for(n=0;n<4;n=n+1)begin
   enqueue(32'hfffffff8,4,90);
   enqueue(32'h8100,1,100);
   query=32'hffffffe0;#1;if(!hazard)$fatal(1,"wrapped group first line head=%0d",n);
   query=0;#1;if(!hazard)$fatal(1,"wrapped group second line head=%0d",n);
   query=32'h8100;#1;if(!hazard)$fatal(1,"later live slot head=%0d",n);
   query=32'h8200;#1;if(hazard)$fatal(1,"unrelated ring slot head=%0d",n);
   for(k=0;k<4;k=k+1)beat(32'hfffffff8+4*k,90+k,4'(k+1));
   query=0;#1;if(hazard)$fatal(1,"retired slot still hazardous head=%0d",n);
   beat(32'h8100,100,1);
   query=32'h8100;#1;if(hazard)$fatal(1,"empty ring still hazardous head=%0d",n);
   enqueue(32'h9000,1,1);beat(32'h9000,1,1);
  end
  // Reservation is immediately nonempty/hazardous, before payload commit.
  enqueue(32'hfffffff8,4,300);query=0;#1;
  if(empty || entries!=1 || !hazard)$fatal(1,"reservation missing from occupancy/hazard");
  issue_delay=0;while(!valid)begin tick();issue_delay++;end
`ifdef NGAGE_WB_REFERENCE
  if(issue_delay!=0)$fatal(1,"reference first-issue latency changed");
`else
  if(issue_delay!=1)$fatal(1,"reservation must commit on exactly the next edge");
`endif
  $display("WB_LATENCY: accepted_to_issuable=%0d",issue_delay);
  for(k=0;k<4;k++)beat(32'hfffffff8+32'(4*k),300+k,4'(k+1));
  // Kill a freshly reserved packet, then immediately reuse the queue.
  enqueue(32'hb000,1,400);reset=1;tick();reset=0;query=32'hb000;tick();
  if(!empty || valid || hazard)$fatal(1,"reset reservation resurrected");
  enqueue(32'hb000,1,401);beat(32'hb000,401,1);
  stream(4);stream(8);
  $display("PASS: 16-word/4-address write buffer, stalls, ordering, error retention and simultaneous pop/push");$finish;
 end
endmodule
