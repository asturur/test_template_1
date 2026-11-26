module refill_ram_tb;
  reg        clk = 0;
  reg        reset = 1;
  reg        cpu_cyc = 0;
  reg        cpu_lock = 0;
  reg [31:0] cpu_address = 32'h02000000;
  reg [ 2:0] cpu_cti = 3'b010;
  reg        wb_ack = 0;
  reg        wb_error = 0;
  reg        line_ready = 0;
  reg        line_reject = 0;
  reg        line_valid = 0;
  reg [63:0] line_data = 0;
  reg        line_wide = 0;
  reg        line_last = 0;
  reg        line_error = 0;
  reg        line_guaranteed = 1;
  wire cpu_ack, cpu_error, cpu_no_late_error;
  wire wb_cyc, wb_lock, line_req;
  wire [31:0] cpu_data;
  wire        candidate = cpu_cti == 3'b010 && cpu_address[4:0] == 0;
  localparam [31:0] SCALAR_DATA = 32'h42bc3dc9;

  ngage_arm9v2_refill #(
      .ENABLE                (1),
      .REGISTERED_SCALAR_PEER(1)
  ) dut (
      .clk               (clk),
      .reset             (reset),
      .cpu_cyc           (cpu_cyc),
      .cpu_lock          (cpu_lock),
      .cpu_line_candidate(candidate),
      .cpu_address       (cpu_address),
      .cpu_write         (1'b0),
      .cpu_sel           (4'hf),
      .cpu_cti           (cpu_cti),
      .cpu_bte           (2'b00),
      .cpu_ack           (cpu_ack),
      .cpu_error         (cpu_error),
      .cpu_no_late_error (cpu_no_late_error),
      .line_no_late_error(line_guaranteed),
      .cpu_data          (cpu_data),
      .wb_cyc            (wb_cyc),
      .wb_lock           (wb_lock),
      .wb_ack            (wb_ack),
      .wb_error          (wb_error),
      .wb_data           (SCALAR_DATA),
      .line_req          (line_req),
      .line_addr         (),
      .line_ready        (line_ready),
      .line_reject       (line_reject),
      .line_valid        (line_valid),
      .line_data         (line_data),
      .line_wide         (line_wide),
      .line_last         (line_last),
      .line_error        (line_error)
  );

  task tick;
    begin
      #2 clk = 1;
      #2 clk = 0;
      #1;
    end
  endtask

  function automatic [15:0] halfword(input int frame, input int half_index);
    return 16'((frame * 4259) ^ (half_index * 24737) ^ (half_index << 14));
  endfunction

  function automatic [31:0] expected_word(input int frame, input int word_index);
    return {halfword(frame, 2 * word_index + 1), halfword(frame, 2 * word_index)};
  endfunction

  task offer_line(input bit guaranteed);
    begin
      cpu_cyc         = 1;
      cpu_address     = 32'h02000000;
      cpu_cti         = 3'b010;
      line_guaranteed = guaranteed;
      line_ready      = 1;
      #1;
      if (!line_req || wb_cyc || cpu_ack || cpu_error) $fatal(1, "New line offered incorrectly");
      tick;
      line_ready = 0;
    end
  endtask

  int responses = 0;
  int error_responses = 0;
  int wide_beats = 0;
  int narrow_beats = 0;
  int bubbles = 0;
  int wrapped = 0;

  task exercise(input int frame, input int mode, input int fail_at, input int reset_at);
    int halfwords, popped, elapsed, width;
    bit failed, should_ack;
    reg [31:0] salt;
    begin
      offer_line(fail_at < 0);
      halfwords = 0;
      popped    = 0;
      elapsed   = 0;
      failed    = 0;
      salt      = 32'h721f1007 ^ (frame * 82695231);
      while (popped < 8 && elapsed != reset_at) begin
        cpu_address[4:2] = popped[2:0];
        cpu_cti = popped == 7 ? 3'b111 : 3'b010;
        salt = (salt << 1) ^ (salt[31] ? 32'h04c11db7 : 32'd0);
        width = (mode == 1 || (mode == 2 && halfwords % 4 == 0 && salt[6])) ? 4 : 1;
        line_valid = halfwords < 16 && !failed && (mode == 1 || salt[9] || salt[4]);
        line_wide = width == 4;
        line_error = line_valid && halfwords == fail_at;
        line_last = halfwords + width == 16 || line_error;
        line_data = {
          halfword(frame, halfwords + 3),
          halfword(frame, halfwords + 2),
          halfword(frame, halfwords + 1),
          halfword(frame, halfwords)
        };
        #1;
        should_ack = !failed && halfwords / 2 > popped;
        if (cpu_ack !== should_ack || cpu_error !== failed || wb_cyc || line_req)
          $fatal(
              1,
              "Reply timing frame=%0d beat=%0d consumed=%0d halfwords=%0d",
              frame,
              elapsed,
              popped,
              halfwords
          );
        if (cpu_no_late_error !== (should_ack && line_guaranteed))
          $fatal(1, "Wrong error guarantee");
        if (should_ack && cpu_data !== expected_word(frame, popped))
          $fatal(
              1,
              "Data frame=%0d word=%0d expected=%h got=%h",
              frame,
              popped,
              expected_word(
                  frame, popped
              ),
              cpu_data
          );
        if (should_ack) responses++;
        if (failed) error_responses++;
        if (!should_ack && !failed) bubbles++;
        if (should_ack || failed) popped++;
        if (line_valid) begin
          if (line_wide) wide_beats++;
          else narrow_beats++;
          halfwords += width;
        end
        failed = failed || line_error;
        tick;
        elapsed++;
        if (elapsed > 100) $fatal(1, "Line timeout");
      end
      if (popped == 8) wrapped++;
      line_valid = 0;
      line_last  = 0;
      line_error = 0;
      cpu_cyc    = 0;
      if (popped != 8) begin
        reset = 1;
        tick;
        reset = 0;
        #1;
        if (cpu_ack || cpu_error || wb_cyc || line_req) $fatal(1, "Reset left a stale owner");
      end
    end
  endtask

  task reject_to_scalar;
    begin
      offer_line(0);
      line_reject = 1;
      tick;
      line_reject = 0;
      #1;
      if (!wb_cyc || cpu_ack || cpu_error || line_req)
        $fatal(1, "Early rejection did not enter scalar fallback");
      tick;
      wb_ack = 1;
      #1;
      if (!cpu_ack || cpu_error || cpu_no_late_error || cpu_data !== SCALAR_DATA)
        $fatal(1, "Fallback lost its scalar response");
      tick;
      cpu_cyc = 0;
      #1;
      if (cpu_ack || cpu_error) $fatal(1, "Stale scalar response");
      wb_ack = 0;
      reset  = 1;
      tick;
      reset = 0;
    end
  endtask

  initial begin
    tick;
    reset = 0;
    for (int frame = 0; frame < 1600; frame++) begin
      if (frame % 8 == 0) reject_to_scalar;
      else if (frame % 8 == 1) exercise(frame, 0, frame % 15, -1);
      else if (frame % 8 == 2) exercise(frame, 0, -1, frame % 13);
      else exercise(frame, frame % 3, -1, -1);
    end
    if (responses < 7000 || error_responses < 700 || wide_beats < 1000 ||
            narrow_beats < 4000 || bubbles < 2000 || wrapped < 1000)
      $fatal(1, "Missing directed coverage");
    $display("PASS refill RAM responses=%0d errors=%0d wide=%0d narrow=%0d bubbles=%0d lines=%0d",
             responses, error_responses, wide_beats, narrow_beats, bubbles, wrapped);
    $finish;
  end
endmodule
