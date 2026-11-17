`ifdef BENCH_LOADPAIR
    integer load_safety=0, safety_fault_offered=0, safety_valid_pair=0;
    integer safety_seen[0:6];
    reg [31:0] forbidden_fault_load, safety_pc[0:6];
    integer sx;
    initial begin
      if($value$plusargs("load_safety=%d",load_safety))begin end
      for(sx=0;sx<7;sx=sx+1)safety_seen[sx]=0;
      if(load_safety)begin
        if(!$value$plusargs("forbidden_fault_load=%h",forbidden_fault_load) ||
           !$value$plusargs("safety_same_rd=%h",safety_pc[0]) ||
           !$value$plusargs("safety_address_dep=%h",safety_pc[1]) ||
           !$value$plusargs("safety_same_address=%h",safety_pc[2]) ||
           !$value$plusargs("safety_ldm=%h",safety_pc[3]) ||
           !$value$plusargs("safety_writeback=%h",safety_pc[4]) ||
           !$value$plusargs("safety_wrong_path=%h",safety_pc[5]) ||
           !$value$plusargs("safety_pair=%h",safety_pc[6]))$fatal(1,"safety symbols required");
      end
    end
    always @(posedge clk)if(!reset && load_safety)begin
      if(`OA.rd && `OA.address==32'h70000000)safety_fault_offered=safety_fault_offered+1;
      if((`OA.rd && `OA.request_ack && overlap_pc==forbidden_fault_load) ||
         (retire && retire_pc==forbidden_fault_load))$fatal(1,"younger LDR published across older fault");
      if(`OC.o_data_load_pair && (`OC.older_memory_exception || `OC.clear_from_writeback ||
        `OC.postalu_mem_srcdest_index_ff==`OC.postalu1_mem_srcdest_index_ff ||
        `OC.postalu_address_ff==`OC.postalu1_address_ff))$fatal(1,"unsafe CPU pair class");
      for(sx=0;sx<7;sx=sx+1)begin
        if(retire && retire_pc==safety_pc[sx])safety_seen[sx]=safety_seen[sx]+1;
        if(sx<6 && `OC.postalu_pc_plus_8_ff-8==safety_pc[sx] && `OC.o_data_load_pair)
          $fatal(1,"serialized CPU case allocated private pair");
      end
      if(`OC.o_data_load_pair && `OC.postalu_pc_plus_8_ff-8==safety_pc[6])safety_valid_pair=safety_valid_pair+1;
      if(cyc && stb && ack && we && address==32'hf0000000)begin
        if(safety_fault_offered==0 || safety_valid_pair==0)$fatal(1,"CPU pair/fault coverage missing");
        for(sx=0;sx<7;sx=sx+1)if(sx!=5 && safety_seen[sx]!=1)$fatal(1,"CPU safety case not retired %0d",sx);
        $display("PASS LOAD_SAFETY older_fault=%0d independent_pair=%0d same_rd address_dependency same_address LDM writeback wrong_path serialized; younger_fault_load_no_effect",safety_fault_offered,safety_valid_pair);
      end
    end

`endif
