`timescale 1ns/1ps
// Bounded actual-RTL boot smoke. DDR/SDRAM are test backing memories; all
// phone bus devices, flash state, address mapping and CPU are HDL.
`ifdef NGAGE_LOGO_RUN
module tb(input wire clk,reset,cold,
 input wire [14:0] frame_index,
 output wire ready,output wire [31:0] cycle_count,pc,frame_word,
 output wire [8:0] scan_x,scan_y,output wire [11:0] scan_rgb,
 output wire scan_ce,scan_de,frame_complete,display_on,unsupported,
 output wire [31:0] bus_errors,data_faults,pixel_writes,
 output wire [31:0] boot_index,boot_limit,retired_count,ddr_command_count,ddr_beat_count);
 integer lcd_unknown_prints=0;
`ifdef NGAGE_EARLY_BOOT_TRACE
 wire delay_retire = dut.board.upp.cpu_inside.cpu.u_zap.u_zap_core.u_zap_writeback.i_uop_last &&
   (dut.board.upp.cpu_inside.cpu.u_zap.u_zap_core.u_zap_writeback.i_valid ||
    dut.board.upp.cpu_inside.cpu.u_zap.u_zap_core.u_zap_writeback.i_decompile_valid) &&
   !(|dut.board.upp.cpu_inside.cpu.u_zap.u_zap_core.u_zap_writeback.i_data_abt) &&
   !dut.board.upp.cpu_inside.cpu.u_zap.u_zap_core.u_zap_writeback.i_instr_abt;
 wire [31:0] delay_pc = dut.board.upp.cpu_inside.cpu.u_zap.u_zap_core.u_zap_writeback.i_pc_plus_8_buf_ff - 8;
 wire [31:0] delay_r0 = dut.board.upp.cpu_inside.cpu.u_zap.u_zap_core.u_zap_writeback.u_zap_register_file.mem[0];
 wire [31:0] delay_r1 = dut.board.upp.cpu_inside.cpu.u_zap.u_zap_core.u_zap_writeback.u_zap_register_file.mem[1];
 wire [31:0] delay_r4 = dut.board.upp.cpu_inside.cpu.u_zap.u_zap_core.u_zap_writeback.u_zap_register_file.mem[4];
 wire [31:0] delay_r5 = dut.board.upp.cpu_inside.cpu.u_zap.u_zap_core.u_zap_writeback.u_zap_register_file.mem[5];
 integer delay_calls=0, delay_entries=0, delay_entry_cycle=0;
 integer delay_retired=0, delay_fetches=0;
 integer cost_ddr_beats=0;
 assign boot_index=delay_r4;assign boot_limit=delay_r5;
 assign retired_count=cost_retired;assign ddr_command_count=cost_ddr;assign ddr_beat_count=cost_ddr_beats;
 integer cost_retired=0,cost_fetch_wait=0,cost_code_stall=0,cost_backing=0,cost_ddr=0;
 integer cost_cache_lookup=0,cost_backend=0;
 integer hit_trace_clocks=0;
 reg cost_core_pending_l=0,cost_bus_pending_l=0;
 wire cost_core_pending=dut.board.upp.cpu_inside.cpu.u_zap.u_zap_core.o_instr_wb_cyc && dut.board.upp.cpu_inside.cpu.u_zap.u_zap_core.o_instr_wb_stb;
 wire cost_bus_pending=dut.wb_cyc && dut.wb_stb && dut.wb_code;
 wire cost_lookup_busy,cost_backend_busy;
 generate if(ROM_CACHE)begin: cost_cached
  assign cost_lookup_busy=adapter.cached.cache.state==1;
  assign cost_backend_busy=adapter.cached.backend.state!=0;
  always @(posedge clk) begin
    if(!reset && delay_entries==3 && hit_trace_clocks<70)begin
     hit_trace_clocks<=hit_trace_clocks+1;
     $display("CPU_HIT cycle=%0d cpu_ack=%b cpu_adr=%h rd=%b launched=%b req=%b ready=%b state=%0d response=%b busvalid=%b inflight=%b offer=%b master=%b master_ack=%b bridge=%0d tlb_busy=%b physical=%h",cycles,dut.board.upp.cpu_inside.cpu.u_zap.u_zap_core.i_instr_wb_ack,dut.board.upp.cpu_inside.cpu.u_zap.cpu_iaddr,dut.board.upp.cpu_inside.cpu.u_zap.cpu_instr_stb,dut.board.upp.cpu_inside.cpu.u_zap.l_generate_with_cache_mmu.u_code_cache.cache_adapter.launched,dut.board.upp.cpu_inside.cpu.u_zap.l_generate_with_cache_mmu.u_code_cache.cache_adapter.req_valid,dut.board.upp.cpu_inside.cpu.u_zap.l_generate_with_cache_mmu.u_code_cache.cache_adapter.req_ready,dut.board.upp.cpu_inside.cpu.u_zap.l_generate_with_cache_mmu.u_code_cache.cache_adapter.cache.state,dut.board.upp.cpu_inside.cpu.u_zap.l_generate_with_cache_mmu.u_code_cache.cache_adapter.response_valid,dut.board.upp.cpu_inside.cpu.u_zap.l_generate_with_cache_mmu.u_code_cache.cache_adapter.bus_valid,dut.board.upp.cpu_inside.cpu.u_zap.l_generate_with_cache_mmu.u_code_cache.cache_adapter.inflight,dut.board.upp.cpu_inside.cpu.u_zap.c_wb_stb,dut.board.upp.cpu_inside.master_stb,dut.board.upp.cpu_inside.master_ack,dut.board.upp.cpu_inside.bridge.state,dut.board.upp.cpu_inside.cpu.u_zap.l_generate_with_cache_mmu.u_code_cache.tlb_busy,dut.board.upp.cpu_inside.cpu.u_zap.l_generate_with_cache_mmu.u_code_cache.tlb_phy_addr);

     $display("HIT_PIPE cycle=%0d bus=%b owner=%b flash_start=%b flash_state=%0d backing=%b accept=%b cache_state=%0d lookup_valid=%b cache_ok=%b raw_rsp=%b flash_rsp=%b bus_ack=%b",cycles,cost_bus_pending,dut.memory_owner_valid,dut.flash_start,dut.code_flash.state,dut.cm_valid,dut.cm_ready,adapter.cached.cache.state,adapter.cached.cache.cache.addr_ok_l,adapter.cached.cache.cache_ok,adone,dut.code_rsp,dut.wb_ack);
    end
  end
 end else begin: cost_uncached
  assign cost_lookup_busy=0;
  assign cost_backend_busy=adapter.uncached.backend.state!=0;
 end endgenerate
 always @(posedge clk) if(!reset) begin
   cost_core_pending_l<=cost_core_pending;
   cost_bus_pending_l<=cost_bus_pending;
   if(delay_entries==3)begin
    if(cost_core_pending && !cost_core_pending_l)$display("BOUNDARY CORE_REQ cycle=%0d address=%h",cycles,dut.board.upp.cpu_inside.cpu.u_zap.u_zap_core.o_instr_wb_adr);
    if(cost_core_pending && dut.board.upp.cpu_inside.cpu.u_zap.u_zap_core.i_instr_wb_ack)$display("BOUNDARY CORE_ACK cycle=%0d address=%h",cycles,dut.board.upp.cpu_inside.cpu.u_zap.u_zap_core.o_instr_wb_adr);
    if(cost_bus_pending && !cost_bus_pending_l)$display("BOUNDARY BUS_REQ cycle=%0d address=%h",cycles,dut.wb_adr);
    if(cost_bus_pending && dut.wb_ack)$display("BOUNDARY BUS_ACK cycle=%0d address=%h",cycles,dut.wb_adr);
   end
   if(delay_retire)cost_retired<=cost_retired+1;
   if(dut.wb_cyc && dut.wb_stb && dut.wb_code && !dut.wb_ack && !dut.wb_err)cost_fetch_wait<=cost_fetch_wait+1;
   if(dut.board.upp.cpu_inside.cpu.u_zap.u_zap_core.code_stall)cost_code_stall<=cost_code_stall+1;
   if(dut.cm_valid && dut.cm_ready)cost_backing<=cost_backing+1;
   if(pr && ddelay==0)cost_ddr<=cost_ddr+1;
   if(phyready)cost_ddr_beats<=cost_ddr_beats+1;
   if(cost_lookup_busy)cost_cache_lookup<=cost_cache_lookup+1;
   if(cost_backend_busy)cost_backend<=cost_backend+1;
   if(delay_retire && delay_pc>=32'h6150 && delay_pc<=32'h6178)delay_retired<=delay_retired+1;
   if(dut.wb_ack && dut.wb_code)delay_fetches<=delay_fetches+1;
   if(delay_retire && delay_pc==32'h63cc)begin
     delay_calls<=delay_calls+1;
     $display("BOOT_DELAY cycle=%0d pc=%h count=%0d outer_r4=%0d outer_r5=%0d",cycles,delay_pc,delay_r0,delay_r4,delay_r5);
   end
   if(delay_retire && delay_pc==32'h6150 && delay_entries<8)begin
     delay_entries<=delay_entries+1;
     if(delay_entries==0)delay_entry_cycle<=cycles;
     $display("BOOT_COST cycle=%0d entry=%0d retired=%0d fetch_ack=%0d fetch_wait=%0d code_stall=%0d backing_reads=%0d ddr_reads=%0d lookup_cycles=%0d backend_cycles=%0d",cycles,delay_entries,cost_retired,delay_fetches,cost_fetch_wait,cost_code_stall,cost_backing,cost_ddr,cost_cache_lookup,cost_backend);
     $display("BOOT_INNER cycle=%0d entry=%0d count=%0d outer_index=%0d outer_limit=%0d",cycles,delay_entries,delay_r0,delay_r4,delay_r5);
   end
   if(cycles%100000==0)$display("BOOT_PROFILE cycle=%0d delay_retired=%0d fetches=%0d r0=%0d r1=%0d r4=%0d r5=%0d",cycles,delay_retired,delay_fetches,delay_r0,delay_r1,delay_r4,delay_r5);
 end
`else
 assign boot_index=0;assign boot_limit=0;assign retired_count=0;assign ddr_command_count=0;assign ddr_beat_count=0;
