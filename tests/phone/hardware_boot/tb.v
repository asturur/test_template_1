`timescale 1ns/1ps
// Bounded actual-RTL boot smoke. DDR/SDRAM are test backing memories; all
// phone bus devices, flash state, address mapping and CPU are HDL.
`ifdef NGAGE_LOGO_RUN
module tb(input wire clk,reset,cold,
 input wire [14:0] frame_index,
 output wire ready,output wire [31:0] cycle_count,pc,frame_word,
 output wire [8:0] scan_x,scan_y,output wire [11:0] scan_rgb,
 output wire scan_ce,scan_de,frame_complete,display_on,unsupported,
 output wire [31:0] bus_errors,data_faults,pixel_writes);
 integer lcd_unknown_prints=0;
 assign ready=init_done;
 assign cycle_count=cycles;
 assign pc=dut.board.upp.cpu_inside.cpu.u_zap.u_zap_core.o_instr_wb_adr;
 assign frame_word=dut.board.display.lcd.pixels[frame_index];
 assign scan_x=dut.board.display.lcd.scan_x-9'd72;assign scan_y=dut.board.display.lcd.scan_y-9'd16;
 assign scan_rgb=dut.rgb444;assign scan_ce=dut.ce_pix;
 assign scan_de=!(dut.hblank || dut.vblank);
 assign frame_complete=dut.board.display.lcd.frame_complete;
 assign display_on=dut.board.display.lcd.display_on;assign unsupported=dut.lcd_unsupported;
 assign bus_errors=errors;assign data_faults=data_errors;assign pixel_writes=lcd_writes;
`else
module tb;
 reg clk=0,reset=1,cold=1;
`endif
`ifndef NGAGE_LOGO_RUN
`ifdef NGAGE_REAL_SDRAM
 always #4.8075 clk=~clk; // match the production 104 MHz clock path
`else
 always #5 clk=~clk;
`endif
 `endif
 wire init_done,lock;wire [24:0] csa,dsa,sa;wire [31:0] csd,csr,dsr,sd,sr;wire [3:0] csb,sb;
 wire cswe,csreq,csack,dsreq,dsack,swe,sreq;wire sack; wire [31:0] sdata;assign sr=sdata;
`ifndef NGAGE_REAL_SDRAM
 reg sack_model=0; reg [31:0] sdata_model=0; assign sack=sack_model; assign sdata=sdata_model;
`else
 wire scrub_done,mem_init; wire [21:0] ba_addr; wire [15:0] ba_din,ba_dout; wire [1:0] ba_dsn;
 wire [3:0] rd,wr,ba_ack,ba_rdy; wire rfsh; tri [15:0] dq; wire [15:0] dq_write; wire [15:0] dq_read=memory.Dq_reg; wire [12:0] sdram_a;
 wire [1:0] bank; wire dqml,dqmh,nwe,ncas,nras,ncs,cke; wire memclk;
 ngage_sdram_clock forward_clock(.clk(clk),.sdram_clk(memclk));
 // Short smoke scrubs 32 bytes. The independent full-size scrub test covers
 // all 16 MiB; the behavioral SDRAM model starts zero in this Verilator run.
 ngage_sdram_adapter #(.RAM_BYTES(32)) sadapter(clk,cold,reset,mem_init,sreq,swe,sa,sd,sb,sack,sdata,scrub_done,ba_addr,ba_din,ba_dsn,rd,wr,ba_ack,ba_rdy,ba_dout,rfsh);
 jtframe_sdram64 #(.AW(22),.HF(1),.READ_CAPTURE_NEGEDGE(1),.BA0_LEN(16),.BA1_LEN(16),.BA2_LEN(16),.BA3_LEN(16),.PROG_LEN(16),.BA0_WEN(1),.BA1_WEN(1)) ctrl(
  .rst(cold),.clk(clk),.init(mem_init),.ba0_addr(ba_addr),.ba1_addr(ba_addr),.ba2_addr(22'b0),.ba3_addr(22'b0),
  .rd(rd),.wr(wr),.ba0_din(ba_din),.ba1_din(ba_din),.ba2_din(16'b0),.ba3_din(16'b0),
  .ba0_dsn(ba_dsn),.ba1_dsn(ba_dsn),.ba2_dsn(2'b11),.ba3_dsn(2'b11),
  .prog_en(1'b0),.prog_addr(22'b0),.prog_rd(1'b0),.prog_wr(1'b0),.prog_din(16'b0),.prog_dsn(2'b11),.prog_ba(2'b0),
  .prog_dst(),.prog_dok(),.prog_rdy(),.prog_ack(),.rfsh(rfsh),.ack(ba_ack),.dst(),.dok(),.rdy(ba_rdy),.dout(ba_dout),
  .sdram_dq(dq_read),.sdram_din(dq_write),.sdram_a(sdram_a),.sdram_dqml(dqml),.sdram_dqmh(dqmh),.sdram_ba(bank),.sdram_nwe(nwe),.sdram_ncas(ncas),.sdram_nras(nras),.sdram_ncs(ncs),.sdram_cke(cke));
 mt48lc16m16a2 memory(.Dq_write(dq_write),.Clk(memclk),.Cke(cke),.Dq(dq),.Addr(sdram_a),.Ba(bank),.Cs_n(ncs),.Ras_n(nras),.Cas_n(ncas),.We_n(nwe),.Dqm({dqmh,dqml}),.downloading(1'b0),.VS(1'b0),.frame_cnt(32'b0));
`endif
 wire [31:0] da,dd,back;wire [3:0] db;wire dr,dw,accept,done,dirty,busy;wire [13:0] sector;
 wire av,ar,aw,adone;wire [31:0] aa,ad,arsp;wire [3:0] ab;
 wire [28:0] pa;wire [63:0] pd;wire [7:0] pb;wire pr,pw;reg phyready=0;reg [63:0] phydata=0;
 reg [7:0] ddr[0:25231359];reg [31:0] ram[0:4194303];
 integer board_log; integer fd,got,i,cycles=0,transactions=0,lcd_writes=0,errors=0,data_errors=0,phys_writes=0;reg [31:0] read_addr=0;reg [2:0] ddelay=0,sdelay=0;
 integer owner_counts[0:17]; integer owner; integer k; integer memory_samples=0;
 task report_owner;
  input integer id;
  input [127:0] name;
  begin
   owner_counts[id]=owner_counts[id]+1;
   if(owner_counts[id]==1) $display("REACHED owner=%0s cycle=%0d addr=%h write=%b data=%h",name,cycles,dut.pa,dut.wb_we,dut.wb_we ? dut.wb_dat_o : dut.wb_dat_i);
  end
 endtask
 reg spending=0;reg [24:0] saddr=0;reg [31:0] swdata=0;reg [3:0] sbe=0;reg swrite=0;integer n;
 // Bounded historical comparison uses legacy alarm profile; logo boots select explicitly.
