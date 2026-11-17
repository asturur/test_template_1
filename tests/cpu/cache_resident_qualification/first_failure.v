`timescale 1ns/1ps
module test;
reg clk=0, reset=1, req=0, wr=0, early=1, enabled=1;
reg resident=1, ordinary=1,inv=0,lock=0,mv=0,mc=0,mi=0;
reg [31:0] address=0,din=0;reg [3:0] mask=15;reg [5:0] lockbase=0;
wire mr,md,ready,valid,error,bus_valid,bus_write,empty;
wire [31:0] data,bus_address,bus_data;wire [3:0] bus_mask;
reg [31:0] mem[0:32767],gold[0:32767];
reg fasten=1,probe=0;reg [31:0] paddr=0;wire fvalid;wire [31:0] fword;
wire lreq;wire [31:0] laddr;reg lready=1,lreject=1,lvalid=0,llast=0;reg [63:0] ldata=0;
integer edge_id=0,accepts=0,replies=0,commits=0,writes=0,line_beats=0;
integer i,j,stage,event_id,oldc,oldr,olda,waits,basewrites,checks=0;
reg tracing=0, checking=0;reg [31:0] qaddr[0:255],qdata[0:255];reg [3:0] qmask[0:255];
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
      .req_physical(address),
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
 if(tracing)$display("EDGE e=%0d event=%0d stage=%0d req=%0d ready=%0d owner=%0d intent=%0d commit=%0d reply=%0d inv=%0d lock=%0d reset=%0d fast=%0d",edge_id,event_id,stage,req,ready,dut.pipe_owner,dut.bank.store_commit,|enables,valid,inv,lock,reset,fvalid);
 if(!reset) begin
 if(bus_valid && bus_write) begin
 writes=writes+1;
 mem[bus_address[16:2]]<=merge(mem[bus_address[16:2]],bus_data,bus_mask);
 if(checking && bus_mask!==15)$fatal(1,"bad writeback mask");
 end
 if(checking) begin
 if(req&&ready) begin
 qaddr[accepts]=address;qdata[accepts]=din;qmask[accepts]=mask;accepts=accepts+1;
 end
 if(valid)replies=replies+1;
 if(|enables) begin
 if(commits>=accepts)$fatal(1,"unowned mutation");
 sampled_address=qaddr[commits];sampled_slot=slot;sampled_word=sampled_address[4:2];
 if(slotline!={sampled_address[31:5],5'b0} || enables!==({28'b0,qmask[commits]}<<(sampled_word*4)))$fatal(1,"wrong commit slot/mask");
 for(integer b=0;b<4;b=b+1)if(qmask[commits][b] && payload[sampled_word*32+b*8+:8]!==qdata[commits][b*8+:8])$fatal(1,"wrong commit bytes");
 sampled_expected=merge(gold[sampled_address>>2],qdata[commits],qmask[commits]);
 gold[sampled_address>>2]=sampled_expected;commits=commits+1;
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
end endtask
task read_word(input [31:0] addr);
begin
 req=0;while(!ready)tick();address=addr;wr=0;req=1;mask=15;tick();req=0;
 while(!valid)tick();if(error||data!==gold[addr>>2])$fatal(1,"readback %h got=%h expected=%h",addr,data,gold[addr>>2]);tick();
end endtask
task warm;
begin read_word('h100);read_word('h1100);read_word('h100);read_word('h1100);end
endtask
task start_pair(input integer delay_stage);
begin
 accepts=0;replies=0;commits=0;checking=1;req=1;wr=1;address='h100;din=32'hbda10203;mask=5;
 if(delay_stage>0)begin tick();address='h110;din=32'h81a23b45;mask=10;end
 if(delay_stage>1)begin tick();req=0;end
 if(delay_stage>2)tick();
 if(delay_stage>3)tick();
end endtask
task drain;
begin req=0;waits=0;while(commits<accepts||replies<accepts)begin tick();waits=waits+1;if(waits>12)$fatal(1,"drain timeout");end
 repeat(2)tick();checking=0;
end endtask
initial begin
 for(i=0;i<32768;i=i+1)begin mem[i]=32'h51000000^(i*4);gold[i]=mem[i];end
 init_cache();warm();
 stage=2;event_id=1;tracing=1;start_pair(stage);inv=1;tick();inv=0;drain();
 $display("PASS qualification first reproduce");$finish;
end
initial begin #5000000;$fatal(1,"qualification timeout");end
endmodule
