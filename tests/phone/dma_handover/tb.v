`timescale 1ns/1ps
module tb;
 parameter integer TIMER_CLK_DIV=1,NOS_TICK_HZ=1000;
 reg clk=0,reset=1,cold=1,cpu_hold=0;
 wire dma_reset;
 reg reset_retry=0,reset_released=0,discard=0;
 integer held_pixels=0;always #5 clk=~clk;
 wire init_done,bus_lock;wire [24:0] csa,dsa;wire [31:0] csd,csread,dsread;wire [3:0] csb;wire cswe,csreq,csack,dsreq,dsack;
 wire [24:0] sa;wire [31:0] sd;wire [3:0] sb;wire swe,sreq;
 reg [31:0] sr=0;reg sack=0;reg [2:0] swait=0;reg spending=0;reg [24:0] saved_sa;reg [31:0] saved_sd;reg [3:0] saved_sb;reg saved_swe;
 wire [31:0] da,dd;wire dr,dw;wire [3:0] db;reg [31:0] rd=0;reg rdy=0;reg [3:0] delay_count=0;reg [31:0] saved_da;wire accept=(dr||dw) && delay_count==0 && !rdy;
 wire dirty,busy;wire [13:0] sector;wire ce,hs,vs,hb,vb;wire [11:0] rgb;
 reg [31:0] rom[0:2047],ram[0:32767];integer i,j,cycles=0;integer dd_reads=0;
 reg [26:0] test_keys=0;
 wire cpu_ram_accept;
 reg [1:0] request_phase=0;
 wire dma_cmd_valid,dma_cmd_write;
 wire [31:0] dma_cmd_addr,dma_cmd_data;
 wire [3:0] dma_cmd_be;
 wire dma_cmd_ready,dma_rsp_valid,dma_rsp_error;
 wire [31:0] dma_rsp_data;
 wire local_waiting,local_valid,local_ready,local_write,local_done,local_error;
 wire [31:0] local_addr,local_data,local_rdata;
 wire [3:0] local_be;
 wire fast_req,fast_accept,fast_ack,merge_req,merge_write,merge_ack,merge_accept;
 wire [24:0] fast_addr,merge_addr;
 wire [31:0] fast_data,merge_data,merge_rdata;
 wire [3:0] merge_be;
 wire dswe; wire [31:0] dsd; wire [3:0] dsb;
 reg held_once=0;
 integer lcd_dma_words=0,frame_words=0,phase=0,prefix_words=0,frame_start=0;
 reg [23:0] full_pixels[0:18303];
 function [31:0] full_word;
  input integer index;
  begin full_word = ((index & 4095) << 16) | ((index + 173) & 4095); end
 endfunction
 function [31:0] band_word;
  input integer index;
  begin band_word = (((index + 2222) & 4095) << 16) | ((index + 555) & 4095); end
 endfunction
 ngage_dma_route route (
  .clk(clk),.reset(dma_reset),.cpu_lock(bus_lock),.cmd_valid(dma_cmd_valid),.cmd_ready(dma_cmd_ready),
  .cmd_write(dma_cmd_write),.cmd_addr(dma_cmd_addr),.cmd_data(dma_cmd_data),.cmd_be(dma_cmd_be),
  .rsp_valid(dma_rsp_valid),.rsp_error(dma_rsp_error),.rsp_data(dma_rsp_data),
  .ram_req(dsreq),.ram_write(dswe),.ram_addr(dsa),.ram_data(dsd),.ram_be(dsb),.ram_ack(dsack),.ram_rdata(dsread),
  .local_valid(local_valid),.local_waiting(local_waiting),.local_ready(local_ready),.local_write(local_write),.local_addr(local_addr),
  .local_data(local_data),.local_be(local_be),.local_done(local_done),.local_error(local_error),.local_rdata(local_rdata)
 );
 ngage_mister #(.TIMER_CLK_DIV(TIMER_CLK_DIV),.NOS_TICK_HZ(NOS_TICK_HZ),.DMA_LOCAL(1)) dut(
  .mmc_card_reset(1'b0),.mmc_img_mounted(1'b0),.mmc_img_readonly(1'b1),.mmc_img_size(64'd0),
  .mmc_sd_ack(1'b0),.mmc_sd_buff_addr(13'd0),.mmc_sd_buff_dout(16'd0),.mmc_sd_buff_wr(1'b0),
.debug_freeze_trace(1'b0),.sim_present(1'b1),.clk_sys(clk),.reset(reset || cpu_hold),.cold_reset(cold),.dma_reset(dma_reset),.board_init_done(init_done),.bus_lock(bus_lock),
  .sdram_addr(csa),.sdram_din(csd),.sdram_dout(csread),.sdram_be(csb),.sdram_we(cswe),.sdram_req(csreq),.sdram_ack(csack),.sdram_accept(cpu_ram_accept),
  .dma_sdram_req(fast_req),.dma_sdram_addr(fast_addr),.dma_sdram_accept(fast_accept),.dma_sdram_ack(fast_ack),.dma_sdram_data(fast_data),
  .dma_cmd_valid(dma_cmd_valid),.dma_cmd_ready(dma_cmd_ready),.dma_cmd_write(dma_cmd_write),
  .dma_cmd_addr(dma_cmd_addr),.dma_cmd_data(dma_cmd_data),.dma_cmd_be(dma_cmd_be),
  .dma_rsp_valid(dma_rsp_valid),.dma_rsp_error(dma_rsp_error),.dma_rsp_data(dma_rsp_data),
  .dma_local_valid(local_valid),.dma_local_waiting(local_waiting),.dma_local_ready(local_ready),.dma_local_write(local_write),
  .dma_local_addr(local_addr),.dma_local_data(local_data),.dma_local_be(local_be),
  .dma_local_done(local_done),.dma_local_error(local_error),.dma_local_rdata(local_rdata),
  .ddram_addr(da),.ddram_rd(dr),.ddram_wr(dw),.ddram_din(dd),.ddram_be(db),.ddram_dout(rd),.ddram_dout_ready(rdy),.ddram_accept(accept),
  .flash_dirty(dirty),.flash_dirty_sector(sector),.flash_busy(busy),.ce_pix(ce),.hsync(hs),.vsync(vs),.hblank(hb),.vblank(vb),.rgb444(rgb),.keys(test_keys));
 ngage_dma_ram_mux dma_merge(.clk(clk),.reset(dma_reset),
 .dma_req(dsreq),.dma_write(dswe),.dma_addr(dsa),.dma_data(dsd),.dma_be(dsb),.dma_ack(dsack),.dma_rdata(dsread),
 .lcd_req(fast_req),.lcd_addr(fast_addr),.lcd_accept(fast_accept),.lcd_ack(fast_ack),.lcd_rdata(fast_data),
 .mem_req(merge_req),.mem_write(merge_write),.mem_addr(merge_addr),.mem_data(merge_data),.mem_be(merge_be),.mem_accept(merge_accept),.mem_ack(merge_ack),.mem_rdata(merge_rdata));
 ngage_sdram_arbiter arb(.cpu_accept(cpu_ram_accept),.clk(clk),.reset(dma_reset),.cpu_lock(bus_lock),.cpu_req(csreq),.cpu_we(cswe),.cpu_addr(csa),.cpu_data(csd),.cpu_be(csb),.cpu_ack(csack),.cpu_rdata(csread),
 .dma_accept(merge_accept),.dma_req(merge_req),.dma_we(merge_write),.dma_addr(merge_addr),.dma_data(merge_data),.dma_be(merge_be),.dma_ack(merge_ack),.dma_rdata(merge_rdata),
 .mem_req(sreq),.mem_we(swe),.mem_addr(sa),.mem_data(sd),.mem_be(sb),.mem_ack(sack),.mem_rdata(sr));
 always @(posedge clk)begin
  if(!reset && dut.board.lcd_dma_retire && dut.board.lcd_dma_pixel) begin
   lcd_dma_words<=lcd_dma_words+1;
   frame_words<=frame_words+1;
  end
  ram[32'h110/4] <= frame_words;
  if(!reset && phase==2 && dut.board.upp.general_dma_irq[1] && frame_words!=18304)
   $fatal(1,"DMA completion before final normal queued pixel: %0d",frame_words);
  rdy<=0;sack<=0;
  if(dma_reset && spending) discard<=1;
  if(accept)begin
   if(dw || da<32'h30000000 || da>=32'h30002000)begin $fatal(1,"FAIL unexpected DDR request %h",da);end
   saved_da<=da;delay_count<=4;dd_reads<=dd_reads+1;
  end else if(delay_count!=0)begin
   delay_count<=delay_count-1'b1;
   if(delay_count==1)begin rd<=rom[(saved_da-32'h30000000)>>2];rdy<=1;end
  end
  if(sreq && !spending && !sack)begin
   saved_sa<=sa;saved_sd<=sd;saved_sb<=sb;saved_swe<=swe;spending<=1;swait<=3;
  end else if(spending)begin
   if(swait!=0)swait<=swait-1'b1;
   else begin
    spending<=0;sack<=!discard&&!dma_reset;discard<=0;
    if(saved_sa>=131072)begin $fatal(1,"FAIL SDRAM address %h",saved_sa);end
    if(saved_swe)begin
     for(i=0;i<4;i=i+1)if(saved_sb[i])ram[saved_sa[16:2]][i*8+:8]<=saved_sd[i*8+:8];
     if(saved_sa==25'h100)begin
      if(saved_sd==32'hdeadbeef)$fatal(1,"ARM program reported failure pc=%h phase=%0d",dut.cpu_pc,phase);
      if(saved_sd==1)begin
       for(i=0;i<8;i=i+1)begin
        for(j=0;j<4;j=j+1)
         if(ram[(32'h4000+32*i)/4+j]!==ram[(32'h2000+32*i)/4+j])$fatal(1,"CPU-programmed memory copy channel %0d word %0d",i,j);
        if(ram[(32'h4010+32*i)/4]!==0)$fatal(1,"CPU-programmed halfword-count guard channel %0d",i);
       end
       if(dut.board.upp.general_dma_irq!==0)$fatal(1,"selective ACK incomplete");
       if(reset_retry && reset_released)begin
        if(frame_words!=held_pixels)$fatal(1,"logical reset leaked stale LCD tail");
        $display("PASS CPU Hold logical reset cancels DMA route/mux/accepted RAM tail; restarted CPU programs fresh eight-channel transfers");$finish;
       end
       phase<=1;
      end
      if(saved_sd==11)begin
       if(!dut.board.upp.general_dma_irq[2] || ram[32'h4800/4]!==ram[32'h2000/4] || ram[32'h480c/4]!==ram[32'h200c/4])
        $fatal(1,"peer DMA failed during paced LCD");
       if($test$plusargs("hold"))begin
        if(!held_once || !dut.board.upp.dma_active[1] || frame_words!=0 || dut.board.upp.general_dma_irq[1])$fatal(1,"held LCD blocked CPU/peer progress or completed early");
        force dut.board.display.command_queue.hold = 1'b0;
       end
      end
      if(saved_sd==2)begin
       prefix_words=frame_words;
       if(prefix_words<32 || prefix_words>=18304 || dut.board.upp.general_dma_irq[1])$fatal(1,"stop did not drain silently");
       phase<=2;frame_words<=0;frame_start<=cycles;
      end
      if(saved_sd==3)begin
       if(frame_words!=18304 || !dut.board.upp.general_dma_irq[1] || dut.board.display.lcd.cursor!=18303 || !dut.board.display.lcd.frame_complete)
        $fatal(1,"full LCD completion/count %0d",frame_words);
       for(i=0;i<18304;i=i+1)begin
        full_pixels[i]=(full_word(i) & 32'h00000fff) | ((full_word(i) >> 4) & 32'h00fff000);
        if(dut.board.display.lcd.framebuffer.memory[i]!==full_pixels[i])$fatal(1,"full pixel %0d",i);
       end
       $display("METRIC production full-frame interval clocks=%0d words=18304 clocks-per-word=%0f",cycles-frame_start,$itor(cycles-frame_start)/18304.0);
       phase<=3;frame_words<=0;
      end
      if(saved_sd==4)begin
       if(frame_words!=616 || !dut.board.upp.general_dma_irq[1] || dut.board.display.lcd.frame_complete)$fatal(1,"row band count/completion");
       for(i=0;i<18304;i=i+1)begin
        if(i>=264 && i<880)begin
         if(dut.board.display.lcd.framebuffer.memory[i]!==((band_word(i-264) & 32'h00000fff) | ((band_word(i-264) >> 4) & 32'h00fff000)))$fatal(1,"row pixel %0d",i);
        end else if(dut.board.display.lcd.framebuffer.memory[i]!==full_pixels[i])$fatal(1,"row band touched sentinel %0d",i);
       end
       phase<=4;frame_words<=0;
      end
      if(saved_sd==5 || saved_sd==6)begin
       if(frame_words!=0 || dut.board.upp.general_dma_irq[1] || !dut.board.upp.dma_errors[1])$fatal(1,"invalid endpoint falsely succeeded");
       phase<=saved_sd;
      end
      if(saved_sd==7)begin
       if(frame_words!=1 || !dut.board.upp.general_dma_irq[4] || dut.board.display.lcd.framebuffer.memory[0]!==24'h123abc)
        $fatal(1,"general on-chip LCD fallback");
       phase<=7;frame_words<=0;
      end
      if(saved_sd==8 || saved_sd==9)begin
       if(frame_words || dut.board.upp.general_dma_irq[4] || !dut.board.upp.dma_errors[4])$fatal(1,"unsupported request or unpaced FIFO bypass");
       phase<=saved_sd;
      end
      if(saved_sd==10)begin
       if(frame_words==0 || frame_words>=18304 || dut.board.upp.general_dma_irq[4] || !dut.board.upp.dma_errors[4])$fatal(1,"midstream transport reset falsely completed words=%0d",frame_words);
       phase<=10;
      end
      if(saved_sd==32'h50415353)begin
       if(phase!=10 || dut.board.upp.general_dma_irq!==0)$fatal(1,"unfinished phases");
       $display("PASS production DMA CPU copy/all eight IRQs/selective ACK/mask preservation; full 18304-word normal FIFO frame; row-band packing/sentinels; CPU interleave; stop/restart prefix=%0d; invalid LCD/MMC errors in %0d cycles",prefix_words,cycles);$finish;
      end
     end
    end else sr<=ram[saved_sa[16:2]];
   end
  end
  if(!reset)begin cycles<=cycles+1;if(cycles>3000000)begin $fatal(1,"FAIL ARM timeout");end end
 end
 initial begin
  if($test$plusargs("hold-reset"))begin
   wait(phase==1);
   wait(fast_accept);
   @(posedge clk);@(negedge clk);
   held_pixels=frame_words;
   cpu_hold=1;reset_retry=1;
   repeat(12)@(negedge clk);
   if(!dma_reset || dut.board.upp.general_dma_irq!==0 || dut.board.upp.dma_active!==0 || route.state!=0 || dma_merge.owned || arb.state!=0 || local_done || dma_rsp_valid)
    $fatal(1,"CPU Hold failed shared logical cancellation boundary");
   reset_released=1;cpu_hold=0;
  end
 end
 initial begin
  if($test$plusargs("hold") || $test$plusargs("reset-tail"))begin
   wait(phase==1);
   @(negedge clk);
   while(!(dut.board.display.queued_valid && dut.board.display.queued_dma))@(negedge clk);
   if($test$plusargs("hold"))begin
    force dut.board.display.command_queue.hold = 1'b1;
    held_once=1;
   end else begin
    reset=1;
    repeat(20)@(negedge clk);
    if(frame_words!=0 || dut.board.upp.general_dma_irq!==0 || dut.board.upp.dma_active!==0 || local_done || dma_rsp_valid || dut.board.display.queued_valid)
     $fatal(1,"reset leaked queued pixel or completion");
    $display("PASS production DMA reset cancels accepted queued LCD tail, channel and route completion");$finish;
   end
  end
 end
 initial begin
  for(i=0;i<2048;i=i+1)rom[i]=0;
  for(i=0;i<32768;i=i+1)ram[i]=0;
  for(i=0;i<18304;i=i+1)ram[32'h8000/4+i]=full_word(i);
  for(i=0;i<616;i=i+1)ram[32'h800/4+i]=band_word(i);
  for(i=0;i<64;i=i+1)ram[32'h2000/4+i]=32'h76543210+i;
  $readmemh("build/sim/unit-dma-handover/program.hex",rom);
  repeat(4)@(negedge clk);cold=0;wait(init_done);repeat(2)@(negedge clk);reset=0;
 end

endmodule
