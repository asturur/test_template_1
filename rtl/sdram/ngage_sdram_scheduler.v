// SPDX-License-Identifier: GPL-3.0-or-later
//
// SDRAM controller for the MiSTer SDRAM module (16-bit, 32 MB or larger:
// AS4C16M16SA, AS4C32M16SB, IS42S16320, W9825G6KH class). It holds the
// N-Gage's 16 MB SDRAM in the first 16 MB; the rest is spare.
//
// Derived from Sorgelig's MiSTer SDRAM controller (sdram.sv, Copyright (c)
// 2015-2019 Sorgelig, GPL-3.0-or-later; copies in
// ../direct-video/PMD85/rtl/sdram.sv and GBA_MiSTer, which credit the
// hamsterworks "Simple SDRAM Controller"): the command encoding, the mode
// register, the power-up sequence, SDRAM_CLK as the inverted clock from a
// DDIO output, DQM carried on A12:A11 during READ and WRITE, and the read
// capture one clock after the CAS latency. The request port, the 16-byte
// line transfers and the timing schedule are new.
//
// Clocking. Everything runs on clk (clk_sys, 104 MHz: 2 x 52 MHz). The chip
// gets ~clk from a DDIO output, so it samples a command half a clock (4.8 ns)
// after the FPGA's output registers launch it; both leave through the same
// kind of I/O register, so setup and hold are each about T/2. Read data is
// captured in the DQ input register CAS_LATENCY + CAPTURE_CLKS clocks after
// the READ edge. With the clock-out delay and the input delay (together
// D = 4.5-7 ns), tAC <= 6 ns and tOH >= 2.5 ns, the window of the element is
// [1.5T + tAC + D, 2.5T + tOH + D] after the READ edge, 27.4-31.0 ns at
// 104 MHz worst case, and the capture edge at 3T = 28.8 ns sits inside it
// with about 1.4 ns either side. Command, address, DQM and DQ registers sit in
// the I/O cells (sys/sys.tcl sets FAST_*_REGISTER for SDRAM_*). They copy a
// stage of internal registers (p_*), where the schedule's decisions land,
// so that the I/O registers at the chip's edge need no logic before them
// (timing); everything reaches the pins a clock later, and the capture
// clock (CAP) counts that clock too.
//
// Policy: open page, one row per bank. A hit issues READ/WRITE immediately;
// a closed bank needs ACTIVE and tRCD; a conflict precharges only that bank,
// waits tRP and the previous ACTIVE's tRC, then opens the new row. Per-bank
// saturating ages enforce tRAS even across multiple accesses. The mapping
// uses 1 KB rows with bank bits at byte address 13:12 (4 KB interleaving). No reordering or
// overlapping accesses. All four rows close for each refresh.
//
// Mode: burst length 8 (sequential) for reads, single-location writes. An
// aligned 32-byte line read issues two BL8 reads eight clocks apart. Word
// reads issue BURST TERMINATE two clocks after READ, leaving two halfwords
// with the same capture schedule. Writes issue one WRITE per halfword with
// its DQM (two for a word, eight for a line). Reads finish after capture;
// writes finish tWR after the last WRITE. This leaves the shared data bus
// free for either direction, with DQM low before any read data arrives.
//
// Schedule at the defaults (tRCD, tRP 20 ns, tRAS 45 ns, tRC, tRFC 70 ns,
// tWR 15 ns, rounded up at 104 MHz to 3, 3, 5, 8, 8 and 2 clocks):
//                    column command     words at port     next request
//   word read hit:    READ 0, STOP 2      5                 6
//   16-byte read hit: READ 0            5 through 11      12
//   32-byte read hit: READ 0 and 8        5 through 19      20
//   word write hit:   WRITE 0-1                            3
//   line write hit:   WRITE 0-7                            9
// A closed bank adds ACTIVE at 0 and 3 clocks to these numbers; a conflict
// adds PRECHARGE at 0, ACTIVE at 3 and 6 clocks (plus any outstanding tRAS
// or tRC wait). Commands reach the pins one clock after the listed edge,
// through the unchanged output stage. Capture includes that extra clock.
//
// Refresh: after REFRESH_CLKS (755 by default), block new requests, finish
// the current access and tRAS, PRECHARGE ALL, wait tRP, AUTO REFRESH, wait
// tRFC. The timer resets on AUTO REFRESH. Its interval reserves the worst
// access (conservatively 23 clocks), close wait (8), due-flag latency (2),
// tRFC (8) and REFRESH_SLACK (16): even that bound is 788 clocks (7.58 us)
// between refreshes, below tREFI (8192 rows in 64 ms = 7.81 us). Normally
// closing and refreshing takes 3 + 8 = 11 clocks. Power-up: POWERUP_US of
// NOPs, PRECHARGE ALL, INIT_REFRESHES refreshes, mode register, then tMRD.
//
// Port (one clock domain with the requester):
//   A request is taken at an edge where req is high and busy is low; addr,
//   we, line, wdata and wbe must be valid then and are latched. A read
//   returns its words on rvalid/rword/rdata, one every other clock, in the
//   chip's order (from addr's word, wrapping in the 16-byte block); rdata
//   is driven straight from the DQ input registers and is valid only while
//   rvalid is high. A write needs nothing back: its data is latched.
//   wdata/wbe are indexed by the byte in the 16-byte block (word k of the
//   block in wdata[32k+31:32k]); a word write uses the word at addr only.
//   Accesses are carried out in order.
//
// Unknowns, behind parameters: the module's chip and speed grade (timing
// above, CAS_LATENCY 2: every MiSTer module's chip runs CL2 at 104 MHz), the
// board delay that CAPTURE_CLKS assumes, the module size (only the first
// 32 MB, 9 column bits, are used, which every module has).
module ngage_sdram_scheduler #(
    parameter integer CLK_HZ          = 104000000,
    parameter integer CAS_LATENCY     = 2,
    parameter integer CAPTURE_CLKS    = 1,       // clocks from the chip's data edge to the DQ capture
    parameter integer T_RCD_NS        = 20,
    parameter integer T_RP_NS         = 20,
    parameter integer T_RAS_NS        = 45,
    parameter integer T_RC_NS         = 70,
    parameter integer T_RFC_NS        = 70,
    parameter integer T_WR_NS         = 15,
    parameter integer T_REFI_NS       = 7812,    // 64 ms / 8192 rows
    parameter integer REFRESH_SLACK   = 16,      // clocks of margin under tREFI
    parameter integer POWERUP_US      = 200,
    parameter integer INIT_REFRESHES  = 8
) (
    input  wire          clk,
    input  wire          init,      // restarts the power-up sequence while high
    output wire          ready,     // the chip is set up

    input  wire          req,
    output wire          busy,
    input  wire          we,
    input  wire          line,      // 1: read a line or write 16 bytes
    input  wire          read_short, // aligned 16-byte line instead of 32-byte line
    input  wire  [24:2]  addr,      // word address in the module
    input  wire  [127:0] wdata,
    input  wire  [15:0]  wbe,
    output wire          rvalid,
    output reg   [1:0]   rword,     // word of the block that rdata holds
    output wire  [31:0]  rdata,

    output wire          sdram_cke,
    output wire          sdram_cs_n,
    output reg           sdram_ras_n,
    output reg           sdram_cas_n,
    output reg           sdram_we_n,
    output reg   [1:0]   sdram_ba,
    output reg   [12:0]  sdram_a,
    output reg           sdram_dqml,
    output reg           sdram_dqmh,
    output reg   [15:0]  sdram_dq_o,
    output reg   [15:0]  sdram_dq_oe,
    input  wire  [15:0]  sdram_dq_i
);

    // ------------------------------------------------------------------
    // Timing in clocks
    // ------------------------------------------------------------------
    localparam integer T_PS = 1000000000 / (CLK_HZ / 1000);

    function automatic integer clks;
        input [31:0] ns;
        begin
            clks = (ns * 1000 + T_PS - 1) / T_PS;
        end
    endfunction

    function automatic integer imax;
        input [31:0] a;
        input [31:0] b;
        begin
            imax = (a > b) ? a : b;
        end
    endfunction

    localparam integer RCD = imax(1, clks(T_RCD_NS));
    localparam integer RP  = imax(1, clks(T_RP_NS));
    localparam integer RAS = imax(1, clks(T_RAS_NS));
    localparam integer RC  = imax(1, clks(T_RC_NS));
    localparam integer RFC = imax(1, clks(T_RFC_NS));
    localparam integer WR  = imax(2, clks(T_WR_NS));
    localparam integer MRD = 2;
    // first halfword captured (+ 1: the output stage before the I/O registers)
    localparam integer CAP = RCD + CAS_LATENCY + CAPTURE_CLKS + 1;

    // Keep the capture schedule relative to a real or virtual ACTIVE. A
    // row hit starts at RCD and issues its column command on acceptance.
    // Reads finish after capture; writes keep DQ free for WR clocks after
    // the last halfword (also covers write-to-read and DQM recovery).
    localparam integer END_RW = CAP + 2;
    localparam integer END_RL = CAP + 16;
    localparam integer END_RS = CAP + 8;
    localparam integer END_WW = RCD + 1 + WR;
    localparam integer END_WL = RCD + 7 + WR;
    localparam integer AGE_MAX = imax(RAS, RC);
    localparam integer AW = $clog2(AGE_MAX + 1);
    // Conservative bounds even for an access accepted just after ACTIVE:
    // finish tRAS, PRECHARGE, then respect both tRP and the previous tRC.
    localparam integer LONGEST = imax(RAS + RP, RC) + imax(imax(END_RW, END_RL), imax(END_WW, END_WL));
    localparam integer REF_CLOSE = RAS + RP;

    localparam integer REFI_CLKS     = T_REFI_NS * 1000 / T_PS;
    localparam integer REFRESH_CLKS  = REFI_CLKS - LONGEST - REF_CLOSE - RFC - REFRESH_SLACK - 2;
    localparam integer POWERUP_CLKS  = POWERUP_US * (CLK_HZ / 1000000);

    localparam integer TW = $clog2(imax(LONGEST, RFC) + 2);

    function [AW-1:0] age_counter;
        input [31:0] value;
        begin
            age_counter = value[AW-1:0];
        end
    endfunction

    function [TW-1:0] access_counter;
        input [31:0] value;
        begin
            access_counter = value[TW-1:0];
        end
    endfunction

    function [TW:0] capture_counter;
        input [31:0] value;
        begin
            capture_counter = value[TW:0];
        end
    endfunction

    function [15:0] long_counter;
        input [31:0] value;
        begin
            long_counter = value[15:0];
        end
    endfunction

    function [3:0] init_counter;
        input [31:0] value;
        begin
            init_counter = value[3:0];
        end
    endfunction

    // Mode register: single-location writes (A9), CAS latency, sequential,
    // burst length 8
    localparam [12:0] MODE = {3'b000, 1'b1, 2'b00, CAS_LATENCY[2:0], 1'b0, 3'b011};

    // {ras_n, cas_n, we_n}
    localparam [2:0] CMD_NOP       = 3'b111;
    localparam [2:0] CMD_ACTIVE    = 3'b011;
    localparam [2:0] CMD_READ      = 3'b101;
    localparam [2:0] CMD_WRITE     = 3'b100;
    localparam [2:0] CMD_PRECHARGE = 3'b010;
    localparam [2:0] CMD_REFRESH   = 3'b001;
    localparam [2:0] CMD_MODE      = 3'b000;
    localparam [2:0] CMD_STOP      = 3'b110;

    // ------------------------------------------------------------------
    // State
    // ------------------------------------------------------------------
    localparam [2:0] I_WAIT = 3'd0;
    localparam [2:0] I_PRECHARGE = 3'd1;
    localparam [2:0] I_REFRESH = 3'd2;
    localparam [2:0] I_MODE = 3'd3;
    localparam [2:0] I_DONE = 3'd4;

    reg [2:0] istate = I_WAIT;
    reg [15:0]    icnt = 0;
    reg [3:0]     irefs = 0;

    // t is the edge being prepared, relative to ACTIVE in ACCESS, or to
    // PRECHARGE / REFRESH in the wait states. No request reordering.
    localparam [2:0] IDLE = 3'd0;
    localparam [2:0] PRE_WAIT = 3'd1;
    localparam [2:0] ACT_WAIT = 3'd2;
    localparam [2:0] ACCESS = 3'd3;
    localparam [2:0] REF_PRE = 3'd4;
    localparam [2:0] REF_RP = 3'd5;
    localparam [2:0] REF_WAIT = 3'd6;
    reg [2:0] state = IDLE;
    reg [3:0]     row_open = 0;
    reg [12:0]    row_addr [0:3];
    reg [AW-1:0]  row_age [0:3];  // saturating age of each bank's last ACTIVE
    wire [3:0]     pre_ok;
    // (Quartus 17 wants the genvar declared and an explicit generate block)
    genvar b;
    generate
        for (b = 0; b < 4; b = b + 1) begin : bank_timing
            assign pre_ok[b] = !row_open[b] || row_age[b] >= age_counter(RAS);
        end
    endgenerate
    reg [12:0]    op_row;
    reg           op_we, op_line, op_wide;
    reg [TW-1:0]  t;
    reg [TW-1:0]  t_end;
    reg [1:0]     op_ba = 2'b00;
    reg [8:0]     op_col;
    reg [127:0]   wsh;                  // write halfwords, next at the bottom
    reg [15:0]    wmask;                // their DQM, two bits each
    reg [1:0]     word;                 // next read word of the block
    reg [15:0]    dq_q, dq_hold;        // the last two captured halfwords

    reg [15:0]    rcnt = 0;
    reg           ref_due = 1'b0;
    reg           ready_q = 1'b0;

    wire idle = state == IDLE || (state == ACCESS && t == t_end) ||
                (state == REF_WAIT && t == access_counter(RFC));

    // the output stage (see Clocking): the schedule sets these, the I/O
    // registers take them a clock later
    reg        p_ras_n = 1'b1, p_cas_n = 1'b1, p_we_n = 1'b1;
    reg [1:0]  p_ba;
    reg [12:0] p_a;
    reg        p_dqml, p_dqmh;
    reg [15:0] p_dq_o;
    reg [15:0] p_dq_oe = 16'h0000;
    always @(posedge clk) begin
        {sdram_ras_n, sdram_cas_n, sdram_we_n} <= {p_ras_n, p_cas_n, p_we_n};
        sdram_ba    <= p_ba;
        sdram_a     <= p_a;
        sdram_dqml  <= p_dqml;
        sdram_dqmh  <= p_dqmh;
        sdram_dq_o  <= p_dq_o;
        sdram_dq_oe <= p_dq_oe;
    end

    reg           rvalid_q = 1'b0;

    assign ready     = ready_q;
    assign rvalid    = rvalid_q;
    assign busy      = !ready_q || !idle || ref_due;
    assign sdram_cke = 1'b1;
    assign sdram_cs_n = 1'b0;

    // read capture: halfword k at edge CAP + k; word j complete at CAP + 2j + 1
    wire [TW:0] tcap = {1'b0, t} - access_counter(CAP);
    wire        cap_word = state == ACCESS && !op_we && t >= access_counter(CAP + 1) && tcap[0] &&
                           tcap < (op_wide ? capture_counter(16) : op_line ? capture_counter(8) : capture_counter(2));

    assign rdata = {dq_q, dq_hold};

    // Physical halfword address: column 8:0, row 21:9, bank 23:22.
    // Move logical byte bits 13:12 to the bank; preserve every other bit.
    // This is a bijective remap of all 32 MB; port addresses stay unchanged.
    wire [23:0] h = {addr[13:12], addr[24:14], addr[11:10], addr[9:2], 1'b0};
    wire take = ready_q && idle && !ref_due && req;
    wire hit = row_open[h[23:22]] && row_addr[h[23:22]] == h[21:9];
    wire hit_start = take && hit;
    wire [8:0] req_col = we && line ? {h[8:3], 3'b000} : h[8:0];
    wire [127:0] req_wsh = line ? wdata : {96'd0, wdata[32 * addr[3:2] +: 32]};
    wire [15:0] req_mask = line ? ~wbe : {12'hFFF, ~wbe[4 * addr[3:2] +: 4]};
    wire second_burst = state == ACCESS && !idle && !op_we && op_wide && t == access_counter(RCD + 8);
    wire read_now = second_burst || (hit_start && !we) ||
                    (state == ACCESS && !idle && !op_we && t == access_counter(RCD));
    wire write_now = (hit_start && we) || (state == ACCESS && !idle && op_we &&
                      t >= access_counter(RCD) && t < access_counter(RCD) + (op_line ? access_counter(8) : access_counter(2)));
    wire [8:0] col_now = hit_start ? req_col : op_col;
    wire [127:0] wsh_now = hit_start ? req_wsh : wsh;
    wire [15:0] mask_now = hit_start ? req_mask : wmask;

    integer bank_index;
    always @(posedge clk) begin
        // the DQ input registers take the pins every clock
        dq_q    <= sdram_dq_i;
        dq_hold <= dq_q;

        // output stage, loaded every clock: a NOP unless set below; the
        // bank of the access throughout it, DQ released
        {p_ras_n, p_cas_n, p_we_n} <= CMD_NOP;
        p_a     <= 13'd0;
        p_ba    <= op_ba;
        p_dqml  <= 1'b0;
        p_dqmh  <= 1'b0;
        p_dq_o  <= wsh[15:0];
        p_dq_oe <= 16'h0000;
        for (bank_index = 0; bank_index < 4; bank_index = bank_index + 1) begin
            if (row_age[bank_index] < age_counter(AGE_MAX)) row_age[bank_index] <= row_age[bank_index] + 1'b1;
        end

        rvalid_q <= 1'b0;
        if (cap_word) begin
            rvalid_q <= 1'b1;
            rword  <= word;
            word   <= word + 2'd1;
        end

        // ---- refresh timer ----
        if (ready_q) begin
            if (rcnt == long_counter(REFRESH_CLKS)) ref_due <= 1'b1;
            else rcnt <= rcnt + 16'd1;
        end

        // ---- power-up ----
        if (!ready_q) begin
            case (istate)
                I_WAIT: begin
                    icnt <= icnt + 16'd1;
                    if (icnt == long_counter(POWERUP_CLKS)) begin
                        istate <= I_PRECHARGE;
                        icnt   <= 0;
                    end
                end
                I_PRECHARGE: begin
                    if (icnt == 16'd0) begin
                        {p_ras_n, p_cas_n, p_we_n} <= CMD_PRECHARGE;
                        p_a[10] <= 1'b1;                  // all banks
                    end
                    icnt <= icnt + 16'd1;
                    if (icnt == long_counter(RP - 1)) begin
                        istate <= I_REFRESH;
                        icnt   <= 0;
                        irefs  <= 0;
                    end
                end
                I_REFRESH: begin
                    if (icnt == 16'd0) {p_ras_n, p_cas_n, p_we_n} <= CMD_REFRESH;
                    icnt <= icnt + 16'd1;
                    if (icnt == long_counter(RFC - 1)) begin
                        icnt  <= 0;
                        irefs <= irefs + 4'd1;
                        if (irefs == init_counter(INIT_REFRESHES - 1)) istate <= I_MODE;
                    end
                end
                I_MODE: begin
                    if (icnt == 16'd0) begin
                        {p_ras_n, p_cas_n, p_we_n} <= CMD_MODE;
                        p_a  <= MODE;
                        p_ba <= 2'b00;
                    end
                    icnt <= icnt + 16'd1;
                    if (icnt == long_counter(MRD - 1)) istate <= I_DONE;
                end
                default: begin
                    ready_q <= 1'b1;
                    rcnt    <= 0;
                    ref_due <= 1'b0;
                end
            endcase
        end

        // ---- the access in progress ----
        if (ready_q && !idle) begin
            case (state)
                PRE_WAIT: if (pre_ok[op_ba]) begin
                    {p_ras_n, p_cas_n, p_we_n} <= CMD_PRECHARGE;
                    row_open[op_ba] <= 1'b0;
                    state <= ACT_WAIT;
                    t <= access_counter(1);
                end
                ACT_WAIT: begin
                    if (t < access_counter(RP)) t <= t + 1'b1;
                    if (t >= access_counter(RP) && row_age[op_ba] >= age_counter(RC)) begin
                        {p_ras_n, p_cas_n, p_we_n} <= CMD_ACTIVE;
                        p_a <= op_row;
                        row_addr[op_ba] <= op_row;
                        row_open[op_ba] <= 1'b1;
                        row_age[op_ba] <= age_counter(1);
                        state <= ACCESS;
                        t <= access_counter(1);
                    end
                end
                ACCESS: begin
                    t <= t + 1'b1;
                    // BURST TERMINATE has the same CL delay as READ. Issued
                    // two clocks after READ, it leaves exactly two halfwords
                    // on DQ, without closing the row or changing DQM.
                    if (!op_we && !op_line && t == access_counter(RCD + 2))
                        {p_ras_n, p_cas_n, p_we_n} <= CMD_STOP;
                end
                REF_PRE: if (&pre_ok) begin
                    {p_ras_n, p_cas_n, p_we_n} <= CMD_PRECHARGE;
                    p_a[10] <= 1'b1;
                    row_open <= 0;
                    state <= REF_RP;
                    t <= access_counter(1);
                end
                REF_RP: begin
                    t <= t + 1'b1;
                    if (t == access_counter(RP)) begin
                        {p_ras_n, p_cas_n, p_we_n} <= CMD_REFRESH;
                        state <= REF_WAIT;
                        t <= access_counter(1);
                        ref_due <= 1'b0;
                        rcnt <= 0;
                    end
                end
                REF_WAIT: t <= t + 1'b1;
                default: ;
            endcase
        end else if (ready_q) begin
            state <= IDLE;
            if (ref_due) begin
                // Stop accepting accesses until all banks are precharged,
                // tRP has elapsed, and AUTO REFRESH has completed its tRFC.
                state <= REF_PRE;
                if (&pre_ok) begin
                    {p_ras_n, p_cas_n, p_we_n} <= CMD_PRECHARGE;
                    p_a[10] <= 1'b1;
                    row_open <= 0;
                    state <= REF_RP;
                    t <= access_counter(1);
                end
            end else if (req) begin
                p_ba     <= h[23:22];
                op_ba    <= h[23:22];
                op_row   <= h[21:9];
                op_we    <= we;
                op_line  <= line;
                op_wide  <= line && !read_short;
                if (we) t_end <= line ? access_counter(END_WL) : access_counter(END_WW);
                else if (!line) t_end <= access_counter(END_RW);
                else t_end <= read_short ? access_counter(END_RS) : access_counter(END_RL);
                word     <= addr[3:2];
                op_col   <= req_col;
                wsh      <= req_wsh;
                wmask    <= req_mask;
                if (hit) begin
                    state <= ACCESS;
                    t <= access_counter(RCD + 1);
                end else if (row_open[h[23:22]]) begin
                    state <= PRE_WAIT;
                    if (pre_ok[h[23:22]]) begin
                        {p_ras_n, p_cas_n, p_we_n} <= CMD_PRECHARGE;
                        row_open[h[23:22]] <= 1'b0;
                        state <= ACT_WAIT;
                        t <= access_counter(1);
                    end
                end else begin
                    state <= ACT_WAIT;
                    t <= access_counter(RP); // already closed: no new tRP to wait
                    if (row_age[h[23:22]] >= age_counter(RC)) begin
                        {p_ras_n, p_cas_n, p_we_n} <= CMD_ACTIVE;
                        p_a <= h[21:9];
                        row_addr[h[23:22]] <= h[21:9];
                        row_open[h[23:22]] <= 1'b1;
                        row_age[h[23:22]] <= age_counter(1);
                        state <= ACCESS;
                        t <= access_counter(1);
                    end
                end
            end
        end

        // A hit uses the request directly for its first column command;
        // later beats and misses use the latched operands. These muxes end
        // at p_*, preserving the logic-free I/O register stage.
        if (read_now) begin
            {p_ras_n, p_cas_n, p_we_n} <= CMD_READ;
            p_a[8:0] <= second_burst ? col_now + 9'd8 : col_now;
        end
        if (write_now) begin
            {p_ras_n, p_cas_n, p_we_n} <= CMD_WRITE;
            p_a <= {mask_now[1], mask_now[0], 2'b00, col_now};
            p_dqml <= mask_now[0];
            p_dqmh <= mask_now[1];
            p_dq_o <= wsh_now[15:0];
            p_dq_oe <= 16'hFFFF;
            wsh <= {16'h0000, wsh_now[127:16]};
            wmask <= {2'b11, mask_now[15:2]};
            op_col <= {col_now[8:3], col_now[2:0] + 3'd1};
        end

        if (init) begin
            istate  <= I_WAIT;
            icnt    <= 0;
            ready_q <= 1'b0;
            state   <= IDLE;
            row_open <= 0;
            for (bank_index = 0; bank_index < 4; bank_index = bank_index + 1) row_age[bank_index] <= age_counter(AGE_MAX);
            ref_due <= 1'b0;
        end
    end

endmodule
