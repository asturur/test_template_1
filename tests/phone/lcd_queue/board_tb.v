`timescale 1ns/1ps
module tb;
 reg clk=0,rst=1,cold=1,cyc=0,stb=0,we=0;
 reg [31:0] addr=0,data=0;reg [3:0] sel=15;
 wire claim,ready,bad,init;wire [31:0] dout;
 integer commands=0,headers=0;
 always #5 clk=~clk;
 ngage_board #(.LCD_ENABLE(1)) dut(.clk(clk),.rst(rst),.init_rst(cold),
  .cyc(cyc),.stb(stb),.adr(addr),.we(we),.din(data),.sel(sel),.commit(cyc&&stb),
  .cfg_lcd(1'b1),.cfg_keypad(1'b1),.cfg_clocks(1'b1),.keys(27'b0),
  .dma_irq_pending(1'b0),.sim_fiq_pending(1'b0),.diagnostic_video(1'b0),
  .diagnostic_status(8'b0),.save_state(3'b0),.claim(claim),.ready(ready),
  .unmodeled(bad),.dout(dout),.init_done(init));
 always @(posedge clk)if(!rst && dut.display.queued_valid)begin
  commands=commands+1;
  if(dut.display.queued_addr==32'h0c121200)headers=headers+1;
 end
 task tick;begin @(negedge clk);#1;end endtask
 task start_write;input [31:0] a,d;begin addr=a;data=d;we=1;cyc=1;stb=1;#1;end endtask
 task finish_write;integer waited;begin
  waited=0;while(!ready)begin tick();waited=waited+1;if(waited>20)$fatal(1,"LCD write wait");end
  if(bad || !claim)$fatal(1,"valid write rejected");tick();cyc=0;stb=0;we=0;#1;
 end endtask
 initial begin
  repeat(2)tick();cold=0;wait(init);tick();rst=0;
  // Test-only consumer hold exercises selected-device backpressure; raw DMA
  // injection below checks relative ordering through the production stages.
  force dut.display.command_queue.hold=1'b1;
  start_write('h0c121204,1);finish_write();
  if(!dut.display.command_queue.pending)$fatal(1,"control was not queued");
  start_write('h0c121200,'h09200000);
  repeat(4)begin tick();if(ready || dut.upp.peripherals.hdr_written)$fatal(1,"blocked header mutated transport");end
  // Withdraw the unaccepted header; a full LCD queue must not stall upload RAM.
  cyc=0;stb=0;tick();start_write('h0c030220,'h12345678);
  if(!ready)$fatal(1,"LCD queue stalled unrelated RAM");finish_write();tick();
  start_write('h0c121200,'h09200000);if(ready)$fatal(1,"full queue accepted header");
  release dut.display.command_queue.hold;#1;finish_write();tick();
  if(headers!=1 || dut.display.lcd.header!=='h09200000)$fatal(1,"header lost or duplicated");
  start_write('h0c121208,'haf);finish_write();
  force dut.lcd_dma_valid=1'b1;addr='h0c030220;data='hdeadbeef;
  tick();
  if(!dut.display.lcd.display_on || commands!=3)$fatal(1,"later DMA overtook accepted command");
  repeat(4)tick();release dut.lcd_dma_valid;tick();
  start_write('h0c121200,'hdeadbeef);#1;
  if(!bad || dut.lcd_write_valid)$fatal(1,"invalid header queued");tick();cyc=0;stb=0;tick();
  if(headers!=1 || dut.display.lcd.header!=='h09200000)$fatal(1,"invalid header changed panel");
  force dut.display.command_queue.hold=1'b1;start_write('h0c121200,'h4f300000);finish_write();
  rst=1;tick();release dut.display.command_queue.hold;rst=0;repeat(3)tick();
  if(dut.display.command_queue.pending || dut.display.lcd.header!==0 || headers!=1)$fatal(1,"warm reset leaked queued command");
  $display("PASS board LCD queue: selected backpressure, unrelated RAM, exactly-once ordered commands, local faults, DMA and reset");$finish;
 end
endmodule
