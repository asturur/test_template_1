// SPDX-License-Identifier: GPL-3.0-or-later
// ARM920T: one 64-entry fully associative, mixed-page-size translation table.
// CAM compare -> eight-way grouped selection -> synchronous BRAM payload.
module arm920_tlb_bank (
    input wire clk,
    input wire reset,
    input wire lookup,
    input wire [31:0] lookup_mva,
    output wire result_valid,
    output wire result_hit,
    output wire [37:0] result_payload,
    input wire fill,
    input wire [31:0] fill_mva,
    input wire [37:0] fill_payload,
    input wire invalidate,
    input wire invalidate_mva,
    input wire [31:0] invalidate_address,
    input wire lock_write,
    input wire [31:0] lock_data,
    output wire [31:0] lock_read
);
  reg [21:0] tags [0:63];
  reg [ 1:0] kinds[0:63];
  reg [63:0] valid, preserved;
  reg [5:0] base, victim;
  reg preserve;
  reg [63:0] hit_vector;
  reg compare_valid, read_valid, read_hit;
  wire mutate = fill || invalidate || lock_write;
  wire [7:0] group_hit;
  wire [2:0] group_way[0:7];
  wire [2:0] selected_group;
  wire [5:0] selected_entry;
  wire [37:0] payload;

  function covers;
    input [21:0] tag;
    input [1:0] kind;
    input [31:0] address;
    begin
      case (kind)
        0: covers = tag[21:10] == address[31:20];
        1: covers = tag[21:6] == address[31:16];
        2: covers = tag[21:2] == address[31:12];
        default: covers = tag == address[31:10];
      endcase
    end
  endfunction

  function [2:0] pick8;
    input [7:0] bits;
    begin
      casez (bits)
        8'b???????1: pick8 = 0;
        8'b??????10: pick8 = 1;
        8'b?????100: pick8 = 2;
        8'b????1000: pick8 = 3;
        8'b???10000: pick8 = 4;
        8'b??100000: pick8 = 5;
        8'b?1000000: pick8 = 6;
        default: pick8 = 7;
      endcase
    end
  endfunction

  genvar group;
  generate
    for (group = 0; group < 8; group = group + 1) begin : groups
      assign group_hit[group] = |hit_vector[group*8+:8];
      assign group_way[group] = pick8(hit_vector[group*8+:8]);
    end
  endgenerate
  assign selected_group = pick8(group_hit);
  assign selected_entry = {selected_group, group_way[selected_group]};
  assign result_valid = read_valid && !mutate;
  assign result_hit = read_hit;
  assign result_payload = payload;
  assign lock_read = {base, victim, 19'b0, preserve};

  ngage_bram #(
      .AW(6),
      .DW(38),
      .READ_ONLY_B(1)
  ) entries (
      .clk(clk),
      .addr_a(victim),
      .addr_b(selected_entry),
      .data_a(fill_payload),
      .data_b(38'b0),
      .we_a(fill && !invalidate && !lock_write),
      .we_b(1'b0),
      .q_a(),
      .q_b(payload)
  );

  integer slot;
  always @(posedge clk) begin
    if (reset) begin
      valid <= 0;
      preserved <= 0;
      base <= 0;
      victim <= 0;
      preserve <= 0;
      hit_vector <= 0;
      compare_valid <= 0;
      read_valid <= 0;
      read_hit <= 0;
    end else begin
      compare_valid <= lookup && !mutate;
      read_valid <= compare_valid && !mutate;
      read_hit <= |group_hit;
      for (slot = 0; slot < 64; slot = slot + 1)
      hit_vector[slot] <= lookup && valid[slot] && covers(tags[slot], kinds[slot], lookup_mva);
      if (invalidate) begin
        for (slot = 0; slot < 64; slot = slot + 1)
        if (invalidate_mva ? covers(tags[slot], kinds[slot], invalidate_address) : !preserved[slot])
          valid[slot] <= 0;
      end else if (lock_write) begin
        base <= lock_data[31:26];
        victim <= lock_data[25:20];
        preserve <= lock_data[0];
      end else if (fill) begin
        // Software must invalidate changed mappings. Also avoid ambiguous
        // CAM hits if overlapping mappings are presented to this bank.
        for (slot = 0; slot < 64; slot = slot + 1)
        if (covers(
                tags[slot], kinds[slot], fill_mva
            ) || covers(
                fill_mva[31:10], fill_payload[37:36], {tags[slot], 10'b0}
            ))
          valid[slot] <= 0;
        tags[victim] <= fill_mva[31:10];
        kinds[victim] <= fill_payload[37:36];
        valid[victim] <= 1;
        preserved[victim] <= preserve;
        victim <= victim == 63 ? base : victim + 1'b1;
      end
    end
  end
endmodule
