`timescale 1ns/1ps
module test;
reg clk=0, reset=1, req=0, wr=0, early=1, enabled=1;
reg resident=1, ordinary=1,inv=0,lock=0,mv=0,mc=0,mi=0;
reg [31:0] address=0,din=0,pa=0;reg [3:0] mask=15;reg [5:0] lockbase=0;
wire mr,md,ready,valid,error,bus_valid,bus_write,empty;
wire [31:0] data,bus_address,bus_data;wire [3:0] bus_mask;
reg [31:0] mem[0:32767],gold[0:32767];
reg fasten=1,probe=0;reg [31:0] paddr=0;wire fvalid;wire [31:0] fword;
wire lreq;wire [31:0] laddr;reg lready=1,lreject=1,lvalid=0,llast=0;reg [63:0] ldata=0;
integer edge_id=0,accepts=0,replies=0,commits=0,writes=0,line_beats=0;
integer i,j,stage,event_id,oldc,oldr,olda,waits,basewrites,checks=0,applies=0,oldapplies=0;
reg tracing=0, checking=0;reg [31:0] qaddr[0:255],qdata[0:255],qpa[0:255];reg [3:0] qmask[0:255];
reg [31:0] mutation[0:32767];
reg [31:0] sampled_address,sampled_expected;reg [8:0] sampled_slot;reg [2:0] sampled_word;
wire [31:0] ramwords[0:7];wire [31:0] tags[0:63];
genvar w,t;generate
for(w=0;w<8;w=w+1) begin
assign ramwords[w]=dut.bank.lines.words[w].ram.memory[sampled_slot];
end
for(t=0;t<64;t=t+1) begin
assign tags[t]=dut.bank.tags.ways[t].packed_dirty_tags.tag_ram.memory[dut.bank.lines.write_index[2:0]];
end
endgenerate
wire [31:0] enables=dut.bank.lines.write_enable;
wire [8:0] slot=dut.bank.lines.write_index;
wire [255:0] payload=dut.bank.lines.write_line;
wire [31:0] slotline={tags[slot[8:3]][23:0],slot[2:0],5'b0};
always #5 clk=~clk;
  arm920_cache_access #(.DATA_PROBE(1), .LINE_REFILL(1)) dut (
      .clk(clk),
      .reset(reset),
      .discard_refill(1'b0),
      .req_valid(req),
      .req_ready(ready),
      .req_mva(address),
      .req_physical(pa),
      .req_write(wr),
      .req_early_read(early),
      .req_ordinary_store(ordinary),
      .req_resident_access(resident),
      .req_cache_enable(enabled),
      .req_cacheable(enabled),
      .req_bufferable(1'b1),
      .req_wdata(din),
      .req_byte_enable(mask),
      .response_valid(valid),
      .response_error(error),
      .response_data(data),
      .write_buffer_empty(empty),
      .write_buffer_error(),
      .line_req(lreq),
      .line_addr(laddr),
      .line_ready(lready),
      .line_reject(lreject),
      .line_valid(lvalid),
      .line_data(ldata),
      .line_wide(1'b1),
      .line_last(llast),
      .line_error(1'b0),
      .fast_lookup_enable(fasten),
      .fast_lookup_address(32'b0),
      .data_probe_valid(probe),
      .data_probe_address(paddr),
      .fast_lookup_valid(fvalid),
      .fast_lookup_checked(),
      .fast_lookup_line(),
      .fast_lookup_word(fword),
      .invalidate_all(inv),
      .lock_write(lock),
      .lock_base_in(lockbase),
      .round_robin(1'b1),
      .maint_valid(mv),
      .maint_clean(mc),
      .maint_invalidate(mi),
      .maint_all(1'b1),
      .maint_by_mva(1'b0),
      .maint_address(32'b0),
      .maint_way(6'b0),
      .maint_segment(3'b0),
      .maint_ready(mr),
      .maint_done(md),
      .maint_error(),
      .bus_valid(bus_valid),
      .bus_write(bus_write),
      .bus_address(bus_address),
      .bus_wdata(bus_data),
      .bus_byte_enable(bus_mask),
      .bus_ack(bus_valid),
      .bus_error(1'b0),
      .bus_rdata(mem[bus_address[16:2]])
  );


function [31:0] merge(input [31:0] old,value,input [3:0] be);
integer b;begin merge=old;for(b=0;b<4;b=b+1)if(be[b])merge[b*8+:8]=value[b*8+:8];end
endfunction
always @(posedge clk) begin
 edge_id=edge_id+1;
 if(tracing)$display("EDGE e=%0d event=%0d stage=%0d req=%0d ready=%0d owner=%0d intent=%0d commit=%0d reply=%0d inv=%0d lock=%0d reset=%0d fast=%0d apply_inv=%0d apply_lock=%0d",edge_id,event_id,stage,req,ready,dut.pipe_owner,dut.bank.store_commit,|enables,valid,inv,lock,reset,fvalid,dut.bank.invalidate_all,dut.bank.lock_write);
 if(!reset) begin
 if(dut.bank.invalidate_all || dut.bank.lock_write)applies=applies+1;
 if(bus_valid && bus_write) begin
 writes=writes+1;
 mem[bus_address[16:2]]<=merge(mem[bus_address[16:2]],bus_data,bus_mask);
 if(checking && bus_mask!==15)$fatal(1,"bad writeback mask");
 end
 if(checking) begin
 if(req&&ready) begin
 qpa[accepts]=pa;qaddr[accepts]=address;qdata[accepts]=din;qmask[accepts]=mask;accepts=accepts+1;
 end
 if(valid)replies=replies+1;
 if(|enables) begin
 if(commits>=accepts)$fatal(1,"unowned mutation");
 sampled_address=qaddr[commits];sampled_slot=slot;sampled_word=sampled_address[4:2];
 if(slotline!={sampled_address[31:5],5'b0} || enables!==({28'b0,qmask[commits]}<<(sampled_word*4)))$fatal(1,"wrong commit slot/mask");
 for(integer b=0;b<4;b=b+1)if(qmask[commits][b] && payload[sampled_word*32+b*8+:8]!==qdata[commits][b*8+:8])$fatal(1,"wrong commit bytes");
 sampled_expected=merge(gold[qpa[commits]>>2],qdata[commits],qmask[commits]);
 gold[qpa[commits]>>2]=sampled_expected;commits=commits+1;
 #1;if(ramwords[sampled_word]!==sampled_expected)$fatal(1,"physical RAM mismatch");
 end
 if(replies>commits)$fatal(1,"reply without physical commit");
 end
 end
end
task tick;begin @(posedge clk);#2;@(negedge clk);end endtask
task init_cache;
begin
 checking=0;req=0;mv=0;inv=0;lock=0;probe=0;enabled=1;reset=1;
 repeat(2)tick();reset=0;tick();
 for(integer n=0;n<32768;n=n+1)gold[n]=mem[n];
end endtask
task read_word(input [31:0] addr);
begin
 req=0;while(!ready)tick();address=addr;pa=addr;wr=0;req=1;mask=15;tick();req=0;
 while(!valid)tick();if(error||data!==gold[addr>>2])$fatal(1,"readback %h got=%h expected=%h",addr,data,gold[addr>>2]);tick();
end endtask
task warm;
begin read_word('h100);read_word('h1100);read_word('h100);read_word('h1100);end
endtask
task start_pair(input integer delay_stage);
begin
 accepts=0;replies=0;commits=0;checking=1;req=1;wr=1;address='h100;pa='h100;din=32'hbda10203;mask=5;
 if(delay_stage>0)begin tick();address='h110;pa='h110;din=32'h81a23b45;mask=10;end
 if(delay_stage>1)begin tick();req=0;end
 if(delay_stage>2)tick();
 if(delay_stage>3)tick();
end endtask
task drain;
begin req=0;waits=0;while(commits<accepts||replies<accepts)begin tick();waits=waits+1;if(waits>12)$fatal(1,"drain timeout");end
 repeat(2)tick();checking=0;
end endtask
task lifecycle;
begin
 for(event_id=0;event_id<7;event_id=event_id+1)
 for(stage=0;stage<5;stage=stage+1) begin
 init_cache();warm();probe=1;paddr='h100;address='h100;pa=address;repeat(4)tick();
 if(!fvalid)$fatal(1,"lifecycle probe not primed");
 tracing=1;start_pair(stage);olda=accepts;oldc=commits;oldr=replies;oldapplies=applies;
 case(event_id)
 0:begin
 reset=1;req=0;#1;if(valid||fvalid||bus_valid||lreq||(|enables))$fatal(1,"reset failed immediate suppression");
 tick();checking=0;repeat(2)tick();reset=0;tick();
 for(i=0;i<32768;i=i+1)gold[i]=mem[i];
 repeat(4)begin if(valid||fvalid||(|enables)||bus_valid||lreq)$fatal(1,"stale reset effect");tick();end
 $display("CASE reset stage=%0d accepted=%0d precommitted=%0d canceled=%0d",stage,olda,oldc,olda-oldc);
 end
 1,2:begin
 if(event_id==1)inv=1;else begin lock=1;lockbase=stage+1;end
 tick();inv=0;lock=0;
 waits=0;while(applies==oldapplies)begin tick();waits=waits+1;if(waits>8)$fatal(1,"pending pulse starved");end
 req=0;drain();if(accepts!=olda||applies!=oldapplies+1)$fatal(1,"pulse lost/duplicated/admitted younger");
 if(event_id==1)for(i=0;i<32768;i=i+1)gold[i]=mem[i];
 if(event_id==2&&dut.bank.lock_base!==stage+1)$fatal(1,"lock payload lost");
 $display("CASE pulse event=%0d stage=%0d accepts=%0d commits=%0d replies=%0d applications=1",event_id,stage,accepts,commits,replies);
 end
 3,4,5:begin
 mv=1;mc=event_id!=4;mi=event_id!=3;#1;
 waits=0;while(!mr)begin tick();waits=waits+1;if(waits>8)$fatal(1,"maintenance starved");end
 tick();mv=0;req=0;drain();
 while(!md)tick();tick();while(!empty)tick();
 if(accepts!=olda)$fatal(1,"maintenance accepted younger");
 if(event_id==4)for(i=0;i<32768;i=i+1)gold[i]=mem[i];
 if(event_id!=4 && (mem['h40]!==gold['h40]||mem['h44]!==gold['h44]))$fatal(1,"clean lost older data");
 mc=0;mi=0;
 $display("CASE maintenance event=%0d stage=%0d accepts=%0d commits=%0d replies=%0d",event_id,stage,accepts,commits,replies);
 end
 6:begin enabled=0;req=0;drain();tick();enabled=1;tick();
 if(dut.line_result_valid!==0)$fatal(1,"disabled cache retained certificate");
 $display("CASE disable stage=%0d accepts=%0d commits=%0d replies=%0d",stage,accepts,commits,replies);
 end
 endcase
 tracing=0;read_word('h100);read_word('h110);warm();
 if(dut.line_result_valid===0)$fatal(1,"certificate not reacquired");
 checks=checks+1;
 end
end endtask
integer fast_count=0;
reg consume_fast=0,probes_done=0;
always @(negedge clk) if(probes_done && fast_count!=8)$fatal(1,"missing fast consumer");
always @(posedge clk)if(consume_fast)begin
 if(!fvalid || fword!==gold[address>>2])$fatal(1,"sampled fast ACK/data mismatch");
 fast_count=fast_count+1;
end
reg line_mode=0,peer_active=0;
reg [31:0] peer_address;
integer peer_index=0,peer_gap=0,successful_lines=0,rejected_lines=0,poison_checks=0;
// A line peer has no per-beat ready. Once accepted it drains even in core
// reset. The caller holds reset until the peer is quiet, matching outer drain.
always @(posedge clk) begin
 lvalid<=0;llast<=0;
 if(lreq&&lready&&!reset) begin
 if(!line_mode)rejected_lines=rejected_lines+1;
 else if(!peer_active)begin peer_active<=1;peer_address<=laddr;peer_index<=0;peer_gap<=0;successful_lines=successful_lines+1;end
 end
 if(peer_active)begin
 peer_gap<=peer_gap+1;
 if(peer_gap%3==2)begin
 lvalid<=1;ldata<={mem[(peer_address>>2)+2*peer_index+1],mem[(peer_address>>2)+2*peer_index]};
 llast<=peer_index==3;line_beats=line_beats+1;
 if(peer_index==3)peer_active<=0;else peer_index<=peer_index+1;
 end
 end
end
task probes;
integer relation,pairs,n;
reg [31:0] target;
begin
 for(relation=0;relation<4;relation=relation+1)
 for(pairs=1;pairs<=2;pairs=pairs+1)begin
 init_cache();warm();read_word('h120);warm();
 case(relation)0:target='h100;1:target='h110;2:target='h1100;3:target='h120;endcase
 address=target;pa=target;paddr=target;probe=1;repeat(4)tick();
 if(!fvalid)$fatal(1,"probe not primed");
 event_id=8;stage=relation;tracing=1;start_pair(pairs);req=0;wr=0;address=target;pa=target;#1;
 while(dut.pipe_owner||dut.pipe_commit)begin
 if(fvalid)begin
 $display("STALE_FAST e=%0d target=%h word=%h commits=%0d accepts=%0d",edge_id,target,fword,commits,accepts);
 $fatal(1,"fast ACK before older store drain");end
 tick();
 end
 drain();probe=1;paddr=target;repeat(3)tick();address=target;pa=target;wr=0;req=0;#1;
 if(!fvalid||fword!==gold[target>>2])$fatal(1,"fresh fast consumer mismatch");
 // Faithful fast consumer: no ordinary req when fast ACK is consumed.
 consume_fast=1;tick();consume_fast=0;
 probe=0;tracing=0;read_word(target);
 $display("CASE probes relation=%0d adjacent=%0d commits=%0d replies=%0d fast_word=%h PASS",relation,pairs,commits,replies,gold[target>>2]);
 end
 $display("FAST_CONSUMERS sampled=%0d",fast_count);
 probes_done=1;tick();probes_done=0;
end endtask
task read_alias(input [31:0] mva,physical);
begin
 while(!ready)tick();address=mva;pa=physical;wr=0;req=1;mask=15;tick();req=0;
 while(!valid)tick();if(error||data!==gold[physical>>2])$fatal(1,"alias load mismatch");tick();
end endtask
reg audit_victim=0;
integer victim_words=0;
always @(posedge clk)if(!reset&&audit_victim&&bus_valid&&bus_write)begin
 if(bus_address<'h5000 || bus_address>='h5020 || bus_mask!==15 || bus_data!==gold[bus_address>>2])
 $fatal(1,"dirty victim PA/data/mask mismatch addr=%h data=%h",bus_address,bus_data);
 victim_words=victim_words+1;
end
task transfers;
integer n,old_lines,old_beats;
begin
 init_cache();line_mode=1;lreject=0;old_lines=successful_lines;old_beats=line_beats;
 read_word('h200);if(successful_lines!=old_lines+1 || line_beats!=old_beats+4)$fatal(1,"successful line coverage missing");
 for(n=0;n<8;n=n+1)read_word('h200+4*n);
 $display("CASE successful_line beats=4 wide=64 gaps=2 PASS");
 // Fresh miss takes explicit rejection/scalar fallback.
 line_mode=0;lreject=1;old_lines=rejected_lines;read_word('h400);
 if(rejected_lines<=old_lines)$fatal(1,"no rejected line");
 $display("CASE rejection scalar_fallback PASS");
 // Reset during accepted line, with the old peer still owning its tail.
 line_mode=1;lreject=0;address='h600;pa=address;req=1;wr=0;tick();req=0;
 while(!peer_active)tick();tick();reset=1;tick();
 while(peer_active||lvalid)tick();repeat(2)tick();reset=0;tick();
 repeat(4)begin if(valid||fvalid||bus_valid||(|enables)||lreq)$fatal(1,"stale line after reset drain");tick();end
 read_word('h600);$display("CASE line_reset accepted_tail_drained no_stale_restart PASS");
 // Distinct MVA and saved victim PA; force all 64 ways of one segment.
 init_cache();line_mode=1;lreject=0;read_alias('h10100,'h5000);read_alias('h10100,'h5000);
 checking=1;accepts=0;commits=0;replies=0;req=1;wr=1;address='h10100;pa='h5000;din='h12345678;mask=5;tick();
 address='h10110;pa='h5010;din='ha1b2c3d4;mask=10;tick();drain();
 audit_victim=1;victim_words=0;
 for(n=0;n<64;n=n+1)read_word('h1000+256*n);
 audit_victim=0;if(victim_words!=8)$fatal(1,"dirty victim halves not evicted %0d",victim_words);
 for(n=0;n<8;n=n+1)if(mem['h1400+n]!==gold['h1400+n])$fatal(1,"victim backing mismatch");
 $display("CASE dirty_replacement mva=00010100 saved_pa=00005000 words=8 masks=full original_partial_masks=5/a PASS");
end endtask
initial begin
 for(i=0;i<32768;i=i+1)begin mem[i]=32'h51000000^(i*4);gold[i]=mem[i];end
 if(!$test$plusargs("probe_only") && !$test$plusargs("transfers_only"))lifecycle();
 if(!$test$plusargs("transfers_only"))probes();
 if(!$test$plusargs("probe_only"))transfers();
 $display("PASS qualification lifecycle=%0d probes=8 transfers=4",checks);$finish;
end
initial begin #5000000;$fatal(1,"qualification timeout");end
endmodule
