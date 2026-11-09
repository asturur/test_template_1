`timescale 1ns/1ps
module clock_case #(parameter integer HZ=104000000)(input wire clk,reset,output reg done=0);
 localparam PIX=HZ/6500000, SIM=HZ/3250000, FAST=(HZ+16384)/32768;
 localparam REFRESH=(64'd6800*HZ)/104000000;
 wire ce,rfsh;
 ngage_board #(.SYS_CLK_HZ(HZ),.LCD_ENABLE(1),.SIMIF_ENABLE(1)) dut(
  .clk(clk),.rst(reset),.init_rst(reset),.cyc(1'b0),.stb(1'b0),.we(1'b0),.commit(1'b0),
  .adr(32'b0),.din(32'b0),.sel(4'hf),.keys(27'b0),.sim_present(1'b0),
  .diagnostic_video(1'b1),.diagnostic_status(8'b0),.save_state(3'b0),
  .cfg_lcd(1'b1),.cfg_keypad(1'b1),.cfg_clocks(1'b1),.dma_irq_pending(1'b0),.sim_fiq_pending(1'b0),
  .cpu_ack(1'b0),.cpu_err(1'b0),.cpu_rdata(32'b0),.dma_mem_ack(1'b0),.dma_mem_data(32'b0),.video_ce(ce));
 ngage_sdram_adapter #(.RAM_BYTES(32),.REFRESH_PERIOD(REFRESH)) refresh_check(
  .clk(clk),.rst(reset),.phone_reset(1'b1),.init(1'b0),.req(1'b0),.we(1'b0),
  .addr(25'b0),.din(32'b0),.be(4'b0),.ba_ack(4'b0),.ba_rdy(4'b0),.ba_dout(16'b0),.rfsh(rfsh));
 integer cycles=0,last_pixel=-1,last_sim=-1,last_refresh=-1,pixels=0,sim_ticks=0,refreshes=0;
 always @(posedge clk)if(!reset)begin
  cycles++;
  if(ce)begin
   if(last_pixel>=0 && cycles-last_pixel!=PIX)$fatal(1,"pixel interval HZ=%0d",HZ);
   last_pixel=cycles;pixels++;
  end
  if(dut.test_card.card.cen)begin
   if(last_sim>=0 && cycles-last_sim!=SIM)$fatal(1,"SIM interval HZ=%0d",HZ);
   last_sim=cycles;sim_ticks++;
  end
  if(rfsh)begin
   if(last_refresh>=0 && cycles-last_refresh!=REFRESH)$fatal(1,"refresh interval HZ=%0d",HZ);
   last_refresh=cycles;refreshes++;
  end
 end
 initial begin
  wait(!reset);repeat(312000)@(negedge clk);
  if(dut.upp.peripherals.nos_timer.counter!==312000/(HZ/1000) ||
     dut.upp.peripherals.nos_timer.fast_counter!==312000/FAST ||
     dut.upp.peripherals.fcnt!==312000/FAST)$fatal(1,"NOS/fcnt rate HZ=%0d",HZ);
  if(dut.uem.cbus.SECOND_TICKS!=HZ || dut.uem.cbus.ALARM_TICKS!=(64'd7995392*HZ)/104000000 ||
     dut.uem.cbus.ALARM_INTERVAL!=(64'd65536*HZ)/104000000)$fatal(1,"UEM wall-time parameters");
  if(dut.display.lcd.PIXEL_DIV!=PIX || dut.test_card.card.CLOCK_DIV!=SIM ||
     dut.upp.peripherals.timers.BOOT_DELAY!=18200000 || dut.upp.peripherals.timers.UNIT60_DELAY!=128)
   $fatal(1,"clock propagation or unresolved timer cycle contract changed");
  if(pixels<19000 || sim_ticks<9000 || refreshes<40)$fatal(1,"missing clock events");
  $display("PASS clock rates HZ=%0d pixel_div=%0d SIM_div=%0d NOS_div=%0d fast_div=%0d refresh=%0d",HZ,PIX,SIM,HZ/1000,FAST,REFRESH);
  done=1;
 end
endmodule
module tb;
 reg clk=0,reset=1;always #5 clk=~clk;
 wire a,b;
 clock_case #(104000000) reference_rate(clk,reset,a);
 clock_case #(78000000) hardware_rate(clk,reset,b);
 initial begin repeat(4)@(negedge clk);reset=0;wait(a&&b);$finish;end
 initial begin #4000000;$fatal(1,"clock-rate timeout");end
endmodule
