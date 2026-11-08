// SPDX-License-Identifier: GPL-3.0-or-later
module test;
logic clk=0,reset=1,kill=0,request=0,ack=0;
logic [31:0] data=0,fsr=0,far_addr=0;
logic [1:0] fault=0;
wire offer,valid;
wire [31:0] result,result_fsr,result_far;
wire [1:0] result_fault;
bit expected_valid=0;
logic [97:0] expected;
integer checks=0,accepted=0,consumed=0,killed=0;
zap_data_completion dut(.i_clk(clk),.i_reset(reset),.i_kill(kill),
 .i_request(request),.i_ack(ack),.i_data(data),.i_fault(fault),.i_fsr(fsr),.i_far(far_addr),
 .o_offer(offer),.o_valid(valid),.o_data(result),.o_fault(result_fault),.o_fsr(result_fsr),.o_far(result_far));
task automatic tick;
 bit capture;
 #1;
 if(!reset)begin
  if(valid!==expected_valid || offer!==(request && !expected_valid && !kill))$fatal(1,"owner control");
  if(valid && {result,result_fault,result_fsr,result_far}!==expected)$fatal(1,"completion payload/identity");
 end
 capture=request && !expected_valid && ack;
 if(reset || kill)begin expected_valid=0;if(kill)killed++;end
 else begin
  if(expected_valid)consumed++;
  expected_valid=capture;
  if(capture)begin expected={data,fault,fsr,far_addr};accepted++;end
 end
 clk=1;#1;clk=0;checks++;
 if(valid!==expected_valid)$fatal(1,"completion capture/kill priority");
 if(valid && {result,result_fault,result_fsr,result_far}!==expected)$fatal(1,"captured metadata from another edge");
endtask
initial begin
 tick();reset=0;
 for(integer id=0;id<512;id++)begin
  request=1;ack=0;kill=0;
  // IRQ/FIQ do not cancel a P2 owner: CPU keeps the request held until consume.
  for(integer wait_no=0;wait_no<(id%17);wait_no++)begin
   data=32'(id+wait_no);fsr='1;far_addr='1;fault=3;tick();
  end
  data=32'h12340000+32'(id);fault=2'(id);fsr=32'(id+5);far_addr=32'h80000000+32'(id*4);ack=1;
  kill=(id%7)==0;tick();
  if(kill)begin request=0;kill=0;ack=0;tick();end
  else begin
   // Old external data/fault disappears immediately; captured event must survive.
   data=~data;fsr=~fsr;far_addr=~far_addr;fault=~fault;ack=0;
   kill=(id%11)==0;tick();
   request=0;kill=0;tick();
  end
 end
 request=1;ack=1;reset=1;tick();request=0;ack=0;reset=0;tick();
 if(accepted<400 || consumed<350 || killed<100)$fatal(1,"coverage");
 $display("PASS: completion owner %0d clocks, %0d captures, %0d consumes, %0d kills; pulse, abort/retry, payload, reuse, reset",checks,accepted,consumed,killed);
 $finish;
end
endmodule
