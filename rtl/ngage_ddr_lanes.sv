// Combinational 32-bit client to MiSTer's 64-bit DDR data lanes.
// The caller supplies a 32-bit-word-aligned byte address and retains it until
// the DDR transaction completes. This module does not implement handshaking.
module ngage_ddr_lanes (
    input  wire [31:0] byte_address,
    input  wire [31:0] write_data,
    input  wire [ 3:0] write_enable,
    input  wire [63:0] read_data,
    output wire [28:0] ddr_address,
    output wire [63:0] ddr_write_data,
    output wire [ 7:0] ddr_byte_enable,
    output wire [31:0] client_read_data
);
    assign ddr_address      = byte_address[31:3];
    assign ddr_write_data   = {write_data, write_data};
    assign ddr_byte_enable  = byte_address[2] ? {write_enable, 4'b0000} : {4'b0000, write_enable};
    assign client_read_data = byte_address[2] ? read_data[63:32] : read_data[31:0];
endmodule
