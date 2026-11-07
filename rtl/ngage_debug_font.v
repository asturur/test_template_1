// Synchronous 128-character x 8-row font, 8 pixels/row, explicitly in M10K.
// MIF is the Quartus image; HEX is the identical behavioral simulator image.
module ngage_debug_font (
    input  wire       clk,
    input  wire [9:0] address,
    output wire [7:0] pixels
);
`ifdef ALTERA_RESERVED_QIS
    `define NGAGE_FONT_PRIMITIVE
`elsif SYNTHESIS
    `define NGAGE_FONT_PRIMITIVE
`endif
`ifdef NGAGE_FONT_PRIMITIVE
    altsyncram #(
        .operation_mode        ("SINGLE_PORT"),
        .intended_device_family("Cyclone V"),
        .ram_block_type        ("M10K"),
        .lpm_type              ("altsyncram"),
        .width_a               (8),
        .widthad_a             (10),
        .numwords_a            (1024),
        .width_byteena_a       (1),
        .byte_size             (8),
        .outdata_reg_a         ("UNREGISTERED"),
        .outdata_aclr_a        ("NONE"),
        .clock_enable_input_a  ("BYPASS"),
        .clock_enable_output_a ("BYPASS"),
        .init_file             ("rtl/ngage_debug_font.mif"),
        .power_up_uninitialized("FALSE")
    ) rom (
        .clock0        (clk),
        .clock1        (1'b0),
        .clocken0      (1'b1),
        .clocken1      (1'b1),
        .clocken2      (1'b1),
        .clocken3      (1'b1),
        .aclr0         (1'b0),
        .aclr1         (1'b0),
        .address_a     (address),
        .address_b     (1'b0),
        .addressstall_a(1'b0),
        .addressstall_b(1'b0),
        .data_a        (8'b0),
        .data_b        (1'b0),
        .wren_a        (1'b0),
        .wren_b        (1'b0),
        .byteena_a     (1'b1),
        .byteena_b     (1'b1),
        .rden_a        (1'b1),
        .rden_b        (1'b1),
        .q_a           (pixels),
        .q_b           (),
        .eccstatus     ()
    );
`else
    reg [7:0] font   [0:1023];
    reg [7:0] data_q;
    initial $readmemh("rtl/ngage_debug_font.hex", font);
    always @(posedge clk) data_q <= font[address];
    assign pixels = data_q;
`endif
    `undef NGAGE_FONT_PRIMITIVE
endmodule
