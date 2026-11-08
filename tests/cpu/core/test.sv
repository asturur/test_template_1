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
 integer accepted_fetches=0,fetch_responses=0,accepted_issues=0,retired_instructions=0;
 reg [31:0] measure_load=0,measure_use=0,measure_branch=0,measure_target=0;
 integer load_edge=-1,branch_edge=-1,load_samples=0,branch_samples=0;
 integer load_sum=0,load_min=999999,load_max=0,branch_sum=0,branch_min=999999,branch_max=0;
 integer measured_gap;
 integer first_body_cycle=-1,init_branch_edge=-1,init_samples=0,init_sum=0,init_min=999999,init_max=0;
 reg [31:0] measure_init_branch=0,measure_init_target=0;
 integer init_store_edge=-1,init_subs_edge=-1,store_subs_sum=0,subs_branch_sum=0,store_subs_n=0,subs_branch_n=0;
 integer swp_edge=-1;
 reg sweep_at_edge;
 wire issue_transfer = !dut.u_zap.u_zap_core.data_stall && !dut.u_zap.u_zap_core.stall_from_shifter &&
   !dut.u_zap.u_zap_core.clear_from_writeback && !dut.u_zap.u_zap_core.clear_from_alu &&
   dut.u_zap.u_zap_core.issue_condition_code_ff!=4'hf;
 wire [31:0] issue_pc = dut.u_zap.u_zap_core.issue_pc_ff;
 wire retirement = dut.u_zap.u_zap_core.u_zap_writeback.i_uop_last &&
   (dut.u_zap.u_zap_core.u_zap_writeback.i_valid || dut.u_zap.u_zap_core.u_zap_writeback.i_decompile_valid) &&
   !(|dut.u_zap.u_zap_core.u_zap_writeback.i_data_abt) &&
   !dut.u_zap.u_zap_core.u_zap_writeback.i_fiq && !dut.u_zap.u_zap_core.u_zap_writeback.i_irq &&
   !dut.u_zap.u_zap_core.u_zap_writeback.i_instr_abt && !dut.u_zap.u_zap_core.u_zap_writeback.i_swi &&
   !dut.u_zap.u_zap_core.u_zap_writeback.i_und && !dut.u_zap.u_zap_core.u_zap_writeback.i_copro_reg_en;
 wire [31:0] retirement_pc = dut.u_zap.u_zap_core.u_zap_writeback.i_pc_plus_8_buf_ff - 8;
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
`ifdef NGAGE_ASSOC_EXPERIMENT
`ifndef NGAGE_OPERAND_REFERENCE
  if(dut.u_zap.u_zap_core.data_stall !==
     (dut.u_zap.u_zap_core.postalu_request_stb && dut.u_zap.u_zap_core.postalu_request_cyc && !dut.u_zap.u_zap_core.completion_valid))
   $fatal(1,"advance without an owned completion");
  if(dut.u_zap.u_zap_core.completion_valid && dut.u_zap.cpu_dc_stb)
   $fatal(1,"completed demand replayed to cache");
`endif
`endif
 end
