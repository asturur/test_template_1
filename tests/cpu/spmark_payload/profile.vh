// Simulation observer only. Included into a COPY of tb.v, never production RTL.
// Priority buckets measure blocking-signal occupancy, not additive causal loss:
// other stages can retire concurrently. Raw signals/states may overlap.
`define PROF_CORE dut.u_zap.u_zap_core
`define PROF_ISSUE dut.u_zap.u_zap_core.u_zap_issue_main
`define PROF_DC dut.u_zap.l_generate_with_cache_mmu.u_data_cache.cache_adapter
integer prof_bucket[0:7], prof_state[0:14];
integer prof_total, prof_retire, prof_external, prof_translate, prof_response;
integer prof_read_wait, prof_write_wait, prof_redirect, prof_fetch_wait;
integer prof_hist[0:4][0:589823];
integer prof_init_b, prof_init_pc;
initial begin
    for(prof_init_b=0;prof_init_b<5;prof_init_b=prof_init_b+1)
        for(prof_init_pc=0;prof_init_pc<589824;prof_init_pc=prof_init_pc+1)
            prof_hist[prof_init_b][prof_init_pc]=0;
end
function integer prof_slot(input [31:0] pc);
    if(pc>=32'h10000000 && pc<32'h10100000)prof_slot=pc[19:2];
    else if(pc>=32'h50300000 && pc<32'h50400000)prof_slot=262144+pc[19:2];
    else if(pc<32'h40000)prof_slot=524288+pc[17:2];
    else prof_slot=-1;
endfunction
function [31:0] prof_address(input integer slot);
    if(slot<262144)prof_address=32'h10000000+slot*4;
    else if(slot<524288)prof_address=32'h50300000+(slot-262144)*4;
    else prof_address=(slot-524288)*4;
endfunction
task prof_begin;
    integer j;
    begin
        for(j=0;j<8;j=j+1)prof_bucket[j]=0;
        for(j=0;j<15;j=j+1)prof_state[j]=0;
        prof_total=0;prof_retire=0;prof_external=0;prof_translate=0;
        prof_response=0;prof_read_wait=0;prof_write_wait=0;
        prof_redirect=0;prof_fetch_wait=0;
    end
endtask
task prof_sample;
    integer bucket, slot, state_no;
    reg [31:0] owner_pc;
    begin
        prof_total=prof_total+1;
        if(retire)prof_retire=prof_retire+1;
        if((cyc && stb && !ack) || line_active)prof_external=prof_external+1;
        if(`PROF_CORE.clear_from_writeback || `PROF_CORE.clear_from_alu ||
           `PROF_CORE.clear_from_decode)prof_redirect=prof_redirect+1;
        if(`PROF_CORE.o_instr_wb_stb && `PROF_CORE.o_instr_wb_cyc &&
           !`PROF_CORE.i_instr_wb_ack)prof_fetch_wait=prof_fetch_wait+1;
        bucket=7;owner_pc=0;
        if(`PROF_CORE.data_stall)begin
            bucket=0;owner_pc=`PROF_CORE.postalu_pc_plus_8_ff-8;
            if(`PROF_CORE.o_data_wb_we)prof_write_wait=prof_write_wait+1;
            else prof_read_wait=prof_read_wait+1;
            state_no=`PROF_DC.cache.state;
            if(state_no<0 || state_no>=15)$fatal(1,"unknown data cache state");
            prof_state[state_no]=prof_state[state_no]+1;
            if(`PROF_DC.translation_wait || `PROF_DC.tlb_busy)prof_translate=prof_translate+1;
            if(`PROF_CORE.i_data_wb_ack)prof_response=prof_response+1;
        end else if(`PROF_CORE.stall_from_shifter)begin
            bucket=1;owner_pc=`PROF_CORE.u_zap_shifter_main.i_pc_ff;
        end else if(`PROF_ISSUE.operand_valid && `PROF_ISSUE.lock && `PROF_ISSUE.load_lock)begin
            bucket=2;owner_pc=`PROF_ISSUE.operand_pc_ff;
        end else if(`PROF_ISSUE.operand_valid && `PROF_ISSUE.lock && `PROF_ISSUE.shift_lock)begin
            bucket=3;owner_pc=`PROF_ISSUE.operand_pc_ff;
        end else if(`PROF_CORE.clear_from_writeback || `PROF_CORE.clear_from_alu ||
                    `PROF_CORE.clear_from_decode)bucket=4;
        else if(`PROF_CORE.stall_from_decode)bucket=5;
        else if(!`PROF_ISSUE.operand_valid)bucket=6;
        prof_bucket[bucket]=prof_bucket[bucket]+1;
        if(windows>=2)begin
            if(bucket<4)begin
                slot=prof_slot(owner_pc);
                if(slot<0)$fatal(1,"unmapped profile owner %h",owner_pc);
                prof_hist[bucket][slot]=prof_hist[bucket][slot]+1;
            end
            if(retire)begin
                slot=prof_slot(retire_pc);
                if(slot<0)$fatal(1,"unmapped retire PC %h",retire_pc);
                prof_hist[4][slot]=prof_hist[4][slot]+1;
            end
        end
    end
endtask
task prof_end;
    integer j, sum;
    begin
        sum=0;
        for(j=0;j<8;j=j+1)begin
            sum=sum+prof_bucket[j];
            $display("PROFILE_BUCKET index=%0d bucket=%0d cycles=%0d",windows,j,prof_bucket[j]);
        end
        if(sum!=cycles-start_cycle || prof_total!=cycles-start_cycle ||
           prof_retire!=retired_proxy-start_retired)$fatal(1,"profile window accounting mismatch");
        $display("PROFILE_RAW index=%0d cycles=%0d retire=%0d external_wait=%0d translation_wait=%0d response_ack=%0d read_wait=%0d write_wait=%0d redirects=%0d fetch_wait=%0d",
                 windows,prof_total,prof_retire,prof_external,prof_translate,prof_response,
                 prof_read_wait,prof_write_wait,prof_redirect,prof_fetch_wait);
        for(j=0;j<15;j=j+1)
            $display("PROFILE_STATE index=%0d state=%0d cycles=%0d",windows,j,prof_state[j]);
    end
endtask
task prof_dump;
    integer j,k;
    begin
        for(j=0;j<5;j=j+1)
            for(k=0;k<589824;k=k+1)
                if(prof_hist[j][k]>0)
                    $display("PROFILE_PC bucket=%0d pc=%08h cycles=%0d",j,prof_address(k),prof_hist[j][k]);
    end
endtask
`undef PROF_CORE
`undef PROF_ISSUE
`undef PROF_DC
