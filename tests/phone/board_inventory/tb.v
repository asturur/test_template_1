`timescale 1ns/1ps
module tb;
 reg clk=0,rst=1,cold=1,cyc=0,stb=0;reg [31:0] addr=0;reg [8*80-1:0] device;
 wire claim,ready,bad,irq,fiq,init;wire [31:0] dout;integer f,rc,count=0,missing=0;
 always #5 clk=~clk;
 ngage_board dut(.clk(clk),.rst(rst),.init_rst(cold),.cyc(cyc),.stb(stb),.we(1'b0),.adr(addr),.din(32'b0),.sel(4'hf),.commit(1'b0),
  .cfg_lcd(1'b1),.cfg_keypad(1'b1),.cfg_clocks(1'b1),.dma_irq_pending(1'b0),.sim_fiq_pending(1'b0),.dma_irq_clear(),
  .claim(claim),.ready(ready),.unmodeled(bad),.dout(dout),.irq(irq),.fiq(fiq),.init_done(init),.trace_valid(),.trace_addr(),.trace_data(),.trace_sel());
 initial begin
  f=$fopen("tests/phone/board_inventory/addresses.tsv","r");if(!f)begin $display("FAIL inventory missing");$finish;end
  repeat(2)@(negedge clk);cold=0;wait(init);@(negedge clk);rst=0;
  // Decoder audit only: exercise late-boot ICU address ownership. No
  // firmware execution or checkpoint is altered by this test setting.
  force dut.timers.period=1;
  cyc=1;stb=1;
  while(!$feof(f))begin
   rc=$fscanf(f,"%h %s\n",addr,device);if(rc==2)begin #1;count=count+1;if(!claim)begin $display("MISSING %h %0s",addr,device);missing=missing+1;end end
  end
  release dut.timers.period;
  if(missing!=0)begin $display("FAIL %0d missing of %0d",missing,count);$finish;end
  $display("PASS ownership of %0d retained-trace device/address pairs",count);$finish;
 end
endmodule