`endif

`ifdef NGAGE_NOS_OVERLAY_RUN
 assign ready=init_done && overlay_ready;
`else
 assign ready=init_done;
`endif
 assign cycle_count=cycles;
 assign pc=dut.board.upp.cpu_inside.cpu.u_zap.u_zap_core.o_instr_wb_adr;
 wire [23:0] observed_pixels=dut.board.display.lcd.framebuffer.memory[frame_index];
 assign frame_word={4'b0,observed_pixels[23:12],4'b0,observed_pixels[11:0]};
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
parameter integer OVERLAY_COMPONENT=1;
parameter integer SYS_CLK_HZ=104000000;
parameter integer TIMER_CLK_DIV=1,NOS_TICK_HZ=1000;
parameter integer ROM_CACHE=0;
parameter integer DIRECT_SDRAM=1;
parameter integer LINE_REFILL=0;
parameter integer SHORT_READS=0;
parameter integer BOUNDED_CYCLES=5000000;
parameter integer ROM_CACHE_BITS=64,ROM_CACHE_BYTES=1024;
`ifndef NGAGE_LOGO_RUN
`ifdef NGAGE_REAL_SDRAM
 always #(500000000.0/SYS_CLK_HZ) clk=~clk; // selected nominal hardware frequency
`else
 always #5 clk=~clk;
`endif
 `endif
 wire init_done,lock;wire [24:0] csa,dsa,sa;wire [31:0] csd,csr,dsr,sd,sr;wire [3:0] csb,sb;
 // The production frontend owns complete DMA words; the route preserves
 // writes, byte lanes, local endpoint ownership and terminal errors.
 wire dma_cmd_valid,dma_cmd_ready,dma_cmd_write,dma_rsp_valid,dma_rsp_error;
 wire [31:0] dma_cmd_addr,dma_cmd_data,dma_rsp_data,dma_ram_data;
 wire [3:0] dma_cmd_be,dma_ram_be;
 wire dma_reset;
 wire lcd_fast_req,lcd_fast_accept,lcd_fast_ack;
 wire [24:0] lcd_fast_addr;
 wire [31:0] lcd_fast_data;
 wire shared_dma_req,shared_dma_write,shared_dma_accept,shared_dma_ack;
 wire [24:0] shared_dma_addr;
 wire [31:0] shared_dma_data,shared_dma_rdata;
 wire [3:0] shared_dma_be;
 wire dma_ram_write;
 wire dma_local_valid,dma_local_ready,dma_local_write,dma_local_done,dma_local_error;
 wire [31:0] dma_local_addr,dma_local_data,dma_local_rdata;
 wire [3:0] dma_local_be;
 wire [7:0] dma_error_pending;
 reg [7:0] dma_errors_seen=0;

 wire cswe,csreq,csack,dsreq,dsack,swe,sreq;wire sack; wire [31:0] sdata;assign sr=sdata;
 wire ram_line_req,ram_line_ready,ram_line_valid,ram_line_last;
 wire [24:0] ram_line_addr;wire [15:0] ram_line_data;
`ifndef NGAGE_REAL_SDRAM
 reg [4:0] ram_line_count=0;reg [24:0] ram_line_saved=0;
 reg ram_line_v=0,ram_line_end=0;reg [15:0] ram_line_q=0;
 assign ram_line_ready=LINE_REFILL && !dma_reset && !cold && ram_line_count==0 && !sreq && !spending;
 assign ram_line_valid=ram_line_v;assign ram_line_last=ram_line_end;assign ram_line_data=ram_line_q;
 always @(posedge clk)begin
  ram_line_v<=0;ram_line_end<=0;
  if(dma_reset || cold)ram_line_count<=0;
  else if(ram_line_req && ram_line_ready)begin ram_line_count<=16;ram_line_saved<=ram_line_addr;end
  else if(ram_line_count!=0)begin
   ram_line_q<=ram[ram_line_saved[23:2]] >> (ram_line_saved[1]*16);
   ram_line_saved<=ram_line_saved+2;ram_line_count<=ram_line_count-1;
   ram_line_v<=1;ram_line_end<=ram_line_count==1;
  end
 end
 reg ram_discard=0;
 reg sack_model=0; reg [31:0] sdata_model=0; assign sack=sack_model; assign sdata=sdata_model;