`ifndef NGAGE_OPERAND_REFERENCE
 always @(negedge clk)if(!reset)begin
  if(dut.u_zap.u_zap_core.u_zap_writeback.i_copro_reg_en &&
     dut.u_zap.u_zap_core.u_zap_issue_main.operand_push &&
     !dut.u_zap.u_zap_core.clear_from_writeback && !dut.u_zap.u_zap_core.clear_from_alu)
   $fatal(1,"CP15 operation overlapped meaningful operand acquisition");
  if(dut.u_zap.u_zap_core.operand_busy && !dut.u_zap.u_zap_core.pipeline_is_not_empty)
   $fatal(1,"CP15 drain ignored an owned operand packet");
 end
`endif
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
   if(observed_fetch)fetch_responses=fetch_responses+1;
   if(dut.u_zap.u_zap_core.u_zap_fetch_main.i_valid && !dut.u_zap.u_zap_core.code_stall &&
      !dut.u_zap.u_zap_core.u_zap_fetch_main.sleep_ff &&
      !dut.u_zap.u_zap_core.clear_from_writeback && !dut.u_zap.u_zap_core.clear_from_alu &&
      !dut.u_zap.u_zap_core.clear_from_decode)accepted_fetches=accepted_fetches+1;
   if(issue_transfer)begin
    accepted_issues=accepted_issues+1;
    if(timing_first!=0 && issue_pc==timing_first && first_body_cycle<0)first_body_cycle=cycles;
    if(measure_init_target!=0 && issue_pc==measure_init_target)init_store_edge=cycles;
    if(measure_init_target!=0 && issue_pc==measure_init_target+4 && init_store_edge>=0)begin
     store_subs_sum+=cycles-init_store_edge;store_subs_n++;init_subs_edge=cycles;init_store_edge=-1;
    end
    if(measure_init_branch!=0 && issue_pc==measure_init_branch)begin
     init_branch_edge=cycles;
     if(init_subs_edge>=0)begin subs_branch_sum+=cycles-init_subs_edge;subs_branch_n++;init_subs_edge=-1;end
    end
    if(measure_init_target!=0 && issue_pc==measure_init_target && init_branch_edge>=0)begin
     measured_gap=cycles-init_branch_edge;init_samples++;init_sum+=measured_gap;
     if(measured_gap<init_min)init_min=measured_gap;if(measured_gap>init_max)init_max=measured_gap;
     init_branch_edge=-1;
    end
    if(measure_load!=0 && issue_pc==measure_load)load_edge=cycles;
    if(measure_use!=0 && issue_pc==measure_use && load_edge>=0)begin
     measured_gap=cycles-load_edge;load_samples++;load_sum+=measured_gap;
     if(measured_gap<load_min)load_min=measured_gap;if(measured_gap>load_max)load_max=measured_gap;
     load_edge=-1;
    end
    if(measure_branch!=0 && issue_pc==measure_branch)branch_edge=cycles;
    if(measure_target!=0 && issue_pc==measure_target && branch_edge>=0)begin
     measured_gap=cycles-branch_edge;branch_samples++;branch_sum+=measured_gap;
     if(measured_gap<branch_min)branch_min=measured_gap;if(measured_gap>branch_max)branch_max=measured_gap;
     branch_edge=-1;
    end
   end
   if($test$plusargs("schedule_trace") && first_body_cycle>=0)begin
    $display("SCHEDULE %0d F=%08h D=%08h R=%0d:%08h:%0d:%0d I=%0d:%08h stalls=%0d%0d clear=%0d%0d%0d",
     cycles,observed_pc,dut.u_zap.u_zap_core.u_zap_issue_main.i_pc_ff,
     dut.u_zap.u_zap_core.u_zap_issue_main.operand_valid,
     dut.u_zap.u_zap_core.u_zap_issue_main.operand_valid ? dut.u_zap.u_zap_core.u_zap_issue_main.operand_pc_ff : 0,
     dut.u_zap.u_zap_core.u_zap_issue_main.operand_push,dut.u_zap.u_zap_core.u_zap_issue_main.operand_pop,
     issue_transfer,issue_transfer ? issue_pc : 0,
     dut.u_zap.u_zap_core.data_stall,dut.u_zap.u_zap_core.stall_from_shifter,
     dut.u_zap.u_zap_core.clear_from_writeback,dut.u_zap.u_zap_core.clear_from_alu,dut.u_zap.u_zap_core.clear_from_decode);
   end
   if(retirement) retired_instructions=retired_instructions+1;
   // Structured architectural effects for latency-insensitive reference comparison.
   // Observe selected effective RF writes, not decompile text or guessed retirement.
   if($test$plusargs("effect_trace"))begin
    for(integer r=0;r<40;r++)if(r!=16)begin
     if(dut.u_zap.u_zap_core.i_dc_reg_idx[r])
      $display("EFFECT RF %0d %08h",r,dut.u_zap.u_zap_core.i_dc_reg_dat);
     else if(dut.u_zap.u_zap_core.u_zap_writeback.wen && dut.u_zap.u_zap_core.u_zap_writeback.wa2==r)
      $display("EFFECT RF %0d %08h",r,dut.u_zap.u_zap_core.u_zap_writeback.wdata2);
     else if(dut.u_zap.u_zap_core.u_zap_writeback.wen && dut.u_zap.u_zap_core.u_zap_writeback.wa1==r)
      $display("EFFECT RF %0d %08h",r,dut.u_zap.u_zap_core.u_zap_writeback.wdata1);
    end
    if(retirement)$display("EFFECT RETIRE %08h %08h",retirement_pc,dut.u_zap.u_zap_core.u_zap_writeback.cpsr_nxt);
   end
