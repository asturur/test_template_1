// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
module test;
reg clk=0,reset=1,rd=0,wr=0,discard=0,inject_error=1;
always #5 clk=~clk;
reg alignment_fault=0,fault=0,tlb_busy=0,translation_wait=0;
reg invalidate=0,clean=0,lock_write=0;
reg [31:0] address=32'h80001000;
wire idle,hold,buffer_empty,swp_lock,line_req; wire [31:0] line_addr;
wire idle_ro,hold_ro,buffer_empty_ro,swp_lock_ro,line_req_ro; wire [31:0] line_addr_ro;
wire ack,request_ack,err,err2,inv_done,clean_done,lock_done;
wire wb_cyc,wb_stb,wb_wen;
wire [31:0] data,wb_adr,wb_data;
wire [3:0] wb_sel;
wire [2:0] wb_cti;
wire [7:0] fsr;
wire [31:0] far_addr;
reg fast=0; reg [31:0] fast_address=0; reg [5:0] lock_base=0;
reg single=0, by_mva=0; reg [31:0] maintenance_address=0;
integer waited=0,failed_beats=0,read_beats=0,before_reads=0;
wire wb_error=dut.inflight && waited>=3 && inject_error;
wire wb_ack=dut.inflight && waited>=3 && !inject_error;
always @(posedge clk)begin
 if(reset || !dut.inflight || wb_ack || wb_error)waited<=0;
 else waited<=waited+1;
 if(!reset && wb_error)failed_beats<=failed_beats+1;
 if(!reset && wb_ack)read_beats<=read_beats+1;
