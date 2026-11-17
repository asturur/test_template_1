// SPDX-License-Identifier: GPL-3.0-or-later
// Shared I/D cache bank. Mutation pulses capture data and metadata together;
// both commit on the following edge. The caller must drain before reuse and hold
// MVA stable through victim read/writeback and pulse writeback_done only after
// successful completion. The 32-byte RAM read is synchronous, one cycle.
module arm920_cache_bank #(
    parameter READ_ONLY = 0
) (
    input  logic         clk,
    input  logic         reset,
    input  logic [ 31:0] mva,
    input wire [31:0] indexed_mva,
    input  logic [  7:0] lookup_segment_select,
    // Registered, validated line-result owner. This selects the existing RAM
    // read port; no speculative tag fact may perform a data/metadata mutation.
    input  wire         indexed_read,
    input  wire         indexed_store,
    input  wire [  2:0] indexed_segment,
    input  wire [  5:0] indexed_way,
    // Independent owned read-B address; write-A and dirty metadata retain
    // their existing owner. The caller excludes mixed-port same-slot reads.
    input  wire         data_probe,
    input  wire [  2:0] data_probe_segment,
    input  wire [  5:0] data_probe_way,
    output wire         data_commit_valid,
    output wire [  8:0] data_commit_index,
    output logic         hit,
    output logic [  5:0] hit_way,
    input  logic         read_victim,
    output logic         read_valid,
    output logic [255:0] read_line,
    output logic         victim_valid,
    output logic [  1:0] victim_dirty,
    output logic [ 31:0] victim_physical_line,
    output logic         needs_writeback,
    input  logic         writeback_done,
    input  logic         refill,
    input  logic [ 31:0] refill_physical,
    input  logic [255:0] refill_line,
    output logic         refill_ready,
    input  logic         store,
    input  logic         store_dirty,
    input  logic [ 31:0] store_enable,
    input  logic [255:0] store_line,
    input  logic         invalidate_all,
    input  logic         lock_write,
    input  logic [  5:0] lock_base_in,
    output logic [  5:0] lock_base,
    input  logic         round_robin,
    input  logic         scan_read,
    input  logic [  2:0] scan_segment,
    input  logic [  5:0] scan_way,
    output logic         scan_valid,
    output logic [  1:0] scan_dirty,
    output logic [ 31:0] scan_physical_line,
    input  logic         scan_clean,
    input  logic         scan_invalidate
);
  wire  [ 31:0] lookup_address;
  logic [  1:0] hit_dirty;
  logic [ 31:0] hit_pa;
  logic [  5:0] victim_way;
  logic [ 31:0] write_enable;
  logic [255:0] write_data;
  logic [  5:0] write_way;
  logic fill_commit, store_intent, store_commit;
  reg [2:0] commit_segment;
  reg [5:0] commit_way;
  reg [31:0] commit_enable;
  reg [255:0] commit_data;
  wire cancel_commit = reset || invalidate_all || lock_write || scan_clean || scan_invalidate;
  assign data_commit_valid = |commit_enable && !cancel_commit;
  assign data_commit_index = {commit_way, commit_segment};
  always @(posedge clk) begin
    commit_segment <= indexed_store ? indexed_segment : lookup_address[7:5];
    commit_way     <= write_way;
    commit_enable  <= write_enable;
    commit_data    <= write_data;
  end
  assign needs_writeback = victim_valid && (|victim_dirty);
  assign refill_ready=!reset && !invalidate_all && !lock_write && !scan_clean && !scan_invalidate && !hit && (!needs_writeback || writeback_done);
  assign fill_commit = refill && refill_ready;
  // The RAM address uses encoded hit_way, so its actual write still needs
  // global hit. Metadata has fixed per-way matches and must not route that
  // global reduction back through every dirty flag's write enable.
  assign store_intent = store && !refill && !cancel_commit;
  assign store_commit = store_intent && (indexed_store || hit);
  assign write_enable = fill_commit ? 32'hffffffff : (store_commit ? store_enable : 32'b0);
  assign write_data = refill ? refill_line : store_line;
  assign write_way = refill ? victim_way : indexed_store ? indexed_way : hit_way;
  always_ff @(posedge clk) begin
    if (reset || invalidate_all) read_valid <= 0;
    else read_valid <= scan_read ? scan_valid : indexed_read ? 1'b1 : (read_victim ? victim_valid : hit);
  end
  arm920_cache_tags #(
      .READ_ONLY(READ_ONLY)
  ) tags (
      .clk                  (clk),
      .reset                (reset),
      .mva                  (mva),
      .indexed_mva          (indexed_mva),
      .lookup_segment_select(lookup_segment_select),
      .lookup_address       (lookup_address),
      .hit                  (hit),
      .hit_way              (hit_way),
      .hit_dirty            (hit_dirty),
      .hit_physical_line    (hit_pa),
      .victim_way           (victim_way),
      .victim_valid         (victim_valid),
      .victim_dirty         (victim_dirty),
      .victim_physical_line (victim_physical_line),
      .fill                 (fill_commit),
      .fill_physical        (refill_physical),
      .write_hit            (store_intent && !indexed_store && store_dirty && (|store_enable)),
      .indexed_store        (store_intent && indexed_store && store_dirty && (|store_enable)),
      .indexed_way          (indexed_way),
      .invalidate_line      (1'b0),
      .invalidate_all       (invalidate_all),
      .clean_hit            (1'b0),
      .lock_write           (lock_write),
      .lock_base_in         (lock_base_in),
      .lock_base            (lock_base),
      .round_robin          (round_robin),
      .scan_read            (scan_read),
      .scan_segment         (scan_segment),
      .scan_way             (scan_way),
      .scan_valid           (scan_valid),
      .scan_dirty           (scan_dirty),
      .scan_physical_line   (scan_physical_line),
      .scan_clean           (scan_clean),
      .scan_invalidate      (scan_invalidate)
  );
  arm920_cache_lines lines (
      .clk          (clk),
      .read_segment (data_probe ? data_probe_segment : scan_read ? scan_segment : indexed_read ? indexed_segment : lookup_address[7:5]),
      .read_way     (data_probe ? data_probe_way : scan_read ? scan_way : indexed_read ? indexed_way : (read_victim ? victim_way : hit_way)),
      .read_line    (read_line),
      .write_segment(commit_segment),
      .write_way    (commit_way),
      .write_enable (cancel_commit ? 32'b0 : commit_enable),
      .write_line   (commit_data)
  );
  // synthesis translate_off
`ifndef SYNTHESIS
  always @(posedge clk)
    if (!reset && data_probe && (scan_read || read_victim ||
        (data_commit_valid && data_commit_index == {data_probe_way, data_probe_segment})))
      $fatal(1, "data probe collided with another RAM owner");
  always @(posedge clk)
    if (!reset && indexed_store) begin
      if (!store || refill || scan_read || scan_clean || scan_invalidate || read_victim)
        $fatal(1, "indexed store overlapped another bank owner");
      if (indexed_mva[7:5] != indexed_segment)
        $fatal(1, "indexed data/metadata segment ownership differs");
      // Same-slot overlap is legal: independent registered data owners and
      // tag forwarding replace the former serialized same-slot prohibition.
      if (commit_segment == indexed_segment && commit_way == indexed_way &&
          data_commit_valid && !tags.forward_pending && !tags.forward_recent)
        $fatal(1, "same-slot pipeline lacks dirty forwarding");
    end
  always @(posedge clk)
    if (!reset && READ_ONLY && store_intent)
      $fatal(1, "read-only instruction cache received a store intent");
  always @(posedge clk)
    if (!reset && store_commit && |store_enable) begin
      if ((indexed_store ? indexed_mva[4] : mva[4]) && |store_enable[15:0]) $fatal(1, "store crosses cache half boundary");
      if (!(indexed_store ? indexed_mva[4] : mva[4]) && |store_enable[31:16]) $fatal(1, "store crosses cache half boundary");
    end
`endif
  // synthesis translate_on
endmodule
