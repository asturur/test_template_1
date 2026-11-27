// Read-only ARM9V2 counters. A demand response and a fill can overlap.
`define A9 dut.u_arm925t
`define UPP_CPU `A9.u_zap
`define DATA_CACHE `UPP_CPU.l_generate_with_cache_mmu.u_data_cache
`define CODE_CACHE `UPP_CPU.l_generate_with_cache_mmu.u_code_cache
`define FETCH_PIPE `UPP_CPU.g_arm9.u_arm9_core.u_front_decode.u_fetch
`define CODE_REQ `CODE_CACHE.u_zap_cache_fsm
`define DATA_REQ `DATA_CACHE.u_zap_cache_fsm
`define TAGS `DATA_CACHE.u_zap_cache_tag_ram
integer cache_window_index=0;
integer i_accepts, d_accepts, i_fills, d_fills, d_evictions, wb_words;
integer i_wait_clocks, d_wait_clocks, cp15_clocks, scan_empty_clocks, itlb, dtlb;
integer i_pushes, first_word_clocks, first_word_events, refill_clocks, refill_events;
integer cache_clock=0, fill_started=-1;
reg prior_i_fill=0, first_word_seen=0;
reg [29:0] fill_pc;
reg observing_cache=0;
wire cp15_cleaning = `UPP_CPU.cpu_dc_clean || (`DATA_CACHE.i_line_req && `DATA_CACHE.i_line_op[0]);
wire eviction_ack = `DATA_CACHE.wb_ack[0] && `DATA_REQ.state_ff[`DATA_REQ.CLEAN_SINGLE];
wire i_fill_active = `CODE_REQ.state_ff == `CODE_REQ.FETCH_SINGLE;
always @(posedge clk) if (!reset) begin
    cache_clock=cache_clock+1;
    if (i_fill_active && !prior_i_fill) begin
        fill_started=cache_clock;
        fill_pc=`CODE_REQ.address[31:2];
        first_word_seen=0;
    end
    prior_i_fill=i_fill_active;
    if (retire && retire_pc==begin_pc) begin
        observing_cache=1;
        i_accepts=0;d_accepts=0;i_fills=0;d_fills=0;d_evictions=0;wb_words=0;
        i_wait_clocks=0;d_wait_clocks=0;cp15_clocks=0;scan_empty_clocks=0;itlb=0;dtlb=0;
        i_pushes=0;first_word_clocks=0;first_word_events=0;refill_clocks=0;refill_events=0;
    end
    if (observing_cache && retire && retire_pc==end_pc) begin
        $display("CACHE_WINDOW index=%0d i_responses=%0d d_responses=%0d i_fills=%0d d_fills=%0d dirty_evictions=%0d wb_words=%0d i_wait=%0d d_wait=%0d cp15=%0d empty_groups=%0d itlb=%0d dtlb=%0d",
                 cache_window_index,i_accepts,d_accepts,i_fills,d_fills,d_evictions,wb_words,
                 i_wait_clocks,d_wait_clocks,cp15_clocks,scan_empty_clocks,itlb,dtlb);
        $display("FETCH_WINDOW index=%0d accepted=%0d first_word_clocks=%0d first_word_events=%0d refill_clocks=%0d refill_events=%0d",
                 cache_window_index,i_pushes,first_word_clocks,first_word_events,refill_clocks,refill_events);
        cache_window_index=cache_window_index+1;
        observing_cache=0;
    end
    if (observing_cache) begin
        if (`A9.dbg_fetch_valid) i_accepts=i_accepts+1;
        if (`A9.dbg_d_done) d_accepts=d_accepts+1;
        if (`A9.dbg_icache[2]) i_fills=i_fills+1;
        if (|`A9.dbg_dcache[1:0]) d_fills=d_fills+1;
        if (eviction_ack && `DATA_REQ.o_wb_cti_ff==3'b111) d_evictions=d_evictions+1;
        if (eviction_ack || `DATA_CACHE.wb_ack[1]) wb_words=wb_words+1;
        if (`A9.dbg_icache[3]) i_wait_clocks=i_wait_clocks+1;
        if (`UPP_CPU.cpu_dc_stb && !`A9.dbg_d_done) d_wait_clocks=d_wait_clocks+1;
        if (cp15_cleaning) cp15_clocks=cp15_clocks+1;
        if (`TAGS.state_ff==13'd2 && `TAGS.dirty_scan==0) scan_empty_clocks=scan_empty_clocks+1;
        if (`A9.dbg_icache[6]) itlb=itlb+1;
        if (`A9.dbg_icache[7]) dtlb=dtlb+1;
        if (`FETCH_PIPE.push) i_pushes=i_pushes+1;
        if (`A9.dbg_icache[2] && fill_started>=0) begin
            refill_clocks=refill_clocks+cache_clock-fill_started+1;
            refill_events=refill_events+1;
        end
        if (!first_word_seen && fill_started>=0 && `FETCH_PIPE.push && `UPP_CPU.cpu_iaddr[31:2]==fill_pc) begin
            first_word_clocks=first_word_clocks+cache_clock-fill_started+1;
            first_word_events=first_word_events+1;
        end
    end
    if (fill_started>=0 && `FETCH_PIPE.push && `UPP_CPU.cpu_iaddr[31:2]==fill_pc) first_word_seen=1;
end
`undef TAGS
`undef DATA_REQ
`undef CODE_CACHE
`undef CODE_REQ
`undef FETCH_PIPE
`undef DATA_CACHE
`undef UPP_CPU
`undef A9
