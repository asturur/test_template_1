// Forward the system clock through a Cyclone V output IO register, as in
// JTFRAME's MiSTer 180SHIFT path. Output rises at the falling system edge.
// Pair with jtframe_sdram64 READ_CAPTURE_NEGEDGE=1. Simulation of the ideal
// primitive does not establish fitted clock/data delays or board timing.
module ngage_sdram_clock (
    input  wire clk,
    output wire sdram_clk
);
    altddio_out #(
        .extend_oe_disable     ("OFF"),
        .intended_device_family("Cyclone V"),
        .invert_output         ("OFF"),
        .lpm_hint              ("UNUSED"),
        .lpm_type              ("altddio_out"),
        .oe_reg                ("UNREGISTERED"),
        .power_up_high         ("OFF"),
        .width                 (1)
    ) ddio (
        .datain_h  (1'b0),
        .datain_l  (1'b1),
        .outclock  (clk),
        .dataout   (sdram_clk),
        .aclr      (1'b0),
        .aset      (1'b0),
        .oe        (1'b1),
        .outclocken(1'b1),
        .sclr      (1'b0),
        .sset      (1'b0)
    );
endmodule
