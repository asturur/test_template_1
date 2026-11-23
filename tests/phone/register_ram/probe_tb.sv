module probe_tb;
  reg clk = 0, reset = 1;
  reg offered = 0, live = 0, in_we = 0, permit = 0;
  reg periodic_active = 1, cbus8d_written = 0;
  reg [31:0] in_address = 0, in_data = 0;
  reg [3:0] in_sel = 0;
  wire req, we;
  wire [31:0] address, lookup_address, data;
  wire [3:0] sel;
  wire [1:0] claim, bad, ready, seen;
  wire [31:0] dout[0:1];

  ngage_upp_request_stage #(
      .EXPLICIT_LIVE(1)
  ) stage (
      .clk(clk),
      .reset(reset),
      .in_cyc(offered),
      .in_stb(offered),
      .in_live(live),
      .in_we(in_we),
      .in_code(1'b0),
      .in_address(in_address),
      .in_data(in_data),
      .in_sel(in_sel),
      .out_cyc(req),
      .out_stb(),
      .out_we(we),
      .out_code(),
      .out_address(address),
      .out_lookup_address(lookup_address),
      .out_data(data),
      .out_sel(sel)
  );

  for (genvar mode = 0; mode < 2; mode++) begin : ports
    ngage_icu_extra #(
        .PROBE_PREFETCH(mode)
    ) target (
        .clk(clk),
        .reset(reset),
        .req(req),
        .commit(permit),
        .we(we),
        .periodic_active(periodic_active),
        .addr(address),
        .lookup_addr(lookup_address),
        .din(data),
        .sel(sel),
        .claim(claim[mode]),
        .bad(bad[mode]),
        .dout(dout[mode]),
        .cbus8d_written(cbus8d_written),
        .sysc74_seen(seen[mode]),
        .ready(ready[mode])
    );
  end

  int comparisons = 0;
  logic [31:0] sampled_read;
  task inspect;
    if ({claim[0], bad[0], ready[0], seen[0]} !== {claim[1], bad[1], ready[1], seen[1]})
      $fatal(1, "Changed ownership, error or cycle at %h", address);
    if (req && claim[0] && ready[0] && !we && dout[0] !== dout[1])
      $fatal(1, "Wrong read at %h sel=%h legacy=%h RAM=%h", address, sel, dout[0], dout[1]);
    comparisons++;
  endtask

  task tick;
    begin
      #2 inspect;
      clk = 1;
      #2 clk = 0;
      #1 inspect;
    end
  endtask

  task transaction(input bit write, input logic [31:0] adr, input logic [31:0] value,
                   input logic [3:0] mask, input bit error_expected, input bit want_claim,
                   input bit cancel, input int wait_clocks);
    int clocks;
    begin
      in_we = write;
      in_address = adr;
      in_data = value;
      in_sel = mask;
      offered = 1;
      live = 1;
      tick;
      offered = 0;
      // A new offered address cannot change the active lookup. The
      // following clocks deliberately scramble the unowned input.
      in_address = ~adr;
      in_data = ~value;
      clocks = 0;
      while (!ready[0]) begin
        tick;
        clocks++;
        if (clocks > 70) $fatal(1, "Device did not become ready");
      end
      if (!req || claim[0] !== want_claim || bad[0] !== error_expected ||
                (wait_clocks >= 0 && wait_clocks != clocks))
        $fatal(1, "Wrong directed result %h clocks=%0d", adr, clocks);
      if (!write && want_claim && !error_expected) sampled_read = dout[1];
      if (!cancel) begin
        permit = 1;
        tick;
        permit = 0;
      end
      live = 0;
      tick;
      if (req) $fatal(1, "Request owner remained live");
    end
  endtask

  task unlock_probe;
    cbus8d_written = 0;
    transaction(1, 32'h0c120074, 3, 15, 1, 1, 0, 0);
    cbus8d_written = 1;
    transaction(1, 32'h0c120074, 3, 7, 1, 1, 0, 0);
    transaction(0, 32'h0c120074, 0, 15, 1, 1, 0, 0);
    transaction(1, 32'h0c120074, 2, 15, 1, 1, 0, 0);
    transaction(1, 32'h0c120074, 3, 15, 0, 1, 1, 0);
    transaction(0, 32'h0c14d000, 0, 15, 1, 1, 0, 0);
    transaction(1, 32'h0c120074, 3, 15, 0, 1, 0, 0);
  endtask

  initial begin
    tick;
    reset = 0;
    // Probe attempts during scrub retain the same fault and finish edge.
    transaction(1, 32'h0c14d010, 32'hffffffff, 15, 1, 1, 0, 63);
    for (int epoch = 0; epoch < 3; epoch++) begin
      transaction(0, 32'h0c14d000, 0, 15, 1, 1, 0, 0);
      transaction(0, 32'h0c14d014, 0, 15, 0, 0, 0, 0);
      unlock_probe;
      for (int row = 0; row < 5; row++) begin
        transaction(0, 32'h0c14d000 + 4 * row, 0, 15, 0, 1, 0, 0);
        if (sampled_read !== 0) $fatal(1, "Scrub did not clear");
        for (int mask = 0; mask < 16; mask++) begin
          transaction(1, 32'h0c1200fc, 32'h1234fe00 | 32'(mask), 15, 0, 1, 0, 0);
          transaction(1, 32'h0c14d000 + 4 * row, 32'h5a012345 * (row + mask + 1), mask[3:0], 0, 1,
                      mask[1:0] == 1, 0);
          transaction(0, 32'h0c14d000 + 4 * row, 0, 15, 0, 1, 0, 0);
          transaction(0, 32'h0c14d000 + 4 * row, 0, ~mask[3:0], 0, 1, 0, 0);
          transaction(0, 32'h0c1200fc, 0, 15, 0, 1, 0, 1);
        end
      end
      reset = 1;
      tick;
      reset = 0;
      repeat (64) tick;
    end
    if (comparisons < 4500) $fatal(1, "Missing transaction coverage");
    $display("PASS ICU probe prefetch %0d comparisons", comparisons);
    $finish;
  end
endmodule
