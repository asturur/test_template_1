`timescale 1ns/1ps
module test;
 reg clk=0,reset=1,irq=0,fiq=0;
 integer wfi_ticks=0,refill_irq_ticks=0,swp_irq_state=0;
 wire cyc,stb,we,bus_lock;wire [31:0] addr,wdata;wire [3:0] sel;wire [2:0] cti;wire [1:0] bte;
 reg [31:0] rdata; wire ack, bus_error;
 reg [31:0] fault_addr=0;
 reg fault_read_only=0,fault_write_only=0; integer fault_address_writes=0;
 reg [31:0] rom[0:16383]; reg [31:0] ram[0:524287];
 integer latency=0,delay=0,cycles=0,completed=0,max_cycles=500000;
 reg [31:0] timing_first=0,timing_last=0,trace_pc=0,last_pc=0;
 integer last_cycle=0,timing_count=0,timing_sum=0,timing_min=999999,timing_max=0,gap;
 integer warm_count=0,warm_sum=0,warm_min=999999,warm_max=0;
 integer bus_count=0,last_bus_count=0,tlb_order_stalls=0;
 integer swap_reads=0,swap_writes=0,locked_reads=0,locked_writes=0;
 reg locked_read_pending=0;
 reg dma_pending=0,dma_done=0;reg [31:0] dma_observed=0;
 reg [31:0] instruction_test_addr=0;integer instruction_fetches=0,prefetch_expected=1;
`ifdef NGAGE_ASSOC_EXPERIMENT
 reg [1023:0] recent_trace[0:15];integer recent_pos=0;
`endif
 wire [1023:0] trace_text=dut.u_zap.u_zap_core.o_trace;
 wire trace_valid=dut.u_zap.u_zap_core.o_trace_valid;
 wire trace_last=dut.u_zap.u_zap_core.o_trace_uop_last;
 always #5 clk=~clk;
 wire [31:0] observed_pc,observed_cpsr,observed_instruction;
 wire observed_fetch;
`ifdef NGAGE_TEST_BUS_BRIDGE
 wire master_cyc,master_stb,master_we,master_code,master_ack,master_error;
 wire [31:0] master_address,master_data,master_read_data;
 wire [3:0] master_sel;
 ngage_upp_bus_bridge bridge(
  .clk(clk),.reset(reset),.master_cyc(master_cyc),.master_stb(master_stb),
  .master_we(master_we),.master_code(master_code),.master_address(master_address),
  .master_data(master_data),.master_sel(master_sel),.master_ack(master_ack),
  .master_error(master_error),.master_read_data(master_read_data),
  .bus_cyc(cyc),.bus_stb(stb),.bus_we(we),.bus_code(),.bus_address(addr),
  .bus_data(wdata),.bus_sel(sel),.bus_ack(ack),.bus_error(bus_error),.bus_read_data(rdata));
`endif
 // Check the new demand-only CPU input against the retained original ACK on
 // every active transfer, across all CPU programs, faults and interrupt races.
 always @(negedge clk)if(!reset)begin
  if(dut.u_zap.cpu_dc_stb && dut.u_zap.data_request_ack!==dut.u_zap.data_ack)
   $fatal(1,"demand completion differs from original strobed ACK");
  if(dut.u_zap.u_zap_core.data_stall !==
     (dut.u_zap.u_zap_core.o_data_wb_stb & dut.u_zap.u_zap_core.o_data_wb_cyc & ~dut.u_zap.data_ack))
   $fatal(1,"global data-stall timing changed");
 end
 always @(negedge clk)if(!reset)begin
  if(observed_pc!==dut.u_zap.u_zap_core.o_instr_wb_adr ||
     observed_cpsr!==dut.u_zap.u_zap_core.alu_flags_ff ||
     observed_instruction!==dut.u_zap.u_zap_core.i_instr_wb_dat ||
     observed_fetch!==dut.u_zap.u_zap_core.instr_valid)$fatal(1,"synthesis debug port wiring");
 end
 ngage_cpu dut(.debug_pc(observed_pc),.debug_cpsr(observed_cpsr),
 .debug_instruction(observed_instruction),.debug_fetch(observed_fetch),.clk(clk),.reset(reset),.irq(irq),.fiq(fiq),
  .wb_lock(bus_lock),.wb_cycle_type(cti),.wb_burst_type(bte),
`ifdef NGAGE_TEST_BUS_BRIDGE
  .wb_cyc(master_cyc),.wb_stb(master_stb),.wb_address(master_address),
  .wb_write(master_we),.wb_write_data(master_data),.wb_byte_enable(master_sel),
  .wb_code(master_code),.wb_ack(master_ack),.wb_error(master_error),.wb_read_data(master_read_data));
