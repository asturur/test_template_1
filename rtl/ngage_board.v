/*  N-Gage board devices, migrated one at a time from the C++ reference
    model (scratch/boot-v15-nosprobe/boot_profile.cpp). Wishbone-slave view:
    combinational claim/dout against the live request; registered state
    commits when the harness acknowledges (i_commit). Accesses the module
    claims but cannot serve within observed behavior raise o_unmodeled and
    the simulation stops, exactly like the C++ model's refusals.

    Device 1 (2026-10-31): the LCD transport at 0x0c121200/204/208 - the
    header/control/data registers the boot logo travels through. Semantics
    mirror boot_profile.cpp lcd_probe_transport byte for byte; the C++ model
    runs in lockstep shadow in the HDL sim build and any divergence stops
    the run (docs/hdl-migration.md).
*/

module ngage_board(
    input  wire        rst,
    input  wire        clk,
    // CPU wishbone request (held stable while pending)
    input  wire        cyc,
    input  wire        stb,
    input  wire [31:0] adr,
    input  wire        we,
    input  wire [31:0] din,
    input  wire [ 3:0] sel,
    input  wire        commit,      // harness acknowledges this cycle
    // configuration (from the harness command line)
    input  wire        cfg_lcd,     // lcd-probe option
    // service
    output reg         claim,
    output reg  [31:0] dout,
    output reg         unmodeled
);

wire [31:0] a = {adr[31:2], 2'b00};
wire        lcd_hit = cfg_lcd && (a == 32'h0c12_1200 ||
                                  a == 32'h0c12_1204 ||
                                  a == 32'h0c12_1208);

// LCD transport state (was lcd_control_/lcd_header_ in boot_profile.cpp)
reg        ctl_written, hdr_written;
reg [31:0] ctl, hdr;

// Transfer headers the boot path is known to write (same list as the C++
// model; anything else is unmodeled and stops the run).
wire hdr_ok = din == 32'h4f30_0000 || din == 32'h4920_0000 ||
              din == 32'h0920_0000 || din[31:16] == 16'h0924 ||
              din[31:16] == 16'h8924 || din[31:16] == 16'h0214 ||
              din == 32'h0780_0000 || din[31:16] == 16'h0784;

always @(*) begin
    claim     = lcd_hit && cyc && stb;
    dout      = 32'd0;
    unmodeled = 1'b0;
    if (claim) begin
        if (sel != 4'hf) unmodeled = 1'b1;                 // observed width only
        else if (a == 32'h0c12_1204 && we) begin
            if (din != 32'd1 && din != 32'd2) unmodeled = 1'b1;
        end else if (!ctl_written || ctl != 32'd1) begin
            unmodeled = 1'b1;                              // used before enable
        end else if (a == 32'h0c12_1200 && we) begin
            if (!hdr_ok) unmodeled = 1'b1;
        end else if (a == 32'h0c12_1204 && !we) begin
            dout = 32'd4;                                  // ROM 0x6724 polls bit 2
        end else if (a == 32'h0c12_1200 && !we) begin
            if (hdr_written && hdr == 32'h4920_0000)
                dout = 32'h4000_0000;                      // ROM 0x6cf8 polls bit 30
            else unmodeled = 1'b1;
        end else if (a == 32'h0c12_1208 && we) begin
            if (!hdr_written) unmodeled = 1'b1;
        end else if (a == 32'h0c12_1208 && !we) begin
            // display readback (header 0x0784xxxx): no panel, reads 0
            if (!(hdr_written && hdr[31:16] == 16'h0784)) unmodeled = 1'b1;
        end
    end
end

always @(posedge clk) begin
    if (rst) begin
        ctl_written <= 1'b0;
        hdr_written <= 1'b0;
        ctl         <= 32'd0;
        hdr         <= 32'd0;
    end else if (claim && commit && we && !unmodeled) begin
        if (a == 32'h0c12_1204) begin
            ctl         <= din;
            ctl_written <= 1'b1;
            if (din == 32'd2) hdr_written <= 1'b0;         // reset drops the header
        end else if (a == 32'h0c12_1200) begin
            hdr         <= din;
            hdr_written <= 1'b1;
        end
    end
end

endmodule
