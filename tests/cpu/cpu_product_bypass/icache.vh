    `define IC dut.u_zap.l_generate_with_cache_mmu.u_code_cache
    `define IA `IC.cache_adapter
    `define IK `IA.cache
    task icache_sample;
      begin
        if(windows==2 && mt_cycles<6000)$display("IC_EDGE e=%0d rd=%0d addr=%h ack=%0d launched=%0d tlb=%0d trans=%0d fast=%0d fv=%0d valid=%0d ready=%0d accept=%0d state=%0d lookup=%0d kind=%0d lookupaddr=%h epoch=%0d stream=%h tag0=%h tag1=%h rp=%0d ra=%h cp=%0d ca=%h rv=%0d raddr=%h cancel=%0d hit=%0d",cycles,`IA.rd,`IA.address,`IA.request_ack,`IA.launched,`IA.tlb_busy,`IA.translation_wait,`IA.fast_hit,`IA.fast_valid,`IA.req_valid,`IA.req_ready,`IK.accept_demand,`IK.state,`IK.lookup_owner_valid,`IK.lookup_owner_kind,`IK.lookup_owner_mva,`IK.fast_epoch,`IK.stream_valid,`IK.stream_tag[0],`IK.stream_tag[1],`IK.fast_read_pending,`IK.fast_read_address,`IK.fast_compare_pending,`IK.fast_compare_address,`IK.fast_result_valid,`IK.fast_result_address,`IK.cancel_fast,`IK.bank.hit);
      end
    endtask
