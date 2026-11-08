`timescale 1ns/1ps
`define PANEL_STATE(p) {p.header,p.cursor,p.memory_write,p.display_on,p.last_command,p.window_words,p.window_first,p.row_start,p.row_end,p.col_start,p.col_end,p.frame_complete,p.incomplete,p.unsupported,p.unsupported_valid}
module tb;
 reg clk=0,rst=1,cold=1,cyc=0,we=1;
 reg [31:0] addr=0,data=0;wire init,ready,bad;
 reg dma=0,full=0;reg [14:0] da=0;reg [31:0] dd=0;
 reg previous_dma_valid=0,expected_dma_valid;
 reg [14:0] previous_dma_addr=0,expected_dma_addr;
 reg [23:0] expected_dma_pixel;
 reg [255:0] expected_state;reg [23:0] expected_pixels[0:31];
 reg [31:0] rng=32'ha3912401;integer checked=0;
 always #5 clk=~clk;
 ngage_board #(.LCD_ENABLE(1)) dut(.clk(clk),.rst(rst),.init_rst(cold),
  .cyc(cyc),.stb(cyc),.we(we),.adr(addr),.din(data),.sel(4'hf),.commit(cyc),
  .cfg_lcd(1'b1),.cfg_keypad(1'b0),.cfg_clocks(1'b0),.keys(27'b0),
  .dma_irq_pending(1'b0),.sim_fiq_pending(1'b0),.diagnostic_video(1'b0),
  .diagnostic_status(8'b0),.save_state(3'b0),.init_done(init),.ready(ready),.unmodeled(bad));
 // Same accepted CPU packet and raw DMA stream, without the new stages.
 ngage_lcd_display reference(.clk(clk),.reset(rst),.diagnostic(1'b0),
  .status(8'b0),.save_state(3'b0),.write_valid(dut.lcd_write_valid),
  .write_addr(dut.aligned_addr),.write_data(dut.bus_din),
  .dma_valid(dma),.dma_frame_full(full),.dma_word_addr(da),.dma_data(dd));
 always @(posedge clk)begin
  expected_state=`PANEL_STATE(reference);
  expected_dma_valid=previous_dma_valid;expected_dma_addr=previous_dma_addr;
  expected_dma_pixel=reference.framebuffer.memory[expected_dma_addr];
  previous_dma_valid=!rst && dma;previous_dma_addr=da;
  for(integer i=0;i<32;i=i+1)expected_pixels[i]=reference.framebuffer.memory[i];
  if(!rst)begin
   #1;
   if(`PANEL_STATE(dut.display.lcd)!==expected_state)$fatal(1,"CPU/DMA panel state reordered at check %0d",checked);
   for(integer i=0;i<32;i=i+1)
    if(dut.display.lcd.framebuffer.memory[i]!==expected_pixels[i])$fatal(1,"CPU/DMA pixel order changed at %0d, pixel %0d",checked,i);
   if(expected_dma_valid && dut.display.lcd.framebuffer.memory[expected_dma_addr]!==expected_dma_pixel)
    $fatal(1,"DMA payload/address skew at word %0d",expected_dma_addr);
   checked=checked+1;
  end
 end
 task tick;begin @(negedge clk);#1;end endtask
 task packet;input [31:0] a,d;begin addr=a;data=d;cyc=1;#1;if(!ready || bad)$fatal(1,"invalid test packet");tick();cyc=0;end endtask
 initial begin
  force dut.lcd_dma_valid=dma;force dut.lcd_dma_full=full;
  force dut.lcd_dma_addr=da;force dut.lcd_dma_data=dd;
  repeat(2)tick();cold=0;wait(init);tick();rst=0;
  packet('h0c121204,1);packet('h0c121200,'h09200000);packet('h0c121208,'h5c);
  packet('h0c121200,'h8924d67f);packet('h0c121208,'h01230abc);
  // A later DMA pixel targeting the same word must remain later.
  dma=1;da=0;dd='h0def0456;tick();dma=0;
  packet('h0c121208,'h02340bcd);dma=1;da=1;dd='h05670789;tick();
  // Headers may share an original edge with DMA; data writes may not.
  packet('h0c121200,'h09200000);dma=0;packet('h0c121208,'haf);
  for(integer n=0;n<400;n=n+1)begin
   rng=rng^(rng<<13);rng=rng^(rng>>17);rng=rng^(rng<<5);
   if(n%113==112)begin
    // Reset is permitted to cancel pending commands. Drain first when
    // comparing against a reference that has no pending stage; cancellation
    // itself is covered by the queue/board reset tests.
    cyc=0;dma=0;full=0;repeat(2)tick();rst=1;tick();rst=0;
    packet('h0c121204,1);
   end else begin
    dma=rng[0];full=rng[4:1]==15;da=rng[14:0]%18304;dd=rng;
    if(rng[5])begin cyc=1;addr='h0c121200;data=rng[6]?'h09200000:'h8924d67f;end
    else if(!dma)begin cyc=1;addr='h0c121208;data=rng[6]?'h5c:'haf;end
    else cyc=0;
    tick();
   end
  end
  cyc=0;dma=0;full=0;repeat(3)tick();
  if(checked<400)$fatal(1,"mixed stream not checked");
  $display("PASS queued CPU/DMA streams match original panel state and pixels with exactly one-cycle latency (%0d checks)",checked);$finish;
 end
endmodule
