`define DTLB dut.u_zap.l_generate_with_cache_mmu.u_data_cache.u_zap_tlb
`define ITLB dut.u_zap.l_generate_with_cache_mmu.u_code_cache.u_zap_tlb
`define CORE dut.u_zap.u_zap_core
`define ISSUE `CORE.u_zap_issue_main
`define CACHE dut.u_zap.l_generate_with_cache_mmu.u_data_cache.cache_adapter
`ifdef THIRD_SLOT
wire third_selected = `DTLB.use_third;
`else
wire third_selected = 0;
`endif
wire d_done = `CORE.completion_offer && `CORE.i_data_wb_ack;
wire [31:0] d_address = `CORE.o_data_wb_adr;
wire [31:0] issue_pc = `ISSUE.operand_pc_plus_8_ff - 8;
integer dsearch, isearch, dwalk, iwalk, l1beats, l2beats;
integer dlocal1, dlocal2, dlocal3, dmiss, dother, dhold, hold, stores;
integer total_dsearch=0,total_isearch=0,total_dwalk=0,total_iwalk=0,total_dhold=0;
integer trace_mode=0, stream_mode=0, first_start, last_start, useful_starts;
reg search_pending=0;
reg [31:0] search_address;
reg [63:0] pc_hash, memory_hash;

task mapping_begin;
    begin
        dsearch=0; isearch=0; dwalk=0; iwalk=0; l1beats=0; l2beats=0;
        dlocal1=0; dlocal2=0; dlocal3=0; dmiss=0; dother=0; dhold=0; hold=0; stores=0;
        useful_starts=0; first_start=0; last_start=0;
        pc_hash=64'hcbf29ce484222325; memory_hash=64'hcbf29ce484222325;
    end
endtask

task mapping_sample;
    reg d_walk_start, i_walk_start, d_block, missed;
    integer slot;
    begin
        d_walk_start = `DTLB.state==1 && `DTLB.bank_valid && !`DTLB.bank_hit && !`DTLB.obsolete;
        i_walk_start = `ITLB.state==1 && `ITLB.bank_valid && !`ITLB.bank_hit && !`ITLB.obsolete;
        d_block = `CORE.data_stall && `CORE.completion_offer && `DTLB.o_busy;
        if (`DTLB.mutation || !`DTLB.i_mmu_en) search_pending=0;
        if (`DTLB.bank_lookup) begin
            search_pending=1;
            search_address=`DTLB.i_address;
        end
        missed=search_pending && search_address==`DTLB.i_address;
        slot=third_selected ? 3 : `DTLB.use_second ? 2 : `DTLB.primary_match ? 1 : 0;
        total_dsearch=total_dsearch+int'(`DTLB.bank_lookup);
        total_isearch=total_isearch+int'(`ITLB.bank_lookup);
        total_dwalk=total_dwalk+int'(d_walk_start);
        total_iwalk=total_iwalk+int'(i_walk_start);
        total_dhold=total_dhold+int'(d_block);
        if (start_cycle>=0) begin
            dsearch=dsearch+int'(`DTLB.bank_lookup);
            isearch=isearch+int'(`ITLB.bank_lookup);
            dwalk=dwalk+int'(d_walk_start);
            iwalk=iwalk+int'(i_walk_start);
            l1beats=l1beats+int'(`DTLB.state==2 && `DTLB.i_wb_ack);
            l2beats=l2beats+int'(`DTLB.state==4 && `DTLB.i_wb_ack);
            dhold=dhold+int'(d_block);
            hold=hold+int'(`CORE.data_stall);
            if(d_done) begin
                if(missed) dmiss=dmiss+1;
                else case(slot)
                    1: dlocal1=dlocal1+1;
                    2: dlocal2=dlocal2+1;
                    3: dlocal3=dlocal3+1;
                    default: dother=dother+1;
                endcase
                if(`CORE.o_data_wb_we) begin
                    stores=stores+1;
                    memory_hash=(memory_hash ^ {32'b0,d_address}) * 64'h100000001b3;
                    memory_hash=(memory_hash ^ {28'b0,`CORE.o_data_wb_sel,`CORE.o_data_wb_dat}) * 64'h100000001b3;
                end
                if(trace_mode==2 && windows==2)
                    $display("D_ACCESS va=%08h slot=%0d miss=%0d wr=%0d",`DTLB.i_address,slot,missed,`CORE.o_data_wb_we);
            end
            if(retire && retire_pc>=payload_base && retire_pc<payload_base+32'h100000)
                pc_hash=(pc_hash ^ {32'b0,retire_pc}) * 64'h100000001b3;
            if(stream_mode!=0 && `ISSUE.operand_pop && issue_pc>=32'h10000048 && issue_pc<32'h100003c8) begin
                if(useful_starts==0) first_start=cycles;
                last_start=cycles;
                useful_starts=useful_starts+1;
            end
            if(trace_mode!=0 && windows==2 && cycles-start_cycle<1400)
                $display("D_EDGE t=%0d issue=%0d pc=%08h offer=%0d ack=%0d va=%08h search=%0d slot=%0d busy=%0d data=%0d lock=%0d load_lock=%0d cache_state=%0d probe=%0d operand=%0d",
                    cycles-start_cycle,`ISSUE.operand_pop,issue_pc,`CORE.completion_offer,d_done,d_address,
                    `DTLB.bank_lookup,slot,`DTLB.o_busy,`CORE.data_stall,`ISSUE.lock,`ISSUE.load_lock,
                    `CACHE.cache.state,`CACHE.cache.probe_result_valid,`ISSUE.operand_valid);
        end
        if(d_done) search_pending=0;
    end
endtask

task mapping_end;
    begin
        $display("MAP_WINDOW index=%0d dsearch=%0d isearch=%0d dwalk=%0d iwalk=%0d l1beats=%0d l2beats=%0d hit1=%0d hit2=%0d hit3=%0d misses=%0d other=%0d dhold=%0d hold=%0d stores=%0d starts=%0d start_clocks=%0d",
            windows,dsearch,isearch,dwalk,iwalk,l1beats,l2beats,dlocal1,dlocal2,dlocal3,dmiss,dother,
            dhold,hold,stores,useful_starts,useful_starts>0 ? last_start-first_start+1 : 0);
        $display("MAP_EFFECT index=%0d pc=%016h stores=%016h",windows,pc_hash,memory_hash);
    end
endtask

task mapping_total;
    $display("MAP_TOTAL dsearch=%0d isearch=%0d dwalk=%0d iwalk=%0d dhold=%0d",
        total_dsearch,total_isearch,total_dwalk,total_iwalk,total_dhold);
endtask
`undef DTLB
`undef ITLB
`undef CORE
`undef ISSUE
`undef CACHE
