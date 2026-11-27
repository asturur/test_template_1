`timescale 1ns / 1ps
module packed_write_enable_tb;
  parameter integer LINE_BYTES = 32;
  localparam integer DATA_BITS = 8 * LINE_BYTES;
  localparam integer WORDS = LINE_BYTES / 4;
  reg clk = 0, clken = 1, commit = 1;
  reg live = 0, saved = 0, fill = 0;
  reg [1:0] way_select = 2'b11;
  reg [31:0] live_address = 0, saved_address = 0;
  reg [3:0] live_mask = 0, saved_mask = 0;
  reg read_row = 0, write_row = 0;
  reg [DATA_BITS-1:0] data = 0;
  wire [LINE_BYTES-1:0] mask;
  wire write_enable;

  // Enumerate the write-operation truth table of the generated controller.
  // The CPU contract exercises which operation can occur in each state.
  ngage2_zap_dcache_fsm #(
      .CACHE_LINE(LINE_BYTES)
  ) fsm (
      .i_clk(clk),
      .i_reset(1'b1),
      .i_address(live_address),
      .i_ben(live_mask),
      .o_cache_line_ben(mask),
      .o_cache_line_write(write_enable)
  );

  wire [DATA_BITS-1:0] reference_q[0:1];
  wire [DATA_BITS-1:0] candidate_q[0:1];
  genvar w;
  generate
    for (w = 0; w < 2; w = w + 1) begin : way
      wire commit_way = commit && way_select[w];
      wire [LINE_BYTES-1:0] way_mask = mask & {LINE_BYTES{commit_way}};
      ngage2_zap_ram_bytes #(
          .BYTES(LINE_BYTES),
          .DEPTH(256)
      ) reference (
          .i_clk(clk),
          .i_clken(clken),
          .i_wr_en(way_mask),
          .i_wr_data(data),
          .i_wr_addr({7'b0, write_row}),
          .i_rd_addr({7'b0, read_row}),
          .o_rd_data(reference_q[w])
      );
      ngage2_zap_ram_bytes #(
          .BYTES(LINE_BYTES),
          .DEPTH(256),
          .EXPLICIT_WRITE_ENABLE(1)
      ) candidate (
          .i_clk(clk),
          .i_clken(clken),
          .i_wr_en(way_mask),
          .i_wr_data(data),
          .i_wr_addr({7'b0, write_row}),
          .i_rd_addr({7'b0, read_row}),
          .o_rd_data(candidate_q[w]),
          .i_write_enable(commit_way && write_enable)
      );
    end
  endgenerate

  reg [DATA_BITS-1:0] expected_data[0:1][0:1];
  reg [DATA_BITS-1:0] expected_q[0:1];
  reg [LINE_BYTES-1:0] expected_mask;
  integer cases = 0, collisions = 0, live_word, saved_word, live_lanes, saved_lanes, operations, i;

  task step;
    integer way_index, lane;
    begin
      #1;
      expected_mask = 0;
      if (live) expected_mask[live_address[$clog2(LINE_BYTES)-1:0]+:4] = live_mask;
      if (saved)
        expected_mask[saved_address[$clog2(
            LINE_BYTES
        )-1:0]+:4] = expected_mask[saved_address[$clog2(
            LINE_BYTES
        )-1:0]+:4] | saved_mask;
      if (fill) expected_mask = {LINE_BYTES{1'b1}};
      if (mask !== expected_mask || write_enable !== (|expected_mask))
        $fatal(1, "Controller byte or word enable mismatch at case %0d", cases);
      if (clken) begin
        for (way_index = 0; way_index < 2; way_index = way_index + 1) begin
          expected_q[way_index] = expected_data[way_index][read_row];
          if (commit && way_select[way_index]) begin
            if (read_row == write_row && write_enable) collisions = collisions + 1;
            for (lane = 0; lane < LINE_BYTES; lane = lane + 1)
            if (expected_mask[lane])
              expected_data[way_index][write_row][lane*8+:8] = data[lane*8+:8];
          end
        end
      end
      clk = 1;
      #1;
      for (way_index = 0; way_index < 2; way_index = way_index + 1)
      if (reference_q[way_index] !== expected_q[way_index] ||
                    candidate_q[way_index] !== expected_q[way_index])
        $fatal(1, "Byte lane or OLD_DATA mismatch at case %0d way %0d", cases, way_index);
      clk   = 0;
      cases = cases + 1;
    end
  endtask

  initial begin
    force fsm.live_write = live;
    force fsm.saved_write = saved;
    force fsm.fill_write = fill;
    force fsm.address = saved_address;
    force fsm.ben = saved_mask;
    fill = 1;
    step;
    write_row = 1;
    read_row  = 1;
    step;
    for (live_word = 0; live_word < WORDS; live_word = live_word + 1)
    for (saved_word = 0; saved_word < WORDS; saved_word = saved_word + 1)
    for (live_lanes = 0; live_lanes < 16; live_lanes = live_lanes + 1)
    for (saved_lanes = 0; saved_lanes < 16; saved_lanes = saved_lanes + 1)
    for (operations = 0; operations < 8; operations = operations + 1) begin
      {fill, saved, live} = operations[2:0];
      live_address = live_word * 4;
      saved_address = saved_word * 4;
      live_mask = live_lanes[3:0];
      saved_mask = saved_lanes[3:0];
      clken = cases % 7 != 0;
      commit = cases % 5 != 0;
      way_select = (cases ^ (cases >> 7)) & 3;
      write_row = cases[0];
      read_row = cases[0] ^ cases[3];
      for (i = 0; i < LINE_BYTES; i = i + 1) data[i*8+:8] = (cases >> 4) ^ (cases * 31) ^ (17 * i);
      step;
    end
    commit = 0;
    clken = 1;
    read_row = 0;
    step;
    read_row = 1;
    step;
    if (!collisions) $fatal(1, "No mixed-port write/read collision exercised");
    $display("PASS packed cache WREN line_bytes=%0d cases=%0d collisions=%0d", LINE_BYTES, cases,
             collisions);
    $finish;
  end
endmodule
