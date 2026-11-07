// SPDX-License-Identifier: GPL-3.0-or-later
// Experimental data-cache bank. No CPU/bus connection: the caller must hold
// MVA stable through victim read/writeback and pulse writeback_done only after
// successful completion. The 32-byte RAM read is synchronous, one cycle.
module arm920_cache_bank (
    input  logic         clk,
    input  logic         reset,
    input  logic [ 31:0] mva,
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
    assign needs_writeback = victim_valid && (|victim_dirty);
    assign refill_ready=!reset && !invalidate_all && !lock_write && !hit && (!needs_writeback || writeback_done);
    assign fill_commit = refill && refill_ready;
    // The RAM address uses encoded hit_way, so its actual write still needs
    // global hit. Metadata has fixed per-way matches and must not route that
    // global reduction back through every dirty flag's write enable.
    assign store_intent = store && !refill && !reset && !invalidate_all && !lock_write;
    assign store_commit = store_intent && hit;
    assign write_enable = fill_commit ? 32'hffffffff : (store_commit ? store_enable : 32'b0);
    assign write_data = fill_commit ? refill_line : store_line;
    assign write_way = fill_commit ? victim_way : hit_way;
    always_ff @(posedge clk) begin
        if (reset || invalidate_all) read_valid <= 0;
        else read_valid <= scan_read ? scan_valid : (read_victim ? victim_valid : hit);
    end
    arm920_cache_tags tags (
        .clk                 (clk),
        .reset               (reset),
        .mva                 (mva),
        .lookup_address      (lookup_address),
        .hit                 (hit),
        .hit_way             (hit_way),
        .hit_dirty           (hit_dirty),
        .hit_physical_line   (hit_pa),
        .victim_way          (victim_way),
        .victim_valid        (victim_valid),
        .victim_dirty        (victim_dirty),
        .victim_physical_line(victim_physical_line),
        .fill                (fill_commit),
        .fill_physical       (refill_physical),
        .write_hit           (store_intent && store_dirty && (|store_enable)),
        .invalidate_line     (1'b0),
        .invalidate_all      (invalidate_all),
        .clean_hit           (1'b0),
        .lock_write          (lock_write),
        .lock_base_in        (lock_base_in),
        .lock_base           (lock_base),
        .round_robin         (round_robin),
        .scan_segment        (scan_segment),
        .scan_way            (scan_way),
        .scan_valid          (scan_valid),
        .scan_dirty          (scan_dirty),
        .scan_physical_line  (scan_physical_line),
        .scan_clean          (scan_clean),
        .scan_invalidate     (scan_invalidate)
    );
    arm920_cache_lines lines (
        .clk          (clk),
        .read_segment (scan_read ? scan_segment : lookup_address[7:5]),
        .read_way     (scan_read ? scan_way : (read_victim ? victim_way : hit_way)),
        .read_line    (read_line),
        .write_segment(lookup_address[7:5]),
        .write_way    (write_way),
        .write_enable (write_enable),
        .write_line   (write_data)
    );
`ifndef SYNTHESIS
    always @(posedge clk)
        if (!reset && store_commit && |store_enable) begin
            if (mva[4] && |store_enable[15:0]) $fatal(1, "store crosses cache half boundary");
            if (!mva[4] && |store_enable[31:16]) $fatal(1, "store crosses cache half boundary");
        end
`endif
endmodule
