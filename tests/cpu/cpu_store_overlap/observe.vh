    `define OC dut.u_zap.u_zap_core
    `define OA dut.u_zap.l_generate_with_cache_mmu.u_data_cache.cache_adapter
    `define OB `OA.cache.bank
    reg [31:0] stores_begin,stores_end,irq_marker,forbidden_fault,forbidden_irq;
    integer irq_seen=0, fault_seen=0, held_stores=0, full_holds=0;
    reg store_waiting=0;
    reg old_irq_flag=0,old_abort_flag=0;
    reg [103:0] held_store_packet;
    integer oa=0,ow=0,oret=0,oi=0,ocmp=0,opairs=0,ox,jj,wi,si;
    integer target_holds=0,target_full_holds=0,gap,hist[0:15];
    integer last_issue[0:63];
    integer corrupt_oracle=0;
    integer aqedge[0:447],wqedge[0:447],iqedge[0:447];
    reg [5:0] aqway[0:447];
    reg [31:0] apc,ipc,aval;
    reg [31:0] expected_address,expected_enable;
    wire [31:0] overlap_pc=(`OC.completion_next ? `OC.postalu1_pc_plus_8_ff : `OC.postalu_pc_plus_8_ff)-8;
    function [31:0] overlap_value(input integer index);
      overlap_value=32'h11111111*(1+((index/16+index%4)%4));
    endfunction
    initial begin
      if($value$plusargs("corrupt_oracle=%d",corrupt_oracle))begin end
      if(!$value$plusargs("stores_begin=%h",stores_begin) || !$value$plusargs("stores_end=%h",stores_end))$fatal(1,"store markers required");
      if(!$value$plusargs("irq_marker=%h",irq_marker) || !$value$plusargs("forbidden_fault=%h",forbidden_fault) || !$value$plusargs("forbidden_irq=%h",forbidden_irq))$fatal(1,"boundary markers required");
    end
    always @(posedge clk) if(!reset) begin
      if(retire && retire_pc==irq_marker)test_irq<=1;
      if(`OC.memory_irq_ff)begin test_irq<=0;if(!old_irq_flag)irq_seen=irq_seen+1;end
      if((|`OC.memory_data_abt_ff) && !old_abort_flag)fault_seen=fault_seen+1;
      old_irq_flag<=`OC.memory_irq_ff;old_abort_flag<=|`OC.memory_data_abt_ff;
      if(`OA.cache.accept_demand && (overlap_pc==forbidden_fault || overlap_pc==forbidden_irq))$fatal(1,"younger store leaked across older abort/IRQ");
      if(store_waiting && !`OC.clear_from_writeback && (!`OC.o_data_wb_stb || {overlap_pc,`OA.address,`OA.din,`OA.ben,`OA.wr,`OA.rd,`OA.swp_tag}!==held_store_packet))$fatal(1,"held store changed under backpressure");
      store_waiting<=`OC.o_data_wb_stb && `OA.wr && !`OA.request_ack && !`OC.clear_from_writeback;
      held_store_packet<={overlap_pc,`OA.address,`OA.din,`OA.ben,`OA.wr,`OA.rd,`OA.swp_tag};
      if(`OC.o_data_wb_stb && `OA.wr && !`OA.request_ack)begin
        held_stores=held_stores+1;
        if(overlap_pc>=stores_begin && overlap_pc<stores_end)begin
          target_holds=target_holds+1;
          if(`OA.cache.pipe_owner && `OA.cache.pipe_commit)target_full_holds=target_full_holds+1;
        end
        if(`OA.cache.pipe_owner && `OA.cache.pipe_commit)full_holds=full_holds+1;
      end
      ipc=`OC.u_zap_issue_main.operand_pc_plus_8_ff-8;
      if(`OC.u_zap_issue_main.operand_pop && ipc>=stores_begin && ipc<stores_end)begin
        last_issue[(ipc-stores_begin)/4]=cycles;
        if(oa/64==2 && (ipc-stores_begin)/4<8)$display("OVERLAP_EDGE kind=issue seq=%0d pc=%h edge=%0d",oi,ipc,cycles);
        oi=oi+1;
      end
      if(`OA.cache.accept_demand && overlap_pc>=stores_begin && overlap_pc<stores_end)begin
        si=oa%64;
        if(oa>=448 || overlap_pc!=stores_begin+si*4 || !`OA.cache.req_write ||
          `OA.cache.req_mva!==32'h80001000+(si%16)*4 || `OA.cache.req_wdata!==overlap_value(si) || `OA.cache.req_byte_enable!==4'hf)
          $fatal(1,"store acceptance against independent instruction/address/data oracle");
        if(oa>ow)begin
          opairs=opairs+1;
          if(opairs==1)$display("PAIR older_seq=%0d older_pc=%h older_accept=%0d younger_seq=%0d younger_pc=%h younger_accept=%0d physical_write_now=%0d",ow,stores_begin+(ow%64)*4,aqedge[ow],oa,overlap_pc,cycles,|`OB.lines.write_enable);
        end
        iqedge[oa]=last_issue[si];
        if(iqedge[oa]>cycles || iqedge[oa]<=0)$fatal(1,"accepted store lacks real CPU issue");
        aqedge[oa]=cycles;aqway[oa]=`OA.cache.result_way;
        if(oa/64==2 && si<8)$display("OVERLAP_EDGE kind=accept seq=%0d pc=%h edge=%0d outstanding=%0d",oa,overlap_pc,cycles,oa-ow);
        oa=oa+1;
      end
      if((|`OB.lines.write_enable) && ow<oa)begin
        si=ow%64;
        expected_address=32'h80001000+(si%16)*4;
        expected_enable=32'hf<<((expected_address[4:2])*4);
        if(`OB.lines.write_enable!==expected_enable ||
           {`OB.lines.write_way,`OB.lines.write_segment}!=={aqway[ow],expected_address[7:5]} ||
           `OB.lines.write_line[expected_address[4:2]*32+:32]!== (overlap_value(si) ^ ((corrupt_oracle && ow==0) ? 1 : 0)))
          $fatal(1,"physical cache mutation order/slot/word/bytes mismatch seq=%0d mask=%h expmask=%h wayseg=%h expwayseg=%h data=%h expdata=%h pipe=%b",ow,`OB.lines.write_enable,expected_enable,{`OB.lines.write_way,`OB.lines.write_segment},{aqway[ow],expected_address[7:5]},`OB.lines.write_line[expected_address[4:2]*32+:32],overlap_value(si),`OA.cache.pipe_accept);
        wqedge[ow]=cycles;
        if(ow/64==2 && si<8)$display("OVERLAP_EDGE kind=write seq=%0d pc=%h edge=%0d",ow,stores_begin+si*4,cycles);
        ow=ow+1;
      end
      if(`OC.completion_valid && `OC.postalu_request_stb && `OC.postalu_dav_ff &&
         `OC.postalu_pc_plus_8_ff-8>=stores_begin && `OC.postalu_pc_plus_8_ff-8<stores_end)begin
        if(ocmp>=448 || `OC.postalu_pc_plus_8_ff-8!=stores_begin+(ocmp%64)*4 || (|`OC.completion_fault))$fatal(1,"registered completion owner/order/fault mismatch");
        if(ocmp/64==2 && ocmp%64<8)$display("OVERLAP_EDGE kind=complete seq=%0d pc=%h edge=%0d",ocmp,`OC.postalu_pc_plus_8_ff-8,cycles);
        ocmp=ocmp+1;
      end
      if(retire && retire_pc>=stores_begin && retire_pc<stores_end)begin
        if(oret>=448 || retire_pc!=stores_begin+(oret%64)*4)$fatal(1,"architectural store retirement order");
        if(oret/64==2 && oret%64<8)$display("OVERLAP_EDGE kind=retire seq=%0d pc=%h edge=%0d",oret,retire_pc,cycles);
        oret=oret+1;
      end
    end
    task overlap_finish;
      begin
        if(oa!=448 || ow!=448 || oret!=448 || ocmp!=448 || oi<448)$fatal(1,"missing/duplicated architectural store or mutation %0d/%0d/%0d/%0d",oi,oa,ow,oret);
        for(jj=0;jj<16;jj=jj+1)
          if(ram['h400+jj]!== (jj==0 ? 32'h44441144 : overlap_value(48+jj)))$fatal(1,"independent dirty writeback bytes mismatch word=%0d got=%h expected=%h",jj,ram['h400+jj],overlap_value(48+jj));
        if(irq_seen!=1 || fault_seen!=1 || held_stores==0)$fatal(1,"boundary/backpressure cases not exercised irq=%0d abort=%0d held=%0d",irq_seen,fault_seen,held_stores);
        $display("OVERLAP_BOUNDARY irq=%0d abort=%0d held_store_clocks=%0d full_owner_holds=%0d target_holds=%0d target_full_holds=%0d following_load=PASS byte_transition=PASS",irq_seen,fault_seen,held_stores,full_holds,target_holds,target_full_holds);
        for(jj=0;jj<7;jj=jj+1)begin
          if(jj>=2)begin
          for(gap=0;gap<16;gap=gap+1)hist[gap]=0;
          for(si=1;si<64;si=si+1)begin
            gap=aqedge[jj*64+si]-aqedge[jj*64+si-1];
            if(gap<1 || gap>15)$fatal(1,"unexpected acceptance interval");
            hist[gap]=hist[gap]+1;
          end
          for(gap=1;gap<16;gap=gap+1)if(hist[gap])$display("OVERLAP_HIST window=%0d gap=%0d count=%0d",jj,gap,hist[gap]);
          end
          $display("OVERLAP_SUMMARY window=%0d stores=64 first_issue=%0d first_accept=%0d last_accept=%0d first_write=%0d last_write=%0d issue_through_drain=%0d accept_through_drain=%0d",jj,iqedge[jj*64],aqedge[jj*64],aqedge[jj*64+63],wqedge[jj*64],wqedge[jj*64+63],wqedge[jj*64+63]-iqedge[jj*64]+1,wqedge[jj*64+63]-aqedge[jj*64]+1);
        end
        $display("PASS overlap accepted_issue=448 accepted=448 physical_writes=448 completions=448 retired=448 independent_backing_words=16 overlapping_accepts=%0d",opairs);
      end
    endtask
