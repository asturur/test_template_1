module tb;
  parameter TOP_REGISTER = 1;
  localparam [1:0] CALL = 1, RETURN = 2;
  reg clk = 0, reset = 0, clear = 0;
  reg lookup = 0, thumb = 0, accept = 0;
  reg update = 0, repair = 0;
  reg [31:0] pc = 0, repair_link = 0;
  reg [2:0] repair_pointer = 0;
  reg [3:0] repair_count = 0;
  reg [1:0] kind = 0, action = 0;

  wire [44:0] actual, expected;
  `define PREDICT_PORTS(result) \
    .i_clk(clk), .i_reset(reset), .i_clear(clear), .i_lookup(lookup), \
    .i_pc(pc), .i_pc_redirect(pc), .i_pc_sequential(pc), \
    .i_sel_redirect(1'b0), .i_sel_predicted(1'b0), .i_thumb(thumb), .i_accept(accept), \
    .i_update(update), .i_update_pc(pc), .i_update_target(32'hd00df000), \
    .i_update_thumb(thumb), .i_update_taken(1'b1), .i_update_hit(1'b0), \
    .i_update_state(2'b10), .i_update_kind(kind), \
    .i_repair(repair), .i_repair_pointer(repair_pointer), .i_repair_count(repair_count), \
    .i_repair_action(action), .i_repair_link(repair_link), \
    .o_hit(result[44]), .o_taken(result[43]), .o_target(result[42:11]), \
    .o_state(result[10:9]), .o_kind(result[8:7]), \
    .o_pointer(result[6:4]), .o_count(result[3:0])

  ngage2_arm9v2_predict #(
      .RAS_TOP_FF(TOP_REGISTER)
  ) candidate (
      `PREDICT_PORTS(actual)
  );
  reference_predict #(
      .RAS_TOP_FF(TOP_REGISTER)
  ) original (
      `PREDICT_PORTS(expected)
  );
  `undef PREDICT_PORTS

  integer edges = 0;
  integer i, p, n, a, c;

  task tick;
    begin
      #1 clk = 1;
      #1 clk = 0;
      #1;
      edges = edges + 1;
      if (actual !== expected)
        $fatal(1, "edge %0d predicted %h, expected %h", edges, actual, expected);
      if (TOP_REGISTER && actual[3:0] != 0 && candidate.ras_top !== original.ras_top)
        $fatal(1, "edge %0d top %h, expected %h", edges, candidate.ras_top, original.ras_top);
    end
  endtask

  task select_branch;
    input take_return, is_thumb;
    begin
      thumb = is_thumb;
      pc = take_return ? (is_thumb ? 32'h402 : 32'h300) : (is_thumb ? 32'h202 : 32'h100);
      kind = take_return ? RETURN : CALL;
    end
  endtask

  task train;
    begin
      update = 1;
      lookup = 1;
      for (i = 0; i < 4; i = i + 1) begin
        select_branch(i[1], i[0]);
        tick;
      end
      update = 0;
    end
  endtask

  initial begin
    reset = 1;
    tick;
    reset = 0;
    train;
    // Saturation and underflow with consecutive ARM/Thumb calls and returns.
    for (i = 0; i < 32; i = i + 1) begin
      select_branch(i[4], i[0]);
      lookup = 1;
      tick;
      lookup = 0;
      accept = 1;
      tick;
      accept = 0;
      if (i == 15 && actual[3:0] != 8 || i == 31 && actual[3:0] != 0)
        $fatal(1, "Depth did not saturate/empty at edge %0d", edges);
    end

    // Advance a new lookup on every cycle while accepting the previous one.
    lookup = 1;
    for (i = 0; i < 32; i = i + 1) begin
      select_branch(i[4], i[0]);
      accept = i != 0;
      tick;
    end
    lookup = 0;
    accept = 1;
    tick;
    accept = 0;
    if (actual[3:0] != 0) $fatal(1, "Consecutive returns failed to empty stack");

    // Every pointer, depth, repair action, and simultaneous control combination.
    // Insert known nonidentical entries before repairs to make addressing errors visible.
    for (p = 0; p < 8; p = p + 1)
    for (n = 0; n <= 8; n = n + 1)
    for (a = 0; a < 4; a = a + 1)
    for (c = 0; c < 32; c = c + 1) begin
      for (i = 0; i < 8; i = i + 1) begin
        repair = 1;
        action = CALL;
        repair_pointer = i[2:0];
        repair_count = {1'b0, i[2:0]};
        repair_link = 32'hf1000000 + 32'(i * 4) + 32'(i[0]);
        tick;
      end
      select_branch(1, c[0]);
      lookup = 1;
      tick;
      {reset, clear, repair, accept, lookup} = c[4:0];
      action = a[1:0];
      repair_pointer = p[2:0];
      repair_count = n[3:0];
      repair_link = 32'hdec0dead ^ edges;
      tick;
      {reset, clear, repair, accept, lookup} = 0;
      tick;
      if (c[4] || c[3]) train;
    end
    $display(
        "PASS RAS registered mode=%0d, %0d matched edges, all repair pointers/depths/actions and control priorities",
        TOP_REGISTER, edges);
    $finish;
  end
endmodule
