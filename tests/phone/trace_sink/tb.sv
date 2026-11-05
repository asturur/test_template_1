module tb;
reg clk=0;always #5 clk=~clk;reg reset=1,req=0,commit=0,we=0;reg [31:0] addr=0,din=0;reg [3:0] sel=0;
wire claim,bad,valid;wire [31:0] ta,td;wire [3:0] ts;
ngage_trace_sink dut(clk,reset,req,commit,we,addr,din,sel,claim,bad,valid,ta,td,ts);
task tick;begin @(posedge clk);#1;end endtask
initial begin
 tick();reset=0;@(negedge clk);req=1;we=1;addr='h0de00000;din=32'h41;sel=1;commit=0;tick();if(valid)$fatal(1,"uncommitted trace");
 commit=1;tick();if(!valid||ta!=='h0de00000||td!=='h41||ts!=1)$fatal(1,"missing trace");
 @(negedge clk);commit=0;sel=15;#1;if(!bad)$fatal(1,"wrong byte-sink width accepted");
 addr='h0def0000;#1;if(bad||!claim)$fatal(1,"word trace rejected");we=0;#1;if(!bad)$fatal(1,"trace read accepted");
 $display("PASS write-only trace events and widths");$finish;
end
endmodule
