`timescale 1ns/1ps
module tb;
 reg clk=0,reset=1,cold=1;always #5 clk=~clk;
 wire init_done,bus_lock;wire [24:0] csa,dsa;wire [31:0] csd,csread,dsread;wire [3:0] csb;wire cswe,csreq,csack,dsreq,dsack;
 wire [24:0] sa;wire [31:0] sd;wire [3:0] sb;wire swe,sreq;
 reg [31:0] sr=0;reg sack=0;reg [2:0] swait=0;reg spending=0;reg [24:0] saved_sa;reg [31:0] saved_sd;reg [3:0] saved_sb;reg saved_swe;
 wire [31:0] da,dd;wire dr,dw;wire [3:0] db;reg [31:0] rd=0;reg rdy=0;reg [3:0] delay_count=0;reg [31:0] saved_da;wire accept=(dr||dw) && delay_count==0 && !rdy;
 wire dirty,busy;wire [13:0] sector;wire ce,hs,vs,hb,vb;wire [11:0] rgb;
 reg [31:0] rom[0:1023],ram[0:1023];integer i,cycles=0;integer dd_reads=0;
 ngage_mister dut(.debug_freeze_trace(1'b0),.sim_present(1'b1),.clk_sys(clk),.reset(reset),.cold_reset(cold),.board_init_done(init_done),.bus_lock(bus_lock),
  .sdram_addr(csa),.sdram_din(csd),.sdram_dout(csread),.sdram_be(csb),.sdram_we(cswe),.sdram_req(csreq),.sdram_ack(csack),
  .dma_sdram_req(dsreq),.dma_sdram_addr(dsa),.dma_sdram_ack(dsack),.dma_sdram_data(dsread),
  .ddram_addr(da),.ddram_rd(dr),.ddram_wr(dw),.ddram_din(dd),.ddram_be(db),.ddram_dout(rd),.ddram_dout_ready(rdy),.ddram_accept(accept),
  .flash_dirty(dirty),.flash_dirty_sector(sector),.flash_busy(busy),.ce_pix(ce),.hsync(hs),.vsync(vs),.hblank(hb),.vblank(vb),.rgb444(rgb),.keys(27'b0));
 ngage_sdram_arbiter arb(.clk(clk),.reset(reset),.cpu_lock(bus_lock),.cpu_req(csreq),.cpu_we(cswe),.cpu_addr(csa),.cpu_data(csd),.cpu_be(csb),.cpu_ack(csack),.cpu_rdata(csread),
 .dma_req(dsreq),.dma_we(1'b0),.dma_addr(dsa),.dma_data(32'b0),.dma_be(4'hf),.dma_ack(dsack),.dma_rdata(dsread),
 .mem_req(sreq),.mem_we(swe),.mem_addr(sa),.mem_data(sd),.mem_be(sb),.mem_ack(sack),.mem_rdata(sr));
 always @(posedge clk)begin
  rdy<=0;sack<=0;
  if(accept)begin
   if(dw || da<32'h30000000 || da>=32'h30001000)begin $display("FAIL unexpected DDR request %h",da);$finish;end
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
    spending<=0;sack<=1;
    if(saved_sa>=4096)begin $display("FAIL SDRAM address %h",saved_sa);$finish;end
    if(saved_swe)begin
     for(i=0;i<4;i=i+1)if(saved_sb[i])ram[saved_sa[11:2]][i*8+:8]<=saved_sd[i*8+:8];
     if(saved_sa==25'h100)begin
      if(saved_sb!=15 || saved_sd!=32'h50415353 || dd_reads==0 || dut.board.display.lcd.pixels[0]!==32'h01230abc || !dut.debug_fault_seen || dut.diagnostics.first_address!==32'h08000000)begin $display("FAIL ARM reported %h",saved_sd);$finish;end
      $display("PASS HDL ARM board SIMIF, LCD DMA, diagnostic fault, IRQ/FIQ and SDRAM with waits");$finish;
     end
    end else sr<=ram[saved_sa[11:2]];
   end
  end
  if(!reset)begin cycles<=cycles+1;if(cycles>100000)begin $display("FAIL ARM timeout");$finish;end end
 end
 initial begin
  for(i=0;i<1024;i=i+1)begin rom[i]=0;ram[i]=0;end
  $readmemh("build/sim/unit-mister-board-cpu/program.hex",rom);
  repeat(4)@(negedge clk);cold=0;wait(init_done);repeat(2)@(negedge clk);reset=0;
 end
endmodule
