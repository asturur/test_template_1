// SPDX-License-Identifier: GPL-3.0-or-later
// 512 x 32-byte cache-line storage prototype. No reset is needed: the tag
// array controls validity. 32 byte lanes permit a line refill or byte stores.
// Read-during-write to the same slot is intentionally unspecified; the cache
// controller must schedule or bypass that case.
module arm920_cache_lines (
    input  logic         clk,
    input  logic [2:0]   read_segment,
    input  logic [5:0]   read_way,
    output logic [255:0] read_line,
    input  logic [2:0]   write_segment,
    input  logic [5:0]   write_way,
    input  logic [31:0]  write_enable,
    input  logic [255:0] write_line
);
    wire [8:0] read_index={read_way,read_segment};
    wire [8:0] write_index={write_way,write_segment};
    // Keep the generate index declaration outside the loop for Quartus 17.
    genvar lane;
    generate for (lane=0;lane<32;lane=lane+1) begin : lanes
        logic [7:0] memory[0:511];
        always_ff @(posedge clk) begin
            if (write_enable[lane]) memory[write_index]<=write_line[lane*8+:8];
            read_line[lane*8+:8]<=memory[read_index];
        end
    end endgenerate
endmodule
