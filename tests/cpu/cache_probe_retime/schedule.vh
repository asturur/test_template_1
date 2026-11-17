  reg trace_on=0, fast_enable=1;
  integer edge_id=0, phase=0, stage_id=0, event_id=0;
  reg [26:0] saved_read_tag;
  reg [5:0] saved_read_way;
  reg sampled_read=0;
  wire [8:0] actual_read_index=dut.cache.bank.lines.read_index;
  wire [31:0] physical_tags[0:63];
  genvar mt;
  generate for(mt=0;mt<64;mt=mt+1)begin
    assign physical_tags[mt]=dut.cache.bank.tags.ways[mt].packed_dirty_tags.tag_ram.memory[actual_read_index[2:0]];
  end endgenerate
  always @(posedge clk) begin
    edge_id=edge_id+1;
    if(trace_on)$display("SCHEDULE e=%0d phase=%0d event=%0d stage=%0d p1=%h p2=%h hint=%h read=%0d slot=%0d result=%0d result_tag=%h accept=%0d admit=%0d fast=%0d ack=%0d tlb_wait=%0d fault=%0d reset=%0d",
      edge_id,phase,event_id,stage_id,probe_addr,addr,dut.cache.probe_owner_tag,dut.cache.probe_read,actual_read_index,dut.cache.probe_result_valid,dut.cache.probe_result_tag,dut.cache.accept_demand,dut.cache.admitted_probe_owner,dut.fast_hit,request_ack,tlb_busy,fault,reset);
    sampled_read=!reset && dut.cache.probe_read;
    if(sampled_read)begin
      // Expected identity comes from actual RAM-B slot and real stored tag,
      // not from the candidate's declared result owner.
      saved_read_tag={physical_tags[actual_read_index[8:3]][23:0],actual_read_index[2:0]};
      saved_read_way=actual_read_index[8:3];
    end
    #1;
    if(sampled_read && dut.cache.probe_result_valid &&
       (dut.cache.probe_result_tag!==saved_read_tag || dut.cache.probe_result_way!==saved_read_way))
      $fatal(1,"retimed result token identity mismatch against physical RAM read slot");
  end
  task consume_read(input [31:0] target);
    integer n, prior_responses;
    begin
      prior_responses=responses;
      addr=target;pa=target;rd=1;wr=0;ben=15;n=0;#1;
      while(!request_ack)begin
        // Alternate speculative P1 targets while the P2 packet stays held.
        probe_addr=(n%2) ? 'h1000 : 'h3000;
        tick();n=n+1;if(n>1000)$fatal(1,"held demand did not progress");
      end
      if(err||err2||dout!==mem[target>>2])$fatal(1,"scheduled demand data/identity mismatch %h got %h",target,dout);
      tick();
      if(responses!=prior_responses+1)$fatal(1,"held/back-to-back demand duplicated or lost ACK"); // exactly one sampled completion; caller replaces packet now
      $display("CASE scheduled read phase=%0d addr=%h waits=%0d PASS",phase,target,n);
    end
  endtask
  task reset_fixture;
    begin
      rd=0;wr=0;probe=0;inv=0;clean=0;lock=0;fault=0;align_fault=0;tlb_busy=0;swp=0;
      enabled=1;cacheable=1;bufferable=1;fast_enable=1;reset=1;repeat(2)tick();reset=0;tick();
      warm_pair('h1000,'h3000);
    end
  endtask
  task schedule_cases;
    integer n,old_req,old_bus,old_w,old_res,acks_before;
    begin
      reset_fixture();phase=0;trace_on=1;
      // A speculative read of A while the live but inactive P2 address is B.
      probe=1;probe_addr='h1000;addr='h3000;pa=addr;repeat(4)tick();
      consume_read('h3000);rd=0;probe=0;tick();
      phase=1;probe=1;
      // No dropped rd between demands. P1 and P2 intentionally disagree.
      for(n=0;n<8;n=n+1)begin
        probe_addr=n%2 ? 'h1000 : 'h3000;
        consume_read(n%2 ? 'h3000 : 'h1000);
      end
      rd=0;tick();
      phase=2;old_bus=beats;tlb_busy=1;addr='h3000;pa=addr;rd=1;probe=1;probe_addr=addr;
      repeat(5)begin #1;if(request_ack||dut.cache.accept_demand)$fatal(1,"translation wait ACK/accept");tick();end
      tlb_busy=0;#1;if(!dut.fast_hit||dout!==mem['h3000>>2])$fatal(1,"late translation did not consume matching private read");
      tick();rd=0;tick();if(beats!=old_bus)$fatal(1,"private probe issued external traffic");
      $display("CASE delayed_translation_hit PASS");
      tlb_busy=1;fault=0;addr='h1000;pa=addr;rd=1;probe_addr=addr;
      repeat(4)begin #1;if(request_ack)$fatal(1,"early ACK while translation undecided");tick();end
      tlb_busy=0;fault=1;#1;if(!request_ack||!err||dut.fast_hit||dut.cache.accept_demand)$fatal(1,"fault consumed speculative data");
      tick();rd=0;fault=0;tick();$display("CASE delayed_translation_fault PASS");
      phase=3;probe=1;probe_addr='h1000;
      // Store remains architectural owner until its ACK; read follows directly.
      addr='h1000;pa=addr;din=32'h12349aef;ben=5;wr=1;rd=0;#1;
      while(!request_ack)tick();tick();wr=0;rd=1;#1;
      while(!request_ack)tick();
      if(err||dout!==32'h513410ef)$fatal(1,"same-slot following load stale %h",dout);
      tick();rd=0;probe=0;tick();$display("CASE same_slot_store_followed_load PASS");
      // Commit changed cache data; the independent backing model is updated
      // only by ordinary clean before later backing-based expected reads.
      clean=1;while(!clean_done)tick();tick();clean=0;while(!empty)tick();
      phase=4;probe=1;probe_addr='h3000;repeat(4)tick();
      fast_enable=0;probe=0;tick();fast_enable=1;tick();
      if(dut.cache.probe_result_valid)$fatal(1,"expired token remained visible");
      consume_read('h3000);rd=0;tick();$display("CASE expired_token_fallback PASS");
      phase=5;probe=1;consume_read('h9000);rd=0;probe=0;tick();
      $display("CASE held_miss_changing_P1 PASS");
      // Exposed new stages: before capture, address captured, RAM result,
      // and a completed result awaiting a possible consumer.
      for(event_id=0;event_id<4;event_id=event_id+1)
      for(stage_id=0;stage_id<4;stage_id=stage_id+1)begin
        trace_on=0;reset_fixture();phase=6;trace_on=1;
        probe=0;fast_enable=0;tick();fast_enable=1;
        probe=1;probe_addr='h3000;addr='h3000;pa=addr;
        repeat(stage_id)tick();
        case(event_id)
          0:begin reset=1;#1;if(dut.fast_hit||dut.cache.probe_read)$fatal(1,"reset did not suppress stage");tick();reset=0;end
          1:begin inv=1;while(!inv_done)tick();tick();inv=0;end
          2:begin lock=1;tick();lock=0;tick();end
          3:begin enabled=0;tick();enabled=1;end
        endcase
        probe=0;#1;if(dut.fast_hit||dut.cache.probe_result_valid)$fatal(1,"revoked stage retained result");
        tick();transaction(0,'h3000,'h3000,0,mem['h3000>>2],15,0);
        $display("CASE stage_revoke event=%0d stage=%0d PASS",event_id,stage_id);
      end
      trace_on=0;$display("PASS registered probe schedule: P1/P2, held/back-to-back, translation hit/fault, store freshness, expiry and 16 stage revokes");
    end
  endtask
