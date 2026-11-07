module tb;
reg clk=0;always #5 clk=~clk;reg reset=1,req=0,commit=0,we=0;reg [31:0] addr=0,data=0;reg [3:0] sel=15;wire [31:0] out;wire full;
ngage_sparse_regs #(.ENTRIES(2)) dut(clk,reset,req,commit,we,addr,data,sel,out,full);
task tick;begin @(posedge clk);#1;end endtask
task write_word(input [31:0] a,input [31:0] d);begin @(negedge clk);req=1;we=1;commit=1;addr=a;data=d;tick();@(negedge clk);req=0;commit=0;end endtask
initial begin
 tick();reset=0;tick();write_word('h0d000220,'h11223344);write_word('h0d010220,'h55667788);
 @(negedge clk);req=1;we=0;addr='h0d000220;tick();#1;if(out!=='h11223344)$fatal(1,"first alias");addr='h0d010220;tick();#1;if(out!=='h55667788)$fatal(1,"second alias");
 we=1;addr='h0d020220;#1;if(!full)$fatal(1,"overflow not reported");commit=1;tick();@(negedge clk);commit=0;we=0;addr='h0d000220;tick();#1;if(out!=='h11223344)$fatal(1,"overflow overwrote data");
 reset=1;tick();reset=0;#1;if(out!==0)$fatal(1,"cold reset");
 $display("PASS sparse address separation and bounded overflow");$finish;
end
endmodule
