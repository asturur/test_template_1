`timescale 1ns/1ps
module tb;
 parameter integer ENTRIES=64;
 localparam integer HASH_AW=ENTRIES>1 ? $clog2(ENTRIES) : 1;
 reg clk=0,cold=1,reset=0,req=0,commit=0,we=0;
 reg [31:0] addr=0,data=0;reg [3:0] sel=15;
 wire [31:0] out;wire full,ready;
 reg live[0:ENTRIES-1];reg [31:0] keys[0:ENTRIES-1],words[0:ENTRIES-1];
 integer i,hit,vacant,seed=47813,iteration,stage,kind,cycles,writes=0,before_writes;
 integer min_latency=999999,max_latency=0,total_latency=0,operations=0;
 integer typical_max=0,collision_max=0;
 function [31:0] collision_address;
  input integer index;
  begin
   // The paired shifts cancel in the folded hash. Start at the final slot
   // to exercise wraparound; all generated addresses remain byte-aligned.
   collision_address=((ENTRIES-1)<<(2*HASH_AW)) ^
                     (index<<(3*HASH_AW)) ^ (index<<(4*HASH_AW));
  end
 endfunction
 reg expected_full;reg [31:0] expected_read,mask;
 always #5 clk=~clk;
 ngage_sparse_regs #(.ENTRIES(ENTRIES)) dut(.clk(clk),.cold_reset(cold),.reset(reset),.req(req),.commit(commit),.we(we),.addr(addr),.din(data),.sel(sel),.dout(out),.full(full),.ready(ready));
 always @(posedge clk) if(dut.write_value) writes=writes+1;
 task tick;begin @(posedge clk);#1;@(negedge clk);end endtask
 // The oracle is keyed by public addresses. Physical slot allocation is
 // intentionally opaque, so a different lookup structure can share this test.
 task check_table;
 begin
  if(!ready && (out!==0 || full))$fatal(1,"response leaked before readiness");
 end endtask
 task predict;
 begin
  hit=-1;vacant=-1;
  for(i=0;i<ENTRIES;i=i+1)begin
   if(live[i] && keys[i]==addr && hit<0)hit=i;
   if(!live[i] && vacant<0)vacant=i;
  end
  expected_full=we && hit<0 && vacant<0;
  expected_read=hit<0 ? 0 : words[hit];
 end endtask
 // Each transaction may be presented with authorization already high or
 // may withhold it through arbitrary terminal waits. Both must perform once.
 task transaction(input integer early,input integer waits,input integer gap);
 begin
  req=1;commit=early;predict;before_writes=writes;cycles=0;#1;
  while(!ready)begin
   check_table;tick();cycles=cycles+1;
   if(cycles>ENTRIES+3)$fatal(1,"lookup did not finish independently of commit");
  end
  if(cycles<min_latency)min_latency=cycles;
  if(cycles>max_latency)max_latency=cycles;
  total_latency=total_latency+cycles;operations=operations+1;
  if(full!==expected_full || out!==expected_read)$fatal(1,"lookup mismatch size=%0d addr=%h",ENTRIES,addr);
  // No payload or valid/tag mutation is allowed ahead of the ready result.
  if(writes!=before_writes)$fatal(1,"early write");check_table;
  if(!early)repeat(waits)begin tick();check_table;if(!ready || full!==expected_full || out!==expected_read)$fatal(1,"unstable waiting result");end
  commit=1;
  if(we && !expected_full)begin
   mask={{8{sel[3]}},{8{sel[2]}},{8{sel[1]}},{8{sel[0]}}};
   if(hit>=0)words[hit]=(words[hit]&~mask)|(data&mask);
   else begin live[vacant]=1;keys[vacant]=addr;words[vacant]=data&mask;end
  end
  tick();check_table;
  repeat(waits+2)begin
   tick();check_table;
   if(!ready || full!==expected_full || out!==expected_read)$fatal(1,"terminal result changed");
  end
  if(writes!=before_writes+(we && !expected_full))$fatal(1,"held request repeated write");
  commit=0;
  if(gap)begin req=0;tick();if(ready || full)$fatal(1,"stale withdrawn result");end
 end endtask
 initial begin
  for(i=0;i<ENTRIES;i=i+1)live[i]=0;
  tick();cold=0;tick();
  // Every occupied stage, including a resolved uncommitted write, can cancel.
  for(kind=0;kind<3;kind=kind+1)for(stage=1;stage<=4;stage=stage+1)begin
   req=1;we=1;commit=0;addr='hdead0000+stage*4;data='hffffffff;
   repeat(stage)tick();
   if(kind==0)req=0;else if(kind==1)reset=1;else cold=1;
   commit=1;tick();reset=0;cold=0;commit=1;
   repeat(6)begin tick();if(ready || full)$fatal(1,"canceled request restarted");check_table;end
   req=0;commit=0;tick();
   // Probe canceled payload through the public read path, not only validity.
   we=0;transaction(0,1,1);if(expected_read!==0)$fatal(1,"ghost entry");
  end
  // Fill every logical entry and verify zero-filled untouched bytes.
  we=1;sel=1;
  for(iteration=0;iteration<ENTRIES;iteration=iteration+1)begin
   addr='h0d000220+iteration*'h10000;data='h12345680+iteration;transaction(iteration%2,3,1);
  end
  addr='hdead0000;data='hffffffff;sel=15;transaction(1,4,1);
  // Full-table updates followed immediately by dependent reads, without req gap.
  for(iteration=0;iteration<ENTRIES;iteration=iteration+1)begin
   addr='h0d000220+iteration*'h10000;we=1;sel=10;data='hffeeddcc;transaction(0,2,0);
   we=0;transaction(0,2,1);
  end
  // Warm reset cancels each occupied stage without losing existing entries.
  for(stage=1;stage<=5;stage=stage+1)begin
   addr='h0d000220;data=0;sel=15;we=1;req=1;commit=0;repeat(stage)tick();
   reset=1;commit=1;tick();reset=0;commit=1;repeat(6)tick();check_table;
   req=0;commit=0;tick();we=0;transaction(0,2,1);
  end
  // Replacing an in-flight identity cancels the old allocation at every stage.
  for(stage=1;stage<=4;stage=stage+1)begin
   addr='hdead0000+stage*4;we=1;data='h11111111;sel=15;req=1;commit=0;
   repeat(stage)tick();addr='h0d000220;data='h22222222;transaction(1,2,1);
   we=0;transaction(0,1,1);
   addr='hdead0000+stage*4;transaction(0,1,1);
   if(expected_read!==0)$fatal(1,"replaced request allocated ghost entry");
  end
  for(iteration=0;iteration<4000;iteration=iteration+1)begin
   addr='h0d000220+(iteration%(ENTRIES+3))*'h10000;
   if(iteration%13==0)addr=addr+1; // Exact byte-address identity, no aliasing.
   we=$random(seed)&1;data=$random(seed);sel=$random(seed);
   transaction(iteration%2,iteration%5,1);
   if(iteration%211==210)begin
    cold=1;tick();cold=0;for(i=0;i<ENTRIES;i=i+1)live[i]=0;tick();check_table;
   end
  end
  // Every bit is part of exact address identity, including low byte bits.
  // Zero-mask new writes allocate zero rather than exposing stale payload RAM.
  for(iteration=0;iteration<32;iteration=iteration+1)begin
   req=0;commit=0;cold=1;tick();cold=0;
   for(i=0;i<ENTRIES;i=i+1)live[i]=0;tick();
   addr='h456789ac;we=1;sel=15;data='h32123456;transaction(1,1,1);
   addr=addr^(32'b1<<iteration);we=0;transaction(0,1,1);
   if(expected_read!==0)$fatal(1,"address bit %0d aliased",iteration);
   we=1;sel=0;data='hffffffff;transaction(0,2,1);
   we=0;transaction(0,1,1);
   addr='h456789ac;transaction(0,1,1);
   if(expected_read!=='h32123456)$fatal(1,"address bit %0d overwrote original",iteration);
  end
  // Empty-table reads never reserve capacity, regardless of byte identity.
  req=0;commit=0;cold=1;tick();cold=0;
  for(i=0;i<ENTRIES;i=i+1)live[i]=0;tick();
  for(iteration=0;iteration<ENTRIES+2;iteration=iteration+1)begin
   addr=collision_address(iteration);we=0;transaction(0,2,1);
  end
  // Typical adjacent register words distribute across all 64 hash buckets.
  for(iteration=0;iteration<ENTRIES;iteration=iteration+1)begin
   addr='h0d000220+iteration*4;we=1;sel=15;data=iteration+1;
   transaction(1,1,1);if(cycles>typical_max)typical_max=cycles;
  end
  for(iteration=0;iteration<ENTRIES;iteration=iteration+1)begin
   addr='h0d000220+iteration*4;we=0;transaction(0,1,1);
   if(cycles>typical_max)typical_max=cycles;
  end
  req=0;commit=0;cold=1;tick();cold=0;
  for(i=0;i<ENTRIES;i=i+1)live[i]=0;tick();
  // A single adversarial collision chain fills every slot, including wrap.
  for(iteration=0;iteration<ENTRIES;iteration=iteration+1)begin
   addr=collision_address(iteration);we=1;sel=1;data='hffffff80+iteration;
   transaction(iteration%2,3,1);
   if(cycles>collision_max)collision_max=cycles;
  end
  addr=collision_address(ENTRIES);we=1;sel=15;data='hffffffff;
  transaction(1,4,1);if(!expected_full)$fatal(1,"collision full miss not rejected");
  if(cycles>collision_max)collision_max=cycles;
  // All occupied keys still read/update in a full table. New partial entries
  // returned zero for all untouched bytes; updates preserve those bytes.
  for(iteration=0;iteration<ENTRIES;iteration=iteration+1)begin
   addr=collision_address(iteration);we=0;transaction(0,1,1);
   we=1;sel=10;data='hffeeccdd;transaction(1,2,0);
   we=0;transaction(0,3,1);
  end
  // Cancel a longest-chain existing update at every probe/terminal clock.
  // A replacement, withdrawal or warm reset must preserve the old payload.
  for(kind=0;kind<3;kind=kind+1)for(stage=1;stage<=ENTRIES+2;stage=stage+1)begin
   addr=collision_address(ENTRIES-1);we=1;sel=15;data='hbad0bad0;
   req=1;commit=0;repeat(stage)tick();
   if(kind==0)begin req=0;commit=1;tick();end
   else if(kind==1)begin
    reset=1;commit=1;tick();reset=0;
    repeat(3)begin tick();if(ready||full)$fatal(1,"reset-held identity restarted");end
    req=0;commit=0;tick();
   end else begin
    addr=collision_address(0);we=0;transaction(1,2,1);
   end
   req=0;commit=0;tick();addr=collision_address(ENTRIES-1);we=0;
   transaction(0,1,1);
  end
  // Cold reset during first, middle and final probes clears only validity;
  // stale tag/payload RAM must never become publicly visible afterward.
  for(kind=0;kind<3;kind=kind+1)begin
   if(kind>0)for(iteration=0;iteration<ENTRIES;iteration=iteration+1)begin
    addr=collision_address(iteration);we=1;sel=15;data=iteration+1;
    transaction(1,0,1);
   end
   addr=collision_address(ENTRIES-1);we=1;sel=15;data='hbad0bad0;req=1;commit=0;
   stage=kind==0?1:kind==1?(ENTRIES/2+1):ENTRIES+1;
   repeat(stage)tick();cold=1;commit=1;tick();cold=0;
   for(i=0;i<ENTRIES;i=i+1)live[i]=0;
   repeat(3)begin tick();if(ready||full)$fatal(1,"cold-held identity restarted");end
   req=0;commit=0;tick();
   for(iteration=0;iteration<ENTRIES;iteration=iteration+1)begin
    addr=collision_address(iteration);we=0;transaction(0,1,1);
    if(expected_read!==0)$fatal(1,"stale RAM exposed after cold reset");
   end
  end
  $display("METRIC sparse ENTRIES=%0d min=%0d max=%0d typical_max=%0d collision_max=%0d operations=%0d lookup_clocks=%0d",ENTRIES,min_latency,max_latency,typical_max,collision_max,operations,total_latency);
  $display("PASS sparse store ENTRIES=%0d: masks, capacity, exact-once, waits, dependencies, collision/wrap/full and cancel/reset stages",ENTRIES);$finish;
 end
 initial begin #10000000;$fatal(1,"timeout");end
endmodule