`ifndef NGAGE_OPERAND_REFERENCE
   // Sweep interrupt arrival through every new acquisition/execution boundary.
   // Program checks that handler sees either whole pre-SWP or whole post-SWP state.
   sweep_at_edge=0;
   case(swp_edge)
    0:sweep_at_edge=dut.u_zap.u_zap_core.decode_swp_tag==1;
    1:sweep_at_edge=dut.u_zap.u_zap_core.u_zap_issue_main.operand_valid && dut.u_zap.u_zap_core.u_zap_issue_main.operand_swp_tag==1;
    2:sweep_at_edge=dut.u_zap.u_zap_core.issue_swp_tag==1;
    3:sweep_at_edge=dut.u_zap.u_zap_core.shifter_swp_tag==1;
    4:sweep_at_edge=dut.u_zap.u_zap_core.alu_swp_tag==1;
    5:sweep_at_edge=dut.u_zap.u_zap_core.postalu0_swp_tag==1;
    6:sweep_at_edge=dut.u_zap.u_zap_core.postalu1_swp_tag==1;
    7:sweep_at_edge=dut.u_zap.u_zap_core.postalu_swp_tag==1;
    8:sweep_at_edge=dut.u_zap.u_zap_core.postalu_swp_tag==2;
    9:sweep_at_edge=dut.u_zap.u_zap_core.completion_valid && dut.u_zap.u_zap_core.postalu_swp_tag==1;
    10:sweep_at_edge=dut.u_zap.u_zap_core.completion_valid && dut.u_zap.u_zap_core.postalu_swp_tag==2;
    default:sweep_at_edge=0;
   endcase
   if(swp_edge>=0)begin
    if(swp_irq_state==0 && sweep_at_edge)begin
     if($test$plusargs("sweep_fiq"))fiq<=1;else irq<=1;
     swp_irq_state=1;
    end
    if(swp_irq_state==1 && dut.u_zap.cpu_cpsr[4:0]==($test$plusargs("sweep_fiq")?5'h11:5'h12))begin
     irq<=0;fiq<=0;swp_irq_state=2;
    end
   end
`endif
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
   if(timing_first != 0 && retirement &&
      retirement_pc>=timing_first && retirement_pc<timing_last) begin
       trace_pc=retirement_pc;
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
     if(swp_edge>=0 && swp_irq_state!=2)$fatal(1,"interrupt sweep did not complete");
     if(first_body_cycle>=0)$display("INIT_EDGES: store_to_subs samples=%0d sum=%0d subs_to_branch samples=%0d sum=%0d",store_subs_n,store_subs_sum,subs_branch_n,subs_branch_sum);
     if(first_body_cycle>=0)$display("PHASES: setup=%0d body=%0d init_branch samples=%0d sum=%0d min=%0d max=%0d",first_body_cycle,cycles-first_body_cycle,init_samples,init_sum,init_min,init_max);
     if(measure_load!=0)begin
      if(load_samples<5 || branch_samples<5)$fatal(1,"insufficient operand timing samples");
      $display("METRICS: load_use samples=%0d sum=%0d min=%0d max=%0d branch_target samples=%0d sum=%0d min=%0d max=%0d",load_samples,load_sum,load_min,load_max,branch_samples,branch_sum,branch_min,branch_max);
     end
     $display("COUNTERS: fetch_response=%0d fetch_accept=%0d issue=%0d retire_uop_last=%0d",fetch_responses,accepted_fetches,accepted_issues,retired_instructions);
     $display("PASS: CPU test, memory delay %0d, %0d cycles",latency,cycles);$finish;
    end else $fatal(1,"unexpected write %h",addr);
   end
  end
 end
 initial begin
  fault_read_only=$test$plusargs("fault_read_only");
  fault_write_only=$test$plusargs("fault_write_only");
  if (!$value$plusargs("latency=%d",latency)) latency=0;
  if (!$value$plusargs("swp_edge=%d",swp_edge))swp_edge=-1;
  if (!$value$plusargs("measure_init_branch=%h",measure_init_branch))measure_init_branch=0;
  if (!$value$plusargs("measure_init_target=%h",measure_init_target))measure_init_target=0;
  if (!$value$plusargs("measure_load=%h",measure_load))measure_load=0;
  if (!$value$plusargs("measure_use=%h",measure_use))measure_use=0;
  if (!$value$plusargs("measure_branch=%h",measure_branch))measure_branch=0;
  if (!$value$plusargs("measure_target=%h",measure_target))measure_target=0;
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
