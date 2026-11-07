// Bounded full-address register store for sparsely accessed diagnostic pages.
// A full table refuses a new write instead of aliasing an unrelated address.
module ngage_sparse_regs #(
    parameter integer ENTRIES = 64
) (
    input  wire        clk,
    input  wire        cold_reset,
    input  wire        req,
    input  wire        commit,
    input  wire        we,
    input  wire [31:0] addr,
    input  wire [31:0] din,
    input  wire [ 3:0] sel,
    output reg  [31:0] dout,
    output reg         full
);
    reg [ENTRIES-1:0] valid;
    reg [       31:0] tags  [0:ENTRIES-1];
    localparam integer AW = ENTRIES > 1 ? $clog2(ENTRIES) : 1;
    wire [31:0] value_q;
    reg         read_hit;
    localparam integer LEAVES = 1 << AW;
    wire [ENTRIES-1:0] hit_mask;
    wire               any_hit = |hit_mask;
    wire               all_valid = &valid;
    wire [2*LEAVES-2:0] hit_present, free_present;
    wire [AW-1:0] hit_index[0:2*LEAVES-2], free_index[0:2*LEAVES-2];
    wire [31:0] mask = {{8{sel[3]}}, {8{sel[2]}}, {8{sel[1]}}, {8{sel[0]}}};
    wire        write_value = !cold_reset && req && commit && we && !full;
    // Full is a membership/capacity predicate, not an encoded-index query.
    // Keep priority selection out of the shared peripheral fault/ACK path.
    always @* begin
        dout = read_hit ? value_q : 0;
        full = req && we && !any_hit && all_valid;
    end
    // Balanced lowest-index trees preserve lookup/allocation order. Padding
    // leaves are absent in both trees, including non-power-of-two capacities.
    genvar slot;
    generate
        for (slot = 0; slot < LEAVES; slot = slot + 1) begin : leaves
            if (slot < ENTRIES) begin : active_slot
                assign hit_mask[slot]              = valid[slot] && tags[slot] == addr;
                assign hit_present[LEAVES-1+slot]  = hit_mask[slot];
                assign free_present[LEAVES-1+slot] = !valid[slot];
                always @(posedge clk) begin
                    if (cold_reset) valid[slot] <= 0;
                    else if (write_value && !any_hit && free_index[0] == slot) begin
                        valid[slot] <= 1;
                        tags[slot]  <= addr;
                    end
                end
            end else begin : padding_slot
                assign hit_present[LEAVES-1+slot]  = 0;
                assign free_present[LEAVES-1+slot] = 0;
            end
            assign hit_index[LEAVES-1+slot]  = slot;
            assign free_index[LEAVES-1+slot] = slot;
        end
        for (slot = 0; slot < LEAVES - 1; slot = slot + 1) begin : nodes
            assign hit_present[slot] = hit_present[2*slot+1] | hit_present[2*slot+2];
            assign free_present[slot] = free_present[2*slot+1] | free_present[2*slot+2];
            assign hit_index[slot] = hit_present[2*slot+1] ?
                hit_index[2*slot+1] : hit_index[2*slot+2];
            assign free_index[slot] = free_present[2*slot+1] ?
                free_index[2*slot+1] : free_index[2*slot+2];
        end
    endgenerate
    // Tags remain a small fully associative CAM; payload is byte-enabled M10K.
    wire [AW-1:0] write_slot = any_hit ? hit_index[0] : free_index[0];
    wire [AW-1:0] read_slot = any_hit ? hit_index[0] : {AW{1'b0}};
    ngage_bram #(
        .AW         (AW),
        .DW         (32),
        .BYTE_WIDTH (8),
        .READ_ONLY_B(1)
    ) payload (
        .clk   (clk),
        .addr_a(write_slot),
        .addr_b(read_slot),
        .data_a(any_hit ? din : din & mask),
        .data_b(32'b0),
        .we_a  (write_value ? (any_hit ? sel : 4'hf) : 4'b0),
        .we_b  (4'b0),
        .q_a   (),
        .q_b   (value_q)
    );
    always @(posedge clk) read_hit <= !cold_reset && any_hit;
endmodule
