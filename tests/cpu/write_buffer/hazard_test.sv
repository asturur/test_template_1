`timescale 1ns/1ps
// Independent logical FIFO oracle: hazards enumerate every queued word. It
// deliberately does not use the DUT's physical slots or first/last-line tags.
module hazard_test;
`ifdef NGAGE_WB_REFERENCE
 localparam COMMIT_DELAY=0;
`else
 localparam COMMIT_DELAY=1;
`endif
 logic clk=0,reset=1,push=0,ack=0,err=0,clear=0;
 logic [31:0] pa=0,query=0;logic [2:0] words=1;
 logic [127:0] pd=0;logic [15:0] be=0;
 wire ready,empty,full,valid,sticky,hazard;wire [2:0] entries;
 wire [31:0] addr,data;wire [3:0] mask;
 arm920_write_buffer dut(clk,reset,push,ready,pa,words,pd,be,empty,full,entries,
  query,hazard,valid,addr,data,mask,ack,err,sticky,clear);
 logic [31:0] ma[0:3];logic [127:0] md[0:3];logic [15:0] mb[0:3];integer ml[0:3];
 integer ready_at[0:3][0:3];integer model_clock=0;
 integer count=0,cursor=0,cycles=0,enqueues=0,merges=0,retirements=0,crossings=0,wraps=0,errors=0;
 integer pending_resets=0,full_replacements=0,ack_errors=0,head_merge_acks=0,pending_head_clocks=0;
 logic failed_bus=0,held_offer=0;logic [31:0] rng=32'had31974c;
 function automatic logic match_query(input logic [31:0] q);
  logic [31:0] a;logic found;
  begin
   found=0;
   for(integer i=0;i<count;i++)for(integer j=0;j<ml[i];j++)begin
    a=ma[i]+32'(j*4);
    if(a[31:5]==q[31:5])found=1;
   end
   return found;
  end
 endfunction
 function automatic logic model_valid();
  return count!=0 && !failed_bus && ready_at[0][cursor]<=model_clock;
 endfunction
 function automatic logic is_merge();
  if(count==0)return 0;
  return words==1 && ml[count-1]<4 && pa==ma[count-1]+32'(ml[count-1]*4) &&
   !(model_valid() && ack && !err && cursor+1==ml[0] && count==1);
 endfunction
 task automatic check_outputs;
  logic want_valid,want_done,want_ready;logic [31:0] a;
  begin
   want_valid=model_valid();
   want_done=0;if(count!=0)want_done=want_valid && ack && !err && cursor+1==ml[0];
   want_ready=count<4 || want_done || is_merge();
   if(entries!==count || empty!==(count==0) || full!==(count==4) || valid!==want_valid || sticky!==failed_bus || ready!==want_ready)
    $fatal(1,"FIFO status mismatch cycle=%0d count=%0d",cycles,count);
   if(want_valid)begin
    a=ma[0]+32'(cursor*4);
    if(addr!==a || data!==md[0][cursor*32+:32] || mask!==mb[0][cursor*4+:4])
     $fatal(1,"ordered bus beat mismatch cycle=%0d",cycles);
   end
   if(hazard!==match_query(query))$fatal(1,"line hazard mismatch cycle=%0d query=%h",cycles,query);
  end
 endtask
 task automatic advance_model;
  logic done,beat,accept,merge,old_valid;logic [31:0] last_address;
  begin
   if(reset)begin
    for(integer i=0;i<count;i++)for(integer w=0;w<ml[i];w++)
     if(ready_at[i][w]>model_clock)pending_resets++;
    count=0;cursor=0;failed_bus=0;held_offer=0;end
   else begin
    old_valid=model_valid();
    beat=old_valid && ack && !err;done=0;
    if(count!=0)done=beat && cursor+1==ml[0];
    merge=is_merge();accept=push && (count<4 || done || merge);
    if(count!=0 && ready_at[0][cursor]>model_clock)pending_head_clocks++;
    if(accept && !merge && done && count==4)full_replacements++;
    if(old_valid && ack && err)ack_errors++;
    if(accept && merge && count==1 && beat)head_merge_acks++;
    model_clock++;
    held_offer=push && !accept;
    if(clear)failed_bus=0;
    if(old_valid && err)begin failed_bus=1;errors++;end
    if(done)begin
     for(integer i=0;i<count-1;i++)begin ma[i]=ma[i+1];ml[i]=ml[i+1];md[i]=md[i+1];mb[i]=mb[i+1];for(integer w=0;w<4;w++)ready_at[i][w]=ready_at[i+1][w];end
     count--;cursor=0;retirements++;
    end else if(beat)cursor++;
    if(accept)begin
     if(merge)begin
      ready_at[count-1][ml[count-1]]=model_clock+COMMIT_DELAY;
      md[count-1][ml[count-1]*32+:32]=pd[31:0];mb[count-1][ml[count-1]*4+:4]=be[3:0];ml[count-1]++;merges++;
     end else begin
      for(integer w=0;w<words;w++)ready_at[count][w]=model_clock+COMMIT_DELAY;
      ma[count]=pa;ml[count]=words;md[count]=pd;mb[count]=be;count++;enqueues++;
      last_address=pa+32'((words-1)*4);
      if(pa[31:5]!=last_address[31:5])crossings++;
      if(last_address<pa)wraps++;
     end
    end
   end
  end
 endtask
 task automatic step;
  begin
   #1;if(!reset)check_outputs();advance_model();clk=1;#1;check_outputs();
   // Clock is controlled manually: query sweeps cannot accidentally cause
   // additional queue mutations while checking every live boundary.
   for(integer i=0;i<count;i++)begin
    query=ma[i];#1;check_outputs();
    query=ma[i]+32'((ml[i]-1)*4);#1;check_outputs();
    query=ma[i]^32'h100;#1;check_outputs();
   end
   clk=0;#1;cycles++;
  end
 endtask
 initial begin
  step();reset=0;
  for(integer n=0;n<12000;n++)begin
   rng=rng^(rng<<13);rng=rng^(rng>>17);rng=rng^(rng<<5);
   reset=n%211==210;ack=rng[1];err=rng[9] && rng[10];clear=rng[11];
   if(!held_offer)begin
    push=rng[0] || rng[2];words={1'b0,rng[6:5]}+3'd1;
    case(rng[4:3])
     0:pa=32'hfffffff0+{28'b0,rng[15:12]};
     1:pa=32'h2000+{24'b0,rng[23:16]};
     2:begin
      if(count!=0)begin pa=ma[count-1]+32'(ml[count-1]*4);words=1;end
      else pa=rng;
     end
     3:pa=rng;
    endcase
    for(integer k=0;k<4;k++)pd[k*32+:32]=rng ^ (32'h127824ab*k);
    be=rng[31:16];
   end
   query=rng;
   if(count!=0 && rng[7])query=ma[rng%count]+{28'b0,rng[15:12]};
   step();
  end
  reset=0;push=0;ack=1;err=0;clear=1;
  repeat(20)step();
  if(!empty || count!=0 || enqueues<100 || merges<100 || crossings<100 || wraps<20 || errors<100)
   $fatal(1,"insufficient wrap/crossing/merge/error coverage or failed drain");
  $display("WB_RACES: pending_resets=%0d full_replacements=%0d ack_errors=%0d head_merge_acks=%0d pending_head_clocks=%0d",pending_resets,full_replacements,ack_errors,head_merge_acks,pending_head_clocks);
  $display("PASS independent write-buffer FIFO/hazard scoreboard: %0d cycles, %0d enqueues, %0d merges, %0d crossings, %0d wraps, %0d errors",cycles,enqueues,merges,crossings,wraps,errors);$finish;
 end
endmodule