`else
 wire scrub_done,mem_init; wire [21:0] ba_addr; wire [15:0] ba_din,ba_dout; wire [1:0] ba_dsn;
 wire [3:0] rd,wr,ba_ack,ba_dst,ba_rdy; wire rfsh; tri [15:0] dq; wire [15:0] dq_write; wire [15:0] dq_read=memory.Dq_reg; wire [12:0] sdram_a;
 wire [1:0] bank; wire dqml,dqmh,nwe,ncas,nras,ncs,cke; wire memclk;
 ngage_sdram_clock forward_clock(.clk(clk),.sdram_clk(memclk));
 // Short smoke scrubs 32 bytes. The independent full-size scrub test covers
 // all 16 MiB; the behavioral SDRAM model starts zero in this Verilator run.
 wire [1:0] ba_line;
 ngage_sdram_adapter #(.LINE_REFILL(LINE_REFILL),.RAM_BYTES(32),.REFRESH_PERIOD((64'd6800*SYS_CLK_HZ)/104000000)) sadapter(
 .clk(clk),.rst(cold),.phone_reset(dma_reset || cold),.init(mem_init),.req(sreq),.we(swe),.addr(sa),.din(sd),.be(sb),.ack(sack),.dout(sdata),.scrub_done(scrub_done),
 .ba_addr(ba_addr),.ba_din(ba_din),.ba_dsn(ba_dsn),.rd(rd),.wr(wr),.ba_ack(ba_ack),.ba_dst(ba_dst),.ba_rdy(ba_rdy),.ba_dout(ba_dout),.rfsh(rfsh),
 .line_req(ram_line_req),.line_addr(ram_line_addr),.line_ready(ram_line_ready),.line_valid(ram_line_valid),.line_data(ram_line_data),.line_last(ram_line_last),.ba_line(ba_line));
 jtframe_sdram64 #(.SHORT_READS(SHORT_READS),.DYNAMIC_LINE(LINE_REFILL),.AW(22),.HF(1),.READ_CAPTURE_NEGEDGE(1),.BA0_LEN(LINE_REFILL?128:32),.BA1_LEN(LINE_REFILL?128:32),.BA2_LEN(16),.BA3_LEN(16),.PROG_LEN(16),.BA0_WEN(1),.BA1_WEN(1)) ctrl(
  .line_read(ba_line),.rst(cold),.clk(clk),.init(mem_init),.ba0_addr(ba_addr),.ba1_addr(ba_addr),.ba2_addr(22'b0),.ba3_addr(22'b0),
  .rd(rd),.wr(wr),.ba0_din(ba_din),.ba1_din(ba_din),.ba2_din(16'b0),.ba3_din(16'b0),
  .ba0_dsn(ba_dsn),.ba1_dsn(ba_dsn),.ba2_dsn(2'b11),.ba3_dsn(2'b11),
  .prog_en(1'b0),.prog_addr(22'b0),.prog_rd(1'b0),.prog_wr(1'b0),.prog_din(16'b0),.prog_dsn(2'b11),.prog_ba(2'b0),
  .prog_dst(),.prog_dok(),.prog_rdy(),.prog_ack(),.rfsh(rfsh),.ack(ba_ack),.dst(ba_dst),.dok(),.rdy(ba_rdy),.dout(ba_dout),
  .sdram_dq(dq_read),.sdram_din(dq_write),.sdram_a(sdram_a),.sdram_dqml(dqml),.sdram_dqmh(dqmh),.sdram_ba(bank),.sdram_nwe(nwe),.sdram_ncas(ncas),.sdram_nras(nras),.sdram_ncs(ncs),.sdram_cke(cke));
 mt48lc16m16a2 memory(.Dq_write(dq_write),.Clk(memclk),.Cke(cke),.Dq(dq),.Addr(sdram_a),.Ba(bank),.Cs_n(ncs),.Ras_n(nras),.Cas_n(ncas),.We_n(nwe),.Dqm({dqmh,dqml}),.downloading(1'b0),.VS(1'b0),.frame_cnt(32'b0));
`endif
 wire ddr_fetch,ddr_line,arb_line,arb_beat_valid,arb_beat_last,core_beat_valid,core_beat_last;
 wire [63:0] arb_beat_data,core_beat_data;
 wire [31:0] da,dd,back;wire [3:0] db;wire dr,dw,accept,done,dirty,busy;wire [13:0] sector;
 wire av,ar,aw,adone;wire [31:0] aa,ad,arsp;wire [3:0] ab;
 wire [7:0] ddr_burst;
 wire [28:0] pa;wire [63:0] pd;wire [7:0] pb;wire pr,pw;reg phyready=0;reg [63:0] phydata=0;
 reg [7:0] ddr[0:25231359];reg [31:0] ram[0:4194303];
 // The request address is allowed to be zero in an idle fetch phase. Track
 // actual F-stage acceptance for bounded-run liveness, not an arbitrary edge.
 reg [31:0] last_fetch_pc=0;
 integer last_fetch_cycle=-10000;
 wire accepted_fetch = dut.board.upp.cpu_inside.cpu.u_zap.u_zap_core.u_zap_fetch_main.i_valid &&
  !dut.board.upp.cpu_inside.cpu.u_zap.u_zap_core.code_stall && !dut.board.upp.cpu_inside.cpu.u_zap.u_zap_core.u_zap_fetch_main.sleep_ff &&
  !dut.board.upp.cpu_inside.cpu.u_zap.u_zap_core.clear_from_writeback && !dut.board.upp.cpu_inside.cpu.u_zap.u_zap_core.clear_from_alu &&
  !dut.board.upp.cpu_inside.cpu.u_zap.u_zap_core.clear_from_decode;
 integer board_log; integer fd,got,i,cycles=0,transactions=0,lcd_writes=0,errors=0,data_errors=0,phys_writes=0;reg [31:0] read_addr=0;reg [2:0] ddelay=0,sdelay=0;reg [7:0] ddr_remaining=0;
 integer owner_counts[0:17]; integer owner; integer k; integer memory_samples=0;
 task report_owner;
  input integer id;
  input [127:0] name;
  begin
   owner_counts[id]=owner_counts[id]+1;
   if(owner_counts[id]==1) $display("REACHED owner=%0s cycle=%0d addr=%h write=%b data=%h",name,cycles,dut.observed_address,dut.observed_write,dut.observed_write ? dut.observed_data : (dut.observe_ram ? csr : dut.wb_dat_i));
  end
 endtask
 reg spending=0;reg [24:0] saddr=0;reg [31:0] swdata=0;reg [3:0] sbe=0;reg swrite=0;integer n;
 // Bounded historical comparison uses legacy alarm profile; logo boots select explicitly.
