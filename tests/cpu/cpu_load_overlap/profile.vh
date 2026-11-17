    `define LC dut.u_zap.u_zap_core
    `define LD dut.u_zap.l_generate_with_cache_mmu.u_data_cache
    `define LA `LD.cache_adapter
    `define LK `LA.cache
    reg lr_active=0,lr_cert,lr_present;
    reg [31:0] lr_pc,lr_addr;
    integer lr_start,lr_pending,lr_tlb,lr_storewait,lr_probe,lr_accept,lr_admit,lr_fast,lr_hit,lr_external;
    integer lr_total=0,lr_certified=0,lr_uncertified=0,lr_trace=0,lr_latency=0,lr_pending_first;
    wire [31:0] load_selected_pc=(`LC.completion_next ? `LC.postalu1_pc_plus_8_ff : `LC.postalu_pc_plus_8_ff)-8;
    task load_begin;
      begin lr_active=0;lr_total=0;lr_certified=0;lr_uncertified=0;lr_trace=0;lr_latency=0;end
    endtask
    task load_sample;
      begin
        if(`LA.rd && !`LA.wr)begin
          if(!lr_active || lr_pc!=load_selected_pc || lr_addr!=`LA.address)begin
            if(lr_active)$fatal(1,"profile read owner changed without ACK");
            lr_active=1;lr_pc=load_selected_pc;lr_addr=`LA.address;lr_start=cycles;
            lr_cert=`LK.result_known;lr_present=`LK.result_present;lr_pending_first=`LA.store_pending;
            lr_tlb=0;lr_storewait=0;lr_probe=0;lr_accept=-1;lr_admit=0;lr_fast=0;lr_hit=0;lr_external=0;
          end
          if(`LA.translation_wait || `LA.tlb_busy)lr_tlb=lr_tlb+1;
          if(`LA.store_pending!=0)lr_storewait=lr_storewait+1;
          if(`LK.probe_read)lr_probe=lr_probe+1;
          if(`LK.accept_demand)begin lr_accept=cycles-lr_start;lr_admit=`LK.use_indexed_read && `LK.probe_read && `LK.probe_owner_tag==`LK.req_mva[31:5] && `LK.probe_owner_way==`LK.result_way;end
          if(`LK.state==1 && `LK.bank.hit)lr_hit=1;
          if(cyc && stb && ack && !code)lr_external=lr_external+1;
          if(`LA.request_ack)begin
            lr_fast=`LA.fast_hit;lr_total=lr_total+1;lr_latency=lr_latency+cycles-lr_start;
            if(lr_cert && lr_present)lr_certified=lr_certified+1;else lr_uncertified=lr_uncertified+1;
            if(windows==2)$display("LOAD_CASE pc=%h addr=%h certified=%0d present=%0d pending_first=%0d latency=%0d translation_wait=%0d store_wait=%0d probe_reads=%0d accept_delta=%0d admit=%0d fast=%0d lookup_hit=%0d external=%0d",lr_pc,lr_addr,lr_cert,lr_present,lr_pending_first,cycles-lr_start,lr_tlb,lr_storewait,lr_probe,lr_accept,lr_admit,lr_fast,lr_hit,lr_external);
            lr_active=0;
          end
        end
        if(windows==2 && ((lr_trace>0 && lr_trace<150) || (lr_trace==0 && ((`LA.rd && load_selected_pc>=32'h10000000 && load_selected_pc<32'h10100000) || (`LC.alu_dav_ff && `LC.alu_data_wb_cyc && !`LC.alu_data_wb_we && `LC.alu_pc_plus_8_ff>=32'h10000008 && `LC.alu_pc_plus_8_ff<32'h10100000)))))begin
          $display("LOAD_EDGE n=%0d edge=%0d alupc=%h aluaddr=%h aluread=%0d p1pc=%h p1addr=%h p1read=%0d p2pc=%h selected=%h addr=%h rd=%0d pending=%0d tlb_owner=%0d tlb_primary=%0d tlb_second=%0d tlb_state=%0d tlb_bank_valid=%0d tlb_bank_hit=%0d trans_wait=%0d tlb_busy=%0d fault=%0d read_permission=%0d cacheable=%0d hit=%0d ram_slot=%0d cert=%0d present=%0d cert_way=%0d hint=%h hint_v=%0d read=%0d port=%0d collision=%0d result_v=%0d result_tag=%h result_way=%0d fast=%0d req=%0d ready=%0d accept=%0d state=%0d indexed=%0d adm=%0d ack=%0d complete=%0d stall=%0d issuepc=%h issue=%0d loadlock=%0d",lr_trace,cycles,`LC.alu_pc_plus_8_ff-8,`LC.alu_address_ff,`LC.alu_dav_ff && `LC.alu_data_wb_cyc && !`LC.alu_data_wb_we,`LC.postalu1_pc_plus_8_ff-8,`LD.i_address_check,`LD.i_rd_check,`LC.postalu_pc_plus_8_ff-8,load_selected_pc,`LA.address,`LA.rd,`LA.store_pending,`LD.checked_owner,`LD.u_zap_tlb.primary_match,`LD.u_zap_tlb.second_match,`LD.u_zap_tlb.state,`LD.u_zap_tlb.bank_valid,`LD.u_zap_tlb.bank_hit,`LA.translation_wait,`LA.tlb_busy,`LA.fault,`LD.u_zap_tlb.read_allowed,`LA.cacheable,`LK.bank.hit,`LK.bank.lines.read_index,`LK.result_known,`LK.result_present,`LK.result_way,`LK.probe_owner_tag,`LK.probe_owner_valid,`LK.probe_read,`LK.probe_port_free,`LK.probe_read_collision,`LK.probe_result_valid,`LK.probe_result_tag,`LK.probe_result_way,`LA.fast_hit,`LA.req_valid,`LA.req_ready,`LK.accept_demand,`LK.state,`LK.use_indexed_read,`LK.admitted_probe_owner,`LA.request_ack,`LC.completion_valid,`LC.data_stall,`LC.u_zap_issue_main.operand_pc_plus_8_ff-8,`LC.u_zap_issue_main.operand_pop,`LC.u_zap_issue_main.load_lock);
          lr_trace=lr_trace+1;
        end
      end
    endtask
    task load_end;
      begin
        if(lr_active)$fatal(1,"profile unfinished read at window end");
        $display("LOAD_PROFILE index=%0d total=%0d certified=%0d uncertified=%0d sum_offer_to_ack=%0d",windows,lr_total,lr_certified,lr_uncertified,lr_latency);
      end
    endtask
