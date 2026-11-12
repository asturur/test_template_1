// Small passive banks use the test model; unrelated UPP RAM uses behavioral RTL.
// Explicit Cyclone V embedded RAM. Port/clock wiring follows JTFRAME's
// target/pocket/hdl/ram/jtframe_pocket_dualram.v. Both ports use clk here.
// Address and write controls are sampled on the rising edge; q is available
// after that edge. Same-port writes return new data. Cross-port collisions
// are undefined and must be avoided or forwarded by the caller.
// READ_ONLY_B selects simple dual-port write-A/read-B: q_a is not a read port.
module ngage_bram #(
    parameter integer AW          = 8,
    parameter integer DW          = 16,
    parameter integer BYTE_WIDTH  = DW,
    parameter integer BYTES       = DW / BYTE_WIDTH,
    parameter integer READ_ONLY_B = 0,
    parameter integer DEPTH       = 1 << AW
) (
    input  wire             clk,
    input  wire [   AW-1:0] addr_a,
    input  wire [   AW-1:0] addr_b,
    input  wire [   DW-1:0] data_a,
    input  wire [   DW-1:0] data_b,
    input  wire [BYTES-1:0] we_a,
    input  wire [BYTES-1:0] we_b,
    output wire [   DW-1:0] q_a,
    output wire [   DW-1:0] q_b
);
    generate
        if (AW <= 6) begin : tested
            ngage_test_bram #(.AW(AW),.DW(DW),.BYTE_WIDTH(BYTE_WIDTH),.BYTES(BYTES),.READ_ONLY_B(READ_ONLY_B),.DEPTH(DEPTH)) ram
                (.clk(clk),.addr_a(addr_a),.addr_b(addr_b),.data_a(data_a),.data_b(data_b),.we_a(we_a),.we_b(we_b),.q_a(q_a),.q_b(q_b));
        end else begin : unrelated
            ngage_behavioral_bram #(.AW(AW),.DW(DW),.BYTE_WIDTH(BYTE_WIDTH),.BYTES(BYTES),.READ_ONLY_B(READ_ONLY_B),.DEPTH(DEPTH)) ram
                (.clk(clk),.addr_a(addr_a),.addr_b(addr_b),.data_a(data_a),.data_b(data_b),.we_a(we_a),.we_b(we_b),.q_a(q_a),.q_b(q_b));
        end
    endgenerate
endmodule
