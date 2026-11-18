// SPDX-License-Identifier: GPL-2.0-or-later
// Verilog-2001 port of ngage2 rtl/board/mmc_card.sv.
// Donor SHA256: 3dad56b55982c4589b173850066ca4e8297c68d88fb376d7529912ac5f73c434
// See tests/phone/mmc_card/README.md for provenance and model limitations.
//
// An MMC card (MMC 3.x, standard capacity, byte addressing) in 1-bit native
// mode, as in the N-Gage game-card slot: CLK, CMD and DAT0. The card's data is
// a disk image mounted through hps_io's SD block interface (WIDE = 1, 512-byte
// blocks); its CID, CSD and OCR come from a sidecar block at the end of the
// image, because a game's copy protection checks the exact CID of its card
// (research/peripherals/MMC.md section 4).
//
// The sidecar is the last 512 bytes of the image file:
//   0   "NGAGEMMC"
//   8   version (1)
//   16  CID, 16 bytes, most significant first (byte 15, the CRC, is ignored)
//   32  CSD, 16 bytes, the same
//   48  OCR, 4 bytes, most significant first (bit 31, the busy bit, ignored)
// Unknown sidecar versions leave this model absent until another mount.
// The card's data is then the file without that block. Without the magic the
// whole file is data, and the card is a writable MiSTer card: CID MID 0,
// product "MiSTer"; CSD with command classes 0, 2 and 4, 512-byte blocks,
// partial and misaligned reads, the capacity rounded down from the file size
// (at most 1 GB), and TMP_WRITE_PROTECT if the file was mounted read-only;
// OCR 0x00FF8000. The CRC7 of CID and CSD is always computed here.
//
// Commands: CMD0, CMD1 (R3, busy for CMD1_BUSY replies), CMD2 (R2 CID),
// CMD3 (the host assigns the RCA), CMD4 (taken, no reply), CMD7, CMD9 (R2
// CSD), CMD10, CMD12, CMD13, CMD15, CMD16, CMD17, CMD18, CMD24, CMD25.
// Anything else, or a command in the wrong state, gets no reply and sets
// ILLEGAL_COMMAND for the next one; a command with a bad CRC sets
// COM_CRC_ERROR. A card whose CSD has no class 4 (the retail game cards:
// CCC 0x007, PERM_WRITE_PROTECT) treats CMD24/25 as illegal; a writable class
// with write protection answers them with WP_VIOLATION. Reads may be any
// length up to 512 bytes and cross block boundaries when the CSD allows it;
// writes are 512-byte aligned blocks. Addresses past the CSD capacity give
// OUT_OF_RANGE; reads past the end of the file read zeros. Writes must fit
// the mounted data payload as well: the sidecar and padding are not writable.
//
// Timing: everything runs on clk; CLK is the host's, sampled in clk, and
// must stay high and low for at least two clk cycles each. The card samples
// CMD and DAT0 when CLK rises and changes its outputs when it falls. A
// response starts NCR clocks after the command's end bit (NID for CMD1 and
// CMD2); read data at least NAC clocks after the response, once the blocks
// are in the buffer (a read waits for the HPS, so the host's read timeout
// must allow for it: TAAC in the default CSD says 10 ms). The 8 KB buffer
// holds 16 512-byte sector slots: three 2 KB (4-sector) quarters (slots 0..11)
// for aligned 4 KB (sd_blk_cnt = 7) CMD18 streaming chunks (the next 4 KB
// chunk prefetched while the second half of the current chunk shifts out,
// unless stop_queued indicates the host controller has already queued CMD12),
// and four 512-byte slots (slots 12..15) reserved for CMD17 metadata reads,
// writes and the mount-time sidecar block. After a written
// block the CRC status token follows two clocks after the end bit, then
// DAT0 stays low until the HPS has written the block. The outputs are
// cmd_o/cmd_oe and dat_o/dat_oe (push-pull while enabled); the lines need
// pull-ups outside, and cmd_i/dat_i are the line levels.
//
// Not modelled [open]: stream read (CMD11; the retail CSD lists class 1),
// erase, write protection groups, card lock (CMD42), and the open-drain
// arbitration of several cards in identification.
module ngage_mmc_card #(
    parameter integer         NCR         = 2,
    parameter integer         NID         = 5,
    parameter integer         NAC         = 2,
    parameter integer         CMD1_BUSY   = 1,
    parameter         [ 31:0] OCR_DEFAULT = 32'h00FF8000,
    // MID, OID, PNM, PRV, PSN, MDT: the CID without its CRC byte
    parameter         [119:0] CID_DEFAULT = {8'h00, 16'h0000, "MiSTer", 8'h10, 32'h00000001, 8'h17}
) (
    input wire clk,
    input wire reset,

    // the MMC bus
    input  wire mmc_clk,
    input  wire cmd_i,
    output reg  cmd_o,
    output reg  cmd_oe,
    input  wire dat_i,
    output reg  dat_o,
    output reg  dat_oe,
    input  wire stop_queued,

    // an image is mounted and its registers are loaded
    output wire present,
    output wire write_protected,
    // a transfer with the HPS is under way
    output wire active,

    // hps_io, one disk, WIDE = 1
    input  wire        img_mounted,
    input  wire        img_readonly,
    input  wire [63:0] img_size,
    output wire [31:0] sd_lba,
    output wire [ 5:0] sd_blk_cnt,
    output reg         sd_rd,
    output reg         sd_wr,
    input  wire        sd_ack,
    input  wire [12:0] sd_buff_addr,
    input  wire [15:0] sd_buff_dout,
    output wire [15:0] sd_buff_din,
    input  wire        sd_buff_wr
);

    // ------------------------------------------------------------------
    // Constants
    // ------------------------------------------------------------------
    localparam [3:0] ST_IDLE  = 4'd0;
    localparam [3:0] ST_READY = 4'd1;
    localparam [3:0] ST_IDENT = 4'd2;
    localparam [3:0] ST_STBY  = 4'd3;
    localparam [3:0] ST_TRAN  = 4'd4;
    localparam [3:0] ST_DATA  = 4'd5;
    localparam [3:0] ST_RCV   = 4'd6;
    localparam [3:0] ST_PRG   = 4'd7;
    localparam [3:0] ST_DIS   = 4'd8;
    localparam [3:0] ST_INA   = 4'd15;  // not a state a response shows

    localparam integer E_OUT_OF_RANGE = 31;
    localparam integer E_MISALIGN     = 30;
    localparam integer E_BLOCK_LEN    = 29;
    localparam integer E_WP           = 26;
    localparam integer E_COM_CRC      = 23;
    localparam integer E_ILLEGAL      = 22;

    // "NGAGEMMC" as little-endian 16-bit words
    localparam [15:0] MAGIC0 = 16'h474E;
    localparam [15:0] MAGIC1 = 16'h4741;
    localparam [15:0] MAGIC2 = 16'h4D45;
    localparam [15:0] MAGIC3 = 16'h434D;

    // ------------------------------------------------------------------
    // CRCs
    // ------------------------------------------------------------------
    function automatic [6:0] crc7_bit(input [6:0] c, input b);
        reg fb;
        begin
            fb       = c[6] ^ b;
            crc7_bit = {c[5], c[4], c[3], c[2] ^ fb, c[1], c[0], fb};
        end
    endfunction

    function automatic [6:0] crc7_byte(input [6:0] c, input [7:0] b);
        reg     [6:0] r;
        integer       i;
        begin
            r = c;
            for (i = 7; i >= 0; i = i - 1) r = crc7_bit(r, b[i]);
            crc7_byte = r;
        end
    endfunction

    function automatic [6:0] crc7_40(input [39:0] d);
        reg     [6:0] r;
        integer       i;
        begin
            r = 7'd0;
            for (i = 39; i >= 0; i = i - 1) r = crc7_bit(r, d[i]);
            crc7_40 = r;
        end
    endfunction

    function automatic [15:0] crc16_bit(input [15:0] c, input b);
        reg fb;
        begin
            fb        = c[15] ^ b;
            crc16_bit = {c[14:12], c[11] ^ fb, c[10:5], c[4] ^ fb, c[3:0], fb};
        end
    endfunction

    // ------------------------------------------------------------------
    // Clock edges
    // ------------------------------------------------------------------
    reg ck_q;
    always @(posedge clk) ck_q <= mmc_clk;
    wire rise = mmc_clk & ~ck_q;
    wire fall = ~mmc_clk & ck_q;

    // ------------------------------------------------------------------
    // State
    // ------------------------------------------------------------------
    // registers and the image
    reg [127:0] cid, csd;
    reg [31:0] ocr;
    reg        ro;
    reg [31:0] nblk;  // data blocks in the file
    reg [33:0] cap;  // capacity in bytes, from the CSD

    wire [11:0] ccc = csd[95:84];
    wire [ 3:0] read_bl_len = csd[83:80];
    wire        rd_partial = csd[79];
    wire        rd_misalign = csd[77];
    wire [11:0] c_size = csd[73:62];
    wire [ 2:0] c_size_mult = csd[49:47];

    // loader
    localparam [3:0] L_OFF   = 4'd0;
    localparam [3:0] L_FETCH = 4'd1;
    localparam [3:0] L_PARSE = 4'd2;
    localparam [3:0] L_DEFLT = 4'd3;
    localparam [3:0] L_CRC   = 4'd4;
    localparam [3:0] L_CAP   = 4'd5;
    localparam [3:0] L_READY = 4'd6;
    localparam [3:0] L_WAITH = 4'd7;
    reg [3:0] l_state;
    reg [5:0] l_idx;
    reg l_magic, l_v1;
    reg [127:0] l_tmp;
    reg [  6:0] l_crc;
    reg [ 31:0] l_blocks;  // blocks in the file

    // card
    reg [ 3:0] st;
    reg [15:0] rca;
    reg [ 9:0] bl;  // block length, 1..512
    reg [31:0] err;  // error bits waiting to be reported
    reg [ 7:0] cmd1_n;

    // command receiver
    reg [47:0] rx_sr;
    reg [ 5:0] rx_cnt;
    reg rx_on, rx_done;
    // the frame's checks, a clock after it is in; the command is decoded then
    reg rx_dec;
    reg p_ok, p_crc, p_rd_oor, p_rd_cross, p_wr_oor;

    // response transmitter
    localparam [1:0] T_IDLE = 2'd0;
    localparam [1:0] T_WAIT = 2'd1;
    localparam [1:0] T_SEND = 2'd2;
    localparam [1:0] T_LAST = 2'd3;
    reg [  1:0] t_state;
    reg [135:0] t_sr;
    reg [  7:0] t_left;
    reg [  6:0] t_wait;
    reg [  7:0] nac;  // CLK rises since the last response or block ended

    // read engine
    localparam [2:0] D_IDLE = 3'd0;
    localparam [2:0] D_WAIT = 3'd1;
    localparam [2:0] D_DATA = 3'd2;
    localparam [2:0] D_CRC  = 3'd3;
    localparam [2:0] D_END  = 3'd4;
    localparam [2:0] D_REL  = 3'd5;
    reg [ 2:0] d_state;
    reg [32:0] d_addr;  // byte address of the block
    reg        d_multi;
    reg        d_first;  // first block of a CMD17/18 transfer
    reg [ 9:0] d_pos;  // byte of the block being sent
    reg [ 2:0] d_bit;
    reg [ 4:0] d_crcn;
    reg [15:0] d_crc;
    reg [7:0] cur_byte, nxt_byte;
    reg nxt_ok;
    reg f_go, f_v;  // byte fetch: address out, data back
    reg [3:0] f_slot;  // 512-byte slot (0..15) of the fetched byte
    reg       f_odd;  // where the fetched byte is

    // write engine
    localparam [3:0] W_OFF   = 4'd0;
    localparam [3:0] W_START = 4'd1;
    localparam [3:0] W_DATA  = 4'd2;
    localparam [3:0] W_CRC   = 4'd3;
    localparam [3:0] W_END   = 4'd4;
    localparam [3:0] W_GAP   = 4'd5;
    localparam [3:0] W_TOKEN = 4'd6;
    localparam [3:0] W_PROG  = 4'd7;
    localparam [3:0] W_STOP  = 4'd8;
    reg [ 3:0] w_state;
    reg [32:0] w_addr;
    reg        w_multi;
    reg [12:0] w_n;  // bits received
    reg [ 6:0] w_byte;
    reg [ 7:0] w_lo;
    reg [15:0] w_crc, w_crc_rx;
    reg [4:0] w_tok;
    reg [2:0] w_gap;
    reg       w_stop12;  // CMD12 came while the block was being written
    reg       w_good;  // the block's CRC and end bit were right
    reg       w_issued;  // the HPS write of the block has been asked for

    integer pipe_i, def_m, pre_m, main_m, main_k;

    // buffer: 8 KB (16 x 512-byte sector slots):
    //   slots  0..11: three 2 KB (4-sector) quarters for aligned 4 KB streaming chunks
    //   slots 12..15: four 512-byte slots reserved for CMD17 metadata, writes, and sidecar
    reg [22:0] tag[0:15];
    reg [15:0] tvalid, tzero;
    reg [1:0] m_repl;  // round-robin index (0..3) for metadata slots 12..15
    reg [1:0] w_m_idx;  // metadata slot (0..3) used by the active write
    reg       bk_touch;  // pulses when tag/tvalid/tzero is updated

    // HPS transfers
    localparam [1:0] H_IDLE = 2'd0;
    localparam [1:0] H_REQ  = 2'd1;
    localparam [1:0] H_XFER = 2'd2;
    reg [1:0] h_state;
    reg       h_wr;
    reg       h_meta;  // 1: single-sector in {2'b11, h_m_idx}; 0: streaming chunk in h_q0/h_q1
    reg [1:0] h_m_idx;
    reg [1:0] h_q0, h_q1;
    reg [31:0] h_lba;
    reg [ 5:0] h_blk_cnt;
    reg        h_done;  // pulse: the transfer finished

    wire    [3:0] h_cur_slot = h_meta ? {2'b11, h_m_idx} :
	                           {sd_buff_addr[10] ? h_q1 : h_q0, sd_buff_addr[9:8]};

    // buffer port of the card side
    reg         c_we;
    reg  [11:0] c_addr;
    reg  [15:0] c_wdata;
    wire [15:0] c_q;

    ngage_mmc_dpram #(
        .AW(12),
        .DW(16)
    ) buffer (
        .clk    (clk),
        .we_a   (sd_buff_wr & (h_state != H_IDLE) & ~h_wr & (sd_buff_addr[12:11] == 2'b00)),
        .addr_a ({h_cur_slot, sd_buff_addr[7:0]}),
        .wdata_a(sd_buff_dout),
        .q_a    (sd_buff_din),
        .we_b   (c_we),
        .addr_b (c_addr),
        .wdata_b(c_wdata),
        .q_b    (c_q)
    );

    assign sd_blk_cnt      = h_blk_cnt;
    assign sd_lba          = h_lba;
    assign active          = h_state != H_IDLE;
    assign present         = l_state == L_READY;
    assign write_protected = ro | csd[13] | csd[12];

    // ------------------------------------------------------------------
    // Read buffer bookkeeping
    // ------------------------------------------------------------------
    function automatic [22:0] sec_of(input [32:0] a);

        begin
            sec_of = a[31:9];
        end
    endfunction

    // 2 KB (4-sector) half-chunk g = s[22:2] modulo 3, mapping streaming
    // sectors into quarters 0, 1, 2 (slots 0..11) so any three consecutive
    // 2 KB half-chunks (6 KB = 12 sectors: the active half-chunk plus the
    // entire next 4 KB chunk) occupy distinct quarters without collision.
    function automatic [1:0] mod3(input [20:0] g);
        reg [5:0] s0;
        reg [3:0] s1;
        reg [2:0] s2;
        reg [1:0] s3;
        begin
            s0 = {4'd0, g[1:0]}   + {4'd0, g[3:2]}   + {4'd0, g[5:4]}   + {4'd0, g[7:6]} +
		     {4'd0, g[9:8]}   + {4'd0, g[11:10]} + {4'd0, g[13:12]} + {4'd0, g[15:14]} +
		     {4'd0, g[17:16]} + {4'd0, g[19:18]} + {5'd0, g[20]};
            s1 = {2'd0, s0[1:0]} + {2'd0, s0[3:2]} + {2'd0, s0[5:4]};
            s2 = {1'b0, s1[1:0]} + {1'b0, s1[3:2]};
            s3 = s2[1:0] + {1'b0, s2[2]};
            mod3 = (s3 == 2'd3) ? 2'd0 : s3;
        end
    endfunction

    function automatic [3:0] s_slot(input [22:0] s);

        begin
            s_slot = {mod3(s[22:2]), s[1:0]};
        end
    endfunction

    // The sectors the current block needs and the next 4 KB chunk's, whether
    // they are in the buffer, and the next HPS request parameters are
    // pipelined across four lightweight register stages so that no path from a
    // tag or slot register passes through an adder and a compare in one clock:
    //   stage 0 (s0_*): candidate sector numbers (adders only)
    //   stage 1 (s1_*): modulo-3 slot indices and per-slot tag compares in parallel
    //   stage 2 (s2_*): 1-bit slot-hit muxes and miss priority selection
    //   stage 3 (want*): HPS request parameters (chunk quarters and block count)
    // The results are used only once the inputs have stayed the same for all
    // four stages (settle == 0).
    reg [22:0] s0_rlo, s0_rhi, s0_pchunk;
    reg s0_act, s0_multi;

    reg [22:0] s1_rlo, s1_rhi, s1_pchunk;
    reg [3:0] s1_srlo, s1_srhi, s1_spchunk;
    reg s1_act, s1_multi, s1_pc_win, s1_pc_in;
    reg [15:0] s1_eq_lo, s1_eq_hi;
    reg [11:0] s1_eq_pc;

    reg have_lo, have_hi;
    reg [3:0] slot_lo, slot_hi;
    reg [22:0] s2_want;
    reg [ 3:0] s2_want_slot;
    reg s2_want_v, s2_want_spec;

    reg [22:0] want;
    reg [ 3:0] want_slot;
    reg want_v, want_spec, want_oor;
    reg [1:0] want_q0, want_q1;
    reg [5:0] want_cnt;

    wire [60:0] bk_in;
    reg  [60:0] bk_q;
    reg  [ 1:0] settle;
    wire        bk_chg = (bk_in != bk_q) || bk_touch;
    wire        bk_ok = settle == 2'd0 && !bk_chg;

    function automatic [3:0] pick_slot(input is_multi, input [3:0] sl, input s_ok,
                                       input [14:12] m_eq);

        begin
            if (is_multi || s_ok) pick_slot = sl;
            else if (m_eq[12]) pick_slot = 4'd12;
            else if (m_eq[13]) pick_slot = 4'd13;
            else if (m_eq[14]) pick_slot = 4'd14;
            else pick_slot = 4'd15;
        end
    endfunction

    assign bk_in = {d_addr, bl, tvalid, d_state != D_IDLE, d_multi};

    wire [22:0] w_rlo = sec_of(d_addr);
    wire [22:0] w_rhi = sec_of(d_addr + {23'd0, bl} - 33'd1);
    wire [22:0] w_pchunk = {w_rlo[22:3] + 20'd1, 3'b000};

    wire s2_slo_ok = s1_eq_lo[s1_srlo];
    wire s2_mlo_ok = |s1_eq_lo[15:12];
    wire s2_has_lo = s1_multi ? s2_slo_ok : (s2_slo_ok || s2_mlo_ok);

    wire s2_shi_ok = s1_eq_hi[s1_srhi];
    wire s2_mhi_ok = |s1_eq_hi[15:12];
    wire s2_has_hi = s1_multi ? s2_shi_ok : (s2_shi_ok || s2_mhi_ok);

    wire s2_spc_ok = s1_eq_pc[s1_spchunk];

    // From s2_want_slot[3:2] = mod3(s2_want[22:2]) and s2_want[2], derive the
    // two quarters of the aligned 4 KB chunk {s2_want[22:3], 3'b000} without
    // any adder or second mod3 tree.
    wire [1:0] s2_q = s2_want_slot[3:2];
    wire [1:0] s2_q_next = (s2_q == 2'd2) ? 2'd0 : (s2_q + 2'd1);
    wire [1:0] s2_q_prev = (s2_q == 2'd0) ? 2'd2 : (s2_q - 2'd1);
    wire [1:0] s2_q0 = s2_want[2] ? s2_q_prev : s2_q;
    wire [1:0] s2_q1 = s2_want[2] ? s2_q : s2_q_next;
    wire       s2_last_chunk = ({9'd0, s2_want[22:3]} == nblk[31:3]);

    always @(posedge clk) begin
        // stage 0: sector addresses (adders only)
        s0_rlo    <= w_rlo;
        s0_rhi    <= w_rhi;
        s0_pchunk <= w_pchunk;
        s0_act    <= d_state != D_IDLE;
        s0_multi  <= d_multi;

        // stage 1: modulo-3 slot indices and per-slot tag compares in parallel
        s1_rlo <= s0_rlo;
        s1_rhi <= s0_rhi;
        s1_pchunk <= s0_pchunk;
        s1_srlo <= s_slot(s0_rlo);
        s1_srhi <= s_slot(s0_rhi);
        s1_spchunk <= s_slot(s0_pchunk);
        s1_act <= s0_act;
        s1_multi <= s0_multi;
        s1_pc_win  <= s0_multi && s0_rlo[2] && (s0_rhi[22:2] == s0_rlo[22:2]) && (s0_rlo[2:0] != 3'd7);
        s1_pc_in <= ({9'd0, s0_pchunk} < nblk);
        for (pipe_i = 0; pipe_i < 16; pipe_i = pipe_i + 1) begin
            s1_eq_lo[pipe_i] <= tvalid[pipe_i] && (tag[pipe_i] == s0_rlo);
            s1_eq_hi[pipe_i] <= tvalid[pipe_i] && (tag[pipe_i] == s0_rhi);
        end
        for (pipe_i = 0; pipe_i < 12; pipe_i = pipe_i + 1) begin
            s1_eq_pc[pipe_i] <= tvalid[pipe_i] && (tag[pipe_i] == s0_pchunk);
        end

        // stage 2: 1-bit slot-hit muxes and miss priority selection
        have_lo      <= s2_has_lo;
        have_hi      <= s2_has_hi;
        slot_lo      <= pick_slot(s1_multi, s1_srlo, s2_slo_ok, s1_eq_lo[14:12]);
        slot_hi      <= pick_slot(s1_multi, s1_srhi, s2_shi_ok, s1_eq_hi[14:12]);
        s2_want_v    <= 1'b0;
        s2_want_spec <= 1'b0;
        s2_want      <= s1_rlo;
        s2_want_slot <= s1_srlo;
        if (s1_act) begin
            if (!s2_has_lo) begin
                s2_want      <= s1_rlo;
                s2_want_slot <= s1_srlo;
                s2_want_v    <= 1'b1;
                s2_want_spec <= 1'b0;
            end else if (!s2_has_hi) begin
                s2_want      <= s1_rhi;
                s2_want_slot <= s1_srhi;
                s2_want_v    <= 1'b1;
                s2_want_spec <= 1'b0;
            end else if (s1_pc_win && s1_pc_in && !s2_spc_ok) begin
                s2_want      <= s1_pchunk;
                s2_want_slot <= s1_spchunk;
                s2_want_v    <= 1'b1;
                s2_want_spec <= 1'b1;
            end
        end

        // stage 3: HPS request parameters from s2_want
        want      <= s2_want;
        want_slot <= s2_want_slot;
        want_v    <= s2_want_v;
        want_spec <= s2_want_spec;
        want_oor  <= ({9'd0, s2_want} >= nblk);
        want_q0   <= s2_q0;
        want_q1   <= s2_q1;
        want_cnt  <= s2_last_chunk ? {3'd0, nblk[2:0] - 3'd1} : 6'd7;

        // how long since the inputs changed
        bk_q <= bk_in;
        if (bk_chg) settle <= 2'd3;
        else if (settle != 2'd0) settle <= settle - 2'd1;
    end

    // ------------------------------------------------------------------
    // Default registers for an image without a sidecar
    // ------------------------------------------------------------------
    reg [ 2:0] def_mult;
    reg [11:0] def_csize;
    reg [31:0] q;
    always @* begin
        def_mult  = 3'd7;
        def_csize = 12'd4095;
        for (def_m = 7; def_m >= 0; def_m = def_m - 1) begin
            q = l_blocks >> (def_m + 2);
            if (q <= 32'd4096) begin
                def_mult  = def_m[2:0];
                def_csize = (q == 32'd0) ? 12'd0 : (q[11:0] - 12'd1);
            end
        end
    end

    wire [127:0] csd_default = {
        2'd2,
        4'd3,
        2'd0,  // CSD_STRUCTURE 1.2, SPEC_VERS 3.1
        8'h0F,  // TAAC 10 ms
        8'h00,  // NSAC
        8'h2A,  // TRAN_SPEED 20 MHz
        12'h015,  // CCC: classes 0, 2, 4
        4'd9,  // READ_BL_LEN 512
        1'b1,
        1'b0,
        1'b1,
        1'b0,  // READ_BL_PARTIAL, WRITE_BLK_MISALIGN, READ_BLK_MISALIGN, DSR_IMP
        2'd0,
        def_csize,
        3'd6,
        3'd6,
        3'd6,
        3'd6,  // VDD currents
        def_mult,
        5'd0,
        5'd15,
        5'd0,
        1'b0,  // ERASE_GRP_SIZE, ERASE_GRP_MULT, WP_GRP_SIZE, WP_GRP_ENABLE
        2'd0,
        3'd2,
        4'd9,
        1'b0,  // DEFAULT_ECC, R2W_FACTOR, WRITE_BL_LEN 512, WRITE_BL_PARTIAL
        4'd0,
        1'b0,  // reserved, CONTENT_PROT_APP
        1'b0,
        1'b0,
        1'b0,
        ro,  // FILE_FORMAT_GRP, COPY, PERM_WRITE_PROTECT, TMP_WRITE_PROTECT
        2'd0,
        2'd0,  // FILE_FORMAT, ECC
        8'h01
    };  // CRC (filled in), 1

    // ------------------------------------------------------------------
    // Responses
    // ------------------------------------------------------------------
    function automatic [47:0] frame48(input [5:0] idx, input [31:0] arg);
        reg [39:0] d;
        begin
            d       = {2'b00, idx, arg};
            frame48 = {d, crc7_40(d), 1'b1};
        end
    endfunction

    wire        prg_busy = w_state == W_PROG;
    wire [31:0] r1_status = err | {19'd0, st == ST_INA ? 4'd0 : st, ~prg_busy, 8'd0};

    // ------------------------------------------------------------------
    // Everything
    // ------------------------------------------------------------------
    wire [5:0] cmd_idx = rx_sr[45:40];
    wire [31:0] cmd_arg = rx_sr[39:8];
    wire cmd_ok = ~rx_sr[47] & rx_sr[46] & rx_sr[0];
    wire crc_ok = crc7_40(rx_sr[47:8]) == rx_sr[7:1];
    wire addressed = cmd_arg[31:16] == rca;
    wire [32:0] arg33 = {1'b0, cmd_arg};
    wire [33:0] rd_end = {1'b0, arg33} + {24'd0, bl};
    wire rd_cross = cmd_arg[31:9] != sec_of(arg33 + {23'd0, bl} - 33'd1);
    wire cmd_quiet = cmd_i && !rx_on && !rx_done && !rx_dec;
    wire        allow_fetch = (!want_spec || !stop_queued) &&
	                          (d_first ? (!want_spec || (d_state == D_DATA && cmd_quiet))
	                                   : (cmd_quiet && (d_state == D_DATA || (d_state == D_WAIT && nac > NAC[7:0]))));
    wire [22:0] w_sec = sec_of(w_addr);
    wire [40:0] file_bytes = {nblk, 9'd0};
    wire [22:0] h_stream_sec = {h_lba[22:3], sd_buff_addr[10:8]};

    // Precomputed read byte offsets, write slot/quarter indices, and HPS
    // metadata invalidation matches (all inputs are stable at least several
    // clk cycles before these registers are read).
    reg [9:0] f_one, f_next;
    reg f_more, d_last;
    reg [1:0] w_q;
    reg       w_in_file;
    reg [3:0] w_m_hit;
    reg [3:0] h_m_match;

    always @(posedge clk) begin
        f_one     <= {1'b0, d_addr[8:0]} + 10'd1;
        f_next    <= {1'b0, d_addr[8:0]} + d_pos + 10'd2;
        f_more    <= (d_pos + 10'd2 < bl);
        d_last    <= (d_pos == bl - 10'd1);
        w_q       <= mod3(w_sec[22:2]);
        w_in_file <= !w_addr[32] && ({8'd0, w_addr} + 41'd512 <= file_bytes);
        for (pre_m = 0; pre_m < 4; pre_m = pre_m + 1) begin
            w_m_hit[pre_m]   <= tvalid[12+pre_m] && (tag[12+pre_m] == w_sec);
            h_m_match[pre_m] <= (tag[12+pre_m] == h_stream_sec);
        end
    end

    task automatic respond(input [135:0] bits, input [7:0] n, input [6:0] dly);
        begin
            t_state <= T_WAIT;
            t_sr    <= bits;
            t_left  <= n;
            t_wait  <= dly;
        end
    endtask

    task automatic respond_r1(input [31:0] extra);
        begin
            respond({frame48(cmd_idx, r1_status | extra), 88'd0}, 8'd48, NCR[6:0]);
            err <= 32'd0;
        end
    endtask

    task automatic illegal;
        begin
            err[E_ILLEGAL] <= 1'b1;
        end
    endtask

    task automatic stop_read;
        begin
            d_state <= D_IDLE;
            dat_oe  <= 1'b0;
        end
    endtask

    task automatic card_reset;
        begin
            st       <= ST_IDLE;
            rca      <= 16'h0001;
            bl       <= 10'd512;
            err      <= 32'd0;
            cmd1_n   <= 8'd0;
            rx_on    <= 1'b0;
            t_state  <= T_IDLE;
            cmd_oe   <= 1'b0;
            d_state  <= D_IDLE;
            d_first  <= 1'b0;
            dat_oe   <= 1'b0;
            w_state  <= W_OFF;
            w_issued <= 1'b0;
            w_stop12 <= 1'b0;
        end
    endtask

    always @(posedge clk) begin
        rx_dec <= rx_done;
        if (rx_done) begin
            p_ok <= cmd_ok;
            p_crc <= crc_ok;
            p_rd_oor <= rd_end > cap;
            p_rd_cross <= rd_cross;
            p_wr_oor <= {2'b00, cmd_arg} + 34'd512 > cap || {9'd0, cmd_arg} + 41'd512 > file_bytes;
        end
    end

    always @(posedge clk) begin
        rx_done  <= 1'b0;
        h_done   <= 1'b0;
        c_we     <= 1'b0;
        f_v      <= f_go;
        f_go     <= 1'b0;
        bk_touch <= 1'b0;

        // ---------------- HPS transfers ----------------
        if (sd_buff_wr && (h_state != H_IDLE) && !h_wr && !h_meta && sd_buff_addr[12:11] == 2'b00 && sd_buff_addr[7:0] == 8'hFF) begin
            tag[h_cur_slot]    <= h_stream_sec;
            tvalid[h_cur_slot] <= 1'b1;
            tzero[h_cur_slot]  <= 1'b0;
            for (main_m = 0; main_m < 4; main_m = main_m + 1)
            if (h_m_match[main_m]) tvalid[12+main_m] <= 1'b0;
            bk_touch <= 1'b1;
        end
        case (h_state)
            H_REQ:
            if (sd_ack) begin
                sd_rd   <= 1'b0;
                sd_wr   <= 1'b0;
                h_state <= H_XFER;
            end
            H_XFER:
            if (!sd_ack) begin
                h_state <= H_IDLE;
                h_done  <= 1'b1;
                if (!h_wr && h_meta) begin
                    tag[{2'b11, h_m_idx}]    <= h_lba[22:0];
                    tvalid[{2'b11, h_m_idx}] <= 1'b1;
                    tzero[{2'b11, h_m_idx}]  <= 1'b0;
                    bk_touch                 <= 1'b1;
                end
            end
            default: ;
        endcase

        // ---------------- loader ----------------
        case (l_state)
            L_FETCH:
            if (h_state == H_IDLE && !h_done) begin
                h_state   <= H_REQ;
                h_wr      <= 1'b0;
                h_meta    <= 1'b1;
                h_m_idx   <= 2'd0;
                h_lba     <= l_blocks - 32'd1;
                h_blk_cnt <= 6'd0;
                sd_rd     <= 1'b1;
                l_state   <= L_WAITH;
            end
            L_WAITH:
            if (h_done) begin
                l_state  <= L_PARSE;
                l_idx    <= 6'd0;
                l_magic  <= 1'b1;
                l_v1     <= 1'b0;
                tvalid   <= 16'd0;
                bk_touch <= 1'b1;
            end
            L_PARSE: begin
                // word l_idx out, its data back two cycles later
                c_addr <= {2'b11, h_m_idx, 2'b00, l_idx};
                if (l_idx >= 6'd2) begin
                    case (l_idx - 6'd2)
                        6'd0: l_magic <= l_magic & (c_q == MAGIC0);
                        6'd1: l_magic <= l_magic & (c_q == MAGIC1);
                        6'd2: l_magic <= l_magic & (c_q == MAGIC2);
                        6'd3: l_magic <= l_magic & (c_q == MAGIC3);
                        6'd4: l_v1 <= c_q[7:0] == 8'd1;
                        6'd8, 6'd9, 6'd10, 6'd11, 6'd12, 6'd13, 6'd14, 6'd15:
                        cid <= {cid[111:0], c_q[7:0], c_q[15:8]};
                        6'd16, 6'd17, 6'd18, 6'd19, 6'd20, 6'd21, 6'd22, 6'd23:
                        csd <= {csd[111:0], c_q[7:0], c_q[15:8]};
                        6'd24, 6'd25: ocr <= {ocr[15:0], c_q[7:0], c_q[15:8]};
                        default: ;
                    endcase
                end
                l_idx <= l_idx + 6'd1;
                if (l_idx == 6'd27) begin
                    if (l_magic) begin
                        nblk    <= l_blocks - 32'd1;
                        l_state <= l_v1 ? L_CRC : L_OFF;
                        l_idx   <= 6'd0;
                    end else begin
                        l_state <= L_DEFLT;
                    end
                end
            end
            L_DEFLT: begin
                nblk    <= l_blocks;
                cid     <= {CID_DEFAULT, 8'h01};
                csd     <= csd_default;
                ocr     <= OCR_DEFAULT;
                l_state <= L_CRC;
                l_idx   <= 6'd0;
            end
            L_CRC: begin
                // CRC7 of the first 15 bytes of CID, then of CSD
                if (l_idx == 6'd0 || l_idx == 6'd16) begin
                    l_tmp <= (l_idx == 6'd0) ? cid : csd;
                    l_crc <= 7'd0;
                end else begin
                    l_tmp <= {l_tmp[119:0], 8'd0};
                    l_crc <= crc7_byte(l_crc, l_tmp[127:120]);
                end
                if (l_idx == 6'd16) cid[7:0] <= {l_crc, 1'b1};
                if (l_idx == 6'd32) begin
                    csd[7:0] <= {l_crc, 1'b1};
                    l_state  <= L_CAP;
                end
                l_idx <= l_idx + 6'd1;
            end
            L_CAP: begin
                cap     <= ({21'd0, {1'b0, c_size} + 13'd1} << ({1'b0, c_size_mult} + 4'd2)) << read_bl_len;
                ocr[31] <= 1'b0;
                l_state <= L_READY;
                card_reset;
            end
            default: ;
        endcase

        // ---------------- command receiver ----------------
        if (present && rise && t_state == T_IDLE) begin
            if (!rx_on) begin
                if (!cmd_i) begin
                    rx_on  <= 1'b1;
                    rx_cnt <= 6'd1;
                    rx_sr  <= 48'd0;
                end
            end else begin
                rx_sr  <= {rx_sr[46:0], cmd_i};
                rx_cnt <= rx_cnt + 6'd1;
                if (rx_cnt == 6'd47) begin
                    rx_on   <= 1'b0;
                    rx_done <= 1'b1;
                end
            end
        end

        // ---------------- response transmitter ----------------
        if (rise && nac != 8'hFF) nac <= nac + 8'd1;
        case (t_state)
            T_WAIT: begin
                if (rise && t_wait != 7'd0) t_wait <= t_wait - 7'd1;
                if (fall && t_wait == 7'd0) begin
                    cmd_oe  <= 1'b1;
                    cmd_o   <= t_sr[135];
                    t_sr    <= {t_sr[134:0], 1'b1};
                    t_left  <= t_left - 8'd1;
                    t_state <= T_SEND;
                end
            end
            T_SEND:
            if (fall) begin
                cmd_o  <= t_sr[135];
                t_sr   <= {t_sr[134:0], 1'b1};
                t_left <= t_left - 8'd1;
                if (t_left == 8'd1) t_state <= T_LAST;
            end
            T_LAST:
            if (fall) begin
                cmd_oe  <= 1'b0;
                t_state <= T_IDLE;
                nac     <= 8'd0;
            end
            default: ;
        endcase

        // ---------------- read engine ----------------
        // byte fetches: c_addr is set with f_go, the byte comes back with f_v
        if (f_v) begin
            nxt_byte <= tzero[f_slot] ? 8'd0 : (f_odd ? c_q[15:8] : c_q[7:0]);
            nxt_ok   <= 1'b1;
        end
        // aligned 4 KB chunks for CMD18 (clamped to nblk), single sectors in
        // reserved metadata slots 12..15 for CMD17
        if (d_state != D_IDLE && bk_ok && want_v && allow_fetch && h_state == H_IDLE && !h_done && l_state == L_READY) begin
            bk_touch <= 1'b1;
            if (want_oor) begin
                if (d_multi) begin
                    tag[want_slot]    <= want;
                    tvalid[want_slot] <= 1'b1;
                    tzero[want_slot]  <= 1'b1;
                end else begin
                    tag[{2'b11, m_repl}]    <= want;
                    tvalid[{2'b11, m_repl}] <= 1'b1;
                    tzero[{2'b11, m_repl}]  <= 1'b1;
                    m_repl                  <= m_repl + 2'd1;
                end
            end else if (d_multi) begin
                h_state   <= H_REQ;
                h_wr      <= 1'b0;
                h_meta    <= 1'b0;
                h_q0      <= want_q0;
                h_q1      <= want_q1;
                h_lba     <= {9'd0, want[22:3], 3'b000};
                h_blk_cnt <= want_cnt;
                sd_rd     <= 1'b1;
                for (main_k = 0; main_k < 4; main_k = main_k + 1)
                tvalid[{want_q0, main_k[1:0]}] <= 1'b0;
                if (want_cnt[2])
                    for (main_k = 0; main_k < 4; main_k = main_k + 1)
                    tvalid[{want_q1, main_k[1:0]}] <= 1'b0;
            end else begin
                h_state                 <= H_REQ;
                h_wr                    <= 1'b0;
                h_meta                  <= 1'b1;
                h_m_idx                 <= m_repl;
                h_lba                   <= {9'd0, want};
                h_blk_cnt               <= 6'd0;
                sd_rd                   <= 1'b1;
                tvalid[{2'b11, m_repl}] <= 1'b0;
                m_repl                  <= m_repl + 2'd1;
            end
        end
        case (d_state)
            D_WAIT: begin
                if (!nxt_ok && !f_go && !f_v && bk_ok && have_lo && have_hi) begin
                    f_go   <= 1'b1;
                    f_slot <= slot_lo;
                    f_odd  <= d_addr[0];
                    c_addr <= {slot_lo, d_addr[8:1]};
                end
                if (fall && nxt_ok && t_state == T_IDLE && nac >= NAC[7:0]) begin
                    dat_oe   <= 1'b1;
                    dat_o    <= 1'b0;  // start bit
                    cur_byte <= nxt_byte;
                    nxt_ok   <= 1'b0;
                    d_pos    <= 10'd0;
                    d_bit    <= 3'd7;
                    d_crc    <= 16'd0;
                    d_state  <= D_DATA;
                    if (bl != 10'd1) begin
                        f_go   <= 1'b1;
                        f_slot <= f_one[9] ? slot_hi : slot_lo;
                        f_odd  <= f_one[0];
                        c_addr <= {f_one[9] ? slot_hi : slot_lo, f_one[8:1]};
                    end
                end
            end
            D_DATA:
            if (fall) begin
                dat_o <= cur_byte[d_bit];
                d_crc <= crc16_bit(d_crc, cur_byte[d_bit]);
                d_bit <= d_bit - 3'd1;
                if (d_bit == 3'd0) begin
                    if (d_last) begin
                        d_state <= D_CRC;
                        d_crcn  <= 5'd16;
                    end else begin
                        d_pos    <= d_pos + 10'd1;
                        cur_byte <= nxt_byte;
                        nxt_ok   <= 1'b0;
                        if (f_more) begin
                            f_go   <= 1'b1;
                            f_slot <= f_next[9] ? slot_hi : slot_lo;
                            f_odd  <= f_next[0];
                            c_addr <= {f_next[9] ? slot_hi : slot_lo, f_next[8:1]};
                        end
                    end
                end
            end
            D_CRC:
            if (fall) begin
                dat_o  <= d_crc[15];
                d_crc  <= {d_crc[14:0], 1'b0};
                d_crcn <= d_crcn - 5'd1;
                if (d_crcn == 5'd1) d_state <= D_END;
            end
            D_END:
            if (fall) begin
                dat_o   <= 1'b1;
                d_state <= D_REL;
            end
            D_REL:
            if (fall) begin
                dat_oe  <= 1'b0;
                nac     <= 8'd0;
                nxt_ok  <= 1'b0;
                d_first <= 1'b0;
                if (!d_multi) begin
                    d_state <= D_IDLE;
                    if (st == ST_DATA) st <= ST_TRAN;
                end else begin
                    d_addr <= d_addr + {23'd0, bl};
                    d_pos  <= 10'd0;
                    if ({1'b0, d_addr} + {23'd0, bl, 1'b0} > cap) begin
                        err[E_OUT_OF_RANGE] <= 1'b1;
                        d_state             <= D_IDLE;  // stays in the data state until CMD12
                    end else if (!rd_misalign && sec_of(
                            d_addr + {23'd0, bl}
                        ) != sec_of(
                            d_addr + {22'd0, bl, 1'b0} - 33'd1
                        )) begin
                        err[E_MISALIGN] <= 1'b1;
                        d_state         <= D_IDLE;
                    end else begin
                        d_state <= D_WAIT;
                    end
                end
            end
            default: ;
        endcase

        // ---------------- write engine ----------------
        case (w_state)
            W_START:
            if (rise && !dat_i) begin : select_write_slot
                reg [1:0] wm;
                wm = m_repl;
                for (main_m = 0; main_m < 4; main_m = main_m + 1)
                if (w_m_hit[main_m]) wm = main_m[1:0];
                w_state <= W_DATA;
                w_n     <= 13'd0;
                w_crc   <= 16'd0;
                w_m_idx <= wm;
                if (wm == m_repl) m_repl <= m_repl + 2'd1;
                tvalid[{2'b11, wm}] <= 1'b0;
                for (main_k = 0; main_k < 4; main_k = main_k + 1)
                tvalid[{w_q, main_k[1:0]}] <= 1'b0;
                bk_touch <= 1'b1;
            end
            W_DATA:
            if (rise) begin
                w_byte <= {w_byte[5:0], dat_i};
                w_crc  <= crc16_bit(w_crc, dat_i);
                w_n    <= w_n + 13'd1;
                if (w_n[2:0] == 3'd7) begin
                    if (!w_n[3]) begin
                        w_lo <= {w_byte[6:0], dat_i};
                    end else begin
                        c_we    <= 1'b1;
                        c_addr  <= {2'b11, w_m_idx, w_n[11:4]};
                        c_wdata <= {w_byte[6:0], dat_i, w_lo};
                    end
                end
                if (w_n == 13'd4095) begin
                    w_state <= W_CRC;
                    w_n     <= 13'd0;
                end
            end
            W_CRC:
            if (rise) begin
                w_crc_rx <= {w_crc_rx[14:0], dat_i};
                w_n      <= w_n + 13'd1;
                if (w_n == 13'd15) w_state <= W_END;
            end
            W_END:
            if (rise) begin
                w_good <= dat_i && w_crc_rx == w_crc && w_in_file;
                // Keep the model's existing negative token; R1 reports range.
                w_tok  <= (dat_i && w_crc_rx == w_crc && w_in_file) ? 5'b00101 : 5'b01011;
                if (!w_in_file) err[E_OUT_OF_RANGE] <= 1'b1;
                w_gap   <= 3'd2;
                w_state <= W_GAP;
            end
            W_GAP: begin
                // the CRC status token two clocks after the end bit
                if (rise && w_gap != 3'd0) w_gap <= w_gap - 3'd1;
                if (fall && w_gap == 3'd0) begin
                    dat_oe  <= 1'b1;
                    dat_o   <= w_tok[4];
                    w_tok   <= {w_tok[3:0], 1'b0};
                    w_n     <= 13'd1;
                    w_state <= W_TOKEN;
                end
            end
            W_TOKEN:
            if (fall) begin
                if (w_n < 13'd5) begin
                    dat_o <= w_tok[4];
                    w_tok <= {w_tok[3:0], 1'b0};
                    w_n   <= w_n + 13'd1;
                end else if (w_good) begin
                    // busy while the block is written
                    dat_o    <= 1'b0;
                    w_state  <= W_PROG;
                    w_issued <= 1'b0;
                    if (st == ST_RCV && !w_multi) st <= ST_PRG;
                end else begin
                    dat_oe                   <= 1'b0;
                    tvalid[{2'b11, w_m_idx}] <= 1'b0;
                    bk_touch                 <= 1'b1;
                    if (w_multi) begin
                        w_state <= W_STOP;
                    end else begin
                        w_state <= W_OFF;
                        if (st == ST_RCV) st <= ST_TRAN;
                    end
                end
            end
            W_PROG: begin
                if (!w_issued && w_in_file && h_state == H_IDLE && !h_done) begin
                    h_state   <= H_REQ;
                    h_wr      <= 1'b1;
                    h_meta    <= 1'b1;
                    h_m_idx   <= w_m_idx;
                    h_lba     <= {9'd0, w_sec};
                    h_blk_cnt <= 6'd0;
                    sd_wr     <= 1'b1;
                    w_issued  <= 1'b1;
                end
                // Never turn a lost payload bound into successful programming.
                if ((w_issued && h_done) || !w_in_file) begin
                    w_issued                 <= 1'b0;
                    dat_oe                   <= 1'b0;
                    tag[{2'b11, w_m_idx}]    <= w_sec;
                    tvalid[{2'b11, w_m_idx}] <= w_in_file;
                    tzero[{2'b11, w_m_idx}]  <= 1'b0;
                    bk_touch                 <= 1'b1;
                    if (!w_in_file) err[E_OUT_OF_RANGE] <= 1'b1;
                    if (!w_multi || w_stop12) begin
                        w_state  <= W_OFF;
                        w_stop12 <= 1'b0;
                        if (st == ST_PRG || st == ST_RCV) st <= ST_TRAN;
                        else if (st == ST_DIS) st <= ST_STBY;
                    end else if (!w_in_file || {1'b0, w_addr} + 34'd1024 > cap ||
				             {8'd0, w_addr} + 41'd1024 > file_bytes) begin
                        err[E_OUT_OF_RANGE] <= 1'b1;
                        w_addr              <= w_addr + 33'd512;
                        w_state             <= W_STOP;
                    end else begin
                        w_addr  <= w_addr + 33'd512;
                        w_state <= W_START;
                    end
                end
            end
            default: ;
        endcase

        // ---------------- commands ----------------
        if (rx_dec) begin
            if (!p_ok) begin
                // not a command frame: ignore
            end else if (!p_crc) begin
                err[E_COM_CRC] <= 1'b1;
            end else if (st == ST_INA) begin
                // an inactive card answers nothing
            end else begin
                case (cmd_idx)
                    6'd0: begin
                        st     <= ST_IDLE;
                        rca    <= 16'h0001;
                        bl     <= 10'd512;
                        err    <= 32'd0;
                        cmd1_n <= 8'd0;
                        stop_read;
                        w_state  <= W_OFF;
                        w_stop12 <= 1'b0;
                    end
                    6'd1: begin
                        if (st != ST_IDLE) illegal;
                        else if (cmd_arg[23:7] != 17'd0 && (cmd_arg[23:7] & ocr[23:7]) == 17'd0)
                            st <= ST_INA;
                        else begin
                            respond({
                                    2'b00,
                                    6'h3F,
                                    cmd1_n >= CMD1_BUSY[7:0],
                                    ocr[30:0],
                                    7'h7F,
                                    1'b1,
                                    88'd0
                                    }, 8'd48, NID[6:0]);
                            if (cmd1_n >= CMD1_BUSY[7:0]) begin
                                if (cmd_arg != 32'd0) st <= ST_READY;
                            end else begin
                                cmd1_n <= cmd1_n + 8'd1;
                            end
                        end
                    end
                    6'd2: begin
                        if (st == ST_READY) begin
                            respond({2'b00, 6'h3F, cid[127:1], 1'b1}, 8'd136, NID[6:0]);
                            st <= ST_IDENT;
                        end else illegal;
                    end
                    6'd3: begin
                        if (st == ST_IDENT) begin
                            respond_r1(32'd0);
                            rca <= cmd_arg[31:16];
                            st  <= ST_STBY;
                        end else illegal;
                    end
                    6'd4:    if (st != ST_STBY) illegal;
                    6'd7: begin
                        if (addressed && rca != 16'd0) begin
                            if (st == ST_STBY) begin
                                respond_r1(32'd0);
                                st <= ST_TRAN;
                            end else if (st == ST_DIS) begin
                                respond_r1(32'd0);
                                st <= ST_PRG;
                            end else if (st == ST_IDLE || st == ST_READY || st == ST_IDENT) begin
                                illegal;
                            end
                            // selecting a selected card changes nothing
                        end else begin
                            case (st)
                                ST_TRAN: st <= ST_STBY;
                                ST_DATA: begin
                                    st <= ST_STBY;
                                    stop_read;
                                end
                                ST_RCV: begin
                                    st <= ST_STBY;
                                    if (w_state != W_PROG) w_state <= W_OFF;
                                end
                                ST_PRG:  st <= ST_DIS;
                                default: ;
                            endcase
                        end
                    end
                    6'd9, 6'd10: begin
                        if (st == ST_STBY) begin
                            if (addressed)
                                respond(
                                    {2'b00, 6'h3F, cmd_idx == 6'd9 ? csd[127:1] : cid[127:1], 1'b1},
                                    8'd136, NCR[6:0]);
                        end else illegal;
                    end
                    6'd12: begin
                        if (st == ST_DATA) begin
                            respond_r1(32'd0);
                            st <= ST_TRAN;
                            stop_read;
                        end else if (st == ST_RCV) begin
                            respond_r1(32'd0);
                            if (w_state == W_PROG) begin
                                st       <= ST_PRG;
                                w_stop12 <= 1'b1;
                            end else begin
                                st      <= ST_TRAN;
                                w_state <= W_OFF;
                                if (dat_oe) dat_oe <= 1'b0;
                            end
                        end else illegal;
                    end
                    6'd13: begin
                        if (st >= ST_STBY && st <= ST_DIS) begin
                            if (addressed) respond_r1(32'd0);
                        end else illegal;
                    end
                    6'd15: begin
                        if (st >= ST_STBY && st <= ST_DIS) begin
                            if (addressed) begin
                                st <= ST_INA;
                                stop_read;
                                w_state <= W_OFF;
                            end
                        end else illegal;
                    end
                    6'd16: begin
                        if (st == ST_TRAN) begin
                            if (cmd_arg == 32'd0 || cmd_arg > 32'd512 || (!rd_partial && cmd_arg != 32'd512)) begin
                                respond_r1(32'd1 << E_BLOCK_LEN);
                            end else begin
                                respond_r1(32'd0);
                                bl <= cmd_arg[9:0];
                            end
                        end else illegal;
                    end
                    6'd17, 6'd18: begin
                        if (st == ST_TRAN && ccc[2]) begin
                            if (p_rd_oor) begin
                                respond_r1(32'd1 << E_OUT_OF_RANGE);
                            end else if (p_rd_cross && !rd_misalign) begin
                                respond_r1(32'd1 << E_MISALIGN);
                            end else begin
                                respond_r1(32'd0);
                                st      <= ST_DATA;
                                d_state <= D_WAIT;
                                d_addr  <= arg33;
                                d_multi <= cmd_idx == 6'd18;
                                d_first <= 1'b1;
                                d_pos   <= 10'd0;
                                nxt_ok  <= 1'b0;
                            end
                        end else illegal;
                    end
                    6'd24, 6'd25: begin
                        if (st == ST_TRAN && ccc[4]) begin
                            if (write_protected) begin
                                respond_r1(32'd1 << E_WP);
                            end else if (bl != 10'd512) begin
                                respond_r1(32'd1 << E_BLOCK_LEN);
                            end else if (cmd_arg[8:0] != 9'd0) begin
                                respond_r1(32'd1 << E_MISALIGN);
                            end else if (p_wr_oor) begin
                                respond_r1(32'd1 << E_OUT_OF_RANGE);
                            end else begin
                                respond_r1(32'd0);
                                st       <= ST_RCV;
                                w_state  <= W_START;
                                w_addr   <= arg33;
                                w_multi  <= cmd_idx == 6'd25;
                                w_stop12 <= 1'b0;
                            end
                        end else illegal;
                    end
                    default: illegal;
                endcase
            end
        end

        // ---------------- mount, reset ----------------
        if (img_mounted) begin
            ro       <= img_readonly;
            l_blocks <= img_size[40:9];
            tvalid   <= 16'd0;
            m_repl   <= 2'd0;
            bk_touch <= 1'b1;
            card_reset;
            if (img_size[40:9] == 32'd0) l_state <= L_OFF;
            else if (img_size[40:9] == 32'd1) l_state <= L_DEFLT;
            else l_state <= L_FETCH;
        end
        if (reset) begin
            l_state   <= L_OFF;
            h_state   <= H_IDLE;
            sd_rd     <= 1'b0;
            sd_wr     <= 1'b0;
            h_blk_cnt <= 6'd0;
            tvalid    <= 16'd0;
            m_repl    <= 2'd0;
            bk_touch  <= 1'b1;
            nac       <= 8'd0;
            card_reset;
        end
    end

endmodule
