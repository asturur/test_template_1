// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
module test;
logic clk=0,reset=1,rd=0,wr=0,discard=0,inject_error=1;
always #5 clk=~clk;
logic alignment_fault=0,fault=0,tlb_busy=0,translation_wait=0;
logic invalidate=0,clean=0,lock_write=0;
logic [31:0] address=32'h80001000;
wire ack,request_ack,err,err2,inv_done,clean_done,lock_done;
wire wb_cyc,wb_stb,wb_wen;
wire [31:0] data,wb_adr,wb_data;
wire [3:0] wb_sel;
wire [2:0] wb_cti;
wire [7:0] fsr;
wire [31:0] far_addr;
integer waited=0,failed_beats=0,read_beats=0,before_reads=0;
wire wb_error=dut.inflight && waited>=3 && inject_error;
wire wb_ack=dut.inflight && waited>=3 && !inject_error;
always @(posedge clk)begin
 if(reset || !dut.inflight || wb_ack || wb_error)waited<=0;
 else waited<=waited+1;
 if(!reset && wb_error)failed_beats<=failed_beats+1;
 if(!reset && wb_ack)read_beats<=read_beats+1;
end
arm920_zap_dcache_adapter dut(
 .clk(clk),.reset(reset),.discard_refill(discard),.external_permit(1'b1),.write_buffer_empty(),
 .fast_enable(1'b0),.fast_next_address(32'd0),
 .address(address),.physical(address),.din(32'h87654321),.far_in(address),
 .rd(rd),.wr(wr),.ben(4'hf),.swp_tag(2'd0),.swp_bus_lock(),
 .alignment_fault(alignment_fault),.alignment_far(address),
 .fault(fault),.fsr_in(8'h05),.external_fsr(8'h08),.tlb_busy(tlb_busy),.translation_wait(translation_wait),
 .cache_enable(1'b1),.cache_rr(1'b0),.cacheable(1'b1),.bufferable(1'b0),
 .cache_invalidate(invalidate),.cache_clean(clean),
 .cache_lock_write(lock_write),.cache_lock_base(6'd0),.cache_lock_done(lock_done),
 .cache_op_single(1'b0),.cache_op_by_mva(1'b0),.cache_op_address(32'd0),
 .data(data),.ack(ack),.request_ack(request_ack),.err(err),.err2(err2),.fsr(fsr),.far(far_addr),
 .idle(),.hold(),.cache_inv_done(inv_done),.cache_clean_done(clean_done),
 .wb_cyc(wb_cyc),.wb_stb(wb_stb),.wb_wen(wb_wen),.wb_sel(wb_sel),
 .wb_adr(wb_adr),.wb_data(wb_data),.wb_cti(wb_cti),.wb_ack(wb_ack),.wb_err(wb_error),.wb_rdata(wb_adr ^ 32'h12345678));


integer timeout;
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
 $display("PASS: live refill errors retry; discarded fetch completes; failed line is not installed");
 $finish;
end
initial begin #20000;$fatal(1,"discard test timed out");end
endmodule
