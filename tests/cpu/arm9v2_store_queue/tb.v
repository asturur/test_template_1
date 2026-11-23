`timescale 1ns / 1ps

module queue_case #(
    parameter AW = 2,
    parameter RANDOM_CYCLES = 100000
) (
    output reg done = 0
);
  localparam DEPTH = 1 << AW;

  reg clk = 0, reset = 1, push = 0, take = 0;
  reg [67:0] input_payload;
  wire full_ref, busy_ref, cyc_ref;
  wire full_ram, busy_ram, cyc_ram;
  wire [67:0] payload_ref, payload_ram;

  queue_reference #(
      .AW(AW)
  ) ref_queue (
      .i_clk(clk),
      .i_reset(reset),
      .i_push(push),
      .i_take(take),
      .i_address(input_payload[67:36]),
      .i_data(input_payload[35:4]),
      .i_ben(input_payload[3:0]),
      .o_full(full_ref),
      .o_busy(busy_ref),
      .o_cyc_nxt(cyc_ref),
      .o_address_nxt(payload_ref[67:36]),
      .o_data_nxt(payload_ref[35:4]),
      .o_ben_nxt(payload_ref[3:0])
  );
  ngage2_zap_store_queue #(
      .AW(AW)
  ) ram_queue (
      .i_clk(clk),
      .i_reset(reset),
      .i_push(push),
      .i_take(take),
      .i_address(input_payload[67:36]),
      .i_data(input_payload[35:4]),
      .i_ben(input_payload[3:0]),
      .o_full(full_ram),
      .o_busy(busy_ram),
      .o_cyc_nxt(cyc_ram),
      .o_address_nxt(payload_ram[67:36]),
      .o_data_nxt(payload_ram[35:4]),
      .o_ben_nxt(payload_ram[3:0])
  );

  reg [67:0] scoreboard[0:DEPTH-1];
  integer pending = 0;
  integer cycle = 0;
  integer checks = 0;
  integer resets_nonempty = 0;
  integer both_count = 0;
  integer even_collision_count = 0;
  integer odd_collision_count = 0;
  integer seed = 32'h0010_6a11 ^ AW;

  task compare;
    begin
      checks = checks + 1;
      if ({full_ram, busy_ram, cyc_ram, payload_ram} !== {full_ref, busy_ref, cyc_ref, payload_ref})
        $fatal(
            1,
            "AW=%0d cycle=%0d pending=%0d reset/push/take=%b%b%b RAM=%b%b%b:%h REF=%b%b%b:%h",
            AW,
            cycle,
            pending,
            reset,
            push,
            take,
            full_ram,
            busy_ram,
            cyc_ram,
            payload_ram,
            full_ref,
            busy_ref,
            cyc_ref,
            payload_ref
        );
      if ({full_ram, busy_ram, cyc_ram} !==
                {pending == DEPTH, pending != 0, pending > (take ? 1 : 0)})
        $fatal(1, "AW=%0d cycle=%0d full/busy/cyc differs from scoreboard", AW, cycle);
      if (cyc_ram && payload_ram !== scoreboard[take ? 1 : 0])
        $fatal(1, "AW=%0d cycle=%0d ordered store payload differs from scoreboard", AW, cycle);
    end
  endtask

  task step;
    input rst, enq, ack;
    integer slot;
    begin
      reset = rst;
      push = enq;
      input_payload = {$random(seed), $random(seed), 4'b0} | (cycle & 15);
      // Exercise even a late change of ACK without another memory clock.
      take = 0;
      #1;
      if (cycle != 0) compare();
      take = 1;
      #1;
      if (cycle != 0) compare();
      take = ack;
      #1;
      if (cycle != 0) compare();

      if (rst) begin
        if (pending != 0) resets_nonempty = resets_nonempty + 1;
        pending = 0;
      end else begin
        if ((enq && pending == DEPTH) || (ack && pending == 0))
          $fatal(1, "illegal sampled FIFO inputs in test");
        if (enq && ack) both_count = both_count + 1;
        if (ack) begin
          for (slot = 0; slot < DEPTH - 1; slot = slot + 1) scoreboard[slot] = scoreboard[slot+1];
          pending = pending - 1;
        end
        if (enq) begin
          scoreboard[pending] = input_payload;
          pending = pending + 1;
        end
      end

      clk   = 1;
      cycle = cycle + 1;
      #1;
      if (ram_queue.bypass_even) even_collision_count = even_collision_count + 1;
      if (ram_queue.bypass_odd) odd_collision_count = odd_collision_count + 1;
      compare();
      take = !ack;
      #1;
      compare();
      clk = 0;
      #1;
    end
  endtask

  integer head_slot, occupancy, action, slot, random_control;
  initial begin
    // Test every legal sampled transition at each head index and occupancy.
    // Populate distinct old slot values before resetting back to index zero.
    for (head_slot = 0; head_slot < DEPTH; head_slot = head_slot + 1)
    for (occupancy = 0; occupancy <= DEPTH; occupancy = occupancy + 1)
    for (action = 0; action < 5; action = action + 1) begin
      if (!(occupancy == 0 && (action == 1 || action == 3)) &&
                        !(occupancy == DEPTH && (action == 2 || action == 3))) begin
        step(1, 0, 0);
        repeat (DEPTH) step(0, 1, 0);
        repeat (DEPTH) step(0, 0, 1);
        repeat (head_slot) begin
          step(0, 1, 0);
          step(0, 0, 1);
        end
        repeat (occupancy) step(0, 1, 0);
        if (action == 4) step(1, 1, 1);
        else step(0, action[1], action[0]);
        // Carry on immediately, including after a full reset or
        // a final take/new push that must leave a bubble.
        step(0, pending < DEPTH, pending != 0);
      end
    end

    // Cover backpressure, multi-entry queues, wrap and repeated warm resets.
    repeat (RANDOM_CYCLES) begin
      random_control = $random(seed);
      if (random_control[9:2] == 0) step(1, random_control[1], random_control[0]);
      else step(0, random_control[1] && pending < DEPTH, random_control[0] && pending != 0);
    end
    while (pending != 0) step(0, 0, 1);
    if (resets_nonempty == 0 || both_count == 0 ||
            even_collision_count == 0 || odd_collision_count == 0)
      $fatal(1, "missing coverage");
    $display(
        "PASS AW=%0d cycles=%0d comparisons=%0d simultaneous=%0d nonempty_resets=%0d even_collisions=%0d odd_collisions=%0d",
        AW, cycle, checks, both_count, resets_nonempty, even_collision_count, odd_collision_count);
    done = 1;
  end
endmodule

module queue_tb;
  wire done1, done2, done3;
  queue_case #(
      .AW(1),
      .RANDOM_CYCLES(25000)
  ) small_queue (
      done1
  );
  queue_case #(
      .AW(2),
      .RANDOM_CYCLES(250000)
  ) production (
      done2
  );
  queue_case #(
      .AW(3),
      .RANDOM_CYCLES(25000)
  ) large_queue (
      done3
  );
  initial begin
    wait (done1 && done2 && done3);
    $finish;
  end
endmodule
