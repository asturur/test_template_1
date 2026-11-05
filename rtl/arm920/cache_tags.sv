// SPDX-License-Identifier: GPL-3.0-or-later
// ARM920T-shaped cache tag/victim prototype. This block is not yet connected
// to the ZAP cache datapath; callers must write back a dirty victim before fill.
// 16 KiB / 32-byte lines = 8 segments x 64 indices, MVA lookup and PA tags.
module arm920_cache_tags (
    input  logic        clk,
    input  logic        reset,
    input  logic [31:0] mva,
    output logic        hit,
    output logic [5:0]  hit_way,
    output logic [1:0]  hit_dirty,
    output logic [31:0] hit_physical_line,
    output logic [5:0]  victim_way,
    output logic        victim_valid,
    output logic [1:0]  victim_dirty,
    output logic [31:0] victim_physical_line,
    input  logic        fill,
    input  logic [31:0] fill_physical,
    input  logic        write_hit,
    input  logic        invalidate_line,
    input  logic        invalidate_all,
    input  logic        clean_hit,
    input  logic        lock_write,
    input  logic [5:0]  lock_base_in,
    output logic [5:0]  lock_base,
    input  logic        round_robin,
    // Indexed maintenance interface; caller excludes simultaneous accesses.
    input  logic [2:0]  scan_segment,
    input  logic [5:0]  scan_way,
    output logic        scan_valid,
    output logic [1:0]  scan_dirty,
    output logic [31:0] scan_physical_line,
    input  logic        scan_clean,
    input  logic        scan_invalidate
);
    logic [23:0] tags[0:7][0:63];
    logic [26:0] physical[0:7][0:63];
    logic valid[0:7][0:63];
    logic [1:0] dirty[0:7][0:63];
    logic [5:0] victim[0:7];
    logic [5:0] random_state[0:7];
    wire [2:0] segment=mva[7:5];
    assign scan_valid=valid[scan_segment][scan_way];
    assign scan_dirty=dirty[scan_segment][scan_way];
    assign scan_physical_line={physical[scan_segment][scan_way],5'b0};
    integer i,j;
    logic [5:0] random_candidate;
    always_comb begin
        hit=0;hit_way=0;hit_dirty=0;hit_physical_line=0;
        for (integer way=0;way<64;way=way+1) begin
            if (!hit && valid[segment][way] && tags[segment][way]==mva[31:8]) begin
                hit=1;hit_way=6'(way);hit_dirty=dirty[segment][way];
                hit_physical_line={physical[segment][way],5'b0};
            end
        end
        random_candidate=random_state[segment];
        if (random_candidate < lock_base) random_candidate=lock_base;
        victim_way=victim[segment];
        victim_valid=valid[segment][victim_way];
        victim_dirty=dirty[segment][victim_way];
        victim_physical_line={physical[segment][victim_way],5'b0};
    end
    always_ff @(posedge clk) begin
        if (reset || invalidate_all) begin
            for (i=0;i<8;i=i+1) begin
                for (j=0;j<64;j=j+1) begin valid[i][j]<=0;dirty[i][j]<=0;end
                if (reset) begin victim[i]<=0;random_state[i]<=6'(i+1);end
            end
            if (reset) lock_base<=0;
        end else if (lock_write) begin
            lock_base<=lock_base_in;
            for (i=0;i<8;i=i+1) victim[i]<=lock_base_in;
        end else if (scan_invalidate) begin
            valid[scan_segment][scan_way]<=0;
            dirty[scan_segment][scan_way]<=0;
        end else if (scan_clean) begin
            dirty[scan_segment][scan_way]<=0;
        end else begin
            if (invalidate_line && hit) begin valid[segment][hit_way]<=0;dirty[segment][hit_way]<=0;end
            else if (clean_hit && hit) dirty[segment][hit_way]<=0;
            else if (write_hit && hit) dirty[segment][hit_way][mva[4]]<=1;
            if (fill && !hit) begin
                tags[segment][victim_way]<=mva[31:8];
                physical[segment][victim_way]<=fill_physical[31:5];
                valid[segment][victim_way]<=1;dirty[segment][victim_way]<=0;
                if (round_robin)
                    victim[segment] <= victim_way==63 ? lock_base : victim_way+1'b1;
                else begin
                    victim[segment] <= random_candidate;
                    random_state[segment] <= {random_state[segment][4:0],random_state[segment][5]^random_state[segment][4]};
                end
            end
        end
    end
endmodule
