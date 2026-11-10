// SPDX-License-Identifier: GPL-3.0-or-later
// Production bridge from the CPU interface to the ARM920T cache.
module arm920_cache_adapter #(parameter LINE_REFILL=0) (

    output wire line_req,
    output wire [31:0] line_addr,
    input wire line_ready,
    input wire line_reject,
    input wire line_valid,
    input wire [63:0] line_data,
    input wire line_wide,
    input wire line_last,
    input wire line_error,

 input logic clk,reset,
 input wire discard_refill,
 input logic external_permit,output logic write_buffer_empty,
 input logic fast_enable,input logic [31:0] fast_next_address,
 input logic [31:0] address,physical,din,far_in,
 input logic rd,wr,input logic [3:0] ben,
 input logic [1:0] swp_tag, output logic swp_bus_lock,
 input logic alignment_fault,input logic [31:0] alignment_far,
 input logic fault,input logic [7:0] fsr_in,external_fsr,input logic tlb_busy,translation_wait,
 input logic cache_enable,cache_rr,cacheable,bufferable,cache_invalidate,cache_clean,
 input logic cache_lock_write,input logic [5:0] cache_lock_base,output logic cache_lock_done,
 input logic cache_op_single,cache_op_by_mva,input logic [31:0] cache_op_address,
 output logic [31:0] data,output logic ack,request_ack,err,err2,output logic [7:0] fsr,output logic [31:0] far,
 output logic idle,hold,cache_inv_done,cache_clean_done,
 output logic wb_cyc,wb_stb,wb_wen,output logic [3:0] wb_sel,
 output logic [31:0] wb_adr,wb_data,output logic [2:0] wb_cti,
 input logic wb_ack,wb_err,input logic [31:0] wb_rdata
);
 logic launched,active_maint,inflight;
 logic swp_read_abort,swp_lock_active;
 wire swp_uncached_begin=req_valid && req_ready && swp_tag==1 && !(cache_enable && cacheable);
 assign swp_bus_lock=swp_lock_active || swp_uncached_begin;
 logic [7:0] swp_abort_fsr; logic [31:0] swp_abort_far;
 logic [7:0] saved_external_fsr;logic [31:0] saved_external_far;
 logic lock_pending;logic [5:0] pending_lock_base;
 wire apply_lock=(lock_pending || cache_lock_write) && !launched && !active_maint;
 assign cache_lock_done=apply_lock;
 wire [5:0] apply_lock_base=cache_lock_write ? cache_lock_base : pending_lock_base;
 logic req_ready,response_valid,response_error,fast_valid;
 logic [31:0] fast_checked;logic [255:0] fast_line;
 logic [31:0] response_data;
 logic mready,mdone,merror;
 logic bus_valid,bus_write;logic [31:0] bus_adr,bus_data;logic [3:0] bus_sel;
 wire request=(rd || wr) && !alignment_fault && !fault && !tlb_busy && !translation_wait;
 wire fast_hit=fast_enable && rd && !wr && cache_enable && cacheable && fast_valid && fast_checked==address &&
               !launched && !active_maint && !lock_pending && !cache_lock_write && !fault && !alignment_fault && !tlb_busy && !translation_wait && !cache_invalidate && !cache_clean;
 wire req_valid=request && !fast_hit && !launched && !cache_invalidate && !cache_clean && !lock_pending && !cache_lock_write;
 wire maint_valid=(cache_invalidate || cache_clean) && !launched && !active_maint && !lock_pending && !cache_lock_write;
 assign idle=!launched && !active_maint;
 assign hold=(launched && !response_valid) || (request && !response_valid && !fast_hit);
 assign data=fast_hit ? fast_line[address[4:2]*32+:32] : response_data;
 assign fsr=alignment_fault ? 8'h01 : response_valid && swp_tag==2 && swp_read_abort ? swp_abort_fsr : response_valid && response_error ? saved_external_fsr : fsr_in;
 assign far=alignment_fault ? alignment_far : response_valid && swp_tag==2 && swp_read_abort ? swp_abort_far : response_valid && response_error ? saved_external_far : far_in;
 assign err=((rd || wr) && (alignment_fault || fault)) ||
            (response_valid && ((response_error && swp_tag!=1) || (swp_tag==2 && swp_read_abort)));
 assign err2=(rd || wr) && tlb_busy && !translation_wait && !launched;
 // Demand completion is distinct from the legacy idle/housekeeping ACK.
 // A strobed data request cannot use the idle term; exposing that fact here
 // keeps maintenance ownership out of the CPU-wide stall fanout. Completion
 // and its data/fault controls stay in the same cycle (no delayed stall).
 assign request_ack=((rd || wr) && (alignment_fault || fault)) || err2 || response_valid || fast_hit;
 assign ack=!(rd || wr) && !active_maint && !cache_invalidate && !cache_clean ? 1'b1 : request_ack;
 assign cache_inv_done=mdone && cache_invalidate;
 assign cache_clean_done=mdone && cache_clean;
 // The enclosing ZAP mux registers next-cycle bus outputs. One request is
 // outstanding at a time and a bubble prevents replaying a completed beat.
 assign wb_cyc=(bus_valid && external_permit) || inflight;
 assign wb_stb=bus_valid && (external_permit || inflight) && !(inflight && (wb_ack || wb_err));
 assign wb_wen=bus_write;assign wb_sel=bus_sel;assign wb_adr=bus_adr;assign wb_data=bus_data;
 assign wb_cti=3'b111;
 always_ff @(posedge clk) begin
  if(reset)begin launched<=0;active_maint<=0;inflight<=0;lock_pending<=0;pending_lock_base<=0;saved_external_fsr<=0;saved_external_far<=0;swp_read_abort<=0;swp_lock_active<=0;swp_abort_fsr<=0;swp_abort_far<=0;end
  else begin
   if(swp_uncached_begin) swp_lock_active<=1;
   if((response_valid && swp_tag==2) || ((alignment_fault || fault) && swp_tag==2)) swp_lock_active<=0;
   if(response_valid && response_error && swp_tag==1) begin
    swp_read_abort<=1;swp_abort_fsr<=saved_external_fsr;swp_abort_far<=saved_external_far;
   end
   if((response_valid && swp_tag==2) || ((alignment_fault || fault) && swp_tag==2)) swp_read_abort<=0;
   if(cache_lock_write) begin lock_pending<=1;pending_lock_base<=cache_lock_base;end
   if(apply_lock) lock_pending<=0;
   if(req_valid && req_ready)begin launched<=1;saved_external_fsr<=external_fsr;saved_external_far<=address;end
   if(response_valid)launched<=0;
   if(maint_valid && mready)active_maint<=1;
   if(mdone)active_maint<=0;
   if(wb_stb && !inflight)inflight<=1;
   if(inflight && (wb_ack || wb_err))inflight<=0;
  end
 end
 arm920_cache_access #(.LINE_REFILL(LINE_REFILL)) cache(
