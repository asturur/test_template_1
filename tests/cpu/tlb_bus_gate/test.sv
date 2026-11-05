`timescale 1ns/1ps
module test;
 logic clk=0;always #5 clk=~clk;
 logic reset=1,empty=0,cyc=0,stb=0,ack=0,err=0;wire oc,os;
 arm920_tlb_bus_gate dut(.clk(clk),.reset(reset),.write_buffer_empty(empty),.in_cyc(cyc),.in_stb(stb),.out_cyc(oc),.out_stb(os),.ack(ack),.err(err));
 task automatic tick;begin @(posedge clk);#1;@(negedge clk);end endtask
 initial begin
  tick();reset=0;cyc=1;stb=1;tick();if(oc || os)$fatal(1,"walk overtook pending writes");
  empty=1;#1;if(!oc || !os)$fatal(1,"walk did not start after drain");tick();
  empty=0;tick();if(!oc || !os)$fatal(1,"in-flight walk was withdrawn");
  ack=1;tick();ack=0;#1;if(oc || os)$fatal(1,"next walk passed buffer");
  empty=1;tick();err=1;tick();err=0;empty=0;#1;if(oc || os)$fatal(1,"error failed to release grant");
  $display("PASS: TLB bus waits for older writes and retains an offered request");$finish;
 end
endmodule
