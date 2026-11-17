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
    if(pc>=32'h50500000 && pc<32'h50600000)prof_slot=pc[19:2];
    else if(pc>=32'h50300000 && pc<32'h50400000)prof_slot=262144+pc[19:2];
    else if(pc<32'h40000)prof_slot=524288+pc[17:2];
    else prof_slot=-1;
endfunction
function [31:0] prof_address(input integer slot);
    if(slot<262144)prof_address=32'h50500000+slot*4;
    else if(slot<524288)prof_address=32'h50300000+(slot-262144)*4;
    else prof_address=(slot-524288)*4;
endfunction
task original_prof_begin;
    integer j;
    begin
        for(j=0;j<8;j=j+1)prof_bucket[j]=0;
        for(j=0;j<15;j=j+1)prof_state[j]=0;
        prof_total=0;prof_retire=0;prof_external=0;prof_translate=0;
        prof_response=0;prof_read_wait=0;prof_write_wait=0;
        prof_redirect=0;prof_fetch_wait=0;
    end
endtask
task original_prof_sample;
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
task original_prof_end;
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

`define FC dut.u_zap.u_zap_core
`define FI dut.u_zap.u_zap_core.u_zap_issue_main
integer front_age, front_total, front_recent5,front_recent10,front_recent20,front_old;
integer front_retire,front_nofifo,front_nomode,front_nopre,front_nodecode,front_calu,front_cwb,front_cdec;
task prof_begin;
begin
 original_prof_begin();front_age=1000;front_total=0;front_recent5=0;front_recent10=0;front_recent20=0;front_old=0;
 front_retire=0;front_nofifo=0;front_nomode=0;front_nopre=0;front_nodecode=0;front_calu=0;front_cwb=0;front_cdec=0;
end endtask
task prof_sample;
begin
 original_prof_sample();
 if(windows==2)begin
  // Sample the ALU's actual acceptance condition; registered clear alone can
  // be held by a data stall and would count the same outcome more than once.
  if(!`FC.u_zap_alu_main.i_reset && !`FC.clear_from_writeback && !`FC.data_stall &&
     !(`FC.u_zap_alu_main.i_data_mem_fault || `FC.u_zap_alu_main.sleep_ff) &&
     !`FC.u_zap_alu_main.o_clear_from_alu && `FC.u_zap_alu_main.branch_instruction)
   $display("ATTR_ALU cycle=%0d pc=%08h pc8=%08h thumb=%0d opcode=%0d taken=%0d predicted=%08h target=%08h rm=%08h clear=%0d confirm=%0d switch=%0d flags=%0d",
    cycles,`FC.u_zap_alu_main.i_pc_ff,`FC.u_zap_alu_main.i_pc_plus_8_ff,`FC.u_zap_alu_main.flags_ff[5],
    `FC.u_zap_alu_main.opcode,`FC.u_zap_alu_main.i_taken_ff,`FC.u_zap_alu_main.i_ppc_ff,
    `FC.u_zap_alu_main.tmp_sum,`FC.u_zap_alu_main.rm,`FC.u_zap_alu_main.w_clear_from_alu,
    `FC.u_zap_alu_main.w_confirm_from_alu,`FC.u_zap_alu_main.i_switch_ff,`FC.u_zap_alu_main.i_flag_update_ff);
  if(!`FC.u_zap_predecode.i_reset && !`FC.clear_from_writeback &&
     !(`FC.clear_from_alu && !`FC.data_stall) &&
     !`FC.u_zap_predecode.o_clear_from_decode && !`FC.u_zap_predecode.stall &&
     !`FC.u_zap_predecode.mem_fetch_stall &&
     `FC.u_zap_predecode.mode32_instruction_valid &&
     (`FC.u_zap_predecode.w_clear_from_decode ||
      `FC.u_zap_predecode.ras_ptr_nxt!=`FC.u_zap_predecode.ras_ptr_ff))
   $display("ATTR_DEC cycle=%0d pc=%08h pc8=%08h instruction=%09h taken=%0d predicted=%09h target=%08h clear=%0d ras_before=%0d ras_after=%0d",
    cycles,`FC.u_zap_predecode.skid_pc_ff,`FC.u_zap_predecode.skid_pc_plus_8_ff,
    `FC.u_zap_predecode.mode32_instruction,`FC.u_zap_predecode.skid_taken,
    `FC.u_zap_predecode.skid_pred,`FC.u_zap_predecode.w_pc_from_decode,
    `FC.u_zap_predecode.w_clear_from_decode,`FC.u_zap_predecode.ras_ptr_ff,
    `FC.u_zap_predecode.ras_ptr_nxt);
 end

 if(`FC.clear_from_alu || `FC.clear_from_writeback || `FC.clear_from_decode)front_age=0;
 else if(front_age<1000)front_age=front_age+1;
 if(`FC.clear_from_alu)front_calu=front_calu+1;
 if(`FC.clear_from_writeback)front_cwb=front_cwb+1;
 if(`FC.clear_from_decode)front_cdec=front_cdec+1;
 if(!`FC.data_stall && !`FC.stall_from_shifter && !`FI.operand_valid &&
    !`FC.clear_from_alu && !`FC.clear_from_writeback && !`FC.clear_from_decode && !`FC.stall_from_decode)begin
  front_total=front_total+1;
  if(front_age<=5)front_recent5=front_recent5+1;
  else if(front_age<=10)front_recent10=front_recent10+1;
  else if(front_age<=20)front_recent20=front_recent20+1;
  else front_old=front_old+1;
  if(retire)front_retire=front_retire+1;
  if(!`FC.fifo_valid)front_nofifo=front_nofifo+1;
  if(!`FC.mode16_valid)front_nomode=front_nomode+1;
  if(!`FC.predecode_val)front_nopre=front_nopre+1;
  if(`FC.decode_condition_code==4'hf)front_nodecode=front_nodecode+1;
 end
end endtask
task prof_end;
begin
 if(front_total!=prof_bucket[6])$fatal(1,"frontend bucket classification differs");
 $display("FRONTEND index=%0d empty=%0d age1to5=%0d age6to10=%0d age11to20=%0d age21plus=%0d concurrent_retire=%0d nofifo=%0d nomode=%0d nopre=%0d nodecode=%0d clear_alu=%0d clear_wb=%0d clear_decode=%0d",windows,front_total,front_recent5,front_recent10,front_recent20,front_old,front_retire,front_nofifo,front_nomode,front_nopre,front_nodecode,front_calu,front_cwb,front_cdec);
 original_prof_end();
end endtask
`undef FC
`undef FI
