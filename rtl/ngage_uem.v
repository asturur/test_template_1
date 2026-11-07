// D190 UEM behavior. This is the existing staged transaction-level model;
// the UPP CBUS register interface is not yet serialized onto CBUS pins.
module ngage_uem #(
    parameter POWER_KEY_ENABLE = 0,
              POWERUP_STATUS   = 1
) (
    input  wire        clk,
    input  wire        reset,
    input  wire        req,
    input  wire        commit,
    input  wire        we,
    input  wire        pwronx,
    input  wire [31:0] addr,
    input  wire [31:0] din,
    input  wire [ 3:0] sel,
    input  wire        kernel_periodic,
    input  wire        clear_irq,
    output wire        claim,
    output wire        bad,
    output wire [31:0] dout,
    output wire        uem_int,
    output wire [15:0] route2a,
    output wire [15:0] route2c,
    output wire [15:0] route3b,
    output wire        cbus8d_written
);
    ngage_cbus_uem #(
        .POWER_KEY_ENABLE(POWER_KEY_ENABLE),
        .POWERUP_STATUS  (POWERUP_STATUS)
    ) cbus (
        .power_pressed  (!pwronx),
        .clk            (clk),
        .reset          (reset),
        .req            (req),
        .commit         (commit),
        .we             (we),
        .addr           (addr),
        .din            (din),
        .sel            (sel),
        .kernel_periodic(kernel_periodic),
        .clear_irq      (clear_irq),
        .claim          (claim),
        .bad            (bad),
        .dout           (dout),
        .irq_pending    (uem_int),
        .route2a        (route2a),
        .route2c        (route2c),
        .route3b        (route3b),
        .cbus8d_written (cbus8d_written)
    );
endmodule
