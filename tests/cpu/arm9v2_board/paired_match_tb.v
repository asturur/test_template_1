module held_pair_tb;
  reg clk = 0;
  reg stall = 0;
  reg move_owner = 0;
  reg [31:0] check_address = 32'h0a109804;
  reg [31:0] m_address = 32'h0a101030;
  reg [31:0] w_address = 32'h0a109804;
  wire [31:0] second_word;

  ngage2_zap_dcache #(
      .CACHE_SIZE(16384),
      .CACHE_LINE(32),
      .WAYS(2)
  ) dut (
      .i_clk(clk),
      .i_reset(1'b0),
      .i_address_check(check_address),
      .i_address(w_address),
      .i_pair_m_address(m_address),
      .i_lock_owner_move(move_owner),
      .i_stall(stall),
      .o_short_next_word(second_word)
  );

  task edge_check;
    input expected_match;
    input [31:0] expected_address;
    input [31:0] expected_word;
    begin
      #1 clk = 1;
      #1;
      if (dut.short_pair_matches_w !== expected_match ||
                dut.short_pair_address !== expected_address ||
                second_word !== expected_word)
        $fatal(
            1,
            "pair sample match=%b address=%h data=%h expected=%b/%h/%h",
            dut.short_pair_matches_w,
            dut.short_pair_address,
            second_word,
            expected_match,
            expected_address,
            expected_word
        );
      clk = 0;
      #1;
    end
  endtask

  initial begin
    // Inject the FSM hold and the second-word result independently of
    // memory traffic to drive all cache/owner handoffs in isolation.
    force dut.hold = 1'b0;
    force dut.short_next_word = 32'h10203040;

    // New cache sample while W retains its current address.
    edge_check(1'b1, 32'h0a109804, 32'h10203040);

    // A stale sample matches the old W but not the promoted M.
    force dut.hold = 1'b1;
    force dut.short_next_word = 32'h11223344;
    check_address = 32'h0a101030;
    move_owner = 1'b1;
    edge_check(1'b0, 32'h0a109804, 32'h10203040);

    // Still held after the promotion, so W remains a mismatch.
    move_owner = 1'b0;
    w_address  = 32'h0a101030;
    edge_check(1'b0, 32'h0a109804, 32'h10203040);

    // The same held sample now matches a returning M owner only.
    move_owner = 1'b1;
    m_address  = 32'h0a109804;
    edge_check(1'b1, 32'h0a109804, 32'h10203040);

    // Cache sampling resumes and advances with a new owner.
    force dut.hold = 1'b0;
    m_address = 32'h0a101030;
    w_address = 32'h0a109804;
    edge_check(1'b1, 32'h0a101030, 32'h11223344);

    // Input stall makes the cache hold even while W changes owner.
    stall = 1'b1;
    check_address = 32'h0a108844;
    m_address = check_address;
    edge_check(1'b0, 32'h0a101030, 32'h11223344);

    $display("PASS held and sampled pair data across W promotion");
    $finish;
  end
endmodule
