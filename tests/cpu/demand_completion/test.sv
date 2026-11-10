// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
module test;
logic clk=0,reset=1;
always #5 clk=~clk;
logic rd=0,wr=0,alignment_fault=0,fault=0,tlb_busy=0,translation_wait=0;
logic invalidate=0,clean=0,lock_write=0;
logic [31:0] address=32'h80001000;
wire ack,request_ack,err,err2,inv_done,clean_done,lock_done;
wire wb_cyc,wb_stb,wb_wen;
wire [31:0] data,wb_adr,wb_data;
wire [3:0] wb_sel;
wire [2:0] wb_cti;
wire [7:0] fsr;
wire [31:0] far_addr;
integer checks=0,accepts=0,completions=0,bus_beats=0,waited=0;
// The enclosing ZAP bus mux captures requests before returning completion.
// ACK must depend on that accepted request, not combinationally on wb_stb,
// which the adapter suppresses during a returning ACK.
wire wb_ack=dut.inflight && waited>=3;
always @(posedge clk)begin
 if(reset || !dut.inflight || wb_ack)waited<=0;else waited<=waited+1;
 if(!reset && wb_ack)bus_beats<=bus_beats+1;
 if(!reset && dut.maint_valid && dut.mready)accepts<=accepts+1;
 if(!reset && (inv_done || clean_done))completions<=completions+1;
end
arm920_zap_dcache_adapter dut(
 .clk(clk),.reset(reset),.discard_refill(1'b0),.external_permit(1'b1),.write_buffer_empty(),
 .fast_enable(1'b0),.fast_next_address(32'd0),
 .address(address),.physical(address),.din(32'h87654321),.far_in(address),
 .rd(rd),.wr(wr),.ben(4'hf),.swp_tag(2'd0),.swp_bus_lock(),
 .alignment_fault(alignment_fault),.alignment_far(address),
 .fault(fault),.fsr_in(8'h05),.external_fsr(8'h08),.tlb_busy(tlb_busy),.translation_wait(translation_wait),
 .cache_enable(1'b0),.cache_rr(1'b0),.cacheable(1'b0),.bufferable(1'b0),
 .cache_invalidate(invalidate),.cache_clean(clean),
 .cache_lock_write(lock_write),.cache_lock_base(6'd0),.cache_lock_done(lock_done),
 .cache_op_single(1'b0),.cache_op_by_mva(1'b0),.cache_op_address(32'd0),
 .data(data),.ack(ack),.request_ack(request_ack),.err(err),.err2(err2),.fsr(fsr),.far(far_addr),
 .idle(),.hold(),.cache_inv_done(inv_done),.cache_clean_done(clean_done),
 .wb_cyc(wb_cyc),.wb_stb(wb_stb),.wb_wen(wb_wen),.wb_sel(wb_sel),
 .wb_adr(wb_adr),.wb_data(wb_data),.wb_cti(wb_cti),.wb_ack(wb_ack),.wb_err(1'b0),.wb_rdata(32'h01234567));

// Independent original equation: shared ACK keeps its exact idle contract.
wire original_ack=!(rd || wr) && !dut.active_maint && !invalidate && !clean ? 1'b1 :
                  ((rd || wr) && (alignment_fault || fault)) || err2 || dut.response_valid || dut.fast_hit;
always @(negedge clk)if(!reset)begin
 if(ack!==original_ack)$fatal(1,"legacy housekeeping ACK changed");
 if((rd || wr) && request_ack!==original_ack)$fatal(1,"strobed demand completion changed");
 if(((rd || wr) && !ack)!==((rd || wr) && !request_ack))$fatal(1,"stall timing changed");
 checks++;
end

task automatic transaction(input bit write_access);
 integer before_beats;
 before_beats=bus_beats;
 @(negedge clk);rd=!write_access;wr=write_access;
 #1;if(request_ack)$fatal(1,"request advanced before data completion");
 do begin @(posedge clk);#1;end while(!request_ack);
 if(!write_access && data!==32'h01234567)$fatal(1,"read data not coherent with completion");
 if(err || err2)$fatal(1,"unexpected request fault");
 @(negedge clk); // ACK/data must remain valid for the following sampling edge.
 @(posedge clk);#1;rd=0;wr=0;
 repeat(4)@(negedge clk);
 if(bus_beats!=before_beats+1)$fatal(1,"duplicate/lost demand completion %0d",bus_beats-before_beats);
 if(!ack || request_ack)$fatal(1,"idle housekeeping/demand distinction lost");
endtask

task automatic maintenance(input bit do_clean,input bit do_inv);
 integer old_accepts,old_completions;
 old_accepts=accepts;old_completions=completions;
 @(negedge clk);clean=do_clean;invalidate=do_inv;
 #1;if(ack || request_ack)$fatal(1,"maintenance claimed demand completion");
 do begin @(posedge clk);#1;end while(!(inv_done || clean_done));
 if(request_ack || !dut.active_maint)$fatal(1,"invalid maintenance completion");
 @(posedge clk);#1;clean=0;invalidate=0;
 repeat(4)@(negedge clk);
 if(accepts!=old_accepts+1 || completions!=old_completions+1)$fatal(1,"maintenance not exact once");
 if(!ack || request_ack)$fatal(1,"maintenance release changed idle ACK");
 transaction(0);
endtask

initial begin
 repeat(3)@(negedge clk);reset=0;
 repeat(4)@(negedge clk);
 if(!ack || request_ack)$fatal(1,"idle ACK must not look like demand completion");
 // Exhaustive combinational fault/walk qualification, without launching traffic.
 for(integer state=0;state<64;state++)begin
  rd=state[0];wr=state[1];alignment_fault=state[2];fault=state[3];tlb_busy=state[4];translation_wait=state[5];
  #0.01;
  if(ack!==original_ack || ((rd || wr) && request_ack!==original_ack))$fatal(1,"fault/walk qualification %0d",state);
 end
 rd=0;wr=0;alignment_fault=0;fault=0;tlb_busy=0;translation_wait=0;
 transaction(0);transaction(1);
 maintenance(0,1);maintenance(1,0);maintenance(1,1);
 @(negedge clk);lock_write=1;#1;if(!lock_done)$fatal(1,"idle lockdown handshake changed");
 @(posedge clk);#1;lock_write=0;
 transaction(0);
 @(negedge clk);invalidate=1;
 repeat(8)@(negedge clk);
 reset=1;@(negedge clk);invalidate=0;reset=0;
 repeat(4)@(negedge clk);
 if(dut.active_maint || !ack || request_ack)$fatal(1,"maintenance reset cancellation");
 transaction(0);
 $display("PASS: demand/housekeeping completion split, %0d checked clocks, fault/walk matrix, waited transfers, exact-once clean/invalidate, lockdown/reset",checks);
 $finish;
end
initial begin #1000000;$fatal(1,"completion timeout");end
endmodule
