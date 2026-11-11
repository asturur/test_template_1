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
    // Quartus 17 defines ALTERA_RESERVED_QIS, not SYNTHESIS in this project.
    // SYNTHESIS also selects the primitive for vendor-model simulation/lint.
`ifdef ALTERA_RESERVED_QIS
    `define NGAGE_BRAM_PRIMITIVE
`elsif SYNTHESIS
    `define NGAGE_BRAM_PRIMITIVE
`endif
`ifdef NGAGE_BRAM_PRIMITIVE
    // Quartus requires legal physical byte lanes even for whole-word writes.
    // Pad arbitrary payload widths to eight bits; discard the padding on read.
    // Whole-word enables drive wren; all native byte-enable pins stay asserted.
    localparam integer RAM_BYTE_WIDTH = BYTES > 1 ? BYTE_WIDTH : 8;
    localparam integer RAM_BYTES      = (DW + RAM_BYTE_WIDTH - 1) / RAM_BYTE_WIDTH;
    localparam integer RAM_WIDTH      = RAM_BYTES * RAM_BYTE_WIDTH;
    wire [RAM_WIDTH-1:0] ram_q_a, ram_q_b;
    assign q_a = READ_ONLY_B ? {DW{1'b0}} : ram_q_a[DW-1:0];
    assign q_b = ram_q_b[DW-1:0];
    altsyncram #(
        .operation_mode                    (READ_ONLY_B ? "DUAL_PORT" : "BIDIR_DUAL_PORT"),
        .intended_device_family            ("Cyclone V"),
        .ram_block_type                    ("M10K"),
        .lpm_type                          ("altsyncram"),
        .width_a                           (RAM_WIDTH),
        .width_b                           (RAM_WIDTH),
        .widthad_a                         (AW),
        .widthad_b                         (AW),
        .numwords_a                        (DEPTH),
        .numwords_b                        (DEPTH),
        .width_byteena_a                   (RAM_BYTES),
        .width_byteena_b                   (RAM_BYTES),
        .byte_size                         (RAM_BYTE_WIDTH),
        .address_reg_b                     ("CLOCK1"),
        .indata_reg_b                      ("CLOCK1"),
        .wrcontrol_wraddress_reg_b         ("CLOCK1"),
        .byteena_reg_b                     ("CLOCK1"),
        .outdata_reg_a                     ("UNREGISTERED"),
        .outdata_reg_b                     ("UNREGISTERED"),
        .outdata_aclr_a                    ("NONE"),
        .outdata_aclr_b                    ("NONE"),
        .clock_enable_input_a              ("BYPASS"),
        .clock_enable_input_b              ("BYPASS"),
        .clock_enable_output_a             ("BYPASS"),
        .clock_enable_output_b             ("BYPASS"),
        .read_during_write_mode_port_a     ("NEW_DATA_NO_NBE_READ"),
        .read_during_write_mode_port_b     ("NEW_DATA_NO_NBE_READ"),
        .read_during_write_mode_mixed_ports("DONT_CARE"),
        .power_up_uninitialized            ("FALSE")
    ) ram (
        .clock0        (clk),
        .clock1        (clk),
        .address_a     (addr_a),
        .address_b     (addr_b),
        .data_a        ({{(RAM_WIDTH - DW) {1'b0}}, data_a}),
        .data_b        ({{(RAM_WIDTH - DW) {1'b0}}, data_b}),
        .wren_a        (|we_a),
        .wren_b        (|we_b),
        .byteena_a     (BYTES > 1 ? we_a : {RAM_BYTES{1'b1}}),
        .byteena_b     (BYTES > 1 ? we_b : {RAM_BYTES{1'b1}}),
        .q_a           (ram_q_a),
        .q_b           (ram_q_b),
        .aclr0         (1'b0),
        .aclr1         (1'b0),
        .addressstall_a(1'b0),
        .addressstall_b(1'b0),
        .clocken0      (1'b1),
        .clocken1      (1'b1),
        .clocken2      (1'b1),
        .clocken3      (1'b1),
        .rden_a        (1'b1),
        .rden_b        (1'b1),
        .eccstatus     ()
    );
`else
    reg [DW-1:0] memory[0:DEPTH-1];
    reg [DW-1:0] a_q, b_q;
    integer init_index;
    initial begin
        for (init_index = 0; init_index < DEPTH; init_index = init_index + 1) begin
            memory[init_index] = 0;
        end
    end
    genvar lane;
    generate
        for (lane = 0; lane < BYTES; lane = lane + 1) begin : bytes
            always @(posedge clk) begin
                if (we_a[lane])
                    memory[addr_a][lane*BYTE_WIDTH+:BYTE_WIDTH] <= data_a[lane*BYTE_WIDTH+:BYTE_WIDTH];
                a_q[lane*BYTE_WIDTH+:BYTE_WIDTH] <= we_a[lane] ? data_a[lane*BYTE_WIDTH+:BYTE_WIDTH] : memory[addr_a][lane*BYTE_WIDTH+:BYTE_WIDTH];
            end
            always @(posedge clk) begin
                if (we_b[lane])
                    memory[addr_b][lane*BYTE_WIDTH+:BYTE_WIDTH] <= data_b[lane*BYTE_WIDTH+:BYTE_WIDTH];
                b_q[lane*BYTE_WIDTH+:BYTE_WIDTH] <= we_b[lane] ? data_b[lane*BYTE_WIDTH+:BYTE_WIDTH] : memory[addr_b][lane*BYTE_WIDTH+:BYTE_WIDTH];
            end
        end
    endgenerate
    // Intel's simple-dual-port model drives q_a to zero. Keep ordinary
    // simulation honest so consuming the write-only port cannot pass tests.
    assign q_a = READ_ONLY_B ? {DW{1'b0}} : a_q;
    assign q_b = b_q;
`endif
    `undef NGAGE_BRAM_PRIMITIVE
endmodule