.line_req(line_req),.line_addr(line_addr),.line_ready(line_ready),
    .line_reject(line_reject),.line_valid(line_valid),.line_data(line_data),
    .line_wide(line_wide),.line_last(line_last),.line_error(line_error),
.clk(clk),.reset(reset),.discard_refill(discard_refill),.req_valid(req_valid),.req_ready(req_ready),
  .req_mva(address),.req_physical(physical),.req_write(wr),.req_cache_enable(cache_enable),
  .req_cacheable(cacheable),.req_bufferable((swp_tag==2 && !(cache_enable && cacheable)) ? 1'b0 : bufferable),.req_wdata(din),.req_byte_enable(ben),
   .response_valid(response_valid),.response_error(response_error),.response_data(response_data),.write_buffer_empty(write_buffer_empty),.write_buffer_error(),
  .fast_lookup_enable(fast_enable),.fast_lookup_address(fast_next_address),.fast_lookup_valid(fast_valid),
  .fast_lookup_checked(fast_checked),.fast_lookup_line(fast_line),
  .invalidate_all(1'b0),.lock_write(apply_lock),.lock_base_in(apply_lock_base),.round_robin(cache_rr),
  .maint_valid(maint_valid),.maint_clean(cache_clean),.maint_invalidate(cache_invalidate),.maint_all(!cache_op_single),.maint_by_mva(cache_op_by_mva),.maint_address(cache_op_address),
  .maint_way(cache_op_address[31:26]),.maint_segment(cache_op_address[7:5]),.maint_ready(mready),.maint_done(mdone),.maint_error(merror),
  .bus_valid(bus_valid),.bus_write(bus_write),.bus_address(bus_adr),.bus_wdata(bus_data),.bus_byte_enable(bus_sel),
  .bus_ack(inflight && wb_ack),.bus_error(inflight && wb_err),.bus_rdata(wb_rdata));
endmodule
