// SPDX-License-Identifier: GPL-3.0-or-later
// 512 x 32-byte cache-line storage. No reset is needed: the tag
// array controls validity. 32 byte lanes permit a line refill or byte stores.
// Read-during-write to the same slot is intentionally unspecified; the cache
// controller must schedule or bypass that case.
module arm920_cache_lines (
    input  logic         clk,
    input  logic [  2:0] read_segment,
    input  logic [  5:0] read_way,
    output logic [255:0] read_line,
    input  logic [  2:0] write_segment,
    input  logic [  5:0] write_way,
    input  logic [ 31:0] write_enable,
    input  logic [255:0] write_line
);
    wire [8:0] read_index = {read_way, read_segment};
    wire [8:0] write_index = {write_way, write_segment};
    // Eight 32-bit banks retain all 32 independent byte enables while
    // selecting explicit M10Ks instead of 32 separate inferred byte RAMs.
    genvar word_lane;
    generate
        for (word_lane = 0; word_lane < 8; word_lane = word_lane + 1) begin : words
            ngage_bram #(
                .AW         (9),
                .DW         (32),
                .BYTE_WIDTH (8),
                .READ_ONLY_B(1)
            ) ram (
                .clk   (clk),
                .addr_a(write_index),
                .data_a(write_line[word_lane*32+:32]),
                .we_a  (write_enable[word_lane*4+:4]),
                .q_a   (),
                .addr_b(read_index),
                .data_b(32'b0),
                .we_b  (4'b0),
                .q_b   (read_line[word_lane*32+:32])
            );
        end
    endgenerate
endmodule
