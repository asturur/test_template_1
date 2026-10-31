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
    input  wire        cfg_keypad,  // keypad-gpio option
    input  wire        cfg_clocks,  // ideal-clocks option
    // service
    output reg         claim,
    output reg  [31:0] dout,
    output reg         unmodeled
);

wire [31:0] a = {adr[31:2], 2'b00};
wire        lcd_hit = cfg_lcd && (a == 32'h0c12_1200 ||
                                  a == 32'h0c12_1204 ||
                                  a == 32'h0c12_1208);

/*  Device 2 (2026-10-31): GPIO/keypad pin-config latches, the clean
    subranges of the C++ keypad bank 0x0c150400..0x0c1505ff. Zero-reset RW
    latches; input reads are zero (idle, no keys); halfword/word widths
    only. Left with the C++ model: 0x420/0x424 (CBUS status) and
    0x538/0x53c (block probe), which its earlier handlers own. The euart1
    TX-idle quirk comes along: status 0x0c150514 reads bit 2 set (the
    modeled modem UART always drains). */
wire gpio_hit = cfg_keypad && a[31:12] == 20'h0c150 &&
                ((a[11:0] >= 12'h400 && a[11:0] < 12'h420) ||
                 (a[11:0] >= 12'h428 && a[11:0] < 12'h538) ||
                 (a[11:0] >= 12'h540 && a[11:0] < 12'h600));

reg  [31:0] gpio [0:127];                     // word latches for 0x400..0x5ff
wire [ 6:0] gidx = a[8:2];
wire [31:0] wmask = { {8{sel[3]}}, {8{sel[2]}}, {8{sel[1]}}, {8{sel[0]}} };
integer gi;
initial for (gi = 0; gi < 128; gi = gi + 1) gpio[gi] = 32'd0;

/*  Device 3 (2026-10-31): the ideal-clock block - control 0x0c120004,
    command 0x0c120008, PLL 0x0c149000 (RW word latches with written-byte
    tracking) and the status read 0x0c120020. Status truth table is the
    validated C++ handler: control 12 -> bit 26; control 0x27 + command 1 ->
    bit 27; control 3 + PLL 0x2210 -> bit 27; control 0x20/0x40 -> bits 25
    and 26 (NOS wait loops 0x514a5b88 TST #0x02000000 and 0x514c13ac AND
    #0x04000000, both pinned 2026-10-31). PLL reads require value 0x2210 and return
    value|1. Anything else is unmodeled and stops the run. */
wire clk_hit = cfg_clocks && (a == 32'h0c12_0004 || a == 32'h0c12_0008 ||
                              a == 32'h0c12_0020 || a == 32'h0c14_9000);

reg [31:0] ctlv, cmdv, pllv;       // latch values
reg [ 3:0] ctlw, cmdw, pllw;       // written-byte masks

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
    claim     = (lcd_hit || gpio_hit || clk_hit) && cyc && stb;
    dout      = 32'd0;
    unmodeled = 1'b0;
    if (clk_hit && cyc && stb) begin
        if (a == 32'h0c12_0020) begin
            if (we || ctlw != 4'hf) unmodeled = 1'b1;  // status is read-only,
            else case (ctlv)                           // needs full control
                32'd12:   dout = 32'h0400_0000;
                32'h27:   if (cmdw == 4'hf && cmdv == 32'd1) dout = 32'h0800_0000;
                          else unmodeled = 1'b1;
                32'd3:    if (pllw == 4'hf && pllv == 32'h2210) dout = 32'h0800_0000;
                          else unmodeled = 1'b1;
                32'h20, 32'h40: dout = 32'h0600_0000;  // lock bits 25+26
                default:  unmodeled = 1'b1;
            endcase
        end else begin
            if (sel & ~4'hf) unmodeled = 1'b1;
            else if (!we) begin
                case (a)
                    32'h0c12_0004: begin dout = ctlv; if ((ctlw & sel) != sel) unmodeled = 1'b1; end
                    32'h0c12_0008: begin dout = cmdv; if ((cmdw & sel) != sel) unmodeled = 1'b1; end
                    default: begin
                        dout = pllv;
                        if ((pllw & sel) != sel || pllv != 32'h2210) unmodeled = 1'b1;
                        else dout = pllv | 32'd1;      // ideal_pll_status
                    end
                endcase
            end
        end
    end else if (gpio_hit && cyc && stb) begin
        if (sel != 4'h3 && sel != 4'hc && sel != 4'hf) unmodeled = 1'b1;
        else begin
            dout = gpio[gidx] & wmask;
            if (a == 32'h0c15_0514 && !we) dout = dout | (32'h4 & wmask);
        end
    end else if (claim) begin
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
        ctlv <= 32'd0; cmdv <= 32'd0; pllv <= 32'd0;
        ctlw <= 4'd0;  cmdw <= 4'd0;  pllw <= 4'd0;
    end else if (clk_hit && commit && we && !unmodeled) begin
        case (a)
            32'h0c12_0004: begin ctlv <= (ctlv & ~wmask) | (din & wmask); ctlw <= ctlw | sel; end
            32'h0c12_0008: begin cmdv <= (cmdv & ~wmask) | (din & wmask); cmdw <= cmdw | sel; end
            default:       begin pllv <= (pllv & ~wmask) | (din & wmask); pllw <= pllw | sel; end
        endcase
    end else if (gpio_hit && commit && we && !unmodeled) begin
        gpio[gidx] <= (gpio[gidx] & ~wmask) | (din & wmask);
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
