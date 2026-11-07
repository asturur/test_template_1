// SPDX-License-Identifier: GPL-3.0-or-later
// ARM920T-shaped cache metadata. Callers must write back a dirty victim
// before fill. MVA lookup and indexed physical reads take one clock.
// 16 KiB / 32-byte lines = 8 segments x 64 indices, MVA lookup and PA tags.
module arm920_cache_tags (
    input  logic        clk,
    input  logic        reset,
    input  logic [31:0] mva,
    output logic [31:0] lookup_address,
    output logic        hit,
    output logic [ 5:0] hit_way,
    output logic [ 1:0] hit_dirty,
    output logic [31:0] hit_physical_line,
    output logic [ 5:0] victim_way,
    output logic        victim_valid,
    output logic [ 1:0] victim_dirty,
    output logic [31:0] victim_physical_line,
    input  logic        fill,
    input  logic [31:0] fill_physical,
    input  logic        write_hit,
    input  logic        invalidate_line,
    input  logic        invalidate_all,
    input  logic        clean_hit,
    input  logic        lock_write,
    input  logic [ 5:0] lock_base_in,
    output logic [ 5:0] lock_base,
    input  logic        round_robin,
    // Indexed maintenance interface; caller excludes simultaneous accesses.
    input  logic [ 2:0] scan_segment,
    input  logic [ 5:0] scan_way,
    output logic        scan_valid,
    output logic [ 1:0] scan_dirty,
    output logic [31:0] scan_physical_line,
    input  logic        scan_clean,
    input  logic        scan_invalidate
);
    logic        valid       [0:7] [0:63];
    logic [ 1:0] dirty       [0:7] [0:63];
    logic [ 5:0] victim      [0:7];
    logic [ 5:0] random_state[0:7];
    logic [31:0] lookup_mva;
    wire [26:0] victim_pa_data, scan_pa_data, hit_pa_data;
    wire [2:0] segment = lookup_mva[7:5];
    assign lookup_address     = lookup_mva;
    assign scan_valid         = valid[scan_segment][scan_way];
    assign scan_dirty         = dirty[scan_segment][scan_way];
    assign scan_physical_line = {scan_pa_data, 5'b0};
    // All 64 ways are compared in parallel after one synchronous segment read.
    // Valid/dirty flags stay in registers for reset and indexed maintenance.
    wire [23:0] tag_data[0:63];
    wire fill_commit = fill && !hit && !reset && !invalidate_all &&
                       !lock_write && !scan_invalidate && !scan_clean;
    genvar tag_way;
    generate
        for (tag_way = 0; tag_way < 64; tag_way = tag_way + 1) begin : ways
            ngage_bram #(
                .AW         (3),
                .DW         (24),
                .READ_ONLY_B(1)
            ) tag_ram (
                .clk   (clk),
                .addr_a(segment),
                .addr_b(mva[7:5]),
                .data_a(lookup_mva[31:8]),
                .data_b(24'b0),
                .we_a  (fill_commit && victim_way == tag_way),
                .we_b  (1'b0),
                .q_a   (),
                .q_b   (tag_data[tag_way])
            );
        end
    endgenerate
    // Two read ports: indexed maintenance and the replacement candidate.
    ngage_bram #(
        .AW(9),
        .DW(27)
    ) physical_ram (
        .clk   (clk),
        .addr_a(fill_commit ? {segment, victim_way} : {scan_segment, scan_way}),
        .addr_b({mva[7:5], victim[mva[7:5]]}),
        .data_a(fill_physical[31:5]),
        .data_b(27'b0),
        .we_a  (fill_commit),
        .we_b  (1'b0),
        .q_a   (scan_pa_data),
        .q_b   (victim_pa_data)
    );
    // Standalone debug interface. Unused by cache_bank and removed there by
    // synthesis. This physical-hit query follows the tag result by one clock.
    ngage_bram #(
        .AW         (9),
        .DW         (27),
        .READ_ONLY_B(1)
    ) hit_physical_ram (
        .clk   (clk),
        .addr_a({segment, victim_way}),
        .addr_b({segment, hit_way}),
        .data_a(fill_physical[31:5]),
        .data_b(27'b0),
        .we_a  (fill_commit),
        .we_b  (1'b0),
        .q_a   (),
        .q_b   (hit_pa_data)
    );
    always_ff @(posedge clk) lookup_mva <= mva;
    integer i, j;
    logic [5:0] random_candidate;
    always_comb begin
        hit               = 0;
        hit_way           = 0;
        hit_dirty         = 0;
        hit_physical_line = 0;
        for (integer way = 0; way < 64; way = way + 1) begin
            if (!hit && valid[segment][way] && tag_data[way] == lookup_mva[31:8]) begin
                hit               = 1;
                hit_way           = 6'(way);
                hit_dirty         = dirty[segment][way];
                hit_physical_line = {hit_pa_data, 5'b0};
            end
        end
        random_candidate = random_state[segment];
        if (random_candidate < lock_base) random_candidate = lock_base;
        victim_way           = victim[segment];
        victim_valid         = valid[segment][victim_way];
        victim_dirty         = dirty[segment][victim_way];
        victim_physical_line = {victim_pa_data, 5'b0};
    end
    always_ff @(posedge clk) begin
        if (reset || invalidate_all) begin
            for (i = 0; i < 8; i = i + 1) begin
                for (j = 0; j < 64; j = j + 1) begin
                    valid[i][j] <= 0;
                    dirty[i][j] <= 0;
                end
                if (reset) begin
                    victim[i]       <= 0;
                    random_state[i] <= 6'(i + 1);
                end
            end
            if (reset) lock_base <= 0;
        end else if (lock_write) begin
            lock_base <= lock_base_in;
            for (i = 0; i < 8; i = i + 1) victim[i] <= lock_base_in;
        end else if (scan_invalidate) begin
            valid[scan_segment][scan_way] <= 0;
            dirty[scan_segment][scan_way] <= 0;
        end else if (scan_clean) begin
            dirty[scan_segment][scan_way] <= 0;
        end else begin
            if (invalidate_line && hit) begin
                valid[segment][hit_way] <= 0;
                dirty[segment][hit_way] <= 0;
            end else if (clean_hit && hit) dirty[segment][hit_way] <= 0;
            else if (write_hit && hit) dirty[segment][hit_way][lookup_mva[4]] <= 1;
            if (fill && !hit) begin
                valid[segment][victim_way] <= 1;
                dirty[segment][victim_way] <= 0;
                if (round_robin)
                    victim[segment] <= victim_way == 63 ? lock_base : victim_way + 1'b1;
                else begin
                    victim[segment] <= random_candidate;
                    random_state[segment] <= {
                        random_state[segment][4:0],
                        random_state[segment][5] ^ random_state[segment][4]
                    };
                end
            end
        end
    end
endmodule