end
// Independent stalled line responder, exercising 16-bit and 64-bit transports.
reg line_active=0,line_wide=1;
reg [31:0] captured_line=0;
integer line_delay=0,line_half=0,line_count=0;
wire line_valid=line_active && line_delay==0;
wire line_last=line_half+(line_wide ? 4 : 1)==16;
wire [31:0] line_word=(captured_line+((line_half>>1)<<2)) ^ 32'h12345678;
wire [31:0] next_line_word=(captured_line+((line_half>>1)<<2)+4) ^ 32'h12345678;
wire [63:0] line_data=line_wide ? {next_line_word,line_word} :
    {48'b0,(line_half[0] ? line_word[31:16] : line_word[15:0])};
initial if($test$plusargs("halfword"))line_wide=0;
always @(posedge clk)begin
 if(reset)begin line_active<=0;line_delay<=0;line_half<=0;end
 else if(line_req && !line_active)begin
  line_active<=1;captured_line<=line_addr;line_delay<=3;line_half<=0;line_count<=line_count+1;
 end else if(line_active)begin
  if(line_delay!=0)line_delay<=line_delay-1;
  else if(line_last)line_active<=0;
  else begin line_half<=line_half+(line_wide ? 4 : 1);line_delay<=1;end
 end
end
arm920_cache_adapter #(.LINE_REFILL(1)) dut(
 .line_req(line_req),.line_addr(line_addr),.line_ready(!line_active),.line_reject(1'b0),
 .line_valid(line_valid),.line_data(line_data),.line_wide(line_wide),.line_last(line_last),.line_error(1'b0),
 .clk(clk),.reset(reset),.discard_refill(discard),.external_permit(1'b1),.write_buffer_empty(buffer_empty),
 .fast_enable(fast),.fast_next_address(fast_address),
 .address(address),.physical(address),.din(32'h87654321),.far_in(address),
 .rd(rd),.wr(wr),.ben(4'hf),.swp_tag(2'd0),.swp_bus_lock(swp_lock),
 .alignment_fault(alignment_fault),.alignment_far(address),
 .fault(fault),.fsr_in(8'h05),.external_fsr(8'h08),.tlb_busy(tlb_busy),.translation_wait(translation_wait),
 .cache_enable(1'b1),.cache_rr(1'b1),.cacheable(1'b1),.bufferable(1'b0),
 .cache_invalidate(invalidate),.cache_clean(clean),
 .cache_lock_write(lock_write),.cache_lock_base(lock_base),.cache_lock_done(lock_done),
 .cache_op_single(single),.cache_op_by_mva(by_mva),.cache_op_address(maintenance_address),
 .data(data),.ack(ack),.request_ack(request_ack),.err(err),.err2(err2),.fsr(fsr),.far(far_addr),
 .idle(idle),.hold(hold),.cache_inv_done(inv_done),.cache_clean_done(clean_done),
 .wb_cyc(wb_cyc),.wb_stb(wb_stb),.wb_wen(wb_wen),.wb_sel(wb_sel),
 .wb_adr(wb_adr),.wb_data(wb_data),.wb_cti(wb_cti),.wb_ack(wb_ack),.wb_err(wb_error),.wb_rdata(wb_adr ^ 32'h12345678));
wire [31:0] data_ro;
wire ack_ro;
wire request_ack_ro;
wire err_ro;
wire err2_ro;
wire [7:0] fsr_ro;
wire [31:0] far_addr_ro;
wire inv_done_ro;
wire clean_done_ro;
wire lock_done_ro;
wire wb_cyc_ro;
wire wb_stb_ro;
wire wb_wen_ro;
wire [3:0] wb_sel_ro;
wire [31:0] wb_adr_ro;
wire [31:0] wb_data_ro;
wire [2:0] wb_cti_ro;
arm920_cache_adapter #(.LINE_REFILL(1), .READ_ONLY(1)) readonly_cache(
 .line_req(line_req_ro),.line_addr(line_addr_ro),.line_ready(!line_active),.line_reject(1'b0),
 .line_valid(line_valid),.line_data(line_data),.line_wide(line_wide),.line_last(line_last),.line_error(1'b0),
 .clk(clk),.reset(reset),.discard_refill(discard),.external_permit(1'b1),.write_buffer_empty(buffer_empty_ro),
 .fast_enable(fast),.fast_next_address(fast_address),
 .address(address),.physical(address),.din(32'h87654321),.far_in(address),
 .rd(rd),.wr(wr),.ben(4'hf),.swp_tag(2'd0),.swp_bus_lock(swp_lock_ro),
 .alignment_fault(alignment_fault),.alignment_far(address),
 .fault(fault),.fsr_in(8'h05),.external_fsr(8'h08),.tlb_busy(tlb_busy),.translation_wait(translation_wait),
 .cache_enable(1'b1),.cache_rr(1'b1),.cacheable(1'b1),.bufferable(1'b0),
 .cache_invalidate(invalidate),.cache_clean(clean),
 .cache_lock_write(lock_write),.cache_lock_base(lock_base),.cache_lock_done(lock_done_ro),
 .cache_op_single(single),.cache_op_by_mva(by_mva),.cache_op_address(maintenance_address),
 .data(data_ro),.ack(ack_ro),.request_ack(request_ack_ro),.err(err_ro),.err2(err2_ro),.fsr(fsr_ro),.far(far_addr_ro),
 .idle(idle_ro),.hold(hold_ro),.cache_inv_done(inv_done_ro),.cache_clean_done(clean_done_ro),
 .wb_cyc(wb_cyc_ro),.wb_stb(wb_stb_ro),.wb_wen(wb_wen_ro),.wb_sel(wb_sel_ro),
 .wb_adr(wb_adr_ro),.wb_data(wb_data_ro),.wb_cti(wb_cti_ro),.wb_ack(wb_ack),.wb_err(wb_error),.wb_rdata(wb_adr ^ 32'h12345678));

integer compared_cycles=0;
always @(negedge clk) begin
 if(!reset) begin
  compared_cycles=compared_cycles+1;
  if (idle !== idle_ro || hold !== hold_ro || buffer_empty !== buffer_empty_ro ||
      swp_lock !== swp_lock_ro || line_req !== line_req_ro || line_addr !== line_addr_ro ||
      data !== data_ro ||
      ack !== ack_ro ||
      request_ack !== request_ack_ro ||
      err !== err_ro ||
      err2 !== err2_ro ||
      fsr !== fsr_ro ||
      far_addr !== far_addr_ro ||
      inv_done !== inv_done_ro ||
      clean_done !== clean_done_ro ||
      lock_done !== lock_done_ro ||
      wb_cyc !== wb_cyc_ro ||
      wb_stb !== wb_stb_ro ||
      wb_wen !== wb_wen_ro ||
      wb_sel !== wb_sel_ro ||
      wb_adr !== wb_adr_ro ||
      wb_data !== wb_data_ro ||
      wb_cti !== wb_cti_ro)
   $fatal(1,"read-only specialization changed an external value/latency at cycle %0d", compared_cycles);
  if(wb_cyc && wb_stb && wb_wen)$fatal(1,"read-only workload issued a writeback");
  if(readonly_cache.cache.bank.tags.hit_dirty !== 0 ||
     readonly_cache.cache.bank.tags.victim_dirty !== 0 ||
     readonly_cache.cache.bank.tags.scan_dirty !== 0)
   $fatal(1,"read-only metadata exposed dirty state");
 end
end



integer timeout,n;
task fetch;
 input [31:0] target;
 input expected_error;
 integer bound;
 begin
  address=target;rd=1;bound=0;#1;
  while(!request_ack && bound<1000)begin @(negedge clk);#1;bound=bound+1;end
  if(!request_ack || err!==expected_error)$fatal(1,"instruction fetch failed addr=%h err=%b",target,err);
  if(!expected_error && data!==(target ^ 32'h12345678))$fatal(1,"instruction data mismatch");
  @(negedge clk);rd=0;repeat(4)@(negedge clk);
 end
endtask
task maintain;
 input do_clean,do_invalidate,one,mva_mode;
 input [31:0] target;
 integer bound;
 begin
  clean=do_clean;invalidate=do_invalidate;single=one;by_mva=mva_mode;maintenance_address=target;bound=0;
  while(!(do_invalidate ? inv_done : clean_done) && bound<10000)begin @(negedge clk);bound=bound+1;end
  if(bound==10000)$fatal(1,"instruction maintenance timed out");
  clean=0;invalidate=0;repeat(5)@(negedge clk);
 end
endtask
initial begin
 repeat(3)@(negedge clk);reset=0;rd=1;
 // A live cacheable demand still retries bus failures without an external abort.
 repeat(400)begin
  @(negedge clk);
  if(request_ack || err)$fatal(1,"live cached demand escaped retry policy");
 end
 if(failed_beats<3)$fatal(1,"test did not exercise repeated refill errors");
 // The CPU has resolved a redirect and inhibits this old fetch's instruction.
 discard=1;timeout=0;
 while(!request_ack && timeout<100)begin @(negedge clk);timeout=timeout+1;end
 if(!request_ack || err || err2)$fatal(1,"abandoned instruction refill did not complete harmlessly");
 rd=0;discard=0;inject_error=0;repeat(4)@(negedge clk);
 // Failed/discarded data must not have been installed as a valid cache line.
 before_reads=read_beats;rd=1;timeout=0;
 while(!request_ack && timeout<500)begin @(negedge clk);timeout=timeout+1;end
 if(!request_ack || err || data!==(address ^ 32'h12345678))$fatal(1,"next live instruction read failed");
 if(read_beats-before_reads!=8)$fatal(1,"failed line was installed or refill was incomplete");
 rd=0;repeat(5)@(negedge clk);
 // Hits, misses and eviction through all 64 ways and all 8 segments; no stores.
 for(n=0;n<64;n=n+1) begin
  fetch(32'h80000000+(n<<8), 0);
 end
 before_reads=read_beats;
 for(n=0;n<64;n=n+1)fetch(32'h80000000+(n<<8),0);
 if(read_beats!=before_reads)$fatal(1,"instruction cache lost 64-way capacity");
 for(n=64;n<70;n=n+1)fetch(32'h80000000+(n<<8),0);
 for(n=0;n<8;n=n+1) begin
  fetch(32'h80010000+(n<<5), 0);
  before_reads=read_beats;fetch(32'h80010000+(n<<5), 0);
  if(read_beats!=before_reads)$fatal(1,"resident instruction failed to hit");
 end
 // Lookahead/prefetch uses the existing cache lookup and token stages.
 fast=1;fast_address=32'h80010020;address=fast_address;
 repeat(8)@(negedge clk);
 before_reads=read_beats;fetch(32'h80010020, 0);
 if(read_beats!=before_reads)$fatal(1,"lookahead instruction missed");
 fast=0;
 // Clean is a no-writeback operation on either read-only trace.
 before_reads=read_beats;maintain(1,0,0,0,0);
 fetch(32'h80010020, 0);
 if(read_beats!=before_reads)$fatal(1,"clean evicted a clean instruction");
 maintain(0,1,1,1,32'h80010020);
 before_reads=read_beats;fetch(32'h80010020, 0);
 if(read_beats-before_reads!=8)$fatal(1,"MVA invalidate did not remove instruction");
 // Indexed maintenance, complete invalidation and lockdown retain timing.
 maintain(1,1,1,0,32'h00000000);
 maintain(0,1,0,0,0);
 lock_base=63;lock_write=1;@(negedge clk);lock_write=0;
 repeat(4)@(negedge clk);
 fetch(32'h80030000,0);fetch(32'h80030100,0);
 if(dut.cache.bank.tags.lock_base!==63 || readonly_cache.cache.bank.tags.lock_base!==63)
  $fatal(1,"lockdown changed");
 // External translation/alignment aborts must have the same visible timing.
 fault=1;fetch(32'h81000000,1);fault=0;
 alignment_fault=1;fetch(32'h81000002,1);alignment_fault=0;
 // Actual production-eligible streamed line refill and cached reuse.
 before_reads=line_count;fetch(32'h0a001000,0);
 if(line_count!=before_reads+1)$fatal(1,"streamed line path was not exercised");
 fetch(32'h0a001004,0);
 if(line_count!=before_reads+1)$fatal(1,"streamed line was not retained");
 // Warm reset while idle forgets tags, then refill exactly as before.
 reset=1;repeat(3)@(negedge clk);reset=0;
 before_reads=read_beats;fetch(32'h80030100,0);
 if(read_beats-before_reads!=8)$fatal(1,"reset retained an instruction tag");
 $display("PASS: read-only cache cycle equivalence (%0d cycles), capacity, streamed/word refill/hit, clean/invalidate, lockdown, lookahead, discard/errors/reset",compared_cycles);
 $finish;
end
initial begin #2000000;$fatal(1,"discard test timed out");end
endmodule
