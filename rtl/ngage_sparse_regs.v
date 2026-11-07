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
    reg [31:0] tags[0:ENTRIES-1], values[0:ENTRIES-1];
    integer i, hit, free_slot;
    wire [31:0] mask = {{8{sel[3]}}, {8{sel[2]}}, {8{sel[1]}}, {8{sel[0]}}};
    always @* begin
        hit       = -1;
        free_slot = -1;
        for (i = 0; i < ENTRIES; i = i + 1) begin
            if (valid[i] && tags[i] == addr && hit < 0) hit = i;
            if (!valid[i] && free_slot < 0) free_slot = i;
        end
        dout = hit < 0 ? 0 : values[hit];
        full = req && we && hit < 0 && free_slot < 0;
    end
    always @(posedge clk) begin
        if (cold_reset) valid <= 0;
        else if (req && commit && we && !full) begin
            if (hit >= 0) values[hit] <= (values[hit] & ~mask) | (din & mask);
            else begin
                valid[free_slot]  <= 1;
                tags[free_slot]   <= addr;
                values[free_slot] <= din & mask;
            end
        end
    end
endmodule
