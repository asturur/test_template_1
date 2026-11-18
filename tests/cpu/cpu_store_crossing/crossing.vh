// Passive pre-edge journal for every scored cycle. It drives no DUT inputs.
`define XC dut.u_zap.u_zap_core
`define XI `XC.u_zap_issue_main
`define XA dut.u_zap.l_generate_with_cache_mmu.u_data_cache.cache_adapter
`define XK `XA.cache
`define XB `XK.bank
wire [23:0] crossing_tags[0:7][0:63];
wire [26:0] crossing_pa[0:7][0:63];
genvar crossing_segment,crossing_way;
generate for(crossing_segment=0;crossing_segment<8;crossing_segment=crossing_segment+1)begin:cross_segments
    for(crossing_way=0;crossing_way<64;crossing_way=crossing_way+1)begin:cross_ways
        assign crossing_tags[crossing_segment][crossing_way]=`XB.tags.ways[crossing_way].packed_dirty_tags.tag_ram.memory[crossing_segment][23:0];
        assign crossing_pa[crossing_segment][crossing_way]=`XB.tags.physical_ram.memory[{crossing_segment[2:0],crossing_way[5:0]}];
    end
end endgenerate
integer crossing_index,crossing_matches,crossing_found;
task crossing_sample;
begin
    if(windows>=2)begin
        crossing_matches=0;crossing_found=0;
        for(crossing_index=63;crossing_index>=0;crossing_index=crossing_index-1)
            if(`XB.tags.valid[`XK.req_mva[7:5]][crossing_index] &&
               crossing_tags[`XK.req_mva[7:5]][crossing_index]==`XK.req_mva[31:8])begin
                crossing_matches=crossing_matches+1;crossing_found=crossing_index;
            end
        $display("CROSS5G w=%0d e=%0d oval=%0d opc=%h pop=%0d store=%0d base=%h addr=%h apc=%h adv=%0d rpc=%h ret=%0d selected=%h req=%0d ready=%0d accept=%0d va=%h pa=%h be=%h din=%h pending=%0d launched=%0d ack=%0d stall=%0d rstall=%0d lock=%0d ll=%0d sl=%0d state=%0d pipe=%0d pmva=%h commit=%0d credit=%0d known=%0d present=%0d pvalid=%0d ptag=%h pway=%0d pread=%0d owner=%h hit=%0d hway=%0d tagaddr=%h lookup=%h matches=%0d way=%0d tagpa=%h wm=%h ww=%0d ws=%0d wd=%h rfwen=%0d rfa=%0d rfd=%h",
            windows,cycles,`XI.operand_valid,`XI.operand_pc_ff,`XI.operand_pop,`XI.operand_mem_store_ff,
            `XI.o_alu_source_value_nxt,`XC.alu_address_ff,`XC.alu_pc_plus_8_ff-8,`XC.alu_dav_ff,
            retire_pc,retire,post_selected_pc,`XK.req_valid,`XK.req_ready,`XK.accept_demand,
            `XK.req_mva,`XK.req_physical,`XK.req_byte_enable,`XK.req_wdata,`XA.store_pending,`XA.launched,
            `XA.request_ack,`XC.data_stall,`XC.postalu_data_wb_we,`XI.lock,`XI.load_lock,`XI.shift_lock,
            `XK.state,`XK.pipe_owner,`XK.pipe_mva,`XK.pipe_commit,`XA.store_credit_accept,
            `XK.result_known,`XK.result_present,`XK.probe_result_valid,`XK.probe_result_tag,`XK.probe_result_way,
            `XK.probe_read,`XK.probe_owner_tag,`XB.hit,`XB.hit_way,`XB.tags.lookup_address,`XK.lookup_owner_mva,
            crossing_matches,crossing_found,{crossing_pa[`XK.req_mva[7:5]][crossing_found],5'b0},
            `XB.lines.write_enable,`XB.lines.write_way,`XB.lines.write_segment,`XB.lines.write_line,
            `XC.rf_wen,`XC.rf_wr_addr_a,`XC.rf_wr_data_a);
    end
end endtask
`undef XC
`undef XI
`undef XA
`undef XK
`undef XB
