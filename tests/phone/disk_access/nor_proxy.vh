  integer invalidations = 0, refills = 0, status_wait = 0, auto_overlap = 0;
  integer start_cycle, start_reads, start_writes, start_invalid, start_refills;
  integer start_host_reads, start_host_writes, start_status, start_overlap;
  integer commands = 0, polls = 0, dirty_events = 0;
  integer start_commands, start_polls, start_dirty;
  bit record_erase = 0;
  reg [31:0] erase_signature = 32'h811c9dc5;
  bit guest_active = 0;
  localparam PAYLOAD_HALFWORDS = 223;
  always @(posedge clk) begin
    if (adapter.shared_cache.cache.tag_write && !adapter.shared_cache.cache.fill_done &&
        !adapter.shared_cache.cache.clearing) invalidations <= invalidations + 1;
    if (adapter.shared_cache.cache.fill_done) refills <= refills + 1;
    if (guest_active && saving) auto_overlap <= auto_overlap + 1;
    if (fpending) status_wait <= status_wait + 1;
    if (fv && fr) begin
      commands <= commands + 1;
      if (!fw && flash.erase_read) polls <= polls + 1;
    end
    if (fdirty) dirty_events <= dirty_events + 1;
    if (record_erase && fmv && fmw && fready)
      erase_signature <= (erase_signature ^ fma) * 32'd16777619;
  end

  task begin_interval;
    start_cycle = cycle;
    start_reads = physical_reads;
    start_writes = physical_writes;
    start_invalid = invalidations;
    start_refills = refills;
    start_host_reads = reads;
    start_host_writes = writes;
    start_status = status_wait;
    start_overlap = auto_overlap;
    start_commands = commands;
    start_polls = polls;
    start_dirty = dirty_events;
  endtask

  task end_interval(input string name);
    $display("DISK %s clocks=%0d ddr_read=%0d ddr_write=%0d invalidate=%0d refill=%0d host_read=%0d host_write=%0d flash_pending=%0d autosave_overlap=%0d hps_bytes=%0d commands=%0d polls=%0d dirty_events=%0d",
             name, cycle-start_cycle, physical_reads-start_reads, physical_writes-start_writes,
             invalidations-start_invalid, refills-start_refills, reads-start_host_reads,
             writes-start_host_writes, status_wait-start_status, auto_overlap-start_overlap,
             512*(reads-start_host_reads+writes-start_host_writes),
             commands-start_commands, polls-start_polls, dirty_events-start_dirty);
  endtask

  function automatic [15:0] content(input integer file_id, input integer n);
    return 16'(file_id*2399 + n*173) & 16'h7fff;
  endfunction

  task flush_files;
    @(negedge clk);
    flush = 1;
    @(negedge clk);
    flush = 0;
    wait ((saved && !saving && !busy && ack == 0) || error);
    if (error || !saved) $fatal(1, "proxy flush lacked final host ACK");
  endtask

  task open_images;
    hold_requests = 1;
    mount_image(1, 0, 16384);
    mount_image(2, 0, 1024);
    hold_requests = 0;
    wait(mounted || error);
    if (error || !mounted) $fatal(1, "proxy mount failed");
  endtask

  task read_files(input [15:0] flags);
    for (integer f = 0; f < 25; f++) begin
      c_read(22'(32*f), 15, {16'h01be, flags});
      for (integer n = 0; n < PAYLOAD_HALFWORDS; n += 2)
        c_read(22'(1024 + 512*f + n*2), 15,
               {n+1 < PAYLOAD_HALFWORDS ? content(f,n+1) : 16'hffff, content(f,n)});
    end
  endtask

  task start_erase;
    flash_cmd('haaa, 'haa);
    flash_cmd('h554, 'h55);
    flash_cmd('haaa, 'h80);
    flash_cmd('haaa, 'haa);
    flash_cmd('h554, 'h55);
    flash_cmd(0, 'h30);
  endtask

  initial begin : test
    integer unused;
    unused = $value$plusargs("host_wait=%d", host_wait);
    for (integer k = 0; k < 8959; k++) disk[k] = 16'hffff;
    for (integer k = 256; k < 16384; k++) erase_tail[k] = 32'hffffffff;
    repeat (4) @(negedge clk);
    reset = 0;
    repeat (12) @(negedge clk);
    begin_interval();
    open_images();
    end_interval("mount_small");

    begin_interval();
    for (integer n = 0; n < 16; n++)
      flash_program(22'('h3f00 + n*2), 16'(16'h6000+n));
    for (integer n = 0; n < 16; n += 2)
      c_read(22'('h3f00 + n*2), 15, {16'(16'h6001+n), 16'(16'h6000+n)});
    end_interval("hot_line");
    flush_files();

    proxy_auto = $test$plusargs("proxy_auto");
    guest_active = 1;
    begin_interval();
    for (integer f = 0; f < 25; f++) begin
      flash_program(22'(32*f), 16'hfffe);
      flash_program(22'(32*f+2), 16'h01be);
      for (integer n = 0; n < PAYLOAD_HALFWORDS; n++)
        flash_program(22'(1024+512*f+n*2), content(f,n));
      // The guest proxy waits for NOR completion. The following interval
      // independently times acknowledgement from the HPS backing protocol.
      wait (!fpending);
    end
    end_interval("create_write");
    begin_interval();
    read_files(16'hfffe);
    end_interval("reopen_read");
    begin_interval();
    for (integer f = 0; f < 25; f++) flash_program(22'(32*f), 16'hfffc);
    end_interval("delete");
    guest_active = 0;
    begin_interval();
    flush_files();
    end_interval("final_ack");

    proxy_auto = 0;
    @(negedge clk);
    reset = 1;
    for (integer k = 0; k < 512; k++) ram[k] = 0;
    for (integer k = 256; k < 4096; k++) erase_tail[k] = 0;
    repeat (4) @(negedge clk);
    reset = 0;
    begin_interval();
    open_images();
    read_files(16'hfffc);
    end_interval("cold_reopen");

    begin_interval();
    record_erase = 1;
    start_erase();
    c_read(0, 3, 32'h8);
    c_read(0, 3, 32'hffff);
    c_read(0, 15, 32'hffffffff);
    c_read(22'(1024+24*512+444), 15, 32'hffffffff);
    end_interval("erase");
    record_erase = 0;
    $display("DISK erase_order signature=%0d", erase_signature);

    flash_program(0, 16'h5a5a);
    start_erase();
    c_read(0, 3, 32'h8);
    c_read('h10000, 15, 32'h1a55ffe0);
    flash_cmd(0, 'hb0);
    c_read(0, 15, 32'hffffffff);
    c_read('h10000, 15, 32'h1a55ffe0);
    flash_program(30, 16'hacac);
    start_erase();
    @(negedge clk);
    warm_flash_reset = 1;
    @(negedge clk);
    warm_flash_reset = 0;
    wait (!fpending);
    c_read(28, 15, 32'hffffffff);
    flash_program(4, 16'h2345);
    start_erase();
    @(negedge clk);
    cold_flash_reset = 1;
    @(negedge clk);
    cold_flash_reset = 0;
    c_read(4, 15, 32'hffff2345);
    $display("PASS erase poll, B0, out-of-sector read, warm recovery and cold cancel");
    $display("PASS disk proxy");
    $finish;
  end
