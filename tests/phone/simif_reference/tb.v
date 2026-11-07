`timescale 1ns/1ps
module tb;
parameter PRESENT=1;
reg clk=0,rst=1,cold=1,cyc=0,stb=0,we=0,commit=0;reg [31:0] adr=0,din=0;reg [3:0] sel=3;
wire claim,ready,bad,fiq,init;wire [31:0] dout;
integer f,rc,line=0;reg [31:0] a,d,ss,w,ok,expected,pending;
always #5 clk=~clk;
ngage_board #(.SIMIF_ENABLE(1)) dut(.clk(clk),.rst(rst),.init_rst(cold),.cyc(cyc),.stb(stb),.we(we),.adr(adr),.din(din),.sel(sel),.commit(commit),.sim_present(PRESENT!=0),
 .cfg_lcd(1'b1),.cfg_keypad(1'b1),.cfg_clocks(1'b1),.dma_irq_pending(1'b0),.sim_fiq_pending(1'b0),.cpu_ack(1'b0),.cpu_err(1'b0),.cpu_rdata(32'b0),
 .init_done(init),.claim(claim),.ready(ready),.unmodeled(bad),.dout(dout),.fiq(fiq));
initial begin
 f=$fopen("build/sim/unit-simif-reference/reference.tsv","r");if(!f)begin $display("FAIL no fixture");$finish;end
 repeat(2)@(negedge clk);cold=0;wait(init);@(negedge clk);rst=0;
 while(!$feof(f))begin
  rc=$fscanf(f,"%h %h %h %h %h %h %h\n",a,d,ss,w,ok,expected,pending);
  if(rc==7)begin
   line=line+1;@(negedge clk);adr=a;din=d;sel=ss;we=w;cyc=1;stb=1;commit=0;
   #1;while(!ready)begin @(negedge clk);#1;end
   // Keep a request stalled for two clocks; accepted read side effects occur once.
   repeat(2)@(negedge clk);
   #1;if(!claim || bad!==!ok || (ok && !w && dout!==expected))begin
    $display("FAIL line %0d addr %h sel %h write %h ok %h data %h expected %h bad %b claim %b",line,a,ss,w,ok,dout,expected,bad,claim);$finish;end
   if(ok)begin commit=1;@(negedge clk);end
   cyc=0;stb=0;commit=0;#1;
   if(dut.upp.peripherals.simif_irq!==pending[0])begin $display("FAIL pending line %0d got %b expected %b",line,dut.upp.peripherals.simif_irq,pending[0]);$finish;end
  end
 end
 $display("PASS SIMIF C++ comparison present=%0d operations=%0d",PRESENT,line);$finish;
end
endmodule