`else
  .wb_cyc(cyc),.wb_stb(stb),.wb_address(addr),.wb_write(we),.wb_write_data(wdata),
  .wb_byte_enable(sel),.wb_ack(ack),.wb_error(bus_error),.wb_read_data(rdata));
`endif
 assign bus_error=cyc && stb && fault_addr!=0 && addr==fault_addr && (!fault_read_only || !we) && (!fault_write_only || we);
`ifdef NGAGE_SDRAM_PATH
 wire ram_access=addr>=32'h80000000 && addr<32'h80200000;
 wire ram_ack, sreq, swe, sack, sd_done, rfsh, mr; wire [31:0] sdata, mwdata, mrdata; wire [24:0] sa; wire [3:0] sb;
 wire [21:0] ba; wire [15:0] bd; wire [1:0] dsn; wire [3:0] rd,wr; reg [3:0] rr=0; reg [31:0] half_latched=0;
 wire [3:0] take=(rd|wr) & {4{delay>=latency}};
 ngage_sdram_arbiter arb(clk,reset,bus_lock,cyc && stb && ram_access && !bus_error,we,addr[24:0],wdata,sel,ram_ack,sdata,
  1'b0,1'b0,25'b0,32'b0,4'b0,,,sreq,swe,sa,mwdata,sb,sack,mrdata);
 ngage_sdram_adapter #(.RAM_BYTES(4)) mem(clk,reset,1'b0,1'b0,sreq,swe,sa,mwdata,sb,sack,mrdata,sd_done,
  ba,bd,dsn,rd,wr,take,rr,ba[0] ? half_latched[31:16] : half_latched[15:0],rfsh);
 always @(posedge clk) begin rr<=take; if(|take) half_latched<=ram[addr[20:2]]; end
 assign ack=ram_access ? ram_ack : (cyc && stb && delay>=latency && !bus_error);
`else
 assign ack=cyc && stb && delay>=latency && !bus_error;
`endif
 always @* begin
  rdata=0;
  if(addr<32'h00010000) rdata=rom[addr[15:2]];
`ifdef NGAGE_SDRAM_PATH
  else if(ram_access) rdata=sdata;
`else
  else if(addr>=32'h80000000 && addr<32'h80200000) rdata=ram[addr[20:2]];
`endif
 end
 always @(posedge clk) begin
`ifdef NGAGE_SDRAM_PATH
  if(reset || !cyc || !stb || ack || |take) delay<=0;else delay<=delay+1;
`else
  if(reset || !cyc || !stb || ack) delay<=0;else delay<=delay+1;
