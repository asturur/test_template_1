    integer late_safety=0;
    initial begin if($value$plusargs("late_safety=%d",late_safety))begin end end
`ifdef BENCH_STORE_LATE
    reg [31:0] ht_pc[0:6];
    integer ht_accept[0:6],ht_early[0:6],ht_private[0:6];
    integer ht_p1[0:6],ht_p2[0:6];
    integer ht_i,ht_stall=0;
    reg ht_waiting=0;
    reg [31:0] ht_addr,ht_value;
    integer ht_owner=-1,ht_writes[0:6];
    reg ht_p1_seen[0:6];reg [31:0] ht_p1_addr[0:6];
    function [31:0] ht_expected(input integer index);
      case(index)
        0:ht_expected=32'h89abcdef;
        1:ht_expected=32'hef89abcd;
        2:ht_expected=32'h80001030;
        3,4:ht_expected=32'h101;
        default:ht_expected=32'h76543210;
      endcase
    endfunction
    initial begin
      for(ht_i=0;ht_i<7;ht_i=ht_i+1)begin ht_accept[ht_i]=0;ht_early[ht_i]=0;ht_private[ht_i]=0;ht_p1[ht_i]=0;ht_p2[ht_i]=0;ht_writes[ht_i]=0;ht_p1_seen[ht_i]=0;end
      #1;
      if(late_safety)begin
        if(!$value$plusargs("late_success_store=%h",ht_pc[0]) ||
           !$value$plusargs("late_rotated_store=%h",ht_pc[1]) ||
           !$value$plusargs("late_base_store=%h",ht_pc[2]) ||
           !$value$plusargs("late_device_store=%h",ht_pc[3]) ||
           !$value$plusargs("late_uncached_store=%h",ht_pc[4]) ||
           !$value$plusargs("late_fault_store=%h",ht_pc[5]) ||
           !$value$plusargs("late_perm_store=%h",ht_pc[6]))$fatal(1,"late safety symbols required");
      end
    end
    always @(posedge clk) if(!reset && late_safety)begin
      for(ht_i=0;ht_i<7;ht_i=ht_i+1)begin
        if(`OC.u_zap_issue_main.operand_pop && `OC.u_zap_issue_main.late_store_eligible && `OC.u_zap_issue_main.operand_pc_plus_8_ff-8==ht_pc[ht_i])ht_early[ht_i]=ht_early[ht_i]+1;
        if(`OC.alu_dav_ff && `OC.alu_store_late && `OC.alu_pc_plus_8_ff-8==ht_pc[ht_i])begin
          ht_private[ht_i]=ht_private[ht_i]+1;
          if(`OC.data_stall)ht_stall=ht_stall+1;
          if(`OA.wr && overlap_pc==ht_pc[ht_i])$fatal(1,"private store became a demand before data success");
        end
        if(`OC.postalu1_dav_ff && `OC.postalu1_store_late && `OC.postalu1_pc_plus_8_ff-8==ht_pc[ht_i])begin
          if(ht_p1_seen[ht_i] && `OC.postalu1_address_ff!==ht_p1_addr[ht_i])$fatal(1,"held private P1 address changed");
          ht_p1_addr[ht_i]=`OC.postalu1_address_ff;ht_p1_seen[ht_i]=1;
          if(`OC.data_stall)ht_stall=ht_stall+1;
          if(!`OC.late_p1_ready && `OA.wr && overlap_pc==ht_pc[ht_i])$fatal(1,"unready P1 store leaked a demand");
        end
        if(`OC.late_p1_ready && `OC.postalu1_pc_plus_8_ff-8==ht_pc[ht_i])begin
          ht_p1[ht_i]=ht_p1[ht_i]+1;
          if(ht_i<5 && `OC.late_p1_data!==ht_expected(ht_i))$fatal(1,"wrong registered producer word");
        end
        if(`OC.late_p2_ready && `OC.postalu_pc_plus_8_ff-8==ht_pc[ht_i])begin
          ht_p2[ht_i]=ht_p2[ht_i]+1;
          if(`OC.late_p2_data!==ht_expected(ht_i))$fatal(1,"wrong formatted producer word");
        end
        if(`OA.cache.accept_demand && `OA.wr && overlap_pc==ht_pc[ht_i])begin
          if(ht_i>=5 || ht_accept[ht_i]!=0 || `OA.din!==ht_expected(ht_i) || `OA.ben!=15)$fatal(1,"faulted/duplicate/wrong late store acceptance");
          ht_accept[ht_i]=ht_accept[ht_i]+1;
          if(ht_i!=3)begin
            if(ht_waiting)$fatal(1,"target RAM owner overlap in fixture");
            ht_owner=ht_i;ht_addr=`OA.address;ht_value=`OA.din;ht_waiting=1;
          end
        end
      end
      if(ht_waiting && (|`OB.lines.write_enable))begin
        if(`OB.lines.write_enable!==(32'hf << (ht_addr[4:2]*4)) ||
           `OB.lines.write_segment!==ht_addr[7:5] || `OB.lines.write_line[ht_addr[4:2]*32+:32]!==ht_value)$fatal(1,"target physical write bytes/address/order");
        ht_writes[ht_owner]=ht_writes[ht_owner]+1;ht_waiting=0;
      end
      if(cyc && stb && ack && we && address==32'hf0000000)begin
        if(ht_waiting || late_device_writes!=1)$fatal(1,"late owner/device write not exactly once");
        for(ht_i=0;ht_i<7;ht_i=ht_i+1)begin
          if(ht_i<5 && ht_accept[ht_i]!=1)$fatal(1,"successful late store absent %0d",ht_i);
          if(ht_i!=3 && ht_i<5 && ht_writes[ht_i]!=1)$fatal(1,"target RAM write count %0d",ht_i);
          if(ht_i>=5 && ht_accept[ht_i]!=0)$fatal(1,"faulting target changed memory");
          if(ht_i==2 && ht_early[ht_i]!=0)$fatal(1,"address-dependent base was issued early");
          if(ht_i!=2 && ht_early[ht_i]!=1)$fatal(1,"late allocation not exercised %0d",ht_i);
          $display("LATE_SAFETY_CASE case=%0d early=%0d private_address_clocks=%0d P1_data=%0d P2_formatted=%0d accepts=%0d physical_writes=%0d",ht_i,ht_early[ht_i],ht_private[ht_i],ht_p1[ht_i],ht_p2[ht_i],ht_accept[ht_i],ht_writes[ht_i]);
        end
        if(ht_stall==0 || ht_p2[1]!=1 || ht_p1[5]!=0 || ht_p2[5]!=0)$fatal(1,"late stall/fault/formatted fallback coverage");
        $display("PASS LATE_SAFETY held_private_address_clocks=%0d exactly_once_device=%0d older_load_fault_flush store_permission base_dependency formatted_fallback",ht_stall,late_device_writes);
      end
    end
`endif