`ifdef NGAGE_POWERUP_NORMAL
 localparam UEM_POWERUP_STATUS=2;
`else
 localparam UEM_POWERUP_STATUS=1;
`endif
 ngage_mister #(.UEM_POWERUP_STATUS(UEM_POWERUP_STATUS)) dut(.clk_sys(clk),.reset(reset),.cold_reset(cold),.sim_present(1'b0),.diagnostic_video(
`ifdef NGAGE_LOGO_RUN
 1'b0
`else
 1'b1
`endif
 ),.diagnostic_status(8'b0),.debug_freeze_trace(1'b0),.debug_read_word(11'b0),.board_init_done(init_done),.bus_lock(lock),
  .sdram_addr(csa),.sdram_din(csd),.sdram_dout(csr),.sdram_be(csb),.sdram_we(cswe),.sdram_req(csreq),.sdram_ack(csack),
  .dma_sdram_req(dsreq),.dma_sdram_addr(dsa),.dma_sdram_ack(dsack),.dma_sdram_data(dsr),
  .ddram_addr(da),.ddram_rd(dr),.ddram_wr(dw),.ddram_din(dd),.ddram_be(db),.ddram_dout(back),.ddram_dout_ready(done),.ddram_accept(accept),.flash_dirty(dirty),.flash_dirty_sector(sector),.flash_busy(busy),.keys(27'b0));
 ngage_sdram_arbiter arb(.clk(clk),.reset(reset),.cpu_lock(lock),.cpu_req(csreq),.cpu_we(cswe),.cpu_addr(csa),.cpu_data(csd),.cpu_be(csb),.cpu_ack(csack),.cpu_rdata(csr),
  .dma_req(dsreq),.dma_we(1'b0),.dma_addr(dsa),.dma_data(32'b0),.dma_be(4'hf),.dma_ack(dsack),.dma_rdata(dsr),.mem_req(sreq),.mem_we(swe),.mem_addr(sa),.mem_data(sd),.mem_be(sb),.mem_ack(sack),.mem_rdata(sr));
 ngage_ddr_arbiter darb(.clk(clk),.reset(cold),.cpu_lock(lock),.l_valid(1'b0),.l_addr(32'b0),.l_data(32'b0),.l_be(4'b0),.l_write(1'b0),
  .c_valid(dr||dw),.c_ready(accept),.c_write(dw),.c_addr(da),.c_data(dd),.c_be(db),.c_done(done),.c_rdata(back),
  .req_valid(av),.req_ready(ar),.req_write(aw),.req_addr(aa),.req_data(ad),.req_be(ab),.rsp_valid(adone),.rsp_data(arsp));
 ngage_ddr_adapter adapter(.clk(clk),.reset(cold),.req_valid(av),.req_ready(ar),.req_write(aw),.req_addr(aa),.req_wdata(ad),.req_be(ab),.rsp_valid(adone),.rsp_data(arsp),
  .ddr_addr(pa),.ddr_din(pd),.ddr_be(pb),.ddr_rd(pr),.ddr_we(pw),.ddr_busy(ddelay!=0),.ddr_dout(phydata),.ddr_dout_ready(phyready));
 always @(posedge clk)begin
  phyready<=0;
`ifndef NGAGE_REAL_SDRAM
  sack_model<=0;
`endif
  if(pr && ddelay==0)begin read_addr<={pa,3'b000}-32'h30000000;ddelay<=3;end
  else if(ddelay!=0)begin ddelay<=ddelay-1'b1;if(ddelay==1)begin
   if(read_addr+7>=25231360)begin $fatal(1,"DDR read out of range %h",read_addr);end
   for(n=0;n<8;n=n+1)phydata[n*8+:8]<=ddr[read_addr+n];phyready<=1;
  end end
  if(pw && ddelay==0)begin
   if(({pa,3'b000}-32'h30000000)+7>=25231360)begin $fatal(1,"DDR write out of range");end
   for(n=0;n<8;n=n+1)if(pb[n])ddr[({pa,3'b000}-32'h30000000)+n]<=pd[n*8+:8];phys_writes<=phys_writes+1;
  end
`ifndef NGAGE_REAL_SDRAM
  if(sreq && !spending && !sack)begin spending<=1;sdelay<=3;saddr<=sa;swdata<=sd;sbe<=sb;swrite<=swe;end
  else if(spending)begin if(sdelay!=0)sdelay<=sdelay-1'b1;else begin
   spending<=0;sack_model<=1;
   if(saddr>=25'h1000000)begin $fatal(1,"SDRAM range");end
   if(swrite)begin for(n=0;n<4;n=n+1)if(sbe[n])ram[saddr[23:2]][n*8+:8]<=swdata[n*8+:8];end
   else sdata_model<=ram[saddr[23:2]];
  end end
`endif
  if(!reset && sack && memory_samples<32)begin
   $display("SDRAM_SAMPLE cycle=%0d addr=%h write=%b data=%h read=%h",cycles,sa,swe,sd,sdata);
   memory_samples<=memory_samples+1;
  end
  if(!reset)begin
   cycles<=cycles+1;
   if(board_log && (dut.wb_ack || dut.wb_err) && (dut.brd_claim || dut.dma_claim))
    $fdisplay(board_log,"%0d\t%s\t0x%08h\t0x%01h\t0x%08h\t%b\t%b\t%b",cycles,dut.wb_we ? "WRITE" : "READ",dut.pa,dut.wb_sel,dut.wb_we ? dut.wb_dat_o : dut.wb_dat_i,dut.wb_err,dut.irq_line,dut.fiq_line);
   if(dut.wb_ack)begin
    transactions<=transactions+1;
    if(dut.dma_claim) report_owner(0,"lcd_dma");
    else if(dut.brd_claim)begin
     if(dut.board.upp.peripherals.simif_claim) report_owner(1,"simif");
     else if(dut.board.upp.peripherals.extra_claim) report_owner(2,"icu_extra");
     else if(dut.board.upp.peripherals.gpio_loop_claim) report_owner(3,"gpio_loop");
     else if(dut.board.upp.peripherals.mdi_claim) report_owner(4,"mdi");
     else if(dut.board.upp.peripherals.trace_claim) report_owner(5,"trace");
     else if(dut.board.upp.peripherals.boot_claim) report_owner(6,"boot_regs");
     else if(dut.board.upp.peripherals.icu_claim) report_owner(7,"icu");
     else if(dut.board.upp.peripherals.timer_claim) report_owner(8,"timers");
     else if(dut.board.upp.peripherals.nos_claim) report_owner(9,"nos_io");
     else if(dut.board.upp.peripherals.cbus_claim) report_owner(10,"cbus_uem");
     else if(dut.board.upp.peripherals.nos4k_hit) report_owner(11,"nos_ram_regs");
     else if(dut.board.upp.peripherals.d_space_hit) report_owner(12,"d_space");
     else if(dut.board.upp.peripherals.clk_hit) report_owner(13,"clock_regs");
     else if(dut.board.upp.peripherals.gpio_hit) report_owner(14,"gpio_ram_regs");
     else if(dut.board.upp.peripherals.lcd_hit) report_owner(15,"lcd");
     else begin $display("FAIL acknowledged board request without owner %h",dut.pa);$fatal(1);end
    end else if(dut.ram_hit) report_owner(16,"sdram");
    else if(dut.flash_hit) report_owner(17,"flash");
    else begin $display("FAIL acknowledged request without owner %h",dut.pa);$fatal(1);end
   end
   if(dut.wb_err)begin
    errors<=errors+1;
    if(!dut.wb_code)data_errors<=data_errors+1;
    if(errors<20)$display("BUS_FAULT addr=%h write=%b instruction=%b",dut.wb_adr,dut.wb_we,dut.wb_code);
   end
   if(dut.wb_ack && dut.wb_we && dut.pa==32'h0c121208)lcd_writes<=lcd_writes+1;
`ifdef NGAGE_LOGO_RUN
   if(dut.wb_ack && dut.wb_we && dut.pa>=32'h0c121200 && dut.pa<=32'h0c121208 && (dut.pa!=32'h0c121208 || dut.board.display.lcd.header[31:16]!=16'h8924))
    $display("LCD cycle=%0d addr=%h data=%h pc=%h",cycles,dut.pa,dut.wb_dat_o,pc);
   if(dut.board.display.lcd.unsupported_valid && lcd_unknown_prints<32)begin
    lcd_unknown_prints<=lcd_unknown_prints+1;
    $display("LCD_UNKNOWN cycle=%0d header=%h command=%h data=%h pc=%h",cycles,dut.board.display.lcd.unsupported_header,dut.board.display.lcd.unsupported_command,dut.board.display.lcd.unsupported_data,pc);
   end
`else
   if(cycles==5000000)begin
    if(transactions<1000 || owner_counts[15]==0 || errors>1000 || data_errors!=0 || !dut.diagnostics.fetch_seen || dut.debug_fault_seen || dut.board.upp.cpu_inside.cpu.u_zap.u_zap_core.o_instr_wb_adr==0)begin $fatal(1,"bounded boot did not progress");end
    for(k=0;k<18;k=k+1)if(owner_counts[k]!=0)$display("OWNER id=%0d count=%0d",k,owner_counts[k]);
    $display("PASS bounded hardware-bound boot cycles=%0d bus=%0d errors=%0d data_errors=%0d lcd_words=%0d DDR_writes=%0d pc=%h",cycles,transactions,errors,data_errors,lcd_writes,phys_writes,dut.board.upp.cpu_inside.cpu.u_zap.u_zap_core.o_instr_wb_adr);$finish;
   end
`endif
  end
 end
 reg [2047:0] core_path,extension_path,cdrive_path;
 initial begin
`ifdef NGAGE_LOGO_RUN
  board_log=0;
`else
`ifdef NGAGE_REAL_SDRAM
  board_log=$fopen("build/sim/unit-hardware-boot-real-sdram/board.tsv","w");
`else
  board_log=$fopen("build/sim/unit-hardware-boot/board.tsv","w");
`endif
  if(!board_log) $fatal(1,"cannot open board trace");
  $fdisplay(board_log,"cycle\top\taddress\tmask\tdata\terror\tirq\tfiq");
`endif
  for(i=0;i<18;i=i+1)owner_counts[i]=0;
  for(i=0;i<4194304;i=i+1)ram[i]=0;
  for(i=0;i<65536;i=i+1)ddr[25165824+i]=8'hff;
  core_path="build/firmware/nem4-factory/core.bin";
  extension_path="build/firmware/nem4-factory/extension.bin";
  cdrive_path="scratch/overnight/cdrive-11b.img";
  if($value$plusargs("core=%s",core_path))begin end
  if($value$plusargs("extension=%s",extension_path))begin end
  if($value$plusargs("cdrive=%s",cdrive_path))begin end
  fd=$fopen(core_path,"rb");if(!fd)begin $fatal(1,"missing core image");end
  got=$fread(ddr,fd,0,18612224);$fclose(fd);if(got!=18612224)begin $fatal(1,"core length %0d",got);end
  fd=$fopen(extension_path,"rb");if(!fd)begin $fatal(1,"missing extension");end
  got=$fread(ddr,fd,18612224,2293760);$fclose(fd);if(got!=2293760)begin $fatal(1,"extension length %0d",got);end
  fd=$fopen(cdrive_path,"rb");if(!fd)begin $fatal(1,"missing C image");end
  got=$fread(ddr,fd,20971520,4194304);$fclose(fd);if(got!=4194304)begin $fatal(1,"C length %0d",got);end
`ifndef NGAGE_LOGO_RUN
  repeat(4)@(negedge clk);cold=0;wait(init_done);
`ifdef NGAGE_REAL_SDRAM
  wait(scrub_done);
`endif
  repeat(2)@(negedge clk);reset=0;
`endif
 end
`ifndef NGAGE_LOGO_RUN
 initial begin #200000000; $fatal(1,"hardware boot watchdog timeout"); end
`endif
endmodule