`ifdef NGAGE_POWERUP_NORMAL
 localparam UEM_POWERUP_STATUS=2;
`else
 localparam UEM_POWERUP_STATUS=1;
`endif
 wire cpu_ram_accept;
 ngage_mister #(.GENERAL_DMA(1),.DMA_LOCAL(1),.LINE_REFILL(LINE_REFILL),.TIMER_CLK_DIV(TIMER_CLK_DIV),.NOS_TICK_HZ(NOS_TICK_HZ),.DIRECT_SDRAM(DIRECT_SDRAM),.UEM_POWERUP_STATUS(UEM_POWERUP_STATUS),.SYS_CLK_HZ(SYS_CLK_HZ)) dut(
  .mmc_card_reset(1'b0),.mmc_img_mounted(1'b0),.mmc_img_readonly(1'b1),.mmc_img_size(64'd0),
  .mmc_sd_ack(1'b0),.mmc_sd_buff_addr(13'd0),.mmc_sd_buff_dout(16'd0),.mmc_sd_buff_wr(1'b0),
.ddram_line(ddr_line),.ddram_beat_valid(core_beat_valid),.ddram_beat_data(core_beat_data),.ddram_beat_last(core_beat_last),
 .ram_line_req(ram_line_req),.ram_line_addr(ram_line_addr),.ram_line_ready(ram_line_ready),.ram_line_valid(ram_line_valid),.ram_line_data(ram_line_data),.ram_line_last(ram_line_last),.clk_sys(clk),.reset(reset),.cold_reset(cold),.sim_present(1'b0),.diagnostic_video(
`ifdef NGAGE_LOGO_RUN
 1'b0
