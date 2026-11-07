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
    integer i, hit, free_slot;
    wire [31:0] mask = {{8{sel[3]}}, {8{sel[2]}}, {8{sel[1]}}, {8{sel[0]}}};
    always @* begin
        hit       = -1;
        free_slot = -1;
        for (i = 0; i < ENTRIES; i = i + 1) begin
            if (valid[i] && tags[i] == addr && hit < 0) hit = i;
            if (!valid[i] && free_slot < 0) free_slot = i;
        end
        dout = read_hit ? value_q : 0;
        full = req && we && hit < 0 && free_slot < 0;
    end
    // Tags remain a small fully associative CAM; payload is byte-enabled M10K.
    wire [AW-1:0] write_slot = hit >= 0 ? hit : free_slot;
    wire [AW-1:0] read_slot = hit >= 0 ? hit : {AW{1'b0}};
    wire          write_value = !cold_reset && req && commit && we && !full;
    ngage_bram #(
        .AW         (AW),
        .DW         (32),
        .BYTE_WIDTH (8),
        .READ_ONLY_B(1)
    ) payload (
        .clk   (clk),
        .addr_a(write_slot),
        .addr_b(read_slot),
        .data_a(hit >= 0 ? din : din & mask),
        .data_b(32'b0),
        .we_a  (write_value ? (hit >= 0 ? sel : 4'hf) : 4'b0),
        .we_b  (4'b0),
        .q_a   (),
        .q_b   (value_q)
    );
    always @(posedge clk) read_hit <= !cold_reset && hit >= 0;
    always @(posedge clk) begin
        if (cold_reset) valid <= 0;
        else if (req && commit && we && !full) begin
            if (hit < 0) begin
                valid[free_slot] <= 1;
                tags[free_slot]  <= addr;
            end
        end
    end
endmodule
