`timescale 1ns/1ps
module tb;
parameter PRESENT=1;
parameter TEST_CARD=1;
reg clk=0,rst=1,cold=1,cyc=0,stb=0,we=0,commit=0,present=PRESENT;
reg [31:0] adr=0,din=0;reg [3:0] sel=3;
wire claim,ready,bad,fiq,init;wire [31:0] dout;
always #5 clk=~clk;
ngage_board #(.SIMIF_ENABLE(1),.TEST_SIM_ENABLE(TEST_CARD)) dut(.clk(clk),.rst(rst),.init_rst(cold),.cyc(cyc),.stb(stb),.we(we),.adr(adr),.din(din),.sel(sel),.commit(commit),.sim_present(present),
 .cfg_lcd(1'b1),.cfg_keypad(1'b1),.cfg_clocks(1'b1),.dma_irq_pending(1'b0),.sim_fiq_pending(1'b0),.cpu_ack(1'b0),.cpu_err(1'b0),.cpu_rdata(32'b0),
 .init_done(init),.claim(claim),.ready(ready),.unmodeled(bad),.dout(dout),.fiq(fiq));
task access;input [31:0] a,d;input w;input [31:0] expect;begin
 @(negedge clk);adr=a;din=d;we=w;cyc=1;stb=1;commit=0;
 #1;while(!ready)begin @(negedge clk);#1;end
 #1;if(!claim || bad || (!w && dout!==expect))begin $display("FAIL %h got %h expected %h claim %b bad %b",a,dout,expect,claim,bad);$finish;end
 commit=1;@(negedge clk);cyc=0;stb=0;commit=0;
end endtask
task wr;input [31:0] a,d;begin access(a,d,1,0);end endtask
task rd;input [31:0] a,d;begin access(a,0,0,d);end endtask
initial begin
 repeat(2)@(negedge clk);cold=0;wait(init);@(negedge clk);rst=0;
 // Selection is sampled during reset, so an OSD change must not hot-plug.
 present=!PRESENT;
 sel=12;wr('h0c150804,32'h00790000);rd('h0c150804,32'h00410000);rd('h0c150804,32'h00410000);sel=3;
 rd('h0c1500b8,0);wr('h0c150808,1);
 if(PRESENT && TEST_CARD)begin
  rd('h0c150800,16);rd('h0c1500b8,4);
  if(fiq!==0)begin $display("FAIL masked FIQ");$finish;end
  sel=15;wr('h0c1201c8,32'h04000000);sel=3;
  if(fiq!==1)begin $display("FAIL SIM FIQ 26");$finish;end rd('h0c15080c,'h3b);rd('h0c15080c,0);
  wr('h0c150800,16);rd('h0c1500b8,0);if(fiq!==0)begin $display("FAIL cleared FIQ");$finish;end
  wr('h0c15080c,'ha0);wr('h0c15080c,'ha4);wr('h0c15080c,0);wr('h0c15080c,0);wr('h0c15080c,2);
  rd('h0c150800,8);wr('h0c150800,8);rd('h0c150800,16);rd('h0c15080c,'ha4);rd('h0c150800,0);
  wr('h0c15080c,'h3f);wr('h0c15080c,0);rd('h0c150800,8);wr('h0c150800,8);
  rd('h0c15080c,'h9f);rd('h0c15080c,'h16);rd('h0c150800,0);
 end else begin rd('h0c150800,0);rd('h0c15080c,0);rd('h0c1500b8,0);end
 $display("PASS board SIMIF present=%0d test_card=%0d",PRESENT,TEST_CARD);$finish;
end
endmodule
