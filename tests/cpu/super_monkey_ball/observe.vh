// Passive edge sampling; no production RTL changes. All PCs are loop-relative.
`define SC dut.u_zap.u_zap_core
`define SI `SC.u_zap_issue_main
`define SA dut.u_zap.l_generate_with_cache_mmu.u_data_cache.cache_adapter
`define SB `SA.cache.bank
integer span_ops=0, span_issues=0, span_writes=0, span_accepts=0;
integer span_store_retires=0, span_last_write=-1, span_last_retire=-1;
integer span_read=0, span_write=0, span_load=0, span_shift=0, span_empty=0, span_other=0;
integer span_mla_busy=0,span_mla_s2=0,span_pipe=0,span_credit=0;
integer trace_enable=0;
reg span_wait_exit=0;
wire span_pop=`SI.operand_pop && `SI.operand_pc_plus_8_ff-8>=32'h10093e38 &&
    `SI.operand_pc_plus_8_ff-8<32'h10093e88;
wire [31:0] span_selected=(`SC.completion_next ? `SC.postalu1_pc_plus_8_ff : `SC.postalu_pc_plus_8_ff)-8;
task span_sample;
begin
    if(span_wait_exit && retire && retire_pc<32'h40000)span_wait_exit=0;
    if(start_cycle<0 && !span_wait_exit && span_pop && `SI.operand_pc_plus_8_ff-8==32'h10093e38)begin
        start_cycle=cycles;start_reads=scalar_reads;start_writes=scalar_writes;
        start_lines=line_requests;start_beats=line_beats;
        span_ops=0;span_issues=0;span_writes=0;span_accepts=0;span_store_retires=0;
        span_last_write=-1;span_last_retire=-1;
        span_read=0;span_write=0;span_load=0;span_shift=0;span_empty=0;span_other=0;
        span_mla_busy=0;span_mla_s2=0;span_pipe=0;span_credit=0;
    end
    if(start_cycle>=0)begin
        // Exclusive occupancy classification, never a sum of overlapping stalls.
        if(cycles>start_cycle)begin
            if(`SC.data_stall)begin
                if(`SC.postalu_data_wb_we)span_write=span_write+1;
                else span_read=span_read+1;
            end else if(`SI.operand_valid && `SI.lock)begin
                if(`SI.load_lock)span_load=span_load+1;
                else span_shift=span_shift+1;
            end else if(!`SI.operand_valid)span_empty=span_empty+1;
            else span_other=span_other+1;
        end
        if(span_pop)begin
            if(`SI.operand_pc_plus_8_ff-8 != 32'h10093e38 + 4*(span_issues%20))
                $fatal(1,"unexpected loop issue order");
            span_issues=span_issues+1;
        end
        if(`SA.cache.accept_demand && `SA.cache.req_write)span_accepts=span_accepts+1;
        if(`SA.cache.pipe_accept)span_pipe=span_pipe+1;
        if(`SA.store_credit_accept)span_credit=span_credit+1;
        if(!`SC.data_stall && `SC.stall_from_shifter && `SC.shifter_pc_plus_8_ff-8==32'h10093e50)begin
            span_mla_busy=span_mla_busy+1;
            if(`SC.u_zap_shifter_main.u_zap_multiply.state_ff==6'b001000 &&
                `SI.operand_valid && `SI.lock && `SI.operand_pc_plus_8_ff-8==32'h10093e54)
                span_mla_s2=span_mla_s2+1;
        end
        if(|`SB.lines.write_enable && `SB.lines.write_enable!=32'hffffffff)begin
            if($countones(`SB.lines.write_enable)!=2)$fatal(1,"unexpected scored cache mutation window=%0d mask=%h ops=%0d",windows,`SB.lines.write_enable,span_ops);
            span_writes=span_writes+1;span_last_write=cycles;
        end
        if(retire && retire_pc>=32'h10093e38 && retire_pc<32'h10093e88)begin
            if(retire_pc != 32'h10093e38+4*(span_ops%20))$fatal(1,"unexpected loop retirement order");
            span_ops=span_ops+1;
            if(retire_pc==32'h10093e6c)begin
                span_store_retires=span_store_retires+1;span_last_retire=cycles;
            end
        end
        // A bounded trace of the first scored window includes source changes and
        // the first destination line crossing. No original instruction words.
        if(trace_enable!=0 && windows==2 && span_ops<360)
            $display("SPAN_EDGE t=%0d ops=%0d issues=%0d pop=%0d opc=%0d ret=%0d rpc=%0d data=%0d oval=%0d lock=%0d ll=%0d sl=%0d shstall=%0d shpc=%0d multstate=%0d p1=%0d p2=%0d offerpc=%0d rd=%0d wr=%0d addr=%h ack=%0d accept=%0d state=%0d probe=%0d fast=%0d pending=%0d ram=%h comp=%0d fvalid=%0d fpc=%0d dec=%0d dpc=%0d aclr=%0d",
                cycles-start_cycle,span_ops,span_issues,span_pop,`SI.operand_pc_plus_8_ff-8-32'h10093e38,
                retire,retire_pc-32'h10093e38,`SC.data_stall,`SI.operand_valid,`SI.lock,`SI.load_lock,`SI.shift_lock,
                `SC.stall_from_shifter,`SC.shifter_pc_plus_8_ff-8-32'h10093e38,
                `SC.u_zap_shifter_main.u_zap_multiply.state_ff,
                `SC.postalu1_dav_ff,`SC.postalu_dav_ff,span_selected-32'h10093e38,
                `SA.rd,`SA.wr,`SA.address,`SA.request_ack,`SA.cache.accept_demand,`SA.cache.state,
                `SA.cache.probe_result_valid,`SA.fast_hit,`SA.store_pending,`SB.lines.write_enable,
                `SC.completion_valid,`SC.fetch_valid,`SC.fetch_pc_plus_8_ff-8-32'h10093e38,
                `SC.decode_condition_code!=15,`SC.decode_pc_plus_8_ff-8-32'h10093e38,`SC.clear_from_alu);
        if(span_ops==10240)begin
            // The trained final BLT can issue a killed next-iteration prefix.
            // Count it separately from the exact architectural PC stream.
            if(span_issues<10240 || span_issues>10260 || (windows>=2 && span_writes!=512) || span_accepts!=512 || span_store_retires!=512)
                $fatal(1,"loop count/mutation mismatch issues=%0d writes=%0d accepts=%0d retires=%0d",span_issues,span_writes,span_accepts,span_store_retires);
            if(`SA.store_pending!=0 || !dut.u_zap.dc_write_buffer_empty || span_last_write>cycles)
                $fatal(1,"last store not completed");
            $display("SPAN_WINDOW index=%0d cycles=%0d instructions=%0d issues=%0d accepts=%0d ram_writes=%0d store_retires=%0d last_ram=%0d last_store_retire=%0d reads=%0d writes=%0d lines=%0d beats=%0d read_stall=%0d write_stall=%0d load_lock=%0d shift_lock=%0d empty=%0d other=%0d mla_busy=%0d mla_s2_exposed=%0d store_pipe=%0d store_credit=%0d",
                windows,cycles-start_cycle,span_ops,span_issues,span_accepts,span_writes,span_store_retires,
                span_last_write<0 ? -1 : span_last_write-start_cycle,span_last_retire-start_cycle,
                scalar_reads-start_reads,scalar_writes-start_writes,line_requests-start_lines,line_beats-start_beats,
                span_read,span_write,span_load,span_shift,span_empty,span_other,
                span_mla_busy,span_mla_s2,span_pipe,span_credit);
            windows=windows+1;start_cycle=-1;span_wait_exit=1;
        end
    end
end
endtask
`undef SC
`undef SI
`undef SA
`undef SB
