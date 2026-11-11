`timescale 1ns/1ps
module tb;
 parameter integer TIMER_CLK_DIV=1,NOS_TICK_HZ=1000;
 reg clk=0,reset=1,cold=1,cpu_hold=0;
 wire dma_reset;
 reg discard=0;
 always #5 clk=~clk;
 wire init_done,bus_lock;wire [24:0] csa,dsa;wire [31:0] csd,csread,dsread;wire [3:0] csb;wire cswe,csreq,csack,dsreq,dsack;
 wire [24:0] sa;wire [31:0] sd;wire [3:0] sb;wire swe,sreq;
 reg [31:0] sr=0;reg sack=0;reg [2:0] swait=0;reg spending=0;reg [24:0] saved_sa;reg [31:0] saved_sd;reg [3:0] saved_sb;reg saved_swe;
 wire [31:0] da,dd;wire dr,dw;wire [3:0] db;reg [31:0] rd=0;reg rdy=0;reg [3:0] delay_count=0;reg [31:0] saved_da;wire accept=(dr||dw) && delay_count==0 && !rdy;
 wire dirty,busy;wire [13:0] sector;wire ce,hs,vs,hb,vb;wire [11:0] rgb;
 reg [31:0] rom[0:2047],ram[0:32767];integer i,j,cycles=0;integer dd_reads=0;
 reg [26:0] test_keys=0;
 wire cpu_ram_accept;

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
 wire mmc_card_reset,mmc_mount,mmc_ro,mmc_present,mmc_wp,mmc_active,mmc_fault,mmc_hps_busy;
 wire [63:0] mmc_size;
 wire [31:0] mmc_lba,hps_lba;wire [5:0] mmc_count,hps_count;
 wire mmc_read,mmc_write,mmc_ack,mmc_wr,hps_read,hps_write;
 wire [12:0] mmc_addr;wire [15:0] mmc_data,mmc_din,hps_din;
 reg img_mount=0;reg [63:0] img_size=2560;
 reg hps_ack=0,hps_wr=0;reg [12:0] hps_addr=0;reg [15:0] hps_data=0;
 reg [15:0] image[0:1279];
 integer hstate=0,hdelay=0,hword=0,hwords=0,hps_reads=0;
 reg [31:0] saved_lba;reg [5:0] saved_count;
 reg held_once=0;
 ngage_mmc_hps backing (
  .clk(clk),.init_reset(cold),.guest_reset(dma_reset),
  .hps_img_mounted(img_mount),.hps_img_readonly(1'b0),.hps_img_size(img_size),
  .card_reset(mmc_card_reset),.card_img_mounted(mmc_mount),.card_img_readonly(mmc_ro),.card_img_size(mmc_size),
  .card_sd_lba(mmc_lba),.card_sd_blk_cnt(mmc_count),.card_sd_rd(mmc_read),.card_sd_wr(mmc_write),.card_sd_ack(mmc_ack),
  .card_sd_buff_addr(mmc_addr),.card_sd_buff_dout(mmc_data),.card_sd_buff_din(mmc_din),.card_sd_buff_wr(mmc_wr),
  .hps_sd_lba(hps_lba),.hps_sd_blk_cnt(hps_count),.hps_sd_rd(hps_read),.hps_sd_wr(hps_write),.hps_sd_ack(hps_ack),
  .hps_buff_addr(hps_addr),.hps_buff_dout(hps_data),.hps_buff_wr(hps_wr),.hps_buff_din(hps_din),
  .busy(mmc_hps_busy),.fault(mmc_fault)
 );
 ngage_dma_route route (
  .clk(clk),.reset(dma_reset),.cpu_lock(bus_lock),.cmd_valid(dma_cmd_valid),.cmd_ready(dma_cmd_ready),
  .cmd_write(dma_cmd_write),.cmd_addr(dma_cmd_addr),.cmd_data(dma_cmd_data),.cmd_be(dma_cmd_be),
  .rsp_valid(dma_rsp_valid),.rsp_error(dma_rsp_error),.rsp_data(dma_rsp_data),
  .ram_req(dsreq),.ram_write(dswe),.ram_addr(dsa),.ram_data(dsd),.ram_be(dsb),.ram_ack(dsack),.ram_rdata(dsread),
  .local_valid(local_valid),.local_waiting(local_waiting),.local_ready(local_ready),.local_write(local_write),.local_addr(local_addr),
  .local_data(local_data),.local_be(local_be),.local_done(local_done),.local_error(local_error),.local_rdata(local_rdata)
 );
 ngage_mister #(.TIMER_CLK_DIV(TIMER_CLK_DIV),.NOS_TICK_HZ(NOS_TICK_HZ),.DMA_LOCAL(1)) dut(.debug_freeze_trace(1'b0),.sim_present(1'b1),.clk_sys(clk),.reset(reset || cpu_hold),.cold_reset(cold),.dma_reset(dma_reset),.board_init_done(init_done),.bus_lock(bus_lock),
  .mmc_card_reset(mmc_card_reset),.mmc_img_mounted(mmc_mount),.mmc_img_readonly(mmc_ro),.mmc_img_size(mmc_size),
  .mmc_sd_lba(mmc_lba),.mmc_sd_blk_cnt(mmc_count),.mmc_sd_rd(mmc_read),.mmc_sd_wr(mmc_write),.mmc_sd_ack(mmc_ack),
  .mmc_sd_buff_addr(mmc_addr),.mmc_sd_buff_dout(mmc_data),.mmc_sd_buff_din(mmc_din),.mmc_sd_buff_wr(mmc_wr),
  .mmc_present(mmc_present),.mmc_write_protected(mmc_wp),.mmc_active(mmc_active),
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
 // HPS peer follows the shared-buffer pipeline contract. The final strobe
 // accompanies ACK falling; unrelated-slot writes occur only without slot2 ACK.
 always @(posedge clk)begin
  hps_wr<=0;
  if(cold)begin hstate<=0;hps_ack<=0;end
  else begin
   if(hps_write)$fatal(1,"read-only MMC emitted HPS write");
   case(hstate)
    0:begin
     hps_addr<=13'h123;hps_data<=16'hdead;hps_wr<=1;
     if(hps_read)begin
      saved_lba<=hps_lba;saved_count<=hps_count;hwords<=(hps_count+1)*256;
      hword<=0;hdelay<=11;hstate<=1;hps_reads<=hps_reads+1;
     end
    end
    1:begin
     if(!hps_read || hps_lba!==saved_lba || hps_count!==saved_count)$fatal(1,"HPS request changed before ACK");
     if(hdelay==0)begin hps_ack<=1;hps_wr<=0;hdelay<=2;hstate<=2;end
     else hdelay<=hdelay-1;
    end
    2:begin
     if(hps_lba!==saved_lba || hps_count!==saved_count)$fatal(1,"owned HPS address changed");
     if(hdelay!=0)hdelay<=hdelay-1;
     else begin
      if(saved_lba*256+hword>=1280)$fatal(1,"HPS read beyond generated image");
      hps_addr<=hword;hps_data<=image[saved_lba*256+hword];hps_wr<=1;hdelay<=2;
      if(hword==hwords-1)begin hps_ack<=0;hstate<=3;hdelay<=5;end
      else hword<=hword+1;
     end
    end
    3:if(hdelay==0)hstate<=0;else hdelay<=hdelay-1;
   endcase
  end
 end
 always @(posedge clk)begin
  rdy<=0;sack<=0;
  if(dma_reset && spending)discard<=1;
  if(accept)begin
   if(dw || da<32'h30000000 || da>=32'h30002000)$fatal(1,"unexpected DDR request %h",da);
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
    if(saved_sa>=131072)$fatal(1,"SDRAM address %h",saved_sa);
    if(saved_swe)begin
     if(!discard && !dma_reset)begin
      for(i=0;i<4;i=i+1)if(saved_sb[i])ram[saved_sa[16:2]][i*8+:8]<=saved_sd[i*8+:8];
      if(saved_sa==25'h104)$fatal(1,"ARM MMC failure stage=%0d PC=%h",ram[32'h108/4],dut.cpu_pc);
      if(saved_sa==25'h100)begin
       if(saved_sd!==32'h50415353 || mmc_fault || !mmc_present || !mmc_wp || hps_reads<3 || dut.dma_error_pending)
        $fatal(1,"MMC completion marker=%h fault%0d present%0d WP%0d HPSreads%0d DMAerrors%h",saved_sd,mmc_fault,mmc_present,mmc_wp,hps_reads,dut.dma_error_pending);
       if($test$plusargs("hold") && (!held_once || hps_reads<4))$fatal(1,"CPU Hold path not exercised");
       $display("PASS authored ARM production MMC identify/exact CID, DMA5+3padding, odd PIO, ICU21/23/24, read-only rejection cycles=%0d HPSreads=%0d hold=%0d",cycles,hps_reads,held_once);$finish;
      end
     end
    end else sr<=ram[saved_sa[16:2]];
   end
  end
  if(!cold)begin cycles<=cycles+1;if(cycles>2000000)$fatal(1,"ARM MMC timeout PC=%h hoststatus%h HPSstate%0d",dut.cpu_pc,32'd0,hstate);end
 end
 initial begin
  for(i=0;i<2048;i=i+1)rom[i]=0;
  for(i=0;i<32768;i=i+1)ram[i]=32'ha5a5a5a5;
  $readmemh("build/sim/unit-mmc-mister/program.hex",rom);
  $readmemh("build/sim/unit-mmc-mister/image.hex",image);
  repeat(4)@(negedge clk);cold=0;
  @(negedge clk);img_mount=1;@(negedge clk);img_mount=0;
  wait(init_done);repeat(2)@(negedge clk);reset=0;
 end
 initial begin
  if($test$plusargs("hold"))begin
   wait(hstate==2 && hword==128);@(negedge clk);cpu_hold=1;held_once=1;
   repeat(12)@(negedge clk);cpu_hold=0;
  end
 end
endmodule
