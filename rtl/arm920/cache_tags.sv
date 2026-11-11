// SPDX-License-Identifier: GPL-3.0-or-later
// ARM920T-shaped cache metadata. Callers must write back a dirty victim
// before fill. MVA lookup takes two clocks; indexed physical reads take one clock.
// Mutation pulses capture a record, committed on the following edge.
// Callers serialize mutations and allow fresh lookup stages after commit.
// 16 KiB / 32-byte lines = 8 segments x 64 indices, MVA lookup and PA tags.
module arm920_cache_tags #(
    parameter READ_ONLY = 0
) (
    input  logic        clk,
    input  logic        reset,
    input  logic [31:0] mva,
    input  logic [ 7:0] lookup_segment_select,
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
    input  logic        scan_read,
    input  logic [ 2:0] scan_segment,
    input  logic [ 5:0] scan_way,
    output logic        scan_valid,
    output logic [ 1:0] scan_dirty,
    output logic [31:0] scan_physical_line,
    input  logic        scan_clean,
    input  logic        scan_invalidate
);
    logic        valid        [ 0:7] [0:63];
    // Byte lane 3 stores dirty halves in the existing simple-dual tag M10K.
    // Reset/invalidate clear valid FFs; stale RAM metadata is masked until fill.
    wire  [31:0] packed_tag   [0:63];
    reg   [ 1:0] commit_dirty;
    logic [ 5:0] victim       [ 0:7];
    logic [ 5:0] random_state [ 0:7];
    reg [31:0] read_mva, lookup_mva;
    reg [63:0] read_valid_bits, match_bits;
    reg [1:0] read_dirty_bits[0:63], compare_dirty[0:63];
    reg [5:0] read_victim_way, compare_victim_way;
    reg        compare_victim_valid;
    reg [ 1:0] compare_victim_dirty;
    reg [26:0] compare_victim_pa;
    reg [31:0] commit_mva, commit_pa;
    reg  [63:0] commit_selected;
    wire [63:0] selected_ways;
    reg  [ 5:0] commit_way;
    reg commit_fill, commit_write, commit_clean, commit_invalidate;
    reg commit_rr;
    wire commit_allowed = !reset && !invalidate_all && !lock_write &&
                          !scan_clean && !scan_invalidate;
    wire [26:0] victim_pa_data, scan_pa_data, hit_pa_data;
    wire [2:0] segment = lookup_mva[7:5];
    assign lookup_address     = lookup_mva;
    assign scan_valid         = valid[scan_segment][scan_way];
    assign scan_dirty         = READ_ONLY || !scan_valid ? 2'b00 : packed_tag[scan_way][25:24];
    assign scan_physical_line = {scan_pa_data, 5'b0};
    // All 64 ways are compared in parallel after one synchronous segment read.
    // Valid flags stay resettable; writable-cache dirty flags share tag RAM.
    wire [23:0] tag_data                                    [0:63];
    wire        fill_commit = commit_fill && commit_allowed;
    wire [ 2:0] commit_segment = commit_mva[7:5];
    wire [ 7:0] valid_by_segment                            [0:63];

    genvar tag_way, lookup_segment;
    generate
        for (tag_way = 0; tag_way < 64; tag_way = tag_way + 1) begin : ways
            for (
                lookup_segment = 0; lookup_segment < 8; lookup_segment = lookup_segment + 1
            ) begin : flag_read
                assign valid_by_segment[tag_way][lookup_segment] = valid[lookup_segment][tag_way];
            end
            if (READ_ONLY) begin : instruction_tags
                ngage_bram #(
                    .AW         (3),
                    .DW         (24),
                    .READ_ONLY_B(1)
                ) tag_ram (
                    .clk   (clk),
                    .addr_a(commit_segment),
                    .addr_b(mva[7:5]),
                    .data_a(commit_mva[31:8]),
                    .data_b(24'b0),
                    .we_a  (fill_commit && commit_way == tag_way),
                    .we_b  (1'b0),
                    .q_a   (),
                    .q_b   (tag_data[tag_way])
                );
                assign packed_tag[tag_way] = {8'b0, tag_data[tag_way]};
            end else begin : packed_dirty_tags
                // Indexed maintenance owns port B from TAG_WAIT onward.
                // Metadata commits write only lane 3, preserving all tag bits.
                wire scan_mutation = !reset && !invalidate_all && !lock_write &&
                    (scan_clean || scan_invalidate) && scan_way == tag_way;
                wire committed_mutation = commit_allowed && commit_selected[tag_way] &&
                    (commit_write || commit_clean || commit_invalidate);
                wire filling = fill_commit && commit_way == tag_way;
                wire [1:0] next_dirty = (commit_clean || commit_invalidate) ? 2'b00 :
                    commit_dirty | (commit_mva[4] ? 2'b10 : 2'b01);
                wire [3:0] byte_enable = scan_mutation ? 4'b1000 : filling ? 4'b1111 :
                    committed_mutation ? 4'b1000 : 4'b0000;
                ngage_bram #(
                    .AW         (3),
                    .DW         (32),
                    .BYTE_WIDTH (8),
                    .READ_ONLY_B(1)
                ) tag_ram (
                    .clk(clk),
                    .addr_a((scan_clean || scan_invalidate) ? scan_segment : commit_segment),
                    .addr_b(scan_read ? scan_segment : mva[7:5]),
                    .data_a({
                        6'b0, (scan_mutation || filling) ? 2'b00 : next_dirty, commit_mva[31:8]
                    }),
                    .data_b(32'b0),
                    .we_a(byte_enable),
                    .we_b(4'b0000),
                    .q_a(),
                    .q_b(packed_tag[tag_way])
                );
                assign tag_data[tag_way] = packed_tag[tag_way][23:0];
            end
        end
    endgenerate
    // Two read ports: indexed maintenance and the replacement candidate.
    ngage_bram #(
        .AW(9),
        .DW(27)
    ) physical_ram (
        .clk   (clk),
        .addr_a(fill_commit ? {commit_segment, commit_way} : {scan_segment, scan_way}),
        .addr_b({mva[7:5], victim[mva[7:5]]}),
        .data_a(commit_pa[31:5]),
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
        .addr_a({commit_segment, commit_way}),
        .addr_b({segment, hit_way}),
        .data_a(commit_pa[31:5]),
        .data_b(27'b0),
        .we_a  (fill_commit),
        .we_b  (1'b0),
        .q_a   (),
        .q_b   (hit_pa_data)
    );
    // Read flags alongside tag RAM, then register parallel comparisons.
    // Consumers wait for both stages; collision results are discarded while
    // a mutation drains, never forwarded from mixed-port RAM collisions.
    integer lookup_way;
    always @(posedge clk) begin
        read_mva             <= mva;
        lookup_mva           <= read_mva;
        read_victim_way      <= victim[mva[7:5]];
        compare_victim_way   <= read_victim_way;
        // Select the victim flags from the same captured segment snapshot.
        // Split segment/way selection across the existing two lookup edges.
        compare_victim_valid <= read_valid_bits[read_victim_way];
        compare_victim_pa    <= victim_pa_data;
        for (lookup_way = 0; lookup_way < 64; lookup_way = lookup_way + 1) begin
            read_valid_bits[lookup_way] <= |(valid_by_segment[lookup_way] & lookup_segment_select);
            match_bits[lookup_way] <= !reset && !invalidate_all &&
                read_valid_bits[lookup_way] && tag_data[lookup_way] == read_mva[31:8];
        end
        commit_dirty      <= hit_dirty;
        commit_mva        <= lookup_mva;
        commit_pa         <= fill_physical;
        commit_way        <= victim_way;
        commit_selected   <= selected_ways;
        commit_rr         <= round_robin;
        commit_fill       <= commit_allowed && fill && !hit;
        commit_write      <= commit_allowed && write_hit;
        commit_clean      <= commit_allowed && clean_hit;
        commit_invalidate <= commit_allowed && invalidate_line;
    end
    // The instruction-only instance has no dirty state or dirty pipeline.
    // Read/write caches retain the same first-read and compare-stage registers.
    genvar dirty_way;
    generate
        if (READ_ONLY) begin : read_only_dirty_pipeline
            assign compare_victim_dirty = 2'b00;
        end else begin : writable_dirty_pipeline
            always @(posedge clk) compare_victim_dirty <= read_dirty_bits[read_victim_way];
        end
        for (dirty_way = 0; dirty_way < 64; dirty_way = dirty_way + 1) begin : dirty_pipeline
            if (READ_ONLY) begin : read_only
                assign read_dirty_bits[dirty_way] = 2'b00;
                assign compare_dirty[dirty_way]   = 2'b00;
            end else begin : writable
                assign read_dirty_bits[dirty_way] = packed_tag[dirty_way][25:24] & {2{read_valid_bits[dirty_way]}};
                always @(posedge clk) compare_dirty[dirty_way] <= read_dirty_bits[dirty_way];
            end
        end
    endgenerate
    // A balanced tree preserves lowest-way priority even for duplicate tags.
    // A procedural "if (!hit)" loop builds a serial 64-way selection chain.
    wire [126:0] hit_tree;
    wire [  5:0] way_tree  [0:126];
    wire [  1:0] dirty_tree[0:126];
    genvar tree_node;
    generate
        for (tree_node = 0; tree_node < 64; tree_node = tree_node + 1) begin : hit_leaves
            assign hit_tree[63+tree_node]   = match_bits[tree_node];
            assign way_tree[63+tree_node]   = tree_node;
            assign dirty_tree[63+tree_node] = compare_dirty[tree_node];
        end
        for (tree_node = 0; tree_node < 63; tree_node = tree_node + 1) begin : hit_nodes
            assign hit_tree[tree_node] = hit_tree[2*tree_node+1] | hit_tree[2*tree_node+2];
            assign way_tree[tree_node] = hit_tree[2 * tree_node + 1] ?
                way_tree[2 * tree_node + 1] : way_tree[2 * tree_node + 2];
            assign dirty_tree[tree_node] = hit_tree[2 * tree_node + 1] ?
                dirty_tree[2 * tree_node + 1] : dirty_tree[2 * tree_node + 2];
        end
    endgenerate
    // Preserve lowest-way priority without routing metadata writes through
    // hit_way's binary encoder and a second decoder. Prefix ORs are balanced
    // reductions of constant slices; each flag has its own fixed write enable.
    wire [63:0] matched_ways = hit_tree[126:63];
    genvar flag_segment, flag_way;
    generate
        for (flag_way = 0; flag_way < 64; flag_way = flag_way + 1) begin : metadata_ways
            if (flag_way == 0) begin : first_way
                assign selected_ways[flag_way] = matched_ways[flag_way];
            end else begin : later_way
                assign selected_ways[flag_way] = matched_ways[flag_way] &&
                                                  !(|matched_ways[flag_way-1:0]);
            end
            for (
                flag_segment = 0; flag_segment < 8; flag_segment = flag_segment + 1
            ) begin : segments
                always_ff @(posedge clk) begin
                    if (reset || invalidate_all) begin
                        valid[flag_segment][flag_way] <= 0;
                    end else if (!lock_write) begin
                        if (scan_invalidate) begin
                            if (scan_segment == flag_segment && scan_way == flag_way)
                                valid[flag_segment][flag_way] <= 0;
                        end else if (!scan_clean && commit_segment == flag_segment) begin
                            if (commit_selected[flag_way] && commit_invalidate)
                                valid[flag_segment][flag_way] <= 0;
                            if (fill_commit && commit_way == flag_way)
                                valid[flag_segment][flag_way] <= 1;
                        end
                    end
                end

            end
        end
    endgenerate
    integer       i;
    logic   [5:0] random_candidate;
    always_comb begin
        hit               = hit_tree[0];
        hit_way           = hit ? way_tree[0] : 6'b0;
        hit_dirty         = hit ? dirty_tree[0] : 2'b0;
        hit_physical_line = hit ? {hit_pa_data, 5'b0} : 32'b0;
        random_candidate  = random_state[commit_segment];
        if (random_candidate < lock_base) random_candidate = lock_base;
        victim_way           = compare_victim_way;
        victim_valid         = compare_victim_valid;
        victim_dirty         = compare_victim_dirty;
        victim_physical_line = {compare_victim_pa, 5'b0};
    end
    always_ff @(posedge clk) begin
        if (reset || invalidate_all) begin
            for (i = 0; i < 8; i = i + 1) begin
                if (reset) begin
                    victim[i]       <= 0;
                    random_state[i] <= 6'(i + 1);
                end
            end
            if (reset) lock_base <= 0;
        end else if (lock_write) begin
            lock_base <= lock_base_in;
            for (i = 0; i < 8; i = i + 1) victim[i] <= lock_base_in;
        end else if (!scan_invalidate && !scan_clean) begin
            if (fill_commit) begin
                if (commit_rr)
                    victim[commit_segment] <= commit_way == 63 ? lock_base : commit_way + 1'b1;
                else begin
                    victim[commit_segment] <= random_candidate;
                    random_state[commit_segment] <= {
                        random_state[commit_segment][4:0],
                        random_state[commit_segment][5] ^ random_state[commit_segment][4]
                    };
                end
            end
        end
    end
endmodule
