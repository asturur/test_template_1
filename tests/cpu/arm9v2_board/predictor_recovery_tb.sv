module predictor_recovery_tb;
  bit clk, reset, clear, lookup;
  bit redirect, select_predicted, use_recovered, thumb, accept;
  bit update, update_thumb, update_taken, update_hit;
  bit repair;
  bit [1:0] repair_action, update_kind, update_state;
  bit [2:0] repair_pointer;
  bit [3:0] repair_count;
  bit [31:0] pc, normal_pc, recovered_pc, sequential_pc;
  bit [31:0] update_pc, update_target, repair_link;
  wire [1:0] hit, taken;
  wire [1:0] state_bits[0:1], kind[0:1];
  wire [31:0] target [0:1];
  wire [ 2:0] pointer[0:1];
  wire [ 3:0] count  [0:1];

  `define PREDICTOR_COMMON(lane) \
        .i_clk(clk), .i_reset(reset), .i_clear(clear), .i_lookup(lookup), \
        .i_pc(pc), .i_pc_sequential(sequential_pc), .i_sel_redirect(redirect), \
        .i_sel_predicted(select_predicted), .i_thumb(thumb), .i_accept(accept), \
        .i_update(update), .i_update_pc(update_pc), .i_update_target(update_target), \
        .i_update_thumb(update_thumb), .i_update_taken(update_taken), .i_update_hit(update_hit), \
        .i_update_state(update_state), .i_update_kind(update_kind), .i_repair(repair), \
        .i_repair_pointer(repair_pointer), .i_repair_count(repair_count), \
        .i_repair_action(repair_action), .i_repair_link(repair_link), \
        .o_hit(hit[lane]), .o_taken(taken[lane]), .o_target(target[lane]), \
        .o_state(state_bits[lane]), .o_kind(kind[lane]), \
        .o_pointer(pointer[lane]), .o_count(count[lane])
  reference_predict reference_dut (
      .i_pc_redirect(use_recovered ? recovered_pc : normal_pc),
      `PREDICTOR_COMMON(0)
  );
  ngage2_arm9v2_predict #(
      .PARALLEL_RECOVERY(1)
  ) parallel_dut (
      .i_pc_redirect  (normal_pc),
      .i_pc_recovered (recovered_pc),
      .i_use_recovered(use_recovered),
      `PREDICTOR_COMMON(1)
  );
  `undef PREDICTOR_COMMON

  function automatic [7:0] folded(input bit [31:0] address);
    return address[8:1] ^ address[16:9];
  endfunction

  bit [255:0] valid_slots = 0;
  bit expected_valid = 0;
  int cycles = 0, normal = 0, recovered = 0, collided_normal = 0, collided_recovered = 0;
  int selected_collisions = 0, held_writes = 0, clears = 0, resets = 0;
  int hits = 0, both_valid = 0, different_valid = 0, aliases = 0;

  task automatic inspect;
    if ({hit[0], taken[0], target[0], state_bits[0], kind[0], pointer[0], count[0]} !==
            {hit[1], taken[1], target[1], state_bits[1], kind[1], pointer[1], count[1]})
      $fatal(1, "Predictor changed at cycle %0d PC %h", cycles, pc);
    if (reference_dut.read_valid_bit !== expected_valid ||
            parallel_dut.selected_valid !== expected_valid)
      $fatal(1, "Wrong held/forwarded valid at cycle %0d PC %h", cycles, pc);
  endtask

  task automatic tick;
    begin
      #1;
      if (cycles > 1) inspect;
      if (lookup) begin
        pc = redirect ? (use_recovered ? recovered_pc : normal_pc) :
                     select_predicted ? target[0] : sequential_pc;
      end
      if (reset || clear) begin
        valid_slots = 0;
        expected_valid = 0;
        if (reset) resets++;
        if (clear) clears++;
      end else begin
        if (update) begin
          valid_slots[folded(update_pc)] = 1;
          if (!lookup) held_writes++;
          if (lookup && folded(update_pc) == folded(pc)) begin
            selected_collisions++;
            if (pc[31:9] != update_pc[31:9]) aliases++;
          end
          if (lookup && redirect) begin
            if (folded(normal_pc) == folded(update_pc)) collided_normal++;
            if (folded(recovered_pc) == folded(update_pc)) collided_recovered++;
          end
        end
        if (lookup) begin
          expected_valid = valid_slots[folded(pc)];
          if (redirect) begin
            if (use_recovered) recovered++;
            else normal++;
            if (valid_slots[folded(normal_pc)] && valid_slots[folded(recovered_pc)]) both_valid++;
            if (valid_slots[folded(normal_pc)] != valid_slots[folded(recovered_pc)])
              different_valid++;
          end
        end
      end
      #1 clk = 1;
      #2 clk = 0;
      #1;
      if (cycles > 1) inspect;
      if (hit[0]) hits++;
      cycles++;
    end
  endtask

  bit [31:0] rng = 32'h2cda71a8;

  function automatic [31:0] advance(input bit [31:0] value);
    bit [31:0] result;
    result = value ^ (value << 13);
    result = result ^ (result >> 17);
    return result ^ (result << 5);
  endfunction

  initial begin
    reset  = 1;
    lookup = 1;
    tick;
    reset = 0;
    normal_pc = 32'h01240002;
    recovered_pc = normal_pc + 2;
    redirect = 1;
    update = 1;
    update_pc = normal_pc;
    update_target = 32'h01243000;
    update_taken = 1;
    thumb = 1;
    update_thumb = 1;
    tick;
    if (hit !== 2'b11 || taken !== 2'b11) $fatal(1, "Normal write-through miss");
    use_recovered = 1;
    update = 0;
    tick;
    if (hit !== 0) $fatal(1, "Normal slot leaked into recovered slot");
    update = 1;
    update_pc = recovered_pc;
    tick;
    if (hit !== 2'b11 || taken !== 2'b11) $fatal(1, "Recovered write-through miss");
    lookup = 0;
    use_recovered = 0;
    update_pc = normal_pc;
    update_target = 32'h01244000;
    tick;
    if (hit !== 2'b11 || target[0] !== 32'h01243000)
      $fatal(1, "Unselected write changed held lookup");
    clear = 1;
    tick;
    if (hit !== 0) $fatal(1, "Clear failed on held lookup");
    clear = 0;
    for (int iteration = 0; iteration < 30000; iteration++) begin
      rng = advance(rng);
      reset = rng[9:0] == 10'h3e0;
      clear = rng[15:10] == 6'd21;
      lookup = rng[16] || rng[17];
      redirect = rng[18];
      select_predicted = rng[19];
      use_recovered = rng[20];
      thumb = rng[21];
      update = rng[22] || rng[23];
      update_hit = rng[24];
      update_state = rng[26:25];
      update_kind = rng[28:27];
      update_taken = rng[29];
      accept = rng[30];
      repair = rng[31] && rng[0];
      repair_pointer = rng[3:1];
      repair_count = rng[7:4];
      repair_action = rng[9:8];
      rng = advance(rng);
      normal_pc = {16'h0124, rng[15:2], 2'b10};
      recovered_pc = normal_pc + 2;
      sequential_pc = {16'h012c, rng[31:17], 1'b0};
      repair_link = rng;
      update_thumb = rng[24] ? !thumb : thumb;
      update_target = {1'b0, rng[31:2], 1'b0};
      case (rng[26:25])
        0: update_pc = normal_pc;
        1: update_pc = recovered_pc;
        2: update_pc = sequential_pc;
        3: update_pc = recovered_pc ^ 32'h00400000;
      endcase
      tick;
    end
    if (normal < 4000 || recovered < 4000 || collided_normal < 1000 ||
            collided_recovered < 1000 || selected_collisions < 2000 ||
            held_writes < 4000 || clears < 400 || resets < 10 ||
            hits < 1000 || both_valid < 500 || different_valid < 1000 || aliases < 500)
      $fatal(1, "Missing predictor test coverage");
    $display(
        "PASS parallel predictor cycles=%0d normal=%0d recovered=%0d normal_writes=%0d recovered_writes=%0d collisions=%0d held_writes=%0d clears=%0d resets=%0d hits=%0d both=%0d different=%0d aliases=%0d",
        cycles, normal, recovered, collided_normal, collided_recovered, selected_collisions,
        held_writes, clears, resets, hits, both_valid, different_valid, aliases);
    $finish;
  end
endmodule
