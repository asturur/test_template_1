module scalar_reply_tb;
  localparam [2:0] BURST = 3'b010, END_BEAT = 3'b111;
  reg clk = 0, reset = 1;
  reg cpu_cyc = 0, cpu_lock = 0, cpu_write = 0, line_candidate = 0;
  reg [31:0] address = 0;
  reg [ 2:0] cti = END_BEAT;
  wire scalar, scalar_lock, route_ack, route_error;
  wire cpu_ack, cpu_error, cpu_guaranteed, line_req;
  wire [31:0] cpu_data, route_data;
  reg line_ready = 0, line_reject = 0, line_valid = 0, line_last = 0;
  reg [63:0] line_data = 0;
  reg ram_grant = 1, ram_ack = 0;
  reg [31:0] ram_data = 0;
  reg slow_ack = 0, slow_error = 0;
  wire ram_req, ram_pending, ram_response, slow_stb;

  ngage_arm9v2_refill #(
      .ENABLE(1),
      .REGISTERED_SCALAR_PEER(1)
  ) refill (
      .clk(clk),
      .reset(reset),
      .cpu_cyc(cpu_cyc),
      .cpu_lock(cpu_lock),
      .cpu_line_candidate(line_candidate),
      .cpu_address(address),
      .cpu_write(cpu_write),
      .cpu_sel(4'hf),
      .cpu_cti(cti),
      .cpu_bte(2'd0),
      .cpu_ack(cpu_ack),
      .cpu_error(cpu_error),
      .cpu_no_late_error(cpu_guaranteed),
      .cpu_data(cpu_data),
      .wb_cyc(scalar),
      .wb_lock(scalar_lock),
      .wb_ack(route_ack),
      .wb_error(route_error),
      .wb_data(route_data),
      .line_req(line_req),
      .line_ready(line_ready),
      .line_reject(line_reject),
      .line_valid(line_valid),
      .line_data(line_data),
      .line_wide(1'b1),
      .line_last(line_last),
      .line_error(1'b0),
      .line_no_late_error(1'b1)
  );

  ngage_cpu_memory_route #(
      .CPU_OWNS_SCALAR_REPLY(1)
  ) route (
      .clk(clk),
      .reset(reset),
      .master_cyc(scalar),
      .master_stb(scalar),
      .master_we(cpu_write),
      .master_code(1'b0),
      .master_address(address),
      .master_data(32'h87654321),
      .master_sel(4'hf),
      .master_ack(route_ack),
      .master_error(route_error),
      .master_rdata(route_data),
      .slow_stb(slow_stb),
      .slow_idle(1'b1),
      .slow_ack(slow_ack),
      .slow_error(slow_error),
      .slow_rdata(32'h99775533),
      .ram_req(ram_req),
      .ram_pending(ram_pending),
      .ram_accept(ram_req && ram_grant),
      .ram_ack(ram_ack),
      .ram_rdata(ram_data),
      .ram_response(ram_response)
  );

  task tick;
    begin
      #1 clk = 1;
      #1 clk = 0;
      #1;
    end
  endtask

  task request;
    input [31:0] start_addr;
    input [2:0] cycle_type;
    input candidate;
    begin
      cpu_cyc = 1;
      address = start_addr;
      cti = cycle_type;
      line_candidate = candidate;
      #1;
    end
  endtask

  task return_ram;
    input [31:0] data;
    begin
      ram_data = data;
      ram_ack  = 1;
      #1;
      if (!cpu_ack || cpu_error || cpu_guaranteed || cpu_data !== data)
        $fatal(1, "Owned SDRAM completion lost, delayed or granted a line promise");
      tick;
      ram_ack = 0;
    end
  endtask

  integer beat;
  reg [31:0] word_index;
  initial begin
    tick;
    reset = 0;

    // Hold the first offer and then complete two adjacent scalar words.
    ram_grant = 0;
    request(32'h0a000004, END_BEAT, 0);
    repeat (3) begin
      if (!ram_req || ram_pending || cpu_ack || cpu_error)
        $fatal(1, "Scalar offer held before admission incorrectly");
      tick;
    end
    ram_grant = 1;
    tick;
    if (!ram_pending || ram_req) $fatal(1, "First scalar did not capture");
    return_ram(32'h12345678);
    request(32'h0a000008, END_BEAT, 0);
    if (!ram_req || cpu_ack) $fatal(1, "Adjacent scalar did not offer on the response edge");
    tick;
    return_ram(32'h22334455);

    // Advance from SDRAM to a registered slow-bus error with CYC held.
    request(32'h0c120004, END_BEAT, 0);
    if (!slow_stb || cpu_error) $fatal(1, "Slow request delayed after SDRAM");
    tick;
    slow_error = 1;
    #1;
    if (!cpu_error || cpu_ack || cpu_data !== 32'h99775533)
      $fatal(1, "Owned slow error dropped or delayed");
    tick;
    slow_error = 0;

    // A reply coincident with cancellation is raw at the route, but the
    // adapter suppresses it using the real donor CYC.
    request(32'h0a00000c, END_BEAT, 0);
    tick;
    cpu_cyc = 0;
    ram_ack = 1;
    #1;
    if (!route_ack || ram_response || cpu_ack || cpu_error)
      $fatal(1, "Cancelled SDRAM completion reached the donor");
    tick;
    ram_ack = 0;

    // A new line can wait for readiness. A stale scalar response never
    // acknowledges that line, even while accepting the offer.
    request(32'h0a000020, BURST, 1);
    slow_ack   = 1;
    slow_error = 1;
    repeat (3) begin
      if (!line_req || scalar || cpu_ack || cpu_error) $fatal(1, "Stale scalar reply reached line");
      tick;
    end
    line_ready = 1;
    tick;
    line_ready = 0;
    slow_ack   = 0;
    slow_error = 0;
    cpu_lock   = 1;
    if (scalar_lock || cpu_ack) $fatal(1, "Owned line inherited a younger SWP lock");

    // Eight consecutive acknowledgements use the guaranteed line data.
    line_valid = 1;
    line_data  = 64'habcdef0112345678;
    tick;
    for (beat = 0; beat < 8; beat = beat + 1) begin
      word_index = beat;
      if (!cpu_ack || cpu_error || !cpu_guaranteed ||
                cpu_data !== (beat[0] ? 32'habcdef01 : 32'h12345678))
        $fatal(1, "Lost, corrupt or delayed line acknowledgement %0d", word_index);
      line_valid = beat < 3;
      line_last  = beat == 2;
      tick;
      address = address + 4;
      line_candidate = 0;
      if (beat == 6) cti = END_BEAT;
      #1;
    end
    cpu_lock = 0;

    // A rejected offer resumes as scalar without the no-late-error
    // promise. A following lock keeps an otherwise eligible line scalar.
    request(32'h0a000040, BURST, 1);
    line_ready = 1;
    tick;
    line_ready  = 0;
    line_reject = 1;
    tick;
    line_reject = 0;
    if (!ram_req || cpu_ack || line_req) $fatal(1, "Rejected line did not offer scalar");
    tick;
    return_ram(32'hdeadbeef);
    request(32'h0a000044, END_BEAT, 0);
    tick;
    return_ram(32'hcdcdbbbb);
    cpu_lock = 1;
    request(32'h0a000060, BURST, 1);
    if (!scalar_lock || !ram_req || line_req) $fatal(1, "SWP lock did not block a line");
    tick;
    return_ram(32'hfadedabc);
    request(32'h0a000064, END_BEAT, 0);
    tick;
    return_ram(32'haabbccdd);
    cpu_lock  = 0;

    // Cancellation before grant cannot create RAM ownership.
    ram_grant = 0;
    request(32'h0a00000c, END_BEAT, 0);
    tick;
    cpu_cyc = 0;
    tick;
    if (ram_pending || cpu_ack || cpu_error) $fatal(1, "Unaccepted request acquired the route");

    // Cancel an accepted word and begin a new scalar before its late
    // physical response. The old payload drains before the next grant.
    ram_grant = 1;
    request(32'h0a000004, END_BEAT, 0);
    tick;
    cpu_cyc = 0;
    tick;
    request(32'h0a000008, END_BEAT, 0);
    ram_ack = 1;
    #1;
    if (route_ack || cpu_ack || ram_req) $fatal(1, "Late reply borrowed a younger request");
    tick;
    ram_ack = 0;
    #1;
    if (!ram_req || cpu_ack) $fatal(1, "Late reply left the route blocked");
    tick;
    return_ram(32'h55558888);

    // Reset clears the adapter token and routes before an old reply.
    request(32'h0a00000c, END_BEAT, 0);
    tick;
    reset   = 1;
    ram_ack = 1;
    tick;
    if (cpu_ack || cpu_error || ram_pending || ram_req || line_req)
      $fatal(1, "Reset leaked the previous scalar owner");
    $display(
        "PASS scalar response ownership: held, adjacent, line, rejected, lock, error, cancellation and reset");
    $finish;
  end
endmodule
