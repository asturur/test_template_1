`timescale 1ns / 1ps

module wb_completion_tb;
  localparam [2:0] BURST = 3'b010, END_BEAT = 3'b111;
  reg clk = 0, reset = 1;
  reg cyc = 0, lock = 0, write_word = 0, candidate = 0;
  reg [31:0] address = 0, write_data = 0;
  reg [2:0] cti = END_BEAT;
  wire ack, error, guarantee, wb_cyc, wb_lock, line_req;
  wire [31:0] data, wb_data;
  wire wb_ack, wb_error, wb_read_ack;
  reg line_ready = 0, reject_line = 0, line_valid = 0, line_wide = 0;
  reg line_last = 0, line_error = 0, promise_line = 1;
  reg [63:0] line_data = 0;
  reg ram_ack = 0, ram_read_ack = 0;
  reg [31:0] ram_data = 0;
  wire ram_req, ram_pending, slow_stb, slow_idle, slow_ack, slow_error;
  wire [31:0] slow_rdata;

  ngage_arm9v2_refill #(
      .ENABLE(1),
      .REGISTERED_SCALAR_PEER(1),
      .REGISTER_COMPLETION(1)
  ) refill (
      .clk(clk),
      .reset(reset),
      .cpu_cyc(cyc),
      .cpu_lock(lock),
      .cpu_line_candidate(candidate),
      .cpu_address(address),
      .cpu_write(write_word),
      .cpu_cti(cti),
      .cpu_bte(2'b00),
      .cpu_sel(4'b1111),
      .cpu_ack(ack),
      .cpu_error(error),
      .cpu_no_late_error(guarantee),
      .cpu_data(data),
      .wb_cyc(wb_cyc),
      .wb_lock(wb_lock),
      .wb_ack(wb_ack),
      .wb_error(wb_error),
      .wb_read_ack(wb_read_ack),
      .wb_data(wb_data),
      .line_req(line_req),
      .line_ready(line_ready),
      .line_reject(reject_line),
      .line_valid(line_valid),
      .line_wide(line_wide),
      .line_last(line_last),
      .line_error(line_error),
      .line_no_late_error(promise_line),
      .line_data(line_data)
  );

  ngage_cpu_memory_route #(
      .CPU_OWNS_SCALAR_REPLY(1)
  ) route (
      .clk(clk),
      .reset(reset),
      .master_cyc(wb_cyc),
      .master_stb(wb_cyc),
      .master_we(write_word),
      .master_code(1'b0),
      .master_address(address),
      .master_data(write_data),
      .master_sel(4'hf),
      .master_ack(wb_ack),
      .master_error(wb_error),
      .master_read_ack(wb_read_ack),
      .master_rdata(wb_data),
      .slow_stb(slow_stb),
      .slow_idle(slow_idle),
      .slow_ack(slow_ack),
      .slow_error(slow_error),
      .slow_rdata(slow_rdata),
      .ram_req(ram_req),
      .ram_pending(ram_pending),
      .ram_accept(ram_req),
      .ram_ack(ram_ack),
      .ram_read_ack(ram_read_ack),
      .ram_rdata(ram_data)
  );

  wire bus_cyc, bus_we;
  wire [31:0] bus_address, bus_data;
  reg device_ready = 0, device_error = 0;
  wire device_done = bus_cyc && device_ready;
  ngage_upp_bus_bridge #(
      .REGISTERED_MASTER(1)
  ) bridge (
      .clk(clk),
      .reset(reset),
      .master_cyc(slow_stb),
      .master_stb(slow_stb),
      .master_we(write_word),
      .master_code(1'b0),
      .master_address(address),
      .master_data(write_data),
      .master_sel(4'hf),
      .master_ack(slow_ack),
      .master_error(slow_error),
      .master_read_data(slow_rdata),
      .bus_cyc(bus_cyc),
      .bus_we(bus_we),
      .bus_address(bus_address),
      .bus_data(bus_data),
      .bus_ack(device_done && !device_error),
      .bus_error(device_done && device_error),
      .bus_read_data(32'habc0def0),
      .idle(slow_idle)
  );

  integer side_effects = 0;
  always @(posedge clk)
    if (device_done && bus_we && !device_error) begin
      if (bus_address != 32'h0c120624 || bus_data != 32'h12340000 + side_effects)
        $fatal(1, "Wrong MMIO side-effect packet");
      side_effects <= side_effects + 1;
    end

  task tick;
    #1 clk = 1;
    #1 clk = 0;
    #1;
  endtask

  task check_reply(input logic expect_ack, expect_error, present_offer,
                   input logic [31:0] expected_data);
    if ({ack, error, guarantee, wb_cyc} !== {expect_ack, expect_error, 1'b0, present_offer})
      $fatal(1, "Wrong scalar response or request owner");
    if ((expect_ack || expect_error) && data !== expected_data)
      $fatal(1, "Wrong scalar reply data");
  endtask

  task ram_return(input logic fast, input logic [31:0] value);
    ram_ack = 1;
    ram_read_ack = fast;
    ram_data = value;
    #1;
    if (fast) begin
      check_reply(1, 0, 1, value);
      tick;
    end else begin
      check_reply(0, 0, 1, 0);
      tick;
      ram_data = 32'hdeaddead;
      check_reply(1, 0, 0, value);
      tick;
    end
    ram_ack = 0;
    ram_read_ack = 0;
  endtask

  task slow_return(input logic err);
    device_ready = 0;
    device_error = err;
    repeat (3) begin
      tick;
      if (!bus_cyc || ack || error) $fatal(1, "Held slow MMIO packet lost");
    end
    device_ready = 1;
    tick;
    check_reply(0, 0, 1, 0);
    tick;
    check_reply(!err, err, 0, 32'habc0def0);
    tick;
    device_ready = 0;
  endtask

  // Drive a native burst with continuous or intentionally gapped input.
  // The same-edge reference assertion inside the adapter checks every beat.
  task native_line(input logic wide, inject_error);
    integer beat;
    integer taken;
    cyc = 1;
    address = 32'h0a000080;
    candidate = 1;
    cti = BURST;
    promise_line = !inject_error;
    line_wide = wide;
    repeat (2) begin
      tick;
      if (!line_req || ack || error || wb_cyc) $fatal(1, "Waiting line borrowed a scalar reply");
    end
    line_ready = 1;
    tick;
    line_ready = 0;
    taken = 0;
    for (beat = 0; taken < 8 && beat < 120; beat++) begin
      line_valid = inject_error ? beat == 0 : wide ? beat < 4 : beat < 48 && beat % 3 == 0;
      line_last  = !inject_error && (wide ? beat == 3 : beat == 45);
      line_error = inject_error && beat == 0;
      if (wide) line_data = {32'h11220001 + 2 * beat, 32'h11220000 + 2 * beat};
      else line_data = beat % 6 == 0 ? 64'(beat / 6) : 64'h1122;
      #1;
      if (ack || error) begin
        if (ack == inject_error || error != inject_error || guarantee == inject_error ||
            (!inject_error && data !== 32'h11220000 + taken))
          $fatal(1, "Native line changed data, error or guarantee at word %0d", taken);
        tick;
        taken++;
        address += 4;
        candidate = 0;
        if (taken == 7) cti = END_BEAT;
      end else tick;
    end
    if (taken != 8) $fatal(1, "Native line did not terminate");
    cyc = 0;
    line_valid = 0;
    line_last = 0;
    line_error = 0;
    tick;
  endtask

  initial begin
    tick;
    reset = 0;

    // Same-address MMIO writes under continuous donor CYC must each commit once.
    cyc = 1;
    address = 32'h0c120624;
    write_word = 1;
    write_data = 32'h12340000;
    slow_return(0);
    write_data = 32'h12340001;
    slow_return(0);
    if (side_effects != 2) $fatal(1, "Lost or duplicated an MMIO write");
    write_word = 0;
    slow_return(1);

    // Keep SWP lock live during a same-edge RAM read and a buffered write reply.
    lock = 1;
    address = 32'h0a000004;
    tick;
    ram_return(1, 32'h76301234);
    write_word = 1;
    tick;
    if (!wb_lock || !ram_pending) $fatal(1, "SWP write lost its reservation");
    ram_return(0, 32'h22222222);
    if (!wb_lock) $fatal(1, "SWP lock dropped while returning the write");
    lock = 0;
    write_word = 0;

    // Cancel an old read while it is owned; a younger scalar cannot take its ACK.
    address = 32'h0a000010;
    tick;
    cyc = 0;
    tick;
    address = 32'h0a000014;
    cyc = 1;
    ram_ack = 1;
    ram_read_ack = 1;
    #1;
    if (ram_req || ack || error) $fatal(1, "Cancelled read acknowledged the next command");
    tick;
    ram_ack = 0;
    ram_read_ack = 0;
    tick;
    ram_return(1, 32'h33334444);

    // A line rejected before its first word remains scalar until the end beat.
    address = 32'h0a000040;
    candidate = 1;
    cti = BURST;
    line_ready = 1;
    tick;
    line_ready  = 0;
    reject_line = 1;
    tick;
    reject_line = 0;
    #1;
    if (!ram_req || line_req || guarantee) $fatal(1, "Rejected line did not fall back to scalar");
    tick;
    ram_return(1, 32'h55556666);
    address = address + 4;
    candidate = 0;
    cti = END_BEAT;
    tick;
    ram_return(1, 32'h77778888);

    // Reset kills a captured, still unconsumed MMIO completion.
    address = 32'h0c120624;
    device_error = 0;
    device_ready = 1;
    tick;
    tick;
    check_reply(1, 0, 0, 32'habc0def0);
    reset = 1;
    #1;
    if (ack || error || wb_cyc || line_req) $fatal(1, "Old reply escaped reset");
    cyc = 0;
    tick;
    reset = 0;
    device_ready = 0;
    tick;

    native_line(1, 0);
    native_line(0, 0);
    native_line(1, 1);
    $display(
        "PASS owned Wishbone completion, scalar bypass, MMIO once, cancel/reset, and exact line credits");
    $finish;
  end
endmodule
