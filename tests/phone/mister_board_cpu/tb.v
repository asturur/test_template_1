`timescale 1ns/1ps
module tb;
 parameter integer TIMER_CLK_DIV=1,NOS_TICK_HZ=1000;
 reg clk=0,reset=1,cold=1;always #5 clk=~clk;
 wire init_done,bus_lock;wire [24:0] csa,dsa;wire [31:0] csd,csread,dsread;wire [3:0] csb;wire cswe,csreq,csack,dsreq,dsack;
 wire [24:0] sa;wire [31:0] sd;wire [3:0] sb;wire swe,sreq;
 reg [31:0] sr=0;reg sack=0;reg [2:0] swait=0;reg spending=0;reg [24:0] saved_sa;reg [31:0] saved_sd;reg [3:0] saved_sb;reg saved_swe;
 wire [31:0] da,dd;wire dr,dw;wire [3:0] db;reg [31:0] rd=0;reg rdy=0;reg [3:0] delay_count=0;reg [31:0] saved_da;wire accept=(dr||dw) && delay_count==0 && !rdy;
 wire dirty,busy;wire [13:0] sector;wire ce,hs,vs,hb,vb;wire [11:0] rgb;
 reg [31:0] rom[0:1023],ram[0:1023];integer i,cycles=0;integer dd_reads=0;
 reg [26:0] test_keys=0;
 wire cpu_ram_accept;
 reg [1:0] request_phase=0;
 reg dma_cmd_valid=0,dma_cmd_write=0;
 reg [31:0] dma_cmd_addr=0,dma_cmd_data=0;
 reg [3:0] dma_cmd_be=0;
 wire dma_cmd_ready,dma_rsp_valid,dma_rsp_error;
 wire [31:0] dma_rsp_data;
 wire local_valid,local_ready,local_write,local_done,local_error;
 wire [31:0] local_addr,local_data,local_rdata;
 wire [3:0] local_be;
 integer lcd_dma_words=0;
 ngage_dma_route route (
  .clk(clk),.reset(reset),.cpu_lock(bus_lock),.cmd_valid(dma_cmd_valid),.cmd_ready(dma_cmd_ready),
  .cmd_write(dma_cmd_write),.cmd_addr(dma_cmd_addr),.cmd_data(dma_cmd_data),.cmd_be(dma_cmd_be),
  .rsp_valid(dma_rsp_valid),.rsp_error(dma_rsp_error),.rsp_data(dma_rsp_data),
  .ram_req(),.ram_write(),.ram_addr(),.ram_data(),.ram_be(),.ram_ack(1'b0),.ram_rdata(32'b0),
  .local_valid(local_valid),.local_ready(local_ready),.local_write(local_write),.local_addr(local_addr),
  .local_data(local_data),.local_be(local_be),.local_done(local_done),.local_error(local_error),.local_rdata(local_rdata)
 );
 // Preserve the four-register LCD fixture as an explicit legacy comparison.
 ngage_mister #(.TIMER_CLK_DIV(TIMER_CLK_DIV),.NOS_TICK_HZ(NOS_TICK_HZ),.DMA_LOCAL(1),.GENERAL_DMA(0)) dut(.debug_freeze_trace(1'b0),.sim_present(1'b1),.clk_sys(clk),.reset(reset),.cold_reset(cold),.board_init_done(init_done),.bus_lock(bus_lock),
  .sdram_addr(csa),.sdram_din(csd),.sdram_dout(csread),.sdram_be(csb),.sdram_we(cswe),.sdram_req(csreq),.sdram_ack(csack),.sdram_accept(cpu_ram_accept),
  .dma_sdram_req(dsreq),.dma_sdram_addr(dsa),.dma_sdram_ack(dsack),.dma_sdram_data(dsread),
  .dma_local_valid(local_valid),.dma_local_ready(local_ready),.dma_local_write(local_write),
  .dma_local_addr(local_addr),.dma_local_data(local_data),.dma_local_be(local_be),
  .dma_local_done(local_done),.dma_local_error(local_error),.dma_local_rdata(local_rdata),
  .ddram_addr(da),.ddram_rd(dr),.ddram_wr(dw),.ddram_din(dd),.ddram_be(db),.ddram_dout(rd),.ddram_dout_ready(rdy),.ddram_accept(accept),
  .flash_dirty(dirty),.flash_dirty_sector(sector),.flash_busy(busy),.ce_pix(ce),.hsync(hs),.vsync(vs),.hblank(hb),.vblank(vb),.rgb444(rgb),.keys(test_keys));
 ngage_sdram_arbiter arb(.cpu_accept(cpu_ram_accept),.clk(clk),.reset(reset),.cpu_lock(bus_lock),.cpu_req(csreq),.cpu_we(cswe),.cpu_addr(csa),.cpu_data(csd),.cpu_be(csb),.cpu_ack(csack),.cpu_rdata(csread),
 .dma_req(dsreq),.dma_we(1'b0),.dma_addr(dsa),.dma_data(32'b0),.dma_be(4'hf),.dma_ack(dsack),.dma_rdata(dsread),
 .mem_req(sreq),.mem_we(swe),.mem_addr(sa),.mem_data(sd),.mem_be(sb),.mem_ack(sack),.mem_rdata(sr));
 always @(posedge clk)begin
  if(dut.board.lcd_write_valid && dut.board.upp.cpu_inside.dma_local_active)
   lcd_dma_words<=lcd_dma_words+1;
  if(!reset && dut.board.upp.internal_dma_irq && dut.board.display.lcd.framebuffer.memory[0]!==24'h123abc)
   $fatal(1,"DMA completion preceded queued pixel commit");
  if(!reset && dut.wb_err && dut.wb_adr==32'h0c121200 && dut.wb_dat_o==32'hdeadbeef)
   if(dut.board.display.lcd.header!==0 || dut.board.upp.peripherals.hdr_written!==0)
    $fatal(1,"invalid header reached LCD queue or transport");
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
    if(saved_sa>=4096)begin $fatal(1,"FAIL SDRAM address %h",saved_sa);end
    if(saved_swe)begin
     // Test-only key injection controlled by the ARM regression program.
     if(saved_sa==25'h104 && saved_sb==15)test_keys<=saved_sd[26:0];
     if(saved_sa==25'h108 && saved_sb==15)request_phase<=saved_sd[1:0];
     for(i=0;i<4;i=i+1)if(saved_sb[i])ram[saved_sa[11:2]][i*8+:8]<=saved_sd[i*8+:8];
     if(saved_sa==25'h100)begin
      if(dut.panic_report!=={3'b111,32'h00010003,32'h6f697470,32'h65637845} || saved_sb!=15 || saved_sd!=32'h50415353 || dd_reads==0 || dut.board.display.lcd.framebuffer.memory[0]!==24'h123abc || dut.board.display.lcd.header!==32'h09200000 || !dut.board.display.lcd.display_on || !dut.board.upp.peripherals.hdr_written || !dut.debug_fault_seen || dut.diagnostics.first_address!==32'h08000000)begin $fatal(1,"FAIL ARM reported %h",saved_sd);end
      if(lcd_dma_words!=1)$fatal(1,"LCD DMA local word committed %0d times",lcd_dma_words);
      $display("PASS HDL ARM board SIMIF, LCD DMA, queued LCD commands, local CAM/LCD faults, diagnostics, IRQ/FIQ and SDRAM with waits");
      $display("PASS DMA via live UPP shared RAM, LCD FIFO and owned error completion");$finish;
     end
    end else sr<=ram[saved_sa[11:2]];
   end
  end
  if(!reset)begin cycles<=cycles+1;if(cycles>100000)begin $fatal(1,"FAIL ARM timeout");end end
 end
 initial begin
  for(i=0;i<1024;i=i+1)begin rom[i]=0;ram[i]=0;end
  $readmemh("build/sim/unit-mister-board-cpu/program.hex",rom);
  repeat(4)@(negedge clk);cold=0;wait(init_done);repeat(2)@(negedge clk);reset=0;
 end

 task dma_word;
  input write_op;
  input [31:0] address,value;
  input [3:0] lanes;
  input expected_error;
  input [31:0] expected_data;
  begin
   @(negedge clk);
   if(!dma_cmd_ready)$fatal(1,"DMA command interface busy");
   dma_cmd_addr=address;dma_cmd_data=value;dma_cmd_be=lanes;
   dma_cmd_write=write_op;dma_cmd_valid=1;
   @(negedge clk);dma_cmd_valid=0;
   wait(dma_rsp_valid);
   #1;
   if(dma_rsp_error!==expected_error || (!write_op && dma_rsp_data!==expected_data))
    $fatal(1,"DMA completion for %h: error %b data %h",address,dma_rsp_error,dma_rsp_data);
   @(posedge clk);
  end
 endtask

 initial begin
  wait(request_phase==1);
  dma_word(0,32'h0c004020,0,4'hf,0,32'hdec0ffee);
  dma_word(1,32'h0c004020,32'h11223344,4'b0101,0,0);
  dma_word(1,32'h10121208,32'haf,4'hf,1,0); // The guest has not set a header yet.
  @(negedge clk);ram[32'h10c/4]=1;
  wait(request_phase==2);
  dma_word(1,32'h10121208,32'haf,4'hf,0,0);
  @(negedge clk);ram[32'h10c/4]=2;
 end
endmodule
