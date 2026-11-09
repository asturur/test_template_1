`timescale 1ns/1ps
module route_tb;
 reg clk=0,reset=1,cyc=0,stb=0,we=0,code=0;
 reg [31:0] a=0,d=0;reg [3:0] be=15;
 reg ready=1,done=0;reg [31:0] q=0;
 wire req,accept,pending,response,ack,error,slow_cyc,slow_stb;
 wire rw,rc;wire [31:0] ra,rd,result;wire [3:0] rb;
 integer admissions=0,i;
 always #5 clk=~clk;
 assign accept=req && ready;
 ngage_cpu_memory_route dut(.clk(clk),.reset(reset),.master_cyc(cyc),.master_stb(stb),
  .master_we(we),.master_code(code),.master_address(a),.master_data(d),.master_sel(be),
  .master_ack(ack),.master_error(error),.master_rdata(result),.slow_cyc(slow_cyc),.slow_stb(slow_stb),
  .slow_idle(1'b1),.slow_ack(1'b0),.slow_error(1'b0),.slow_rdata(32'h12345678),
  .ram_req(req),.ram_we(rw),.ram_code(rc),.ram_address(ra),.ram_wdata(rd),.ram_be(rb),
  .ram_accept(accept),.ram_ack(done),.ram_rdata(q),.ram_pending(pending),.ram_response(response));
 always @(posedge clk)if(!reset && accept)admissions=admissions+1;
 task tick;begin @(posedge clk);#1;@(negedge clk);end endtask
 task finish_ram;input [31:0] value;begin
  q=value;done=1;#1;if(!ack || error || result!==value)$fatal(1,"RAM return lost/misaligned");
  tick;cyc=0;stb=0;done=0;#1;if(ack||pending||req)$fatal(1,"duplicate RAM return");
 end endtask
 initial begin
  tick;reset=0;
  // Both range endpoints select RAM; adjacent addresses select only slow bus.
  a=32'h09fffffc;cyc=1;stb=1;#1;if(req||!slow_stb)$fatal(1,"low range guard");
  a=32'h0b000000;#1;if(req||!slow_stb)$fatal(1,"high range guard");
  a=32'h0a000000;we=1;d=32'hcafebabe;be=5;code=0;
  #1;if(!req||slow_stb||ra!==a||rd!==d||rb!==be||!rw)$fatal(1,"RAM packet wrong");
  tick;if(!pending||req)$fatal(1,"RAM not admitted exactly once");
  repeat(5)begin tick;if(req||ack||slow_stb)$fatal(1,"RAM wait duplicated");end
  finish_ram(32'h12340000);
  a=32'h0afffffc;cyc=1;stb=1;we=0;code=1;tick;finish_ram(32'h87654321);
  // Withdraw before backend grant: no operation is admitted.
  ready=0;a=32'h0a000080;cyc=1;stb=1;tick;
  cyc=0;stb=0;tick;ready=1;if(pending||admissions!=2)$fatal(1,"unaccepted cancellation issued");
  // Withdraw after grant. A pending slow request waits until the old RAM
  // response has drained and must never receive that cancelled payload.
  cyc=1;stb=1;a=32'h0a000084;tick;cyc=0;stb=0;tick;
  cyc=1;stb=1;a=32'h0c120004;
  repeat(3)begin tick;if(slow_stb||ack)$fatal(1,"cancelled request released too soon");end
  done=1;q=32'hbad0bad0;#1;if(ack||response)$fatal(1,"cancelled response escaped");
  tick;done=0;#1;if(!slow_stb||ack)$fatal(1,"slow request not released after drain");
  cyc=0;stb=0;tick;
  // Next RAM request must obtain only its own response.
  a=32'h0a000088;cyc=1;stb=1;tick;finish_ram(32'h77778888);
  // Reset invalidates route ownership; backend owns reset/draining of its
  // accepted physical operation. An unowned response is never delivered.
  cyc=1;stb=1;a=32'h0a00008c;tick;reset=1;tick;cyc=0;stb=0;reset=0;done=1;
  #1;if(ack||pending)$fatal(1,"reset response escaped");tick;done=0;
  if(admissions!=5)$fatal(1,"wrong admission count %0d",admissions);
  $display("PASS direct SDRAM route: range, packet/lane ownership, one admission, cancellation/drain, reset");$finish;
 end
 initial begin #20000;$fatal(1,"route watchdog");end
endmodule
