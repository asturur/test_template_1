`timescale 1ns/1ps
module tb;
 reg clk=0,rst=1,cold=1,cyc=0,stb=0;reg [31:0] addr=0;reg write_op=0,keypad=1;reg [3:0] lanes=15;integer region,offset,mode;reg [31:0] base;reg [8*80-1:0] device;
 wire claim,ready,bad,irq,fiq,init;wire [31:0] dout;integer f,rc,count=0,missing=0;
 always #5 clk=~clk;
 ngage_board #(.SIMIF_ENABLE(1)) dut(.clk(clk),.rst(rst),.init_rst(cold),.cyc(cyc),.stb(stb),.we(write_op),.adr(addr),.din(32'b0),.sel(lanes),.commit(1'b0),
  .cfg_lcd(1'b1),.cfg_keypad(keypad),.cfg_clocks(1'b1),.dma_irq_pending(1'b0),.sim_fiq_pending(1'b0),.dma_irq_clear(),
  .claim(claim),.ready(ready),.unmodeled(bad),.dout(dout),.irq(irq),.fiq(fiq),.init_done(init),.trace_valid(),.trace_addr(),.trace_data(),.trace_sel());
 wire legacy_claim = dut.upp.peripherals.uart_claim || dut.upp.peripherals.simif_claim || dut.upp.peripherals.extra_claim ||
  dut.upp.peripherals.gpio_loop_claim || dut.upp.peripherals.mdi_claim || dut.upp.peripherals.trace_claim ||
  dut.upp.peripherals.boot_claim || dut.upp.peripherals.icu_claim || dut.upp.peripherals.timer_claim ||
  dut.upp.peripherals.nos_claim || dut.upp.peripherals.cbus_claim;
 task check;
 begin
  #1;
  if(dut.upp.peripherals.gpio_selected !== (dut.upp.peripherals.gpio_hit && !legacy_claim))
   $fatal(1,"regional ownership differs address=%h we=%b lanes=%h",addr,write_op,lanes);
  if(dut.upp.peripherals.nos4k_ram !== (dut.upp.peripherals.nos4k_hit && addr[31:12]==20'h0c004 && !legacy_claim))
   $fatal(1,"scratch ownership differs address=%h",addr);
 end
 endtask
 initial begin
  repeat(2)@(negedge clk);cold=0;wait(init);@(negedge clk);rst=0;
  force dut.upp.peripherals.periodic_active=1;
  cyc=1;stb=1;
  for(region=0;region<8;region=region+1)begin
   case(region)
    0:base=32'h0c000000;1:base=32'h0c030000;2:base=32'h0c060000;3:base=32'h0c100000;
    4:base=32'h0c120000;5:base=32'h0c140000;6:base=32'h0c150000;7:base=32'h0d000000;
   endcase
   for(offset=0;offset<65536;offset=offset+4)begin addr=base+offset;check;end
  end
  // All lane/read/write/config combinations at actual GPIO/MDI/scratch overlaps.
  for(mode=0;mode<64;mode=mode+1)begin
   keypad=mode[5];write_op=mode[4];lanes=mode[3:0];
   addr=32'h0c150800;check;addr=32'h0c1500b8;check;addr=32'h0c150008;check;
   addr=32'h0c150420;check;addr=32'h0c150110;check;addr=32'h0c150204;check;
   addr=32'h0c1003e8;check;addr=32'h0c14b004;check;addr=32'h0c120034;check;
   addr=32'h0c004748;check;addr=32'h0c0047f8;check;addr=32'h0c0047fc;check;
   addr=32'h0c030220;check;addr=32'h0c06ff00;check;
  end
  $display("PASS regional ownership: exhaustive windows and overlap/lane/config cases");$finish;
 end
endmodule
