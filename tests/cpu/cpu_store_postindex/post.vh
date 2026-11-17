`define PC dut.u_zap.u_zap_core
`define PI `PC.u_zap_issue_main
`define PS `PC.u_zap_shifter_main
`define PA `PC.u_zap_alu_main
`define DA dut.u_zap.l_generate_with_cache_mmu.u_data_cache.cache_adapter
`define DB `DA.cache.bank
integer post_first=-1,post_drain_start=-1,post_drain_writes=0,post_drain_index=0;
wire post_pending=!dut.u_zap.dc_write_buffer_empty || `DA.store_pending!=0;
wire [31:0] post_selected_pc=(`PC.completion_next ? `PC.postalu1_pc_plus_8_ff : `PC.postalu_pc_plus_8_ff)-8;
task post_drain;
begin
    if(post_drain_start>=0 && !post_pending)begin
        $display("DRAIN5F window=%0d extra=%0d writes=%0d",post_drain_index,cycles-post_drain_start,scalar_writes-post_drain_writes);
        post_drain_start=-1;
    end
end endtask
task post_end;
begin
    post_first=-1;post_drain_start=cycles;post_drain_writes=scalar_writes;post_drain_index=windows;
    post_drain();
end endtask
task post_sample;
begin
    if(windows==2)begin
        if(retire)$display("RET5F e=%0d pc=%h",cycles,retire_pc);
        if(`PI.operand_pop && `PI.operand_mem_store_ff && !`PI.operand_mem_pre_index_ff && !`PI.operand_mem_unsigned_byte_enable_ff && !`PI.operand_mem_unsigned_halfword_enable_ff && !`PI.operand_mem_signed_halfword_enable_ff && post_first<0)post_first=cycles;
        if(post_first>=0 && cycles-post_first<320)
            $display("POST5F e=%0d ret=%0d rpc=%h data=%0d oval=%0d opc=%h pop=%0d lock=%0d ll=%0d sl=%0d baseidx=%h basenext=%h newdata=%h dest=%0d pre=%0d byte=%0d overlap=%0d ipc=%h icc=%0d ibase=%h soff=%h spc=%h scc=%0d sbase=%h sdest=%0d sstore=%0d apre=%0d abase=%h aresult=%h aaddr=%h aval=%0d p0pc=%h p0v=%0d p0base=%h p0adr=%h p1pc=%h p1v=%0d p1base=%h p2pc=%h p2v=%0d p2base=%h offerpc=%h req=%0d ack=%0d overlap_offer=%0d pending=%0d accept=%0d credit=%0d pipe=%0d addr=%h din=%h comp=%0d fault=%0d rfwen=%0d rfa=%0d rfd=%h",
                cycles,retire,retire_pc,`PC.data_stall,`PI.operand_valid,`PI.operand_pc_ff,`PI.operand_pop,`PI.lock,`PI.load_lock,`PI.shift_lock,
                `PI.operand_alu_source_ff,`PI.o_alu_source_value_nxt,`PI.o_mem_srcdest_value_nxt,`PI.operand_destination_index_ff,
                `PI.operand_mem_pre_index_ff,`PI.operand_mem_unsigned_byte_enable_ff,`PI.operand_store_overlap,
                `PC.issue_pc_ff,`PC.issue_condition_code_ff,`PC.issue_alu_source_value_ff,`PC.issue_shift_source_value_ff,
                `PC.shifter_pc_ff,`PC.shifter_condition_code_ff,`PS.o_alu_source_value_ff,`PC.shifter_destination_index_ff,`PC.shifter_mem_store_ff,
                `PA.i_mem_pre_index_ff,`PA.rn,`PC.alu_alu_result_nxt,`PA.mem_address_nxt,`PC.alu_dav_nxt,
                `PC.alu_pc_plus_8_ff-8,`PC.alu_dav_ff,`PC.alu_alu_result_ff,`PC.alu_address_ff,
                `PC.postalu1_pc_plus_8_ff-8,`PC.postalu1_dav_ff,`PC.postalu1_alu_result_ff,
                `PC.postalu_pc_plus_8_ff-8,`PC.postalu_dav_ff,`PC.postalu_alu_result_ff,
                post_selected_pc,`DA.wr,`DA.request_ack,`PC.o_data_store_overlap,`DA.store_pending,
                `DA.cache.accept_demand,`DA.store_credit_accept,`DA.cache.pipe_accept,`DA.address,`DA.din,
                `PC.completion_valid,`PC.completion_fault,`PC.rf_wen,`PC.rf_wr_addr_a,`PC.rf_wr_data_a);
        if(`DA.cache.accept_demand && `DA.cache.req_write)
            $display("ACCEPT5F e=%0d pc=%h va=%h data=%h be=%h credit=%0d way=%0d",cycles,post_selected_pc,`DA.cache.req_mva,`DA.cache.req_wdata,`DA.cache.req_byte_enable,`DA.store_credit_accept,`DA.cache.result_way);
        if(|`DB.lines.write_enable)
            $display("WRITE5F e=%0d mask=%h way=%0d seg=%0d line=%h",cycles,`DB.lines.write_enable,`DB.lines.write_way,`DB.lines.write_segment,`DB.lines.write_line);
        if(ack && we)$display("BUS5F e=%0d addr=%h data=%h be=%h",cycles,address,wdata,be);
        if(`PC.rf_wen && `PC.rf_wr_addr_a==0)$display("BASE5F e=%0d pc=%h data=%h",cycles,`PC.memory_pc_plus_8_ff-8,`PC.rf_wr_data_a);
    end
end endtask
`undef PC
`undef PI
`undef PS
`undef PA
`undef DA
`undef DB
