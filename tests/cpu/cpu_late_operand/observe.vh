`define JC dut.u_zap.u_zap_core
`define JI `JC.u_zap_issue_main
`define JD dut.u_zap.l_generate_with_cache_mmu.u_data_cache
`define JA `JD.cache_adapter
`define JK `JA.cache
`ifdef PIPE_P1
wire j_p1=`JC.p1_load_start;
wire j_select=`JC.data_select_p1;
`else
wire j_p1=1'b0;
wire j_select=`JC.completion_valid;
`endif
`ifdef LOOKUP_PROBE
wire k_hint=`JC.lookup_alu_hint;
`else
wire k_hint=1'b0;
`endif
integer k_hints=0;
wire [31:0] j_selected=(j_select ? `JC.postalu1_pc_plus_8_ff : `JC.postalu_pc_plus_8_ff)-8;
integer j_early=0,j_requests=0,j_trace=0,span_mode=0;
integer j_window=0,j_probes=0,j_load_ack=0,j_store_ack=0,j_mutations=0,j_mutated_bytes=0;
reg j_active=0;
integer j_irq_enable=0,j_irq_count=0,j_irq_seen=0,j_device_reads=0;
reg j_irq=0;
reg j_waiting=0;
reg [31:0] j_wait_pc,j_wait_addr;
task pipeline_sample;
begin
    if(j_trace>=2 || (j_trace!=0 && windows==2 && start_cycle>=0)) begin
        if(`JI.operand_pop && `JI.late_eligible)
            $display("LATE_ACCEPT t=%0d pc=%h producer=%h rd=%0d rn=%0d rm=%0d",cycles-start_cycle,`JI.operand_pc_plus_8_ff-8,`JC.postalu1_pc_plus_8_ff-8,`JC.postalu1_mem_srcdest_index_ff,`JI.late_rn_match,`JI.late_rm_match);
        if(!`JC.data_stall && !`JC.clear_from_writeback && !`JC.clear_from_alu && (`JC.issue_late_rn || `JC.issue_late_rm))
            $display("LATE_PICKUP t=%0d pc=%h producer=%h data=%h",cycles-start_cycle,`JC.issue_pc_plus_8_ff-8,`JC.postalu_pc_plus_8_ff-8,`JC.completion_data);
        if(`JC.alu_dav_ff && !`JC.data_stall)
            $display("LATE_EXEC t=%0d pc=%h result=%h flags=%h",cycles-start_cycle,`JC.alu_pc_plus_8_ff-8,`JC.alu_address_ff,`JC.alu_flags_ff);
    end
    // This asserts packet continuity across P1 -> P2, including every wait.
    if(j_waiting && !`JC.clear_from_writeback &&
       (!`JC.completion_offer || j_selected!=j_wait_pc || `JC.o_data_wb_adr!=j_wait_addr))
        $fatal(1,"P1/P2 demand owner changed during backpressure");
    j_waiting=`JC.completion_offer && !`JC.i_data_wb_ack;
    j_wait_pc=j_selected;j_wait_addr=`JC.o_data_wb_adr;
    if(j_irq_enable!=0 && j_irq_seen==0 && `JC.completion_offer &&
       `JC.o_data_wb_adr==32'h80001004)begin
        j_irq_seen=1;j_irq_count=16;
    end
    j_irq=j_irq_count>0;
    if(j_irq_count>0)j_irq_count=j_irq_count-1;
    if(start_cycle>=0 && !j_active)begin
        k_hints=0;j_active=1;j_window=windows;j_early=0;j_requests=0;j_probes=0;
        j_load_ack=0;j_store_ack=0;j_mutations=0;j_mutated_bytes=0;
    end
    if(start_cycle>=0)begin
        if(k_hint)k_hints=k_hints+1;
        if(j_p1)j_early=j_early+1;
        if(`JC.completion_offer)j_requests=j_requests+1;
        if(`JK.probe_read)j_probes=j_probes+1;
        if(`JC.completion_offer && `JC.i_data_wb_ack)begin
            if(`JC.o_data_wb_we)j_store_ack=j_store_ack+1;
            else j_load_ack=j_load_ack+1;
        end
        if(|`JK.bank.lines.write_enable && `JK.bank.lines.write_enable!=32'hffffffff)begin
            j_mutations=j_mutations+1;j_mutated_bytes=j_mutated_bytes+$countones(`JK.bank.lines.write_enable);
        end
        if(j_trace!=0 && windows==2)begin
            if(`JI.operand_pop)$display("PIPE_ISSUE t=%0d pc=%h last=%0d",cycles-start_cycle,`JI.operand_pc_plus_8_ff-8,`JI.operand_uop_last);
            if(retire)$display("PIPE_RET t=%0d pc=%h",cycles-start_cycle,retire_pc);
            if(cycles-start_cycle<1400)
                $display("LOOKUP_EDGE t=%0d hint=%0d hpc=%h ha=%h private=%0d pa=%h p1valid=%0d p1tag=%h p2valid=%0d p2tag=%h select1=%0d portfree=%0d pair=%0d owner=%0d ptag=%h read=%0d result=%0d rtag=%h collision=%0d commit=%0d commitindex=%h",
                    cycles-start_cycle,k_hint,`JC.alu_pc_plus_8_ff-8,`JC.alu_address_ff,
                    `JC.o_data_wb_re_check,`JC.o_data_wb_adr_check,`JA.probe_p1_valid_q,`JA.probe_p1_tag_q,
                    `JA.probe_p2_valid_q,`JA.probe_p2_tag_q,`JA.select_probe_p1,`JK.probe_port_free,
                    `JA.probe_pair_q,`JK.probe_owner_valid,`JK.probe_owner_tag,`JK.probe_read,
                    `JK.probe_result_valid,`JK.probe_result_tag,`JK.probe_read_collision,
                    `JK.data_commit_valid,`JK.data_commit_index);
            if(cycles-start_cycle<1400)
                $display("PIPE_EDGE t=%0d pop=%0d ipc=%h base=%h off=%h shpc=%h apc=%h av=%0d aa=%h p0pc=%h p0a=%h p1pc=%h p1a=%h p2pc=%h p2a=%h offer=%0d opc=%h early=%0d next=%0d ack=%0d comp=%0d cf=%0d cd=%h stall=%0d ll=%0d sl=%0d oval=%0d checked=%0d trans=%0d busy=%0d walk=%0d fault=%0d cb=%0d tlbpa=%h rd=%0d wr=%0d launched=%0d pending=%0d req=%0d ready=%0d accept=%0d state=%0d probe=%0d ptag=%h prvalid=%0d indexed=%0d ramindex=%h ramvalid=%0d fast=%0d",
                    cycles-start_cycle,`JI.operand_pop,`JI.operand_pc_plus_8_ff-8,`JI.o_alu_source_value_nxt,`JI.o_shift_source_value_nxt,
                    `JC.shifter_pc_plus_8_ff-8,`JC.alu_pc_plus_8_ff-8,`JC.alu_dav_ff,`JC.alu_address_ff,
                    `JC.postalu0_pc_plus_8_ff-8,`JC.postalu0_address_ff,`JC.postalu1_pc_plus_8_ff-8,`JC.postalu1_address_ff,
                    `JC.postalu_pc_plus_8_ff-8,`JC.postalu_address_ff,`JC.completion_offer,j_selected,j_p1,`JC.completion_next,
                    `JC.i_data_wb_ack,`JC.completion_valid,`JC.completion_fault,`JC.completion_data,`JC.data_stall,
                    `JI.load_lock,`JI.shift_lock,`JI.operand_valid,`JD.checked_owner,`JD.translation_ready,
                    `JD.tlb_busy,`JD.tlb_walk_pending,`JD.tlb_fault,`JD.tlb_cacheable,`JD.tlb_phy_addr,
                    `JA.rd,`JA.wr,`JA.launched,`JA.store_pending,`JA.req_valid,`JA.req_ready,`JK.accept_demand,`JK.state,
                    `JK.probe_read,`JK.probe_owner_tag,`JK.probe_result_valid,`JK.indexed_read,
                    `JK.bank.lines.read_index,`JK.bank.read_valid,`JA.fast_hit);
        end
    end
    if(j_active && ((span_mode!=0 && windows>j_window) ||
       (span_mode==0 && retire && retire_pc==end_pc)))begin
        $display("PIPE_WINDOW index=%0d early=%0d offers=%0d probes=%0d load_acks=%0d store_acks=%0d ram_mutations=%0d mutated_bytes=%0d",
                 j_window,j_early,j_requests,j_probes,j_load_ack,j_store_ack,j_mutations,j_mutated_bytes);
        $display("LOOKUP_WINDOW index=%0d hints=%0d",j_window,k_hints);
        j_active=0;
    end
end
endtask
`undef JC
`undef JI
`undef JD
`undef JA
`undef JK
