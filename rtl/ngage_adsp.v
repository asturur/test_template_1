// D550 external audio DSP boundary. AMA-WD2 control and DSP execution are
// explicitly unimplemented; this chip must not impersonate UPP internal MDI.
module ngage_adsp (
    input  wire        clk,
    input  wire        reset,
    input  wire        tick,
    input  wire        periodic_active,
    input  wire        req,
    input  wire        commit,
    input  wire        we,
    input  wire [31:0] addr,
    input  wire [31:0] din,
    input  wire [ 3:0] sel,
    output wire        claim,
    output wire        bad,
    output wire [31:0] dout,
    output wire [15:0] irq_events
);
    // D550 is a separate audio DSP. UPP's internal MDI protocol is modeled
    // by ngage_upp_mdi, not this chip. AMA control/diagnostics remain absent.
    assign claim      = 1'b0;
    assign bad        = 1'b0;
    assign dout       = 32'b0;
    assign irq_events = 16'b0;
endmodule
