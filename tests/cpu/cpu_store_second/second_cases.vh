    integer second_safety=0;
    integer second_hold=0;
    initial if($value$plusargs("second_hold=%d",second_hold))begin end
    initial if($value$plusargs("second_safety=%d",second_safety))begin end
`ifdef BENCH_STORE_SECOND
    reg [31:0] sc_pc[0:10];
    reg [31:0] sc_banked_pc;
    integer sc_banked_alloc=0;
    integer sc_alloc[0:10],sc_accept[0:10],sc_i,sc_held=0,sc_a=0,sc_w=0;
    reg [31:0] sc_addr[0:31],sc_data[0:31];
    initial begin
      for(sc_i=0;sc_i<11;sc_i=sc_i+1)begin sc_alloc[sc_i]=0;sc_accept[sc_i]=0;end
      #1;
      if(second_safety)begin
        if(!$value$plusargs("second_banked=%h",sc_banked_pc) ||
           !$value$plusargs("second_first_ok=%h",sc_pc[0]) ||
           !$value$plusargs("second_distinct=%h",sc_pc[1]) ||
           !$value$plusargs("second_overwrite_alu=%h",sc_pc[2]) ||
           !$value$plusargs("second_overwrite_load=%h",sc_pc[3]) ||
           !$value$plusargs("second_committed=%h",sc_pc[4]) ||
           !$value$plusargs("second_intervening_first=%h",sc_pc[5]) ||
           !$value$plusargs("second_intervening_second=%h",sc_pc[6]) ||
           !$value$plusargs("second_permission_first=%h",sc_pc[7]) ||
           !$value$plusargs("second_permission_second=%h",sc_pc[8]) ||
           !$value$plusargs("second_redirect_first=%h",sc_pc[9]) ||
           !$value$plusargs("second_redirect_second=%h",sc_pc[10]))$fatal(1,"second safety symbols");
      end
    end
    integer sc_hold_left=0,sc_hold_done=0,sc_captured_held=0;
    // Read-only normal tests; optional bounded downstream-capacity perturbation
    // keeps this actual Issue owner held across its producer's return/commit.
    always @(negedge clk)if(!reset && second_safety && second_hold)begin
      if(!sc_hold_done && `OC.issue_store_second && `OC.issue_pc_plus_8_ff-8==sc_pc[1])begin
        force `OC.stall_from_shifter=1'b1;
        force `OC.u_zap_issue_main.i_stall_from_shifter=1'b1;
        force `OC.u_zap_shifter_main.o_stall_from_shifter=1'b1;
        sc_hold_done=1;sc_hold_left=128;
        $display("SECOND_HOLD_BEGIN edge=%0d pc=%h",cycles,`OC.issue_pc_plus_8_ff-8);
      end else if(sc_hold_left>0)begin
        sc_hold_left=sc_hold_left-1;
        if(`OC.issue_pc_plus_8_ff-8!=sc_pc[1])$fatal(1,"held Issue owner changed");
        if(!`OC.issue_store_second)begin
          if(`OC.issue_mem_srcdest_value_ff!==32'h11223344)$fatal(1,"held return did not survive");
          if(sc_captured_held==0)$display("SECOND_HOLD_SAVED edge=%0d value=%h",cycles,`OC.issue_mem_srcdest_value_ff);
          sc_captured_held=sc_captured_held+1;
        end
        if(sc_hold_left==0)begin
          $display("SECOND_HOLD_RELEASE edge=%0d saved_clocks=%0d",cycles,sc_captured_held);
          release `OC.stall_from_shifter;
          release `OC.u_zap_issue_main.i_stall_from_shifter;
          release `OC.u_zap_shifter_main.o_stall_from_shifter;
        end
      end
    end
    always @(posedge clk)if(!reset && second_safety)begin
      if(`OC.u_zap_issue_main.operand_pop && `OC.u_zap_issue_main.second_store_eligible && `OC.u_zap_issue_main.operand_pc_plus_8_ff-8==sc_banked_pc)begin
        if(`OC.u_zap_issue_main.operand_mem_srcdest_index_ff!=18 || `OC.alu_mem_srcdest_index_ff!=18)$fatal(1,"FIQ physical source identity");
        sc_banked_alloc=sc_banked_alloc+1;
      end
      if(`OC.shifter_store_second && `OC.data_stall)sc_held=sc_held+1;
      if(`OC.second_issue_ready || `OC.second_shift_ready)
        $display("SECOND_SAFETY_DATA edge=%0d issue=%0d shift=%0d held=%0d value=%h",cycles,`OC.second_issue_ready,`OC.second_shift_ready,`OC.data_stall,`OC.second_shift_ready ? `OC.second_shift_result[31:0] : `OC.second_issue_result[31:0]);
      for(sc_i=0;sc_i<11;sc_i=sc_i+1)begin
        if(`OC.u_zap_issue_main.operand_pop && `OC.u_zap_issue_main.second_store_eligible && `OC.u_zap_issue_main.operand_pc_plus_8_ff-8==sc_pc[sc_i])begin
          sc_alloc[sc_i]=sc_alloc[sc_i]+1;
          if(sc_i==3 && `OC.alu_pc_plus_8_ff-8!=sc_pc[3]-8)$fatal(1,"older overwritten load chosen");
          $display("SECOND_SAFETY_ALLOC case=%0d pc=%h producer=%h rd=%0d",sc_i,sc_pc[sc_i],`OC.alu_pc_plus_8_ff-8,`OC.alu_mem_srcdest_index_ff);
        end
        if(`OA.cache.accept_demand && `OA.wr && overlap_pc==sc_pc[sc_i])begin
          if(sc_i>=5 || sc_accept[sc_i]!=0)$fatal(1,"faulted/redirected/duplicate second effect %0d",sc_i);
          if((sc_i==0 || sc_i==3) && `OA.din!==32'h55667788)$fatal(1,"younger source identity");
          if((sc_i==1 || sc_i==4) && `OA.din!==32'h11223344)$fatal(1,"older/committed source identity");
          if(sc_i==2 && `OA.din!==32'h55)$fatal(1,"overwritten ALU source identity");
          sc_accept[sc_i]=sc_accept[sc_i]+1;
          sc_addr[sc_a]=`OA.address;sc_data[sc_a]=`OA.din;sc_a=sc_a+1;
        end
      end
      if(sc_w<sc_a && (|`OB.lines.write_enable))begin
        if(`OB.lines.write_enable!==(32'hf << (sc_addr[sc_w][4:2]*4)) || `OB.lines.write_segment!==sc_addr[sc_w][7:5] || `OB.lines.write_line[sc_addr[sc_w][4:2]*32+:32]!==sc_data[sc_w])$fatal(1,"second safety RAM order/data");
        sc_w=sc_w+1;
      end
      if(cyc && stb && ack && we && address==32'hf0000000)begin
        for(sc_i=0;sc_i<11;sc_i=sc_i+1)begin
          if(sc_accept[sc_i]!=(sc_i<5 ? 1 : 0))$fatal(1,"second safety acceptance count %0d",sc_i);
          if(sc_i==1 || sc_i==3 || sc_i==6 || sc_i==8)begin
            if(sc_alloc[sc_i]!=1)$fatal(1,"second owner not exercised %0d",sc_i);
          end else if(sc_alloc[sc_i]!=0)$fatal(1,"unsupported/overwritten owner allocated %0d",sc_i);
          $display("SECOND_SAFETY_CASE case=%0d allocated=%0d accepted=%0d",sc_i,sc_alloc[sc_i],sc_accept[sc_i]);
        end
        if(sc_w!=sc_a || sc_w!=5 || sc_held==0)$fatal(1,"second safety actual writes/holds");
        if(sc_banked_alloc!=1)$fatal(1,"banked producer coverage missing");
        $display("SECOND_BANKED allocated=%0d physical_rd=18 SVC_R8_R9_preserved=1",sc_banked_alloc);
        if(second_hold && (sc_hold_done!=1 || sc_captured_held<2))$fatal(1,"held return coverage missing");
        $display("SECOND_HELD_RETURN enabled=%0d saved_clocks=%0d",second_hold,sc_captured_held);
        $display("PASS SECOND_SAFETY writes=%0d held_owner_clocks=%0d distinct youngest_older_writer intervening_load_fault first_store_fault redirect",sc_w,sc_held);
      end
    end
`endif
