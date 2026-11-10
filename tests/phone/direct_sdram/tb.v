`timescale 1ns/1ps
module tb;
 parameter DIRECT_SDRAM=1;
 reg clk=0,reset=1,cold=1;always #5 clk=~clk;
 wire init_done,bus_lock;wire [24:0] csa,dsa;wire [31:0] csd,csread,dsread;wire [3:0] csb;wire cswe,csreq,csack,dsreq,dsack;
 wire [24:0] sa;wire [31:0] sd;wire [3:0] sb;wire swe,sreq;
 reg [31:0] sr=0;reg sack=0;reg [2:0] swait=0;reg spending=0;reg [24:0] saved_sa;reg [31:0] saved_sd;reg [3:0] saved_sb;reg saved_swe;
 wire [31:0] da,dd;wire dr,dw;wire [3:0] db;reg [31:0] rd=0;reg rdy=0;reg [3:0] delay_count=0;reg [31:0] saved_da;wire accept=(dr||dw) && delay_count==0 && !rdy;
 wire dirty,busy;wire [13:0] sector;wire ce,hs,vs,hb,vb;wire [11:0] rgb;
 reg [31:0] rom[0:1023],ram[0:16383];integer i,cycles=0;integer dd_reads=0,dma_words=0;
 wire cpu_ram_accept;
 ngage_mister #(.DIRECT_SDRAM(DIRECT_SDRAM)) dut(.debug_freeze_trace(1'b0),.sim_present(1'b1),.clk_sys(clk),.reset(reset),.cold_reset(cold),.board_init_done(init_done),.bus_lock(bus_lock),
  .sdram_addr(csa),.sdram_din(csd),.sdram_dout(csread),.sdram_be(csb),.sdram_we(cswe),.sdram_req(csreq),.sdram_ack(csack),.sdram_accept(cpu_ram_accept),
  .dma_sdram_req(dsreq),.dma_sdram_addr(dsa),.dma_sdram_ack(dsack),.dma_sdram_data(dsread),
  .ddram_addr(da),.ddram_rd(dr),.ddram_wr(dw),.ddram_din(dd),.ddram_be(db),.ddram_dout(rd),.ddram_dout_ready(rdy),.ddram_accept(accept),
  .flash_dirty(dirty),.flash_dirty_sector(sector),.flash_busy(busy),.ce_pix(ce),.hsync(hs),.vsync(vs),.hblank(hb),.vblank(vb),.rgb444(rgb),.keys(27'b0));
 ngage_sdram_arbiter arb(.cpu_accept(cpu_ram_accept),.clk(clk),.reset(reset),.cpu_lock(bus_lock),.cpu_req(csreq),.cpu_we(cswe),.cpu_addr(csa),.cpu_data(csd),.cpu_be(csb),.cpu_ack(csack),.cpu_rdata(csread),
 .dma_req(dsreq),.dma_we(1'b0),.dma_addr(dsa),.dma_data(32'b0),.dma_be(4'hf),.dma_ack(dsack),.dma_rdata(dsread),
 .mem_req(sreq),.mem_we(swe),.mem_addr(sa),.mem_data(sd),.mem_be(sb),.mem_ack(sack),.mem_rdata(sr));

 integer cpu_reads=0,cpu_writes=0,measure_start=0,measure_reads=0,measure_writes=0;
 integer profile_state[0:14];integer profile_i=0,profile_rom=0,profile_ram=0;
 reg measuring=0,measure_dirty=0;reg [31:0] measure_address=0;reg measure_write=0,measure_cached=0;
 always @(posedge clk)if(!reset)begin
  if(cpu_ram_accept)begin if(cswe)cpu_writes<=cpu_writes+1;else cpu_reads<=cpu_reads+1;end
  if(dut.board.upp.cpu_inside.cpu.u_zap.l_generate_with_cache_mmu.u_data_cache.cache_adapter.cache.req_valid && dut.board.upp.cpu_inside.cpu.u_zap.l_generate_with_cache_mmu.u_data_cache.cache_adapter.cache.req_ready)begin
   for(profile_i=0;profile_i<15;profile_i=profile_i+1)profile_state[profile_i]=0;
   profile_rom=0;profile_ram=0;
   measuring<=1;measure_start<=cycles;measure_reads<=cpu_reads;measure_writes<=cpu_writes;
   measure_address<=dut.board.upp.cpu_inside.cpu.u_zap.l_generate_with_cache_mmu.u_data_cache.cache_adapter.cache.req_physical;measure_write<=dut.board.upp.cpu_inside.cpu.u_zap.l_generate_with_cache_mmu.u_data_cache.cache_adapter.cache.req_write;
   measure_cached<=dut.board.upp.cpu_inside.cpu.u_zap.l_generate_with_cache_mmu.u_data_cache.cache_adapter.cache.req_cache_enable && dut.board.upp.cpu_inside.cpu.u_zap.l_generate_with_cache_mmu.u_data_cache.cache_adapter.cache.req_cacheable;measure_dirty<=0;
  end
  if(measuring && dut.board.upp.cpu_inside.cpu.u_zap.l_generate_with_cache_mmu.u_data_cache.cache_adapter.cache.refill.transfer_start && dut.board.upp.cpu_inside.cpu.u_zap.l_generate_with_cache_mmu.u_data_cache.cache_adapter.cache.refill.bank_victim_valid && |dut.board.upp.cpu_inside.cpu.u_zap.l_generate_with_cache_mmu.u_data_cache.cache_adapter.cache.refill.bank_victim_dirty)measure_dirty<=1;
  if(measuring)begin
   profile_state[dut.board.upp.cpu_inside.cpu.u_zap.l_generate_with_cache_mmu.u_data_cache.cache_adapter.cache.state]=profile_state[dut.board.upp.cpu_inside.cpu.u_zap.l_generate_with_cache_mmu.u_data_cache.cache_adapter.cache.state]+1;
   if(dut.board.upp.cpu_inside.master_cyc && dut.board.upp.cpu_inside.master_stb && dut.board.upp.cpu_inside.master_code)profile_rom=profile_rom+1;
   if(arb.state==1 && !arb.owner)profile_ram=profile_ram+1;
  end
  if(measuring && dut.board.upp.cpu_inside.cpu.u_zap.l_generate_with_cache_mmu.u_data_cache.cache_adapter.cache.response_valid)begin
   $display("RAM_COST mode=%0d pa=%h write=%b cached=%b dirty=%b clocks=%0d reads=%0d writes=%0d",DIRECT_SDRAM,measure_address,measure_write,measure_cached,measure_dirty,cycles-measure_start,cpu_reads-measure_reads,cpu_writes-measure_writes);
   if((measure_address==32'h0a000020 && !measure_write && measure_cached) || measure_dirty)begin
    $write("RAM_PROFILE mode=%0d pa=%h dirty=%b clocks=%0d rom_port=%0d ram_service=%0d",DIRECT_SDRAM,measure_address,measure_dirty,cycles-measure_start,profile_rom,profile_ram);
    for(profile_i=0;profile_i<15;profile_i=profile_i+1)$write(" state%0d=%0d",profile_i,profile_state[profile_i]);
    $display("");
   end
   measuring<=0;
  end
 end
 always @(posedge clk)begin
  if(dut.dma_lcd_valid)begin
   if((dma_words==0 && dut.dma_lcd_data!==32'h01110222) || (dma_words==1 && dut.dma_lcd_data!==32'h03330444) || dma_words>1)begin
    $fatal(1,"FAIL noncoherent DMA word %0d got %h",dma_words,dut.dma_lcd_data);end
   dma_words<=dma_words+1;
  end
  rdy<=0;sack<=0;
  if(accept)begin
   if(dw || da<32'h30000000 || da>=32'h30001000)begin $fatal(1,"FAIL unexpected DDR request %h",da);end
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
    if(saved_sa>=65536)begin $fatal(1,"FAIL SDRAM address %h",saved_sa);end
    if(saved_swe)begin
     for(i=0;i<4;i=i+1)if(saved_sb[i])ram[saved_sa[15:2]][i*8+:8]<=saved_sd[i*8+:8];
     if(saved_sa==25'h100)begin
      if(saved_sb!=15 || saved_sd!=32'h50415353 || dd_reads==0 || dma_words!=2 || dut.board.display.lcd.framebuffer.memory[0]!==24'h333444)begin $fatal(1,"FAIL ARM reported %h",saved_sd);end
      $display("PASS direct SDRAM benchmark mode=%0d: clean/hit/dirty eviction, DMA coherence, bytes and SWP",DIRECT_SDRAM);$finish;
     end
    end else sr<=ram[saved_sa[15:2]];
   end
  end
  if(!reset)begin cycles<=cycles+1;if(cycles>1000000)begin $fatal(1,"FAIL ARM timeout");end end
 end
 initial begin
  for(i=0;i<1024;i=i+1)rom[i]=0;
  for(i=0;i<16384;i=i+1)ram[i]=0;
  $readmemh("build/sim/unit-direct-sdram/program.hex",rom);
  repeat(4)@(negedge clk);cold=0;wait(init_done);repeat(2)@(negedge clk);reset=0;
 end
endmodule
