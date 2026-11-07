module tb;
reg clk=0;always #5 clk=~clk;reg reset=1,req=0,commit=0,we=0;reg [31:0] addr=0,din=0;reg [3:0] sel=15;
wire claim,bad,irq;wire [31:0] dout;reg [15:0] events=0;
ngage_nos_io #(.TICK_DIV(2),.FAST_DIV(3)) dut(clk,reset,req,commit,we,addr,din,sel,claim,bad,dout,irq,events,);
task tick;begin @(posedge clk);#1;end endtask
task wr(input [31:0] a,input [31:0] d,input [3:0] b);begin @(negedge clk);req=1;we=1;commit=1;addr=a;din=d;sel=b;#1;if(!claim||bad)$fatal(1,"decode");tick();@(negedge clk);req=0;commit=0;end endtask
initial begin
 tick();reset=0;tick();
 @(negedge clk);req=1;we=0;addr='h0c150114;sel=15;#1;if(dout[15:0]!=16'h80)$fatal(1,"window default");req=0;
 wr('h0c150010,32'h00800000,12);wr('h0c150118,32'h00000000,3);wr('h0c150100,32'h00000080,3);
 dut.counter=16'hfffe;dut.divider=0;repeat(5)tick();
 if(!irq)$fatal(1,"counter wrap compare IRQ");
 wr('h0c150100,32'h00000080,3);if(irq)$fatal(1,"W1C failed");
 wr('h0c150010,32'h10000000,12);if(!irq)$fatal(1,"software interrupt set");
 wr('h0c150010,32'h00001000,3);if(irq)$fatal(1,"software interrupt clear");
 @(negedge clk);req=1;we=1;commit=0;addr='h0c150010;din=32'h10000000;sel=12;tick();if(irq)$fatal(1,"uncommitted write");
 // A tick event arrives after a same-cycle W1C bus operation.
 @(negedge clk);req=1;we=1;commit=1;addr='h0c150100;din='h200;sel=3;events='h200;tick();
 @(negedge clk);events=0;req=1;we=0;commit=0;#1;if(!dout[9])$fatal(1,"tick must win over W1C");
 reset=1;tick();reset=0;req=0;repeat(6)tick();
 if(dut.fast_counter!==16'd2 || dut.counter!==16'd3)$fatal(1,"counter dividers conflated");
 @(negedge clk);req=1;we=0;sel=12;addr='h0c150110;#1;if(dout[31:16]!==dut.fast_counter)$fatal(1,"fast alias");
 addr='h0c150114;#1;if(dout[31:16]!==dut.counter)$fatal(1,"slow alias");
 // Actual long-boot failure: the generic bit-15 latch is not a modeled
 // interrupt event. It must read back without starving the CPU on IRQ 25.
 reset=1;tick();reset=0;req=0;
 wr('h0c150010,32'h80000000,12);
 wr('h0c150100,32'h80008000,15);
 if(irq || dut.status_reg[15]!==1'b1)$fatal(1,"generic status bit became pending IRQ");
 wr('h0c150010,32'h00800000,12);
 @(negedge clk);events=16'h80;tick();
 @(negedge clk);events=0;#1;if(!irq)$fatal(1,"modeled timer IRQ masked");
 wr('h0c150100,32'h80,3);if(irq)$fatal(1,"timer IRQ ack after generic latch");
 $display("PASS NOS counter wrap, compare, status and software IRQ");$finish;
end
endmodule
