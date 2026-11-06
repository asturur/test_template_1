`timescale 1ns/1ps
module tb;
reg clk=0,rst=1,cold=1,cyc=0,stb=0,we=0,commit=0;
reg [31:0] addr=0,din=0;reg [3:0] sel=0;
wire claim,ready,bad,irq,fiq,init;wire [31:0] dout;
integer f,rc,line,write_flag,expected_ok;reg [31:0] expected_data;
always #5 clk=~clk;
ngage_board dut(.clk(clk),.rst(rst),.init_rst(cold),.cyc(cyc),.stb(stb),.we(we),.adr(addr),.din(din),.sel(sel),.commit(commit),.cfg_lcd(1'b1),.cfg_keypad(1'b1),.cfg_clocks(1'b1),.claim(claim),.ready(ready),.unmodeled(bad),.dout(dout),.irq(irq),.fiq(fiq),.init_done(init),.trace_valid(),.trace_addr(),.trace_data(),.trace_sel());
initial begin
 f=$fopen("build/sim/unit-lcd-transport/reference.tsv","r");
 if(!f)begin $display("FAIL fixture missing");$finish;end
 repeat(2)@(negedge clk);cold=0;wait(init);@(negedge clk);rst=0;line=0;
 // A cancelled, uncommitted enable must not alter subsequent decoding.
 cyc=1;stb=1;we=1;addr=32'h0c121204;din=1;sel=15;commit=0;
 repeat(2)@(negedge clk);cyc=0;stb=0;@(negedge clk);
 cyc=1;stb=1;we=1;addr=32'h0c121200;din=32'h49200000;#1;
 if(!bad)begin $display("FAIL uncommitted enable changed LCD state");$finish;end
 cyc=0;stb=0;@(negedge clk);
 while(!$feof(f))begin
  rc=$fscanf(f,"%h %h %h %h %h %h\n",addr,din,sel,write_flag,expected_ok,expected_data);
  if(rc==6)begin
   line=line+1;cyc=1;stb=1;we=write_flag;commit=0;#1;
   if(!claim||!ready||bad===expected_ok[0])begin $display("FAIL acceptance line %0d",line);$finish;end
   if(!we && expected_ok && dout!==expected_data)begin $display("FAIL data line %0d",line);$finish;end
   // An arbitrary stall must not perform a write.
   repeat(2)@(negedge clk);
   commit=expected_ok;@(negedge clk);cyc=0;stb=0;commit=0;
  end
 end
 $display("PASS LCD transport ordering and stalls against C++");$finish;
end
endmodule