`else
 1'b1
`endif
 ),.diagnostic_status(8'b0),.debug_freeze_trace(1'b0),.debug_read_word(11'b0),.board_init_done(init_done),.bus_lock(lock),
  .sdram_addr(csa),.sdram_din(csd),.sdram_dout(csr),.sdram_be(csb),.sdram_we(cswe),.sdram_req(csreq),.sdram_ack(csack),.sdram_accept(cpu_ram_accept),
  .dma_reset(dma_reset),.dma_sdram_accept(lcd_fast_accept),
  .dma_sdram_req(lcd_fast_req),.dma_sdram_addr(lcd_fast_addr),.dma_sdram_ack(lcd_fast_ack),.dma_sdram_data(lcd_fast_data),
  .dma_error_pending(dma_error_pending),
  .dma_cmd_valid(dma_cmd_valid),.dma_cmd_ready(dma_cmd_ready),.dma_cmd_write(dma_cmd_write),
  .dma_cmd_addr(dma_cmd_addr),.dma_cmd_data(dma_cmd_data),.dma_cmd_be(dma_cmd_be),
  .dma_rsp_valid(dma_rsp_valid),.dma_rsp_error(dma_rsp_error),.dma_rsp_data(dma_rsp_data),
  .dma_local_valid(dma_local_valid),.dma_local_ready(dma_local_ready),.dma_local_write(dma_local_write),
  .dma_local_addr(dma_local_addr),.dma_local_data(dma_local_data),.dma_local_be(dma_local_be),
  .dma_local_done(dma_local_done),.dma_local_error(dma_local_error),.dma_local_rdata(dma_local_rdata),
  .ddram_addr(da),.ddram_fetch(ddr_fetch),.ddram_rd(dr),.ddram_wr(dw),.ddram_din(dd),.ddram_be(db),.ddram_dout(back),.ddram_dout_ready(done),.ddram_accept(accept),.flash_dirty(dirty),.flash_dirty_sector(sector),.flash_busy(busy),.keys(27'b0));
 ngage_dma_route dma_route (
  .clk(clk),.reset(dma_reset || cold),.cpu_lock(lock),
  .cmd_valid(dma_cmd_valid),.cmd_ready(dma_cmd_ready),.cmd_write(dma_cmd_write),
  .cmd_addr(dma_cmd_addr),.cmd_data(dma_cmd_data),.cmd_be(dma_cmd_be),
  .rsp_valid(dma_rsp_valid),.rsp_error(dma_rsp_error),.rsp_data(dma_rsp_data),
  .ram_req(dsreq),.ram_write(dma_ram_write),.ram_addr(dsa),.ram_data(dma_ram_data),
  .ram_be(dma_ram_be),.ram_ack(dsack),.ram_rdata(dsr),
  .local_valid(dma_local_valid),.local_ready(dma_local_ready),.local_write(dma_local_write),
  .local_addr(dma_local_addr),.local_data(dma_local_data),.local_be(dma_local_be),
  .local_done(dma_local_done),.local_error(dma_local_error),.local_rdata(dma_local_rdata)
 );
 ngage_dma_ram_mux dma_ram_mux (
  .clk(clk),.reset(dma_reset || cold),
  .lcd_req(lcd_fast_req),.lcd_addr(lcd_fast_addr),.lcd_accept(lcd_fast_accept),.lcd_ack(lcd_fast_ack),.lcd_rdata(lcd_fast_data),
  .dma_req(dsreq),.dma_write(dma_ram_write),.dma_addr(dsa),.dma_data(dma_ram_data),.dma_be(dma_ram_be),.dma_ack(dsack),.dma_rdata(dsr),
  .mem_req(shared_dma_req),.mem_write(shared_dma_write),.mem_addr(shared_dma_addr),.mem_data(shared_dma_data),.mem_be(shared_dma_be),
  .mem_accept(shared_dma_accept),.mem_ack(shared_dma_ack),.mem_rdata(shared_dma_rdata)
 );
 ngage_sdram_arbiter arb(.cpu_accept(cpu_ram_accept),.clk(clk),.reset(dma_reset || cold),.cpu_lock(lock),.cpu_req(csreq),.cpu_we(cswe),.cpu_addr(csa),.cpu_data(csd),.cpu_be(csb),.cpu_ack(csack),.cpu_rdata(csr),
  .dma_req(shared_dma_req),.dma_we(shared_dma_write),.dma_addr(shared_dma_addr),.dma_data(shared_dma_data),.dma_be(shared_dma_be),.dma_ack(shared_dma_ack),.dma_rdata(shared_dma_rdata),.dma_accept(shared_dma_accept),.mem_req(sreq),.mem_we(swe),.mem_addr(sa),.mem_data(sd),.mem_be(sb),.mem_ack(sack),.mem_rdata(sr));
`ifdef NGAGE_NOS_OVERLAY_RUN
 // Separate experiment: exercise the real staged loader and shared DDR path,
 // not a host-prepatched ROM. The CPU remains reset until application completes.
 reg overlay_download=0, overlay_wr=0;
 reg [26:0] overlay_pos=0;
 reg [15:0] overlay_input=0;
 reg [15:0] overlay_words[0:4095];
 reg [1023:0] overlay_path;
 integer overlay_feed=0, overlay_length=0;
 wire overlay_wait, overlay_ready, overlay_loaded, overlay_applied, overlay_busy;
 wire [3:0] overlay_error;
 wire overlay_req, overlay_accept, overlay_write, overlay_done;
 wire [31:0] overlay_addr, overlay_data, overlay_response;
 initial begin
  if(!$value$plusargs("nos-overlay=%s",overlay_path)) $fatal(1,"component overlay input required");
  $readmemh(overlay_path,overlay_words);
  overlay_length={overlay_words[23],overlay_words[22]};
 end
 ngage_nos_overlay #(.OVERLAY_ID(OVERLAY_COMPONENT)) nos_overlay (
  .clk(clk),.reset(cold),.firmware_valid(init_done),.firmware_loading(1'b0),
  .enabled(1'b1),.checksum_required(1'b1),.blocked(1'b0),.download(overlay_download),.wr(overlay_wr),
  .addr(overlay_pos),.data(overlay_input),.wait_req(overlay_wait),.ready(overlay_ready),
  .loaded(overlay_loaded),.applied(overlay_applied),.busy(overlay_busy),.error(overlay_error),
  .mem_valid(overlay_req),.mem_ready(overlay_accept),.mem_write(overlay_write),
  .mem_addr(overlay_addr),.mem_data(overlay_data),.mem_done(overlay_done),.mem_rdata(overlay_response)
 );
 always @(posedge clk) if(!cold) begin
  case(overlay_feed)
   0: begin overlay_download<=1;overlay_feed<=1;end
   1: if(!overlay_wait)begin
    overlay_input<=overlay_words[overlay_pos>>1];overlay_wr<=1;overlay_feed<=2;
   end
   2: begin
    overlay_wr<=0;
    if(overlay_pos+2==overlay_length)begin overlay_download<=0;overlay_feed<=3;end
    else begin overlay_pos<=overlay_pos+2;overlay_feed<=1;end
   end
   3: if(overlay_ready)begin
    if(!overlay_applied || {ddr[32'h8f1b],ddr[32'h8f1a],ddr[32'h8f19],ddr[32'h8f18]}!=32'hffffffff ||
       {ddr[32'h8f1f],ddr[32'h8f1e],ddr[32'h8f1d],ddr[32'h8f1c]}!=32'hffffffff)
     $fatal(1,"component overlay/checksum bypass not applied before CPU release");
    $display("PASS component overlay ID%0d applied through real DDR adapter before CPU release; checksum bypass active",OVERLAY_COMPONENT);
    overlay_feed<=4;
   end
  endcase
  if(overlay_error!=0)$fatal(1,"component overlay error %0d",overlay_error);
  if(!reset && !overlay_ready)$fatal(1,"CPU released before component overlay ready");
 end
 ngage_ddr_arbiter darb(.clk(clk),.reset(cold),.cpu_lock(lock),
  .l_valid(overlay_req),.l_ready(overlay_accept),.l_addr(overlay_addr),.l_data(overlay_data),
  .l_be(4'hf),.l_write(overlay_write),.l_done(overlay_done),.l_rdata(overlay_response),
`else
 ngage_ddr_arbiter darb(.clk(clk),.reset(cold),.cpu_lock(lock),.l_valid(1'b0),.l_addr(32'b0),.l_data(32'b0),.l_be(4'b0),.l_write(1'b0),
`endif
  .c_line(ddr_line),.req_line(arb_line),.rsp_beat_valid(arb_beat_valid),.rsp_beat_data(arb_beat_data),.rsp_beat_last(arb_beat_last),
  .c_beat_valid(core_beat_valid),.c_beat_data(core_beat_data),.c_beat_last(core_beat_last),
  .c_valid(dr||dw),.c_ready(accept),.c_write(dw),.c_addr(da),.c_data(dd),.c_be(db),.c_done(done),.c_rdata(back),
  .req_valid(av),.req_ready(ar),.req_write(aw),.req_addr(aa),.req_data(ad),.req_be(ab),.rsp_valid(adone),.rsp_data(arsp));
 ngage_ddr_adapter #(.LINE_REFILL(LINE_REFILL),.ROM_CACHE(ROM_CACHE),.ROM_CACHE_BITS(ROM_CACHE_BITS),.ROM_CACHE_BYTES(ROM_CACHE_BYTES)) adapter(.req_line(arb_line),.rsp_beat_valid(arb_beat_valid),.rsp_beat_data(arb_beat_data),.rsp_beat_last(arb_beat_last),.ddr_burstcount(ddr_burst),.req_fetch(accept && ddr_fetch),.clk(clk),.reset(cold),.req_valid(av),.req_ready(ar),.req_write(aw),.req_addr(aa),.req_wdata(ad),.req_be(ab),.rsp_valid(adone),.rsp_data(arsp),
  .ddr_addr(pa),.ddr_din(pd),.ddr_be(pb),.ddr_rd(pr),.ddr_we(pw),.ddr_busy(ddelay!=0),.ddr_dout(phydata),.ddr_dout_ready(phyready));
 always @(posedge clk)begin
  phyready<=0;
`ifndef NGAGE_REAL_SDRAM
  sack_model<=0;
`endif
  if(pr && ddelay==0)begin read_addr<={pa,3'b000}-32'h30000000;ddelay<=3;ddr_remaining<=ddr_burst;end
  else if(ddelay!=0)begin ddelay<=ddelay-1'b1;if(ddelay==1)begin
   if(read_addr+7>=25231360)begin $fatal(1,"DDR read out of range %h",read_addr);end
   for(n=0;n<8;n=n+1)phydata[n*8+:8]<=ddr[read_addr+n];phyready<=1;
   if(ddr_remaining>1)begin
    ddelay<=1;ddr_remaining<=ddr_remaining-1'b1;read_addr<=read_addr+8;
   end
  end end
  if(pw && ddelay==0)begin
   if(({pa,3'b000}-32'h30000000)+7>=25231360)begin $fatal(1,"DDR write out of range");end
   for(n=0;n<8;n=n+1)if(pb[n])ddr[({pa,3'b000}-32'h30000000)+n]<=pd[n*8+:8];phys_writes<=phys_writes+1;
  end
`ifndef NGAGE_REAL_SDRAM
  // Mirror the physical adapter's logical-reset drain: accepted work may
  // commit, but its old ACK cannot be returned to a newly reset owner.
  if((dma_reset || cold) && spending) ram_discard<=1;
  if(sreq && ram_line_count==0 && !spending && !sack && !dma_reset && !cold)begin spending<=1;ram_discard<=0;sdelay<=3;saddr<=sa;swdata<=sd;sbe<=sb;swrite<=swe;end
  else if(spending)begin if(sdelay!=0)sdelay<=sdelay-1'b1;else begin
   spending<=0;sack_model<=!ram_discard && !dma_reset && !cold;
   if(saddr>=25'h1000000)begin $fatal(1,"SDRAM range");end
   if(swrite)begin for(n=0;n<4;n=n+1)if(sbe[n])ram[saddr[23:2]][n*8+:8]<=swdata[n*8+:8];end
   else sdata_model<=ram[saddr[23:2]];
  end end
`endif
  if(!reset && sack && memory_samples<32)begin
   $display("SDRAM_SAMPLE cycle=%0d addr=%h write=%b data=%h read=%h",cycles,sa,swe,sd,sdata);
   memory_samples<=memory_samples+1;
  end
  if(reset) dma_errors_seen<=0;
  if(!reset)begin
   if (|(dma_error_pending & ~dma_errors_seen))
    $display("DMA_ERROR cycle=%0d channels=%h pc=%h",cycles,dma_error_pending,dut.board.upp.cpu_inside.cpu.u_zap.u_zap_core.o_instr_wb_adr);
   dma_errors_seen<=dma_errors_seen | dma_error_pending;
   cycles<=cycles+1;
   if(accepted_fetch)begin last_fetch_pc<=dut.board.upp.cpu_inside.cpu.u_zap.u_zap_core.o_instr_wb_adr;last_fetch_cycle<=cycles;end
   if(board_log && (dut.wb_ack || dut.wb_err) && (dut.brd_claim || dut.dma_claim))
    $fdisplay(board_log,"%0d\t%s\t0x%08h\t0x%01h\t0x%08h\t%b\t%b\t%b",cycles,dut.wb_we ? "WRITE" : "READ",dut.pa,dut.wb_sel,dut.wb_we ? dut.wb_dat_o : dut.wb_dat_i,dut.wb_err,dut.irq_line,dut.fiq_line);
   if(dut.fast_ram_response)begin
    transactions<=transactions+1;
    report_owner(16,"sdram");
   end
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
   if(cycles==BOUNDED_CYCLES)begin
    if(transactions<1000 || owner_counts[15]==0 || errors>1000 || data_errors!=0 || !dut.diagnostics.fetch_seen || dut.debug_fault_seen || last_fetch_pc==0 || cycles-last_fetch_cycle>10000)begin $fatal(1,"bounded boot did not progress bus=%0d owner15=%0d errors=%0d data_errors=%0d fetched=%b debug_fault=%b fetch_pc=%h",transactions,owner_counts[15],errors,data_errors,dut.diagnostics.fetch_seen,dut.debug_fault_seen,dut.board.upp.cpu_inside.cpu.u_zap.u_zap_core.o_instr_wb_adr);end
    for(k=0;k<18;k=k+1)if(owner_counts[k]!=0)$display("OWNER id=%0d count=%0d",k,owner_counts[k]);
    $display("PASS bounded hardware-bound boot cycles=%0d bus=%0d errors=%0d data_errors=%0d lcd_words=%0d DDR_writes=%0d pc=%h bus_pc=%h last_fetch_age=%0d",cycles,transactions,errors,data_errors,lcd_writes,phys_writes,last_fetch_pc,dut.board.upp.cpu_inside.cpu.u_zap.u_zap_core.o_instr_wb_adr,cycles-last_fetch_cycle);$finish;
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
  board_log=0;
  if(!$test$plusargs("no-board-log")) board_log=$fopen("build/sim/unit-hardware-boot-real-sdram/board.tsv","w");
`else
  board_log=$fopen("build/sim/unit-hardware-boot/board.tsv","w");
`endif
  if(!board_log && !$test$plusargs("no-board-log")) $fatal(1,"cannot open board trace");
  if(board_log) $fdisplay(board_log,"cycle\top\taddress\tmask\tdata\terror\tirq\tfiq");
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
 initial begin #(200000000.0 + BOUNDED_CYCLES*(1000000000.0/SYS_CLK_HZ)); $fatal(1,"hardware boot watchdog timeout"); end
`endif
endmodule
