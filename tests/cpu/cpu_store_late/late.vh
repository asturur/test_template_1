    integer lf_a=0,lf_w=0,lf_i;
    reg lf_transpose=0;
    reg [31:0] lf_pc[0:2047],lf_va[0:2047],lf_data[0:2047];
    reg [5:0] lf_way[0:2047];
    reg [3:0] lf_mask[0:2047];
    task late_begin;begin lf_a=0;lf_w=0;lf_transpose=0;
`ifdef BENCH_STORE_LATE
      la_count=0;la_addr_count=0;la_data_count=0;la_accept_count=0;
`endif
end endtask
    task late_sample;
      begin
        if(windows==2)begin
          if(`LC.alu_dav_ff && `LC.alu_pc_plus_8_ff-8==32'h10002644)lf_transpose=1;
          if(lf_transpose && (|`LK.bank.lines.write_enable) && lf_w>=lf_a)
            $fatal(1,"duplicate/unowned transpose RAM write");
`ifdef BENCH_STORE_LATE
          late_owned_sample();
`endif
          if(`LK.pipe_accept)begin
            if(lf_a>=2048)$fatal(1,"late physical queue bound");
            lf_pc[lf_a]=load_selected_pc;lf_va[lf_a]=`LA.address;lf_data[lf_a]=`LA.din;
            lf_way[lf_a]=`LK.result_way;lf_mask[lf_a]=`LA.ben;lf_a=lf_a+1;
            $display("LATE_ACCEPT edge=%0d pc=%h addr=%h data=%h way=%0d pending=%0d cache_state=%0d",cycles,load_selected_pc,`LA.address,`LA.din,`LK.result_way,`LA.store_pending,`LK.state);
          end
          if((|`LK.bank.lines.write_enable) && lf_w<lf_a)begin
            if({`LK.bank.lines.write_way,`LK.bank.lines.write_segment}!=={lf_way[lf_w],lf_va[lf_w][7:5]} ||
               `LK.bank.lines.write_enable!==(32'hf << (lf_va[lf_w][4:2]*4)) ||
               `LK.bank.lines.write_line[lf_va[lf_w][4:2]*32+:32]!==lf_data[lf_w])$fatal(1,"late store actual RAM order/address/mask/data");
            $display("LATE_WRITE edge=%0d pc=%h addr=%h data=%h way=%0d",cycles,lf_pc[lf_w],lf_va[lf_w],lf_data[lf_w],lf_way[lf_w]);lf_w=lf_w+1;
          end
          if(`IS.operand_valid && `IS.operand_store_overlap && `IS.operand_mem_store_ff &&
             `IS.o_load_pair_class && `IS.o_condition_code_ff==14 && `IS.o_mem_load_ff &&
             `IS.o_pc_plus_8_ff+4==`IS.operand_pc_plus_8_ff &&
             `IS.o_mem_srcdest_index_ff==`IS.operand_mem_srcdest_index_ff)
            $display("LATE_OPPORTUNITY edge=%0d store=%h producer=%h base=%h offset=%h rd=%0d pop=%0d stall=%0d lock=%0d",cycles,`IS.operand_pc_plus_8_ff-8,`IS.o_pc_plus_8_ff-8,`IS.o_alu_source_value_nxt,`IS.o_shift_source_value_nxt,`IS.operand_mem_srcdest_index_ff,`IS.operand_pop,`LC.data_stall,`IS.load_lock);
        end
      end
    endtask
    task late_end;
      begin
        if(windows==2)begin
          if(lf_a!=lf_w)$fatal(1,"late physical owner not drained at window end");
          $display("LATE_PHYSICAL accepted=%0d written=%0d",lf_a,lf_w);
`ifdef BENCH_STORE_LATE
          if(la_count!=la_addr_count || la_count!=la_data_count || la_count!=la_accept_count)$fatal(1,"late owner ledger incomplete");
          $display("LATE_OWNERS issued=%0d address=%0d exact_data=%0d accepted=%0d",la_count,la_addr_count,la_data_count,la_accept_count);
`endif
        end
      end
    endtask

`ifdef BENCH_STORE_LATE
    integer la_count=0,la_addr_count=0,la_data_count=0,la_accept_count=0;
    reg [31:0] la_pc[0:511],la_addr[0:511],la_value[0:511];
    reg [5:0] la_rd[0:511];
    task late_owned_sample;
      begin
        if(`IS.operand_pop && `IS.late_store_eligible)begin
          if(la_count>=512)$fatal(1,"late allocation bound");
          la_pc[la_count]=`IS.operand_pc_plus_8_ff-8;
          la_rd[la_count]=`IS.operand_mem_srcdest_index_ff;la_count=la_count+1;
          $display("LATE_EARLY_ISSUE edge=%0d pc=%h producer=%h rd=%0d",cycles,`IS.operand_pc_plus_8_ff-8,`IS.o_pc_plus_8_ff-8,`IS.operand_mem_srcdest_index_ff);
        end
        if(`LC.alu_dav_ff && `LC.alu_store_late && la_addr_count<la_count && `LC.alu_pc_plus_8_ff-8==la_pc[la_addr_count])begin
          la_addr[la_addr_count]=`LC.alu_address_ff;la_addr_count=la_addr_count+1;
          $display("LATE_PRIVATE_ADDRESS edge=%0d pc=%h addr=%h older=%h cache_state=%0d accepted=0",cycles,`LC.alu_pc_plus_8_ff-8,`LC.alu_address_ff,`LC.postalu_pc_plus_8_ff-8,`LK.state);
        end
        if(`LC.late_p1_ready || `LC.late_p2_ready)begin
          if(la_data_count>=la_count)$fatal(1,"unallocated late data");
          if(`LC.late_p1_ready)begin
            if(`LC.postalu1_pc_plus_8_ff-8!=la_pc[la_data_count] || `LC.postalu_pc_plus_8_ff-4!=la_pc[la_data_count] || `LC.postalu_mem_srcdest_index_ff!=la_rd[la_data_count])$fatal(1,"wrong exact P1 producer identity");
            la_value[la_data_count]=`LC.late_p1_data;
            $display("LATE_DATA edge=%0d pc=%h producer=%h rd=%0d value=%h source=P2_registered",cycles,`LC.postalu1_pc_plus_8_ff-8,`LC.postalu_pc_plus_8_ff-8,`LC.postalu_mem_srcdest_index_ff,`LC.late_p1_data);
          end else begin
            if(`LC.postalu_pc_plus_8_ff-8!=la_pc[la_data_count] || `LC.memory_pc_plus_8_ff-4!=la_pc[la_data_count] || `LC.memory_mem_srcdest_index_ff!=la_rd[la_data_count])$fatal(1,"wrong exact P2 producer identity");
            la_value[la_data_count]=`LC.late_p2_data;
            $display("LATE_DATA edge=%0d pc=%h producer=%h rd=%0d value=%h source=formatted_B",cycles,`LC.postalu_pc_plus_8_ff-8,`LC.memory_pc_plus_8_ff-8,`LC.memory_mem_srcdest_index_ff,`LC.late_p2_data);
          end
          la_data_count=la_data_count+1;
        end
        if(`LK.accept_demand && `LA.wr && la_accept_count<la_count && load_selected_pc==la_pc[la_accept_count])begin
          if(la_accept_count>=la_data_count || `LA.din!==la_value[la_accept_count] || `LA.address!==la_addr[la_accept_count] || `LA.ben!=15)$fatal(1,"late admission address/data/producer");
          la_accept_count=la_accept_count+1;
        end
      end
    endtask
`endif
