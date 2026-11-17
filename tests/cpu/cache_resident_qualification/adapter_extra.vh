  integer lock_pulses = 0, lock_before;
  always @(posedge clk) if (!reset && lock_done) lock_pulses = lock_pulses + 1;
  task pending_adapter_lock;
    begin
      rd=0;wr=0;inv=0;clean=0;lock=0;probe=0;fault=0;align_fault=0;tlb_busy=0;swp=0;
      enabled=1;cacheable=1;bufferable=1;reset=1;repeat(2)tick();reset=0;tick();
      warm_pair('h6000,'h7000);
      addr='h6000;pa=addr;din=32'h91628374;ben=15;wr=1;rd=0;
      lock_before=lock_pulses;tick();
      if(!dut.launched)$fatal(1,"adapter store did not launch");
      lock=1;tick();lock=0;
      if(!dut.lock_pending)$fatal(1,"adapter lost pulsed lock while launched");
      while(!request_ack)tick();tick();wr=0;
      repeat(3)tick();
      if(lock_pulses!=lock_before+1||dut.lock_pending)$fatal(1,"adapter lock not applied once");
      transaction(0,'h6000,'h6000,0,32'h91628374,15,0);
      $display("PASS adapter pulsed pending lock after live store: one done, correct following read");
    end
  endtask
