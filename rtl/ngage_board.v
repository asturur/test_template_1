/*  N-Gage board devices, migrated one at a time from the C++ reference
    model (scratch/boot-v15-nosprobe/boot_profile.cpp). Wishbone-slave view:
    combinational claim/dout against the live request; registered state
    commits when the harness acknowledges (i_commit). Accesses the module
    claims but cannot serve within observed behavior raise o_unmodeled and
    the simulation stops, exactly like the C++ model's refusals.

    Device 1 (2026-10-31): the LCD transport at 0x0c121200/204/208 - the
    header/control/data registers the boot logo travels through.

    Device 2: GPIO/keypad/system-control latch banks.  Extended 2026-11-01
    to cover all the NOS-phase GPIO ranges the authentic run uses:
    0x0c150000-0x05ff (original), 0x0c150800-0x08ff (FBUS port),
    0x0c120c00-0x0c1f (ICU-adjacent), 0x0c14f000-0x0c14f0ff,
    0x0c100000-0x0c10ffff, 0x0c148000-0x0c14801f, 0x0c142000/14a/14b/14c,
    plus the upload RAMs 0x0c030000-0x0c03ffff and 0x0c06ff00-0x0c06ffff.
    Quirk bits: euart1 TX-idle 0x0c150514 bit 2, FBUS TX drained
    0x0c150504 |=0x1D0, 0x0c150568 bits 1+2, MBUS strobe 0x0c15021c
    self-clears, GSM strap 0x0c150002 bit 22.

    Device 3 (2026-10-31): ideal-clock block.

    Device 4 (2026-11-01): NOS peripheral block 0x0c004000-0x0c004fff
    and ASIC ROM stub page 0x0c000000-0x0c000fff.

    Device 5 (2026-11-01): 0x0d space peripherals + trace sink.

    Device 6 (2026-11-01): free-running counter 0x0c150112 + window 0x0c150114.

    All byte/halfword/word widths accepted (the NOS uses all three).
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
wire [31:0] wmask = { {8{sel[3]}}, {8{sel[2]}}, {8{sel[1]}}, {8{sel[0]}} };

// ---- device 1: LCD transport ------------------------------------------------
wire lcd_hit = cfg_lcd && (a == 32'h0c12_1200 ||
                           a == 32'h0c12_1204 ||
                           a == 32'h0c12_1208);

reg        ctl_written, hdr_written;
reg [31:0] ctl, hdr;

wire hdr_ok = din == 32'h4f30_0000 || din == 32'h4920_0000 ||
              din == 32'h0920_0000 || din[31:16] == 16'h0924 ||
              din[31:16] == 16'h8924 || din[31:16] == 16'h0214 ||
              din == 32'h0780_0000 || din[31:16] == 16'h0784;

// ---- device 2: GPIO/keypad/system-control latch family ----------------------
// All ranges that the C++ keypad_regs_ map covers, including the NOS-phase
// extensions added on 2026-10-31/11-01.
wire gpio_hit = cfg_keypad && (
    // original GPIO banks
    (a[31:12] == 20'h0c150 && (
        (a[11:0] < 12'h600) ||          // 0x0c150000-0x05ff
        (a[11:0] >= 12'h800 && a[11:0] < 12'h900)  // FBUS port 0x800-0x8ff
    )) ||
    // ICU-adjacent
    (a[31:8] == 24'h0c120c && a[7:0] < 8'h20) ||
    // 0x0c14fxxx
    (a[31:8] == 24'h0c14f0) ||
    // clock-unit siblings
    (a[31:12] == 20'h0c148 && a[11:0] < 12'h020) ||
    (a[31:12] == 20'h0c142 && a[11:0] < 12'h020) ||
    (a[31:12] == 20'h0c14a && a[11:0] < 12'h020) ||
    (a[31:12] == 20'h0c14b && a[11:0] < 12'h020) ||
    (a[31:12] == 20'h0c14c && a[11:0] < 12'h020) ||
    // 0x0c10xxxx peripheral block
    (a[31:16] == 16'h0c10) ||
    // upload RAMs
    (a[31:16] == 16'h0c03) ||
    (a[31:8] == 24'h0c06ff) ||
    // clock reg 0x0c120034
    a == 32'h0c12_0034
);

// GPIO storage: block-RAM-friendly 16K-word array, word-addressed.
// Address mapping: the combinational index select maps each range into
// a 16-bit array index. Ranges that don't overlap share index space.
// We use the low 16 bits of the physical address as the index since
// no two gated ranges share the same low-16 value.
// GPIO latch storage: synthesis infers block RAM; reset via the
// registered always block (reads return 0 until written, matching
// zero-reset latch semantics). No initial loop needed.
(* ramstyle = "no_rw_check" *)
reg  [31:0] gpr [0:16383];   // 64KB, covers all widths
wire [13:0] gidx = a[15:2];

// ---- device 3: ideal-clock block -------------------------------------------
wire clk_hit = cfg_clocks && (a == 32'h0c12_0004 || a == 32'h0c12_0008 ||
                              a == 32'h0c12_0020 || a == 32'h0c14_9000);

reg [31:0] ctlv, cmdv, pllv;
reg [ 3:0] ctlw, cmdw, pllw;

// ---- device 4: NOS peripheral 0x0c004xxx + ASIC ROM stub -------------------
wire nos4k_hit = cfg_keypad && (
    (a[31:12] == 20'h0c004) ||     // comm RAM shared block
    (a[31:12] == 20'h0c000)        // ASIC ROM stub page (reads only)
);

(* ramstyle = "no_rw_check" *)
reg [31:0] nos4k [0:1023];         // 4KB for 0x0c004xxx

// ---- device 5: 0x0d space (peripherals + trace sink) -----------------------
wire d_space_hit = cfg_keypad && (a[31:24] == 8'h0d);

(* ramstyle = "no_rw_check" *)
reg [31:0] d_regs [0:1023];        // sampled subset (not full 16MB)
wire [9:0] d_idx = a[11:2];        // per-64KB-block window

// ---- device 6: free-running counter ----------------------------------------
reg [31:0] fcnt;                    // ticks once per 3174 clocks (32.768kHz@104MHz)
reg [11:0] fcnt_div;

// ---- combinational output ---------------------------------------------------
always @(*) begin
    claim     = (lcd_hit || gpio_hit || clk_hit || nos4k_hit || d_space_hit) && cyc && stb;
    dout      = 32'd0;
    unmodeled = 1'b0;

    if (nos4k_hit && cyc && stb) begin
        if (a[31:12] == 20'h0c000) begin
            // ASIC ROM stub: reads return Thumb BX LR (0x4770)
            if (we) unmodeled = 1'b1;
            else dout = 32'h4770_4770;
        end else begin
            dout = nos4k[a[11:2]] & wmask;
            if (we) ; // commit handles write
        end
    end else if (d_space_hit && cyc && stb) begin
        dout = d_regs[d_idx] & wmask;
    end else if (clk_hit && cyc && stb) begin
        if (a == 32'h0c12_0020) begin
            if (we || ctlw != 4'hf) unmodeled = 1'b1;
            else case (ctlv)
                32'd12:   dout = 32'h0400_0000;
                32'h27:   if (cmdw == 4'hf && cmdv == 32'd1) dout = 32'h0800_0000;
                          else unmodeled = 1'b1;
                32'd3:    if (pllw == 4'hf && pllv == 32'h2210) dout = 32'h0800_0000;
                          else unmodeled = 1'b1;
                32'h20, 32'h40: dout = 32'h0600_0000;
                default:  unmodeled = 1'b1;
            endcase
        end else if (!we) begin
            case (a)
                32'h0c12_0004: begin dout = ctlv; if ((ctlw & sel) != sel) unmodeled = 1'b1; end
                32'h0c12_0008: begin dout = cmdv; if ((cmdw & sel) != sel) unmodeled = 1'b1; end
                default: begin
                    dout = pllv;
                    if ((pllw & sel) != sel || pllv != 32'h2210) unmodeled = 1'b1;
                    else dout = pllv | 32'd1;
                end
            endcase
        end
    end else if (gpio_hit && cyc && stb) begin
        dout = gpr[gidx] & wmask;
        // ---- quirk bits on reads ----
        // euart1 TX idle (0x0c150514 bit 2)
        if (a == 32'h0c15_0514 && !we) dout = dout | (32'h4 & wmask);
        // FBUS TX drained (0x0c150504 bits 4,6,7,8 = 0x1D0)
        if (a == 32'h0c15_0504 && !we) dout = dout | (32'h1d0 & wmask);
        // FBUS TX empty (0x0c150568 bits 1+2 in upper halfword = 0x60000)
        if (a == 32'h0c15_0568 && !we) dout = dout | (32'h6_0000 & wmask);
        // MBUS strobe self-clear: low halfword reads 0
        if (a == 32'h0c15_021c && !we) dout = dout & 32'hffff_0000;
        // GSM system-type strap (0x0c150000 bit 22)
        if (a == 32'h0c15_0000 && !we) dout = dout | (32'h0040_0000 & wmask);
        // clock-unit 0x0c148000 lock bit 0
        if (a == 32'h0c14_8000 && !we) dout = dout | (32'h1 & wmask);
        // free-running counter 0x0c150110 upper halfword = counter
        if (a == 32'h0c15_0110 && !we) dout = (dout & 32'h0000_ffff) | {fcnt[15:0], 16'd0};
        // window constant 0x0c150114: reads 0x0080 if never written
        if (a == 32'h0c15_0114 && !we && (gpr[gidx] & 16'hffff) == 16'd0)
            dout = (dout & 32'hffff_0000) | 16'h0080;
    end else if (lcd_hit && cyc && stb) begin
        if (sel != 4'hf) unmodeled = 1'b1;
        else if (a == 32'h0c12_1204 && we) begin
            if (din != 32'd1 && din != 32'd2) unmodeled = 1'b1;
        end else if (!ctl_written || ctl != 32'd1) begin
            unmodeled = 1'b1;
        end else if (a == 32'h0c12_1200 && we) begin
            if (!hdr_ok) unmodeled = 1'b1;
        end else if (a == 32'h0c12_1204 && !we) begin
            dout = 32'd4;
        end else if (a == 32'h0c12_1200 && !we) begin
            if (hdr_written && hdr == 32'h4920_0000)
                dout = 32'h4000_0000;
            else unmodeled = 1'b1;
        end else if (a == 32'h0c12_1208 && we) begin
            if (!hdr_written) unmodeled = 1'b1;
        end else if (a == 32'h0c12_1208 && !we) begin
            if (!(hdr_written && hdr[31:16] == 16'h0784)) unmodeled = 1'b1;
        end
    end
end

// ---- registered state -------------------------------------------------------
always @(posedge clk) begin
    if (rst) begin
        ctl_written <= 1'b0;
        hdr_written <= 1'b0;
        ctl <= 32'd0; hdr <= 32'd0;
        ctlv <= 32'd0; cmdv <= 32'd0; pllv <= 32'd0;
        ctlw <= 4'd0;  cmdw <= 4'd0;  pllw <= 4'd0;
        fcnt <= 32'd0; fcnt_div <= 12'd0;
    end else begin
        // free-running counter: one tick per 3174 clocks
        if (fcnt_div == 12'd3173) begin
            fcnt_div <= 12'd0;
            fcnt     <= fcnt + 32'd1;
        end else
            fcnt_div <= fcnt_div + 12'd1;

        if (nos4k_hit && commit && we && !unmodeled && a[31:12] == 20'h0c004)
            nos4k[a[11:2]] <= (nos4k[a[11:2]] & ~wmask) | (din & wmask);

        if (d_space_hit && commit && we && !unmodeled)
            d_regs[d_idx] <= (d_regs[d_idx] & ~wmask) | (din & wmask);

        if (clk_hit && commit && we && !unmodeled) begin
            case (a)
                32'h0c12_0004: begin ctlv <= (ctlv & ~wmask) | (din & wmask); ctlw <= ctlw | sel; end
                32'h0c12_0008: begin cmdv <= (cmdv & ~wmask) | (din & wmask); cmdw <= cmdw | sel; end
                default:       begin pllv <= (pllv & ~wmask) | (din & wmask); pllw <= pllw | sel; end
            endcase
        end

        if (gpio_hit && commit && we && !unmodeled)
            gpr[gidx] <= (gpr[gidx] & ~wmask) | (din & wmask);

        if (lcd_hit && commit && we && !unmodeled) begin
            if (a == 32'h0c12_1204) begin
                ctl         <= din;
                ctl_written <= 1'b1;
                if (din == 32'd2) hdr_written <= 1'b0;
            end else if (a == 32'h0c12_1200) begin
                hdr         <= din;
                hdr_written <= 1'b1;
            end
        end
    end
end

endmodule
