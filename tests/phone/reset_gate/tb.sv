module tb;
reg clk=0;always #5 clk=~clk;reg cold=1,req=0,block_reset=0;wire rst;
ngage_reset_gate dut(.clk(clk),.cold_reset(cold),.reset_request(req),.block_reset(block_reset),.phone_reset(rst));
task tick;begin @(posedge clk);#1;end endtask
initial begin
 tick();cold=0;tick();if(rst)$fatal(1,"reset did not release");
 block_reset=1;req=1;tick();if(rst)$fatal(1,"reset interrupted save");req=0;repeat(4)tick();if(rst)$fatal(1,"reset not deferred");
 block_reset=0;tick();if(!rst)$fatal(1,"deferred reset lost");tick();if(rst)$fatal(1,"reset did not finish");
 req=1;tick();if(!rst)$fatal(1,"held reset missing");tick();if(!rst)$fatal(1,"held reset dropped");req=0;tick();tick();if(rst)$fatal(1,"held reset stuck");
 $display("PASS deferred phone reset");$finish;
end
endmodule
