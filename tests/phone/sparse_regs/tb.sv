module tb;
reg clk=0;always #5 clk=~clk;
reg cold=1,reset=0,req=0,commit=0,we=0;reg [31:0] addr=0,data=0;reg [3:0] sel=15;
wire [31:0] out;wire full,ready;
ngage_sparse_regs #(.ENTRIES(2)) dut(.clk(clk),.cold_reset(cold),.reset(reset),.req(req),.commit(commit),.we(we),.addr(addr),.din(data),.sel(sel),.dout(out),.full(full),.ready(ready));
task tick;begin @(posedge clk);#1;@(negedge clk);end endtask
task lookup(input bit w,input [31:0] a,input [31:0] d);
begin req=1;we=w;addr=a;data=d;commit=0;#1;while(!ready)tick();end endtask
task finish_access;begin commit=1;tick();req=0;commit=0;tick();end endtask
initial begin
 tick();cold=0;tick();
 lookup(1,'h0d000220,'h11223344);finish_access();
 lookup(1,'h0d010220,'h55667788);finish_access();
 lookup(0,'h0d000220,0);if(out!=='h11223344)$fatal(1,"first alias");finish_access();
 lookup(0,'h0d010220,0);if(out!=='h55667788)$fatal(1,"second alias");finish_access();
 lookup(1,'h0d020220,'hffffffff);if(!full)$fatal(1,"overflow not reported");finish_access();
 lookup(0,'h0d000220,0);if(out!=='h11223344)$fatal(1,"overflow overwrote data");finish_access();
 reset=1;tick();reset=0;lookup(0,'h0d010220,0);if(out!=='h55667788)$fatal(1,"warm reset lost table");finish_access();
 cold=1;tick();cold=0;lookup(0,'h0d000220,0);if(out!==0)$fatal(1,"cold reset");finish_access();
 $display("PASS sparse address separation, warm/cold reset and bounded overflow");$finish;
end
initial begin #100000;$fatal(1,"timeout");end
endmodule
