`timescale 1ns / 1ps
module test;
  reg clk = 0, reset = 1, rd = 0, wr = 0, enabled = 1, cacheable = 1, bufferable = 1;
  reg probe = 0, inv = 0, clean = 0, lock = 0, fault = 0, align_fault = 0, tlb_busy = 0;
  reg [31:0] addr = 0, din = 0, pa = 0, probe_addr = 0;
  reg [3:0] ben = 15;
  reg [1:0] swp = 0;
  wire ack, request_ack, err, err2, idle, hold_request, empty, inv_done, clean_done, lock_done;
  wire cyc, stb, we;
  wire [31:0] dout, bus_addr, bus_data, far_addr;
  wire [3:0] bus_sel;
  wire [7:0] fsr;
  reg [31:0] mem[0:32767], expected[0:7];
  integer seg;
  integer
      i,
      j,
      k,
      checks = 0,
      requests = 0,
      responses = 0,
      beats = 0,
      writes = 0,
      parallel = 0,
      collisions = 0;
  integer waits = 0, latency, fast_reads = 0, old_responses, old_beats;
  wire bus_ack = dut.inflight && waits >= 1;
  always #5 clk = ~clk;
  always @(posedge clk) begin
    if (reset || !dut.inflight || bus_ack) waits <= 0;
    else waits <= waits + 1;
    if (!reset) begin
      if ((rd || wr) && request_ack) responses = responses + 1;
      if (bus_ack) begin
        beats = beats + 1;
        if (we) begin
          writes = writes + 1;
          for (i = 0; i < 4; i = i + 1)
          if (bus_sel[i]) mem[bus_addr[16:2]][i*8+:8] <= bus_data[i*8+:8];
        end
      end
      if (dut.cache.probe_read && dut.cache.data_commit_valid) parallel = parallel + 1;
      if (dut.cache.probe_read_collision) collisions = collisions + 1;
    end
  end
  arm920_cache_adapter #(
      .DATA_PROBE(1)
  ) dut (
      .clk(clk),
      .reset(reset),
      .discard_refill(1'b0),
      .external_permit(1'b1),
      .write_buffer_empty(empty),
      .store_overlap_enable(credit_enable),
      .load_pair_enable(pair_enable),
      .fast_enable(1'b1),
      .fast_next_address(32'b0),
      .data_probe_valid(probe),
      .data_probe_address(probe_addr),
      .address(addr),
      .physical(pa),
      .din(din),
      .far_in(addr),
      .rd(rd),
      .wr(wr),
      .ben(ben),
      .swp_tag(swp),
      .swp_bus_lock(),
      .alignment_fault(align_fault),
      .alignment_far(addr),
      .fault(fault),
      .fsr_in(8'h0d),
      .external_fsr(8'h08),
      .tlb_busy(tlb_busy),
      .translation_wait(tlb_busy),
      .cache_enable(enabled),
      .cache_rr(1'b1),
      .cacheable(cacheable),
      .bufferable(bufferable),
      .cache_invalidate(inv),
      .cache_clean(clean),
      .cache_lock_write(lock),
      .cache_lock_base(6'b0),
      .cache_lock_done(lock_done),
      .cache_op_single(1'b0),
      .cache_op_by_mva(1'b0),
      .cache_op_address(32'b0),
      .data(dout),
      .ack(ack),
      .request_ack(request_ack),
      .err(err),
      .err2(err2),
      .fsr(fsr),
      .far(far_addr),
      .idle(idle),
      .hold(hold_request),
      .cache_inv_done(inv_done),
      .cache_clean_done(clean_done),
      .wb_cyc(cyc),
      .wb_stb(stb),
      .wb_wen(we),
      .wb_sel(bus_sel),
      .wb_adr(bus_addr),
      .wb_data(bus_data),
      .wb_cti(),
      .wb_ack(bus_ack),
      .wb_err(1'b0),
      .wb_rdata(mem[bus_addr[16:2]]),
      .line_req(),
      .line_addr(),
      .line_ready(1'b0),
      .line_reject(1'b0),
      .line_valid(1'b0),
      .line_data(64'b0),
      .line_wide(1'b0),
      .line_last(1'b0),
      .line_error(1'b0)
  );
  reg credit_enable=0, pair_enable=0;
  reg [3:0] delayed_returns=0;
  wire delayed_response=delayed_returns[3];
  always @(posedge clk)begin
    if(reset)delayed_returns<=0;
    else delayed_returns<={delayed_returns[2:0],dut.cache.pipe_commit};
  end
  reg measuring=0;
  integer ca=0,cw=0,peak=0,simultaneous=0,full_pressure=0,probed_wait=0;
  reg [31:0] qa[0:31],qd[0:31];
  reg [5:0] qway[0:31];
  reg [31:0] emask;
  always @(posedge clk)begin
    if(reset)begin ca=0;cw=0;end
    else if(measuring)begin
      if(dut.store_pending>peak)peak=dut.store_pending;
      if(dut.store_pending==3 && wr && !fault)begin
        full_pressure=full_pressure+1;
        if(request_ack || dut.cache.accept_demand)$fatal(1,"full credit over-admission");
      end
      if(dut.store_credit_accept && dut.store_response)simultaneous=simultaneous+1;
      if(dut.store_credit_accept)begin
        qa[ca]=addr;qd[ca]=din;qway[ca]=dut.cache.result_way;ca=ca+1;
      end
      if((|dut.cache.bank.lines.write_enable) && cw<ca)begin
        emask=32'hf << (qa[cw][4:2]*4);
        if(dut.cache.bank.lines.write_enable!==emask ||
           {dut.cache.bank.lines.write_way,dut.cache.bank.lines.write_segment}!=={qway[cw],qa[cw][7:5]} ||
           dut.cache.bank.lines.write_line[qa[cw][4:2]*32+:32]!==qd[cw])$fatal(1,"pressure RAM order/bytes mismatch");
        cw=cw+1;
      end
      if(rd && dut.store_pending!=0 && dut.cache.probe_result_valid)begin
        probed_wait=probed_wait+1;
        if(request_ack || dut.fast_hit)$fatal(1,"probed load bypassed active credits");
      end
    end
  end
  task credit_store;
    input integer word_id;
    input [31:0] value;
    integer bound;
    begin
      addr=32'h1000+word_id*4;pa=addr;din=value;ben=15;wr=1;rd=0;credit_enable=1;
      #1;bound=0;
      while(!request_ack && bound<100)begin tick();bound=bound+1;end
      if(!request_ack || !dut.store_credit_accept || err || err2)$fatal(1,"credit not granted");
      tick();
    end
  endtask
  task begin_pressure;
    begin
      credit_enable=0;rd=0;wr=0;probe=0;
      clean=1;while(!clean_done)tick();tick();clean=0;tick();
      warm_pair(32'h1000,32'h3000);prepare(32'h3000);
      ca=0;cw=0;measuring=1;
      force dut.response_valid=delayed_response;
    end
  endtask
  task drain_pressure;
    integer bound;
    begin
      rd=0;wr=0;credit_enable=0;bound=0;
      while((dut.store_pending!=0 || delayed_returns!=0) && bound<100)begin tick();bound=bound+1;end
      if(dut.store_pending!=0 || ca!=cw)$fatal(1,"pressure drain lost an owner");
      release dut.response_valid;
      tick();measuring=0;
    end
  endtask
  reg collision_seen, high_way_seen = 0;
  always @(posedge clk)
    if (!reset) begin
      collision_seen=dut.cache.data_commit_valid &&
   dut.cache.data_commit_index==dut.cache.bank.lines.read_index;
      #1;
      if (collision_seen && dut.cache.probe_result_valid)
        $fatal(1, "published unspecified mixed-port RAM result");
    end
  task tick;
    begin
      @(posedge clk);
      #1;
      @(negedge clk);
      #1;
    end
  endtask
  task transaction;
    input write_access;
    input [31:0] address, physical, value, expect_value;
    input [3:0] mask;
    input expect_fast;
    integer n;
    begin
      if (!idle) $fatal(1, "adapter not idle");
      old_responses = responses;
      requests = requests + 1;
      addr = address;
      pa = physical;
      din = value;
      ben = mask;
      rd = !write_access;
      wr = write_access;
      #1;
      latency = 0;
      if (expect_fast && !dut.fast_hit)
        $fatal(1, "prepared probe did not complete immediately VA=%h", addr);
      if (!expect_fast && (swp != 0 || !enabled || !cacheable) && dut.fast_hit)
        $fatal(1, "SWP used speculative data probe");
      n = 0;
      while (!request_ack && n < 1000) begin
        tick();
        n = n + 1;
        latency = latency + 1;
      end
      if (!request_ack || err || err2) $fatal(1, "transaction failed VA=%h", addr);
      if (!write_access && dout !== expect_value)
        $fatal(1, "wrong word VA=%h got=%h expect=%h", addr, dout, expect_value);
      if (!write_access && dut.fast_hit) fast_reads = fast_reads + 1;
      tick();
      rd = 0;
      wr = 0;
      tick();
      if (responses != old_responses + 1 || request_ack) $fatal(1, "missing/duplicate response");
      checks = checks + 1;
    end
  endtask
  task prepare;
    input [31:0] address;
    begin
      probe = 1;
      probe_addr = address;
      repeat (4) tick();
      if (!dut.cache.probe_result_valid || dut.cache.probe_result_tag != address[31:5])
        $fatal(1, "probe fixture was not primed VA=%h", address);
    end
  endtask
  task warm_pair;
    input [31:0] a, b;
    begin
      transaction(0, a, a, 0, mem[a[16:2]], 15, 0);
      transaction(0, b, b, 0, mem[b[16:2]], 15, 0);
      transaction(0, a, a, 0, mem[a[16:2]], 15, 0);
      transaction(0, b, b, 0, mem[b[16:2]], 15, 0);
    end
  endtask
  task pair_reply;
    integer bound;
    begin
      pair_enable=0; probe=0; rd=0;wr=0;
      warm_pair(32'h1000,32'h1020);probe=0;repeat(3)tick();
      pair_enable=1;probe=1;probe_addr=32'h1020;addr=32'h1004;pa=addr;rd=1;wr=0;
      #1;bound=0;
      while(!request_ack && bound<100)begin tick();bound=bound+1;end
      if(!request_ack || !dut.cache.early_reply || !dut.cache.pair_read_slot ||
         !dut.cache.probe_read || dut.cache.probe_owner_tag!=32'h1020>>5 ||
         dout!==mem['h401])$fatal(1,"pair work did not overlap the older reply");
      tick();pair_enable=0;rd=0;
      if(!dut.cache.probe_result_valid || dut.cache.probe_result_tag!=32'h1020>>5)
        $fatal(1,"younger private result owner lost");
    end
  endtask
  task pair_cases;
    integer prior;
    begin
      pair_reply();prior=beats;
      addr=32'h1024;pa=addr;rd=1;#1;
      if(!request_ack || !dut.fast_hit || dout!==mem['h409])$fatal(1,"second owner did not consume its own word");
      tick();rd=0;probe=0;tick();
      if(beats!=prior)$fatal(1,"private pair work generated external traffic");
      $display("PRESSURE_CASE pair_read_on_older_reply correct_younger_word in_order no_external PASS");
      pair_reply();prior=beats;
      addr=32'h1024;pa=addr;rd=1;fault=1;#1;
      if(!request_ack || !err || dut.fast_hit || dut.cache.accept_demand)$fatal(1,"private result bypassed younger permission");
      tick();rd=0;fault=0;probe=0;tick();
      if(beats!=prior)$fatal(1,"faulting second read generated external traffic");
      $display("PRESSURE_CASE pair_result younger_permission_fault no_accept no_external PASS");
      pair_reply();prior=beats;
      addr=32'h1024;pa=addr;rd=1;tlb_busy=1;#1;
      repeat(3)begin
        if(request_ack || dut.fast_hit || dut.cache.accept_demand)$fatal(1,"private pair bypassed translation");
        tick();
      end
      if(beats!=prior)$fatal(1,"untranslated pair generated external traffic");
      tlb_busy=0;while(!request_ack)tick();
      if(err || dout!==mem['h409])$fatal(1,"translated pair result wrong");
      tick();rd=0;probe=0;tick();
      $display("PRESSURE_CASE pair_result waits_for_current_translation PASS");
      pair_reply();addr=32'h1044;pa=addr;rd=1;#1;
      if(dut.fast_hit)$fatal(1,"mismatched younger address consumed old result");
      while(!request_ack)tick();
      if(err || dout!==mem['h411])$fatal(1,"mismatched demand returned stale word");
      tick();rd=0;probe=0;tick();
      $display("PRESSURE_CASE pair_result changed_address no_stale_consume PASS");
      pair_reply();
      credit_store(8,32'hb001beef);rd=1;wr=0;credit_enable=0;addr=32'h1020;pa=addr;#1;
      while(!request_ack)begin
        if(dut.store_pending!=0 && dut.fast_hit)$fatal(1,"pair result passed older store");
        tick();
      end
      if(dout!==32'hb001beef || err)$fatal(1,"aliased store did not poison younger result");
      tick();rd=0;probe=0;tick();
      $display("PRESSURE_CASE pair_result intervening_alias_store fresh_value PASS");
      // Restore dirty backing before later independent pressure phases.
      clean=1;while(!clean_done)tick();tick();clean=0;tick();
      pair_reply();reset=1;rd=0;probe=0;tick();reset=0;repeat(4)tick();
      if(request_ack || dut.cache.probe_result_valid || dut.probe_pair_q)$fatal(1,"pair survived reset");
      $display("PRESSURE_CASE pair_result reset_cancels_owner PASS");
    end
  endtask
  initial begin
    for(j=0;j<32768;j=j+1)mem[j]=32'h51000000^(j*4);
    repeat(4)tick();reset=0;
    pair_cases();
    warm_pair(32'h1000,32'h3000);prepare(32'h1000);
    if(!dut.cache.probe_result_valid)$fatal(1,"stale-read setup lacks old result");
    ca=0;cw=0;measuring=1;
    credit_store(0,32'hc0011234);credit_store(1,32'hc0025678);
    // Leave a different P1 line selected while P2 needs the just-written A.
    probe=1;probe_addr=32'h3000;addr=32'h1000;pa=addr;rd=1;wr=0;credit_enable=0;#1;
    while(!request_ack)begin
      if(dut.store_pending!=0 && dut.fast_hit)$fatal(1,"stale same-address ACK behind store");
      tick();
    end
    if(err || dout!==32'hc0011234 || ca!=2 || cw!=2)$fatal(1,"stale same-address result after store");
    tick();rd=0;tick();measuring=0;
    $display("PRESSURE_CASE old_A_probe write_A competing_P1_B fresh_P2_A PASS");
    begin_pressure();
    credit_store(0,32'h6a000000);credit_store(1,32'h6a000001);credit_store(2,32'h6a000002);
    if(dut.store_pending!=3)$fatal(1,"third reserve not reached");
    credit_store(3,32'h6a000003);
    // Primed independent B read is offered before delayed physical returns drain.
    addr=32'h3000;pa=addr;wr=0;rd=1;credit_enable=0;#1;
    while(!request_ack)tick();
    if(dout!==32'h51003000 || err)$fatal(1,"following primed B value");
    tick();rd=0;tick();
    drain_pressure();
    transaction(0,32'h1000,32'h1000,0,32'h6a000000,15,0);
    $display("PRESSURE_CASE reserve_full simultaneous_return held_fourth active_probe_read same_address_read PASS");
    begin_pressure();
    credit_store(0,32'h6b000000);credit_store(1,32'h6b000001);credit_store(2,32'h6b000002);
    fault=1;wr=1;rd=0;addr=32'h1010;pa=addr;din=32'hdeadbeef;credit_enable=1;#1;
    while(dut.store_pending!=0)begin
      if(request_ack || dut.cache.accept_demand)$fatal(1,"fault skipped old credits");
      tick();
    end
    if(!request_ack || !err || ca!=3)$fatal(1,"fault owner lost or younger accepted");
    tick();fault=0;wr=0;credit_enable=0;drain_pressure();
    transaction(0,32'h1010,32'h1010,0,32'h51001010,15,0);
    $display("PRESSURE_CASE following_fault_after_full no_younger_write PASS");
    // Clean the real dirty RAM and compare independently known backing words.
    probe=0;clean=1;while(!clean_done)tick();tick();clean=0;tick();
    if(mem['h400]!==32'h6b000000 || mem['h401]!==32'h6b000001 || mem['h402]!==32'h6b000002 || mem['h403]!==32'h6a000003)$fatal(1,"full pressure dirty bytes/writeback");
    begin_pressure();
    credit_store(0,32'h90000000);credit_store(1,32'h90000001);credit_store(2,32'h90000002);
    if(dut.store_pending!=3)$fatal(1,"reset not at full occupancy");
    reset=1;wr=0;rd=0;tick();
    if(dut.store_pending!=0 || dut.cache.pipe_owner || dut.cache.pipe_commit)$fatal(1,"reset retained owner");
    release dut.response_valid;measuring=0;reset=0;probe=0;credit_enable=0;
    repeat(8)begin tick();if(request_ack || dut.cache.probe_result_valid || dut.store_pending!=0)$fatal(1,"reset stale credit/probe");end
    transaction(0,32'h1000,32'h1000,0,mem['h400],15,0);
    if(peak!=3 || full_pressure==0 || probed_wait==0 || simultaneous==0)$fatal(1,"pressure coverage peak=%0d full=%0d probed=%0d both=%0d",peak,full_pressure,probed_wait,simultaneous);
    $display("PRESSURE_CASE reset_at_full fresh_read no_stale_reply PASS");
    $display("PASS pressure peak=%0d full_hold_clocks=%0d simultaneous=%0d active_probed_load_clocks=%0d",peak,full_pressure,simultaneous,probed_wait);
    $finish;
  end
  initial begin
    #10000000;
    $fatal(1, "timeout");
  end
endmodule
