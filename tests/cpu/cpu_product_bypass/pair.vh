    integer pair_cert_i;
    reg pair_cert;
    wire pair_present = `LC.postalu_dav_ff && `LC.postalu1_dav_ff &&
        `LC.postalu_mem_load_ff && `LC.postalu1_mem_load_ff &&
        `LC.postalu_request_cyc && `LC.postalu1_data_wb_cyc &&
        !`LC.postalu_data_wb_we && !`LC.postalu1_data_wb_we &&
        `LC.postalu_pc_plus_8_ff != `LC.postalu1_pc_plus_8_ff;
    task pair_sample;
      begin
        pair_cert=0;
        for(pair_cert_i=0;pair_cert_i<8;pair_cert_i=pair_cert_i+1)
          if(`LK.line_result_valid[pair_cert_i] && `LK.line_result_present[pair_cert_i] &&
             `LK.line_result_tag[pair_cert_i]==`LC.postalu1_address_ff[31:5])pair_cert=1;
        if(windows==2 && pair_present)begin
          $display("PAIR_EDGE edge=%0d old_pc=%h next_pc=%h old_va=%h next_va=%h old_rd=%0d next_rd=%0d old_dest=%0d next_dest=%0d same_block=%0d next_cert=%0d trans=%0d cacheable=%0d fault=%0d pending=%0d state=%0d port=%0d collision=%0d probe=%0d probe_tag=%h result_v=%0d result_tag=%h old_offer=%0d selected_pc=%h ack=%0d fast=%0d complete=%0d complete_data=%h issue=%0d issue_pc=%h loadlock=%0d retire=%0d retire_pc=%h",cycles,`LC.postalu_pc_plus_8_ff-8,`LC.postalu1_pc_plus_8_ff-8,`LC.postalu_address_ff,`LC.postalu1_address_ff,`LC.postalu_mem_srcdest_index_ff,`LC.postalu1_mem_srcdest_index_ff,`LC.postalu_destination_index_ff,`LC.postalu1_destination_index_ff,`LC.postalu_address_ff[31:10]==`LC.postalu1_address_ff[31:10],pair_cert,!`LA.translation_wait && !`LA.tlb_busy,`LA.cacheable,`LA.fault,`LA.store_pending,`LK.state,`LK.probe_port_free,`LK.probe_read_collision,`LK.probe_read,`LK.probe_owner_tag,`LK.probe_result_valid,`LK.probe_result_tag,`LA.rd,load_selected_pc,`LA.request_ack,`LA.fast_hit,`LC.completion_valid,`LC.completion_data,`LC.u_zap_issue_main.operand_pop,`LC.u_zap_issue_main.operand_pc_plus_8_ff-8,`LC.u_zap_issue_main.load_lock,retire,retire_pc);
        end
        if(windows==2 && lr_trace>0 && lr_trace<150)begin
          if(`LC.completion_valid && `LC.postalu_dav_ff && `LC.postalu_mem_load_ff)
            $display("PAIR_COMPLETE edge=%0d pc=%h rd=%0d data=%h fault=%0d",cycles,`LC.postalu_pc_plus_8_ff-8,`LC.postalu_mem_srcdest_index_ff,`LC.completion_data,`LC.completion_fault);
          if(retire && retire_pc>=32'h10002644 && retire_pc<32'h100026a8 && `LC.u_zap_writeback.wa2!=16)
            $display("PAIR_REGISTER edge=%0d pc=%h rd=%0d data=%h",cycles,retire_pc,`LC.u_zap_writeback.wa2,`LC.u_zap_writeback.wdata2);
          if(`LK.accept_demand && `LA.wr)
            $display("PAIR_DEPSTORE edge=%0d pc=%h addr=%h data=%h",cycles,load_selected_pc,`LA.address,`LA.din);
        end
        // A new RAM read while a demand is still owned may only use the
        // fault-free older hit's completion edge. Publication stays in order.
        if(`LK.probe_read && `LK.state!=0 && `LK.state!=3 && `LK.state!=12 && `LK.state!=8 && !(`LK.state==13 && `LK.wr))begin
          if(!`LK.early_reply || `LA.fault || `LA.translation_wait || `LA.tlb_busy || `LA.store_pending!=0 || !pair_present)
            $fatal(1,"unowned load-pair RAM read");
          $display("PAIR_WORK edge=%0d old_pc=%h next_pc=%h tag=%h way=%0d word=%0d old_ack=%0d next_completed=%0d",cycles,`LC.postalu_pc_plus_8_ff-8,`LC.postalu1_pc_plus_8_ff-8,`LK.probe_owner_tag,`LK.probe_owner_way,`LC.postalu1_address_ff[4:2],`LA.request_ack,`LC.completion_valid);
        end
      end
    endtask
