// SPDX-License-Identifier: GPL-2.0-or-later
//
// Adapted from ngage2 rtl/upp/upp_haudio.sv, revision 6e80660.
// Software playback registers at 0x0c1f0000-0x0c1f00ff. The guest bridge
// submits SDRAM buffers here. This is a logical interface outside the UPP
// and DSP hardware models. The bus wrapper checks 32-bit accesses.
//
//   +0x00  ID      reads 0x41554431 ("AUD1")
//   +0x04  CTRL    reads the value written. Bit 0 RUN: 0 -> 1 starts at
//                  buffer 0, position 0, PLAYED 0; 1 -> 0 stops and empties
//                  both buffers (FULL and DONE clear). Bit 1 IRQ enable
//   +0x08  FORMAT  bit 0 stereo (L, R frames); samples are signed 16-bit LE
//   +0x0C  RATE    frames per second, clamped to 4000-48000; reset 16000
//   +0x10  ADDR0   byte address of buffer 0 (bit 0 reads 0)  +0x14 ADDR1
//   +0x18  LEN0    frames in buffer 0; a nonzero write marks it full
//                                                            +0x1C LEN1
//   +0x20  STATUS  bits 0/1 DONE0/1 (write 1 to clear), 4/5 FULL0/1,
//                  8 running, 9 the buffer being played, 10 starved
//   +0x24  POS     frames played from the current buffer
//   +0x28  VOLUME  gain, 0x100 = unity (reset value); larger values clamp
//   +0x2C  PLAYED  frames played since RUN, silence included
//   +0x30  CONTEXT native firmware's pool pointer, zero on reset
//   the rest of the window reads 0, writes are dropped.
//
// Play, frame by frame as the model's catch-up (aud_play): while RUN is set a
// frame is due each time the frame clock (RATE per second, its phase counted
// from the RUN write or from a RATE write that changes the rate while
// running, as the model restarts its count there) comes round. Then if the
// current buffer is empty and the other is full, play moves to the other one
// at position 0; if it is still empty the frame is silence (starved), else
// it is the next frame of the buffer, and when the position reaches LEN the
// buffer is empty, its DONE is set and play moves to the other one at
// position 0. A frame due at the same clock edge as a register write is
// played first (the model catches up before every access). The interrupt,
// interrupt source 5, is DONE0 | DONE1 with IRQ enable.
//   [deviation] Frame by frame where the model plays chunks: the same unless
// LEN is rewritten below POS for the buffer being played, which then ends
// after one more frame (the model plays up to the end of its chunk first).
//
// Samples are read from the bus (this block's master port, which upp_periph
// shares with the DMA controller) when their frame is played: one 32-bit read
// a frame, two (in one cycle) for a stereo frame that is not on a 4-byte
// boundary; a read that ends with an error gives 0. The value is the sample
// times VOLUME at that moment, shifted right 8 (the model's (v * volume) >>
// 8). The reads wait one frame deep: a bus that holds them off for more than
// a frame period loses frames (the bus answers in well under a microsecond).
// Reads still under way when a run starts are dropped.
//
// Output: AUDIO_L/R at OUT_HZ (48 kHz), resampled by linear interpolation
// as the model's host output (out_put): between the two frames before the
// latest, at the frame clock's phase. Interpolating one frame later than the
// play gives the sample read a whole frame period. Mono goes to both
// channels; the output is 0 while RUN is clear, and a run starts from
// silence. [deviation] The model's phase steps by RATE / 48000 in 16.16 (so
// its 48 kHz stream runs slightly fast); here the phase is the frame clock's,
// in real time, to 16 bits. Its interpolation product can overflow 32 bits
// for steps above half of full scale; here it is exact.
module ngage_game_pcm #(
    parameter integer CLK_HZ = 104_000_000,
    parameter integer OUT_HZ = 48_000
) (
    input  wire         clk,
    input  wire         reset,

    // Software playback registers
    input  wire         acc,
    input  wire         wr,
    input  wire  [7:0]  off,          // byte offset in the window
    input  wire  [31:0] wdata,
    output reg   [31:0] rmask,
    output reg   [31:0] rdata,

    output wire         irq,

    // sample reads (Wishbone B3 classic)
    output reg          m_cyc,
    output wire         m_stb,
    output wire         m_we,
    output reg   [31:0] m_adr,
    output wire  [31:0] m_dat_o,
    output wire  [3:0]  m_sel,
    input  wire         m_ack,
    input  wire         m_err,
    input  wire  [31:0] m_dat_i,

    // the output, signed, at OUT_HZ
    output reg   [15:0] out_l,
    output reg   [15:0] out_r,
    output reg          out_valid,

    // for the bench: each frame as its samples arrive
    output reg          frame_we,
    output wire  [15:0] frame_l,
    output wire  [15:0] frame_r
);

    function integer clog2;
        input [63:0] value;
        reg   [63:0] n;
        begin
            n = value - 64'd1;
            for (clog2 = 0; n != 0; clog2 = clog2 + 1)
                n = n >> 1;
        end
    endfunction

    localparam [63:0] CLOCK_64 = {32'd0, CLK_HZ};
    localparam [63:0] OUT_RATE_64 = {32'd0, OUT_HZ};
    localparam integer FW = clog2(CLOCK_64 + 64'd48001);
    localparam integer OW = clog2(CLOCK_64 + OUT_RATE_64 + 64'd1);
    // 2^40 / CLK_HZ: the frame phase (0 to CLK_HZ - 1) as 16 bits
    localparam [63:0] PK = (64'd1 << 40) / CLOCK_64;
    localparam integer KW = clog2(PK + 64'd1);
    localparam [FW-1:0] FRAME_CLOCK = CLOCK_64[FW-1:0];
    localparam [OW-1:0] OUTPUT_CLOCK = CLOCK_64[OW-1:0];
    localparam [OW-1:0] OUTPUT_RATE = OUT_RATE_64[OW-1:0];

    // ------------------------------------------------------------------
    // Registers
    // ------------------------------------------------------------------
    reg [31:0]   ctrl, addr0, addr1, len0, len1, pos, played;
    reg [31:0]   firmware_context;
    reg [15:0]   rate;
    reg [8:0]    volume;
    reg          stereo, cur, starved;
    reg [1:0]    full, done;
    reg [FW-1:0] facc;

    wire run = ctrl[0];
    assign irq = ctrl[1] && done != 2'b00;

    always @* begin
        rmask = acc ? 32'hFFFF_FFFF : 32'd0;
        rdata = 32'd0;
        if (acc) begin
            case (off)
                8'h00: rdata = 32'h4155_4431;
                8'h04: rdata = ctrl;
                8'h08: rdata = {31'd0, stereo};
                8'h0C: rdata = {16'd0, rate};
                8'h10: rdata = addr0;
                8'h14: rdata = addr1;
                8'h18: rdata = len0;
                8'h1C: rdata = len1;
                8'h20: rdata = {21'd0, starved, cur, run, 2'b00, full, 2'b00, done};
                8'h24: rdata = pos;
                8'h28: rdata = {23'd0, volume};
                8'h2C: rdata = played;
                8'h30: rdata = firmware_context;
                default: rdata = 32'd0;
            endcase
        end
    end

    // the frame clock
    wire [FW-1:0] fsum = facc + {{(FW-16){1'b0}}, rate};
    wire          tick = run && fsum >= FRAME_CLOCK;

    // the frame the tick plays
    wire        sw     = !full[cur] && full[!cur];
    wire        b      = sw ? !cur : cur;
    wire [31:0] p      = sw ? 32'd0 : pos;
    wire        play   = full[b];
    wire [31:0] p1     = p + 32'd1;
    wire [31:0] blen   = b ? len1 : len0;
    // p1 >= blen without p1's carry chain in front of the compare: the
    // length minus one and its zero flag are registers, set with the length
    // (p + 1 >= blen is blen == 0, or p >= blen - 1 unless p + 1 wraps).
    reg [31:0] len0m1, len1m1;
    reg        len0z, len1z;
    wire        ends   = (b ? len1z : len0z) || (p >= (b ? len1m1 : len0m1) && p != 32'hFFFF_FFFF);
`ifndef SYNTHESIS
    always @(posedge clk) if (!reset) if (ends != (p1 >= blen)) begin
        $display("haudio buffer end");
        $stop;
    end
`endif
    wire [31:1] fadr   = (b ? addr1[31:1] : addr0[31:1]) + (stereo ? {p[29:0], 1'b0} : p[30:0]);

    wire        run_set = wr && off == 8'h04 && wdata[0] && !ctrl[0];
    wire [15:0] rate_w = (wdata < 32'd4000) ? 16'd4000 : (wdata > 32'd48000) ? 16'd48000 : wdata[15:0];

    // the sample-read request: one deep, the latest frame
    reg        rq_v, rq_play, rq_st;
    reg [31:1] rq_adr;               // halfword address
    reg [8:0]  rq_vol;
    reg        start;                // in the clock after a RUN 0 -> 1 write

    localparam [1:0] F_IDLE = 2'd0, F_L = 2'd1, F_R = 2'd2;
    reg [1:0] fst;
    wire         f_take = fst == F_IDLE && rq_v && !start;

    always @(posedge clk) begin
        start <= 1'b0;
        if (run) facc <= tick ? fsum - FRAME_CLOCK : fsum;
        if (f_take || start) rq_v <= 1'b0;

        if (tick) begin
            played  <= played + 32'd1;
            cur     <= b;
            pos     <= p;
            starved <= !play;
            if (play) begin
                pos <= p1;
                if (ends) begin
                    full[b] <= 1'b0;
                    done[b] <= 1'b1;
                    cur     <= !b;
                    pos     <= 32'd0;
                end
            end
            rq_v    <= 1'b1;
            rq_play <= play;
            rq_st   <= stereo;
            rq_adr  <= fadr;
            rq_vol  <= volume;
        end

        if (wr) begin
            case (off)
                8'h04: begin
                    ctrl <= wdata;
                    if (run_set) begin
                        cur     <= 1'b0;
                        pos     <= 32'd0;
                        played  <= 32'd0;
                        starved <= 1'b0;
                        facc    <= {FW{1'b0}};
                        start   <= 1'b1;
                    end
                    if (!wdata[0] && ctrl[0]) begin
                        full <= 2'b00;
                        done <= 2'b00;
                    end
                end
                8'h08: stereo <= wdata[0];
                8'h0C: begin
                    if (rate_w != rate && run) facc <= {FW{1'b0}};
                    rate <= rate_w;
                end
                8'h10: addr0 <= {wdata[31:1], 1'b0};
                8'h14: addr1 <= {wdata[31:1], 1'b0};
                8'h18: begin
                    len0 <= wdata;
                    len0m1 <= wdata - 32'd1;
                    len0z <= wdata == 32'd0;
                    full[0] <= wdata != 32'd0;
                end
                8'h1C: begin
                    len1 <= wdata;
                    len1m1 <= wdata - 32'd1;
                    len1z <= wdata == 32'd0;
                    full[1] <= wdata != 32'd0;
                end
                8'h20: begin
                    if (wdata[0]) done[0] <= 1'b0;
                    if (wdata[1]) done[1] <= 1'b0;
                end
                8'h28: volume <= (wdata > 32'h100) ? 9'h100 : wdata[8:0];
                8'h30: firmware_context <= wdata;
                default: ;
            endcase
        end

        if (reset) begin
            ctrl    <= 32'd0;
            stereo  <= 1'b0;
            rate    <= 16'd16000;
            addr0   <= 32'd0;
            addr1   <= 32'd0;
            len0    <= 32'd0;
            len1    <= 32'd0;
            len0m1  <= 32'hFFFF_FFFF;
            len1m1  <= 32'hFFFF_FFFF;
            len0z   <= 1'b1;
            len1z   <= 1'b1;
            full    <= 2'b00;
            done    <= 2'b00;
            cur     <= 1'b0;
            pos     <= 32'd0;
            played  <= 32'd0;
            firmware_context <= 32'd0;
            starved <= 1'b0;
            volume  <= 9'h100;
            facc    <= {FW{1'b0}};
            rq_v    <= 1'b0;
            start   <= 1'b0;
        end
    end

    // ------------------------------------------------------------------
    // Sample reads
    // ------------------------------------------------------------------
    reg        w_st, w_hi, drop;
    reg [29:0] w_nxt;                // the word after the first
    reg [8:0]  w_vol;
    // The frame's samples as read: the products are formed after these
    // registers, in the clock of frame_we (w_vol changes at the earliest at
    // the end of it), so the multipliers' inputs are this block's registers.
    // (The fitter had packed upp_bus's read data register into them, which
    // put the bus's longest enable path on a DSP block.)
    reg [15:0] r_l, r_r;

    function [15:0] gain;
        input        [15:0] sample;
        input        [ 8:0] gain_value;
        reg   signed [25:0] product;
        begin
            product = $signed(sample) * $signed({1'b0, gain_value});
            gain = product[23:8];
        end
    endfunction

    assign m_stb   = m_cyc;
    assign m_we    = 1'b0;
    assign m_dat_o = 32'd0;
    assign m_sel   = 4'b1111;

    wire [15:0] lo = m_err ? 16'd0 : m_dat_i[15:0];
    wire [15:0] hi = m_err ? 16'd0 : m_dat_i[31:16];
    wire        bus_end = m_ack || m_err;
    // the last read of a frame ends
    wire        fin = bus_end && ((fst == F_L && !(w_st && w_hi)) || fst == F_R);

    assign frame_l = gain(r_l, w_vol);
    assign frame_r = gain(r_r, w_vol);

    always @(posedge clk) begin
        frame_we <= 1'b0;
        case (fst)
            F_IDLE: if (f_take) begin
                w_st  <= rq_st;
                w_nxt <= rq_adr[31:2] + 30'd1;
                w_vol <= rq_vol;
                w_hi  <= rq_adr[1];
                if (rq_play) begin
                    m_cyc <= 1'b1;
                    m_adr <= {rq_adr[31:2], 2'b00};
                    fst   <= F_L;
                end else begin
                    frame_we <= 1'b1;
                    r_l      <= 16'd0;
                    r_r      <= 16'd0;
                end
            end
            F_L: if (bus_end) begin
                r_l <= w_hi ? hi : lo;
                if (w_st && w_hi) begin
                    m_adr <= {w_nxt, 2'b00};        // R in the next word
                    fst   <= F_R;
                end else begin
                    m_cyc    <= 1'b0;
                    fst      <= F_IDLE;
                    frame_we <= !drop && !start;
                    r_r      <= w_st ? hi : (w_hi ? hi : lo);
                end
            end
            F_R: if (bus_end) begin
                m_cyc    <= 1'b0;
                fst      <= F_IDLE;
                frame_we <= !drop && !start;
                r_r      <= lo;
            end
            default: fst <= F_IDLE;
        endcase
        // a read still under way when a run starts is from the run before
        if (fin) drop <= 1'b0;
        if (start && fst != F_IDLE && !fin) drop <= 1'b1;
        if (reset) begin
            fst      <= F_IDLE;
            m_cyc    <= 1'b0;
            drop     <= 1'b0;
            frame_we <= 1'b0;
        end
    end

    // ------------------------------------------------------------------
    // The output: linear interpolation at OUT_HZ
    // ------------------------------------------------------------------
    reg [15:0]   fr_l, fr_r, o0_l, o0_r, o1_l, o1_r;
    reg [OW-1:0] oacc;
    reg          ot1, ot2;
    reg [15:0]   frac;
    reg signed [16:0] d_l, d_r;
    reg signed [15:0] b_l, b_r;
    reg signed [33:0] x_l, x_r;

    wire [OW-1:0] osum = oacc + OUTPUT_RATE;
    wire          otick = osum >= OUTPUT_CLOCK;
    wire [FW+KW-1:0] ph = facc * PK[KW-1:0];

    always @(posedge clk) begin
        oacc <= otick ? osum - OUTPUT_CLOCK : osum;
        ot1  <= otick;
        ot2  <= ot1;
        out_valid <= ot2;

        if (frame_we) begin
            fr_l <= frame_l;
            fr_r <= frame_r;
        end
        if (tick) begin
            o0_l <= o1_l;
            o0_r <= o1_r;
            o1_l <= frame_we ? frame_l : fr_l;
            o1_r <= frame_we ? frame_r : fr_r;
        end
        // a run starts from silence: the frames at the RUN write, and a frame
        // that comes in just after it (from the run before)
        if (run_set) begin
            o0_l <= 16'd0;
            o0_r <= 16'd0;
            o1_l <= 16'd0;
            o1_r <= 16'd0;
        end
        if (start) begin
            fr_l <= 16'd0;
            fr_r <= 16'd0;
        end

        // stage 1, at the output tick: the phase and the step (0 while stopped)
        if (otick) begin
            frac <= ph[39:24];
            d_l  <= run ? $signed({o1_l[15], o1_l}) - $signed({o0_l[15], o0_l}) : 17'sd0;
            d_r  <= run ? $signed({o1_r[15], o1_r}) - $signed({o0_r[15], o0_r}) : 17'sd0;
            b_l  <= run ? $signed(o0_l) : 16'sd0;
            b_r  <= run ? $signed(o0_r) : 16'sd0;
        end
        // stage 2: the step times the phase
        if (ot1) begin
            x_l <= d_l * $signed({1'b0, frac});
            x_r <= d_r * $signed({1'b0, frac});
        end
        // stage 3
        if (ot2) begin
            out_l <= run ? b_l + x_l[31:16] : 16'd0;
            out_r <= run ? b_r + x_r[31:16] : 16'd0;
        end

        if (reset) begin
            oacc  <= {OW{1'b0}};
            ot1   <= 1'b0;
            ot2   <= 1'b0;
            fr_l  <= 16'd0;
            fr_r  <= 16'd0;
            o0_l  <= 16'd0;
            o0_r  <= 16'd0;
            o1_l  <= 16'd0;
            o1_r  <= 16'd0;
            out_l <= 16'd0;
            out_r <= 16'd0;
            out_valid <= 1'b0;
        end
    end

endmodule