`endif
  if(!reset) begin
   cycles<=cycles+1;
`ifdef NGAGE_ASSOC_EXPERIMENT
   if ((($test$plusargs("tlb_order") && dut.u_zap.l_generate_with_cache_mmu.u_data_cache.tlb_raw_stb) ||
        ($test$plusargs("tlb_order_i") && dut.u_zap.l_generate_with_cache_mmu.u_code_cache.tlb_raw_stb)) &&
       !dut.u_zap.l_generate_with_cache_mmu.u_data_cache.o_write_buffer_empty)tlb_order_stalls=tlb_order_stalls+1;
   if ($test$plusargs("check_prefetch") && dut.u_zap.l_generate_with_cache_mmu.u_code_cache.o_cache_prefetch_done && instruction_fetches!=prefetch_expected)
    $fatal(1,"prefetch completed with %0d target line fetches, expected %0d",instruction_fetches,prefetch_expected);
   if ($test$plusargs("irq_refill") || $test$plusargs("irq_writeback")) begin
    if(refill_irq_ticks==0 && (($test$plusargs("irq_refill") &&
       dut.u_zap.l_generate_with_cache_mmu.u_data_cache.experimental_cache.cache.refill.transfer.state==2 &&
       dut.u_zap.l_generate_with_cache_mmu.u_data_cache.experimental_cache.cache.refill.transfer.new_address==32'h80030100) ||
       ($test$plusargs("irq_writeback") &&
       dut.u_zap.l_generate_with_cache_mmu.u_data_cache.experimental_cache.cache.refill.transfer.state==1 &&
       dut.u_zap.l_generate_with_cache_mmu.u_data_cache.experimental_cache.cache.refill.transfer.old_address==32'h80030100)))refill_irq_ticks=1;
    else if(refill_irq_ticks>0 && refill_irq_ticks<100)refill_irq_ticks=refill_irq_ticks+1;
    if(refill_irq_ticks==2)irq<=1;
    if(refill_irq_ticks>2 && dut.u_zap.cpu_cpsr[4:0]==5'h12)irq<=0;
   end
`endif
   // A competing bus master becomes ready after the first swap read. It may
   // observe memory only after the CPU releases the external bus lock.
   if(($test$plusargs("swp_cached") || $test$plusargs("swp_cached_irq") || $test$plusargs("swp_mmu_abort")) && bus_lock) $fatal(1,"cached SWP asserted external lock");
   if($test$plusargs("swp_dma")) begin
    if(!dma_done && !dma_pending && ack && bus_lock && !we && addr==32'h80001000) dma_pending=1;
    if(dma_pending && !bus_lock) begin dma_observed=ram['h400];dma_pending=0;dma_done=1;end
   end
   if ($test$plusargs("swp_tags") || $test$plusargs("swp_abort_check") || $test$plusargs("swp_bufferable")) begin
    if(locked_read_pending && !bus_lock) $fatal(1,"SWP bus lock released before write");
    if(bus_lock && (ack || bus_error)) begin
     if(addr!=($test$plusargs("swp_bufferable") ? 32'h80030000 : 32'h80001000)) $fatal(1,"other bus request interleaved with SWP: %h",addr);
     if(we) begin locked_writes=locked_writes+1;locked_read_pending=0;end
     else begin locked_reads=locked_reads+1;locked_read_pending=1;end
    end
   end
   if ($test$plusargs("swp_tags") && dut.u_zap.u_zap_core.o_data_wb_stb &&
       dut.u_zap.u_zap_core.o_data_wb_cyc && dut.u_zap.u_zap_core.i_data_wb_ack) begin
    if(dut.u_zap.u_zap_core.postalu_swp_tag==1) begin
     if(dut.u_zap.u_zap_core.o_data_wb_we)$fatal(1,"SWP read tag on write");
     swap_reads=swap_reads+1;
    end
    if(dut.u_zap.u_zap_core.postalu_swp_tag==2) begin
     if(!dut.u_zap.u_zap_core.o_data_wb_we)$fatal(1,"SWP write tag on read");
     swap_writes=swap_writes+1;
    end
   end
   if ($test$plusargs("swp_cached_irq") || $test$plusargs("swp_irq_core")) begin
    if(swp_irq_state==0 && dut.u_zap.u_zap_core.postalu_swp_tag==1 &&
       dut.u_zap.u_zap_core.o_data_wb_stb && dut.u_zap.u_zap_core.i_data_wb_ack) begin irq<=1;swp_irq_state=1;end
    if(swp_irq_state==1 && dut.u_zap.cpu_cpsr[4:0]==5'h12) begin irq<=0;swp_irq_state=2;end
   end
   if ($test$plusargs("swp_irq") || $test$plusargs("swp_fiq") || $test$plusargs("swp_irq_abort")) begin
    if(swp_irq_state==0 && (ack || ($test$plusargs("swp_irq_abort") && bus_error)) && !we && addr==32'h80001000) begin
     if($test$plusargs("swp_fiq")) fiq<=1; else irq<=1;
     swp_irq_state=1;
    end
    if(swp_irq_state==1 && dut.u_zap.cpu_cpsr[4:0]==($test$plusargs("swp_fiq") ? 5'h11 : 5'h12)) begin irq<=0;fiq<=0;swp_irq_state=2;end
   end
   if ($test$plusargs("fiq_privileged_store")) begin
    if(swp_irq_state==0 && dut.u_zap.cpu_cpsr[4:0]==5'h10 &&
       (!$test$plusargs("fiq_during_usrt") || dut.u_zap.cpu_mem_translate)) begin fiq<=1;swp_irq_state=1;end
    if(swp_irq_state==1 && dut.u_zap.cpu_cpsr[4:0]==5'h11) begin fiq<=0;swp_irq_state=2;end
   end
   if ($test$plusargs("wfi_test")) begin
    if(dut.u_zap.u_zap_core.u_zap_cp15_cb.state==15 && wfi_ticks==0)wfi_ticks=1;
    else if(wfi_ticks>0 && wfi_ticks<100)wfi_ticks=wfi_ticks+1;
    if(wfi_ticks==20)begin if($test$plusargs("wfi_fiq"))fiq<=1;else irq<=1;end
    if(wfi_ticks==40)begin irq<=0;fiq<=0;end
   end
`ifdef NGAGE_ASSOC_EXPERIMENT
   if(trace_valid && trace_last) begin recent_trace[recent_pos%16]=trace_text;recent_pos=recent_pos+1;end
`endif
`ifdef NGAGE_ASSOC_EXPERIMENT
   if(cycles==499999) begin
    $display("EXPERIMENT: last trace %s",trace_text);
    $display("EXPERIMENT2: mgrstate=%b d-wb=%b/%b d-ack=%b cpu_req=%b ready=%b response=%b ia=%h pa=%h translation_wait=%b",dut.u_zap.l_generate_with_cache_mmu.u_data_cache.state_ff,dut.u_zap.l_generate_with_cache_mmu.u_data_cache.o_wb_cyc,dut.u_zap.l_generate_with_cache_mmu.u_data_cache.o_wb_stb,dut.u_zap.l_generate_with_cache_mmu.u_data_cache.wb_ack[0],dut.u_zap.l_generate_with_cache_mmu.u_data_cache.experimental_cache.req_valid,dut.u_zap.l_generate_with_cache_mmu.u_data_cache.experimental_cache.req_ready,dut.u_zap.l_generate_with_cache_mmu.u_data_cache.experimental_cache.response_valid,dut.u_zap.l_generate_with_cache_mmu.u_data_cache.i_address,dut.u_zap.l_generate_with_cache_mmu.u_data_cache.tlb_phy_addr,dut.u_zap.l_generate_with_cache_mmu.u_data_cache.experimental_cache.translation_wait);
    $display("EXPERIMENT: addr=%h rd=%b wr=%b ack=%b err2=%b busy=%b launched=%b cache_state=%d bus=%b inflight=%b wb=%b/%b external=%b/%b/%b",dut.u_zap.l_generate_with_cache_mmu.u_data_cache.i_address,dut.u_zap.l_generate_with_cache_mmu.u_data_cache.i_rd,dut.u_zap.l_generate_with_cache_mmu.u_data_cache.i_wr,dut.u_zap.l_generate_with_cache_mmu.u_data_cache.o_ack,dut.u_zap.l_generate_with_cache_mmu.u_data_cache.o_err2,dut.u_zap.l_generate_with_cache_mmu.u_data_cache.tlb_busy,dut.u_zap.l_generate_with_cache_mmu.u_data_cache.experimental_cache.launched,dut.u_zap.l_generate_with_cache_mmu.u_data_cache.experimental_cache.cache.state,dut.u_zap.l_generate_with_cache_mmu.u_data_cache.experimental_cache.bus_valid,dut.u_zap.l_generate_with_cache_mmu.u_data_cache.experimental_cache.inflight,dut.u_zap.l_generate_with_cache_mmu.u_data_cache.wb_cyc[0],dut.u_zap.l_generate_with_cache_mmu.u_data_cache.wb_stb[0],cyc,stb,ack);
   end
`endif
   if(cycles>max_cycles) $fatal(1,"CPU unit test timed out");
   if (ack) bus_count=bus_count+1;
   if (ack && !we && instruction_test_addr!=0 && addr==instruction_test_addr)
      instruction_fetches=instruction_fetches+1;
   if(timing_first != 0 && trace_valid && trace_last && $sscanf(trace_text,"%h:",trace_pc)==1 &&
      trace_pc>=timing_first && trace_pc<timing_last) begin
       if(trace_pc==last_pc+4) begin
        gap=cycles-last_cycle;timing_count=timing_count+1;timing_sum=timing_sum+gap;
        if(gap<timing_min)timing_min=gap;if(gap>timing_max)timing_max=gap;
        if(gap>1) $display("STALL: ADD interval %0d cycles at PC %h sample %0d bus transfers %0d",gap,trace_pc,timing_count,bus_count-last_bus_count);
        if(timing_count>30) begin
         warm_count=warm_count+1;warm_sum=warm_sum+gap;
         if(gap<warm_min)warm_min=gap;if(gap>warm_max)warm_max=gap;
        end
       end
       last_pc=trace_pc;last_cycle=cycles;last_bus_count=bus_count;
   end
   if(bus_error && we && addr==fault_addr) fault_address_writes=fault_address_writes+1;
   if(ack && we) begin
    if(addr==fault_addr) fault_address_writes=fault_address_writes+1;
    if ($test$plusargs("cache_conflict") && addr==32'h80030100)
      $display("EVICTION: dirty first line written to memory at cycle %0d data=%h",cycles,wdata);
    if(addr>=32'h80000000 && addr<32'h80200000) begin
     for(integer i=0;i<4;i=i+1) if(sel[i]) ram[addr[20:2]][8*i+:8]<=wdata[8*i+:8];
    end else if(addr==32'hf0000004) begin
     // Optional diagnostic word; the success mailbox remains authoritative.
    end else if(addr==32'hf0000000) begin
     if ($test$plusargs("swp_dma") && (!dma_done || dma_observed!==32'haabbccdd))
      $fatal(1,"competing master observed %h done=%b",dma_observed,dma_done);
     if ($test$plusargs("swp_tags") && (locked_reads!=2 || locked_writes!=2 || locked_read_pending))
      $fatal(1,"SWP lock read=%0d write=%0d",locked_reads,locked_writes);
     if ($test$plusargs("swp_tags") && (swap_reads!=2 || swap_writes!=2))
      $fatal(1,"SWP metadata read=%0d write=%0d",swap_reads,swap_writes);
     if ($test$plusargs("swp_bufferable") && (locked_reads!=1 || locked_writes!=1 || locked_read_pending))
      $fatal(1,"bufferable SWP lock read=%0d write=%0d",locked_reads,locked_writes);
     if ($test$plusargs("swp_abort_check") && (locked_reads!=1 || locked_writes!=1 || locked_read_pending))
      $fatal(1,"SWP abort lock read=%0d write=%0d",locked_reads,locked_writes);
     if ($test$plusargs("swp_abort_check") && fault_address_writes!=1)
      $fatal(1,"SWP read aborted but write attempts=%0d",fault_address_writes);
     if(wdata!==32'h50415353) begin
`ifdef NGAGE_ASSOC_EXPERIMENT
      for(integer z=0;z<16;z=z+1) $display("RECENT %s",recent_trace[(recent_pos+z)%16]);
`endif
      $fatal(1,"CPU diagnostic failed: %h",wdata);
     end
     if(($test$plusargs("tlb_order") || $test$plusargs("tlb_order_i")) && tlb_order_stalls==0)$fatal(1,"test did not overlap a TLB walk with buffered writes");
     if(instruction_test_addr!=0 && instruction_fetches!=1)
      $fatal(1,"instruction cache fetched first line %0d times (expected once)",instruction_fetches);
     if(timing_first!=0) begin
      if(timing_count<100) $fatal(1,"insufficient timing observations: %0d",timing_count);
      $display("TIMING: ARM ADDs all: samples=%0d min=%0d max=%0d total=%0d",timing_count,timing_min,timing_max,timing_sum);
      $display("TIMING: ARM ADDs after two passes: samples=%0d min=%0d max=%0d total=%0d (ARM920 normal ADD: 1 cycle)",warm_count,warm_min,warm_max,warm_sum);
      if(warm_count<100 || warm_min!=1 || warm_max!=1)$fatal(1,"cached ARM ADD throughput regressed");
     end
     $display("PASS: CPU test, memory delay %0d, %0d cycles",latency,cycles);$finish;
    end else $fatal(1,"unexpected write %h",addr);
   end
  end
 end
 initial begin
  fault_read_only=$test$plusargs("fault_read_only");
  fault_write_only=$test$plusargs("fault_write_only");
  if (!$value$plusargs("latency=%d",latency)) latency=0;
  if (!$value$plusargs("max_cycles=%d",max_cycles)) max_cycles=500000;
  if (!$value$plusargs("fault_addr=%h",fault_addr)) fault_addr=0;
  if (!$value$plusargs("icache_first=%h",instruction_test_addr)) instruction_test_addr=0;
  if (!$value$plusargs("prefetch_expected=%d",prefetch_expected)) prefetch_expected=1;
  if (!$value$plusargs("pc_first=%h",timing_first)) timing_first=0;
  if (!$value$plusargs("pc_last=%h",timing_last)) timing_last=0;
  for(integer i=0;i<16384;i=i+1)rom[i]=0;
  for(integer i=0;i<524288;i=i+1)ram[i]=0;
  $readmemh("build/sim/unit-core/program.hex",rom);
  repeat(5) @(negedge clk);reset=0;
 end
endmodule
