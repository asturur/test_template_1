// SPDX-License-Identifier: GPL-2.0-or-later
//
// Standalone Verilog-2001 port of ngage2 rtl/upp/upp_mmc.sv, SHA-256
// ff319b6ed1347b735d2fe2ec72748274ac9e723b9db49756cd697d98309b5ef5.
// No production bus/IRQ ownership is selected by this module. Direct native
// pins are a transaction-level shortcut for the unmodeled D550/AMA path.
// QD-derived clock/timeout/type-4 timing and IRQ22 level behavior remain
// unverified for NEM-4. General malformed-response status handling is unchanged;
// only the reviewed CMD16 cache guard rejects malformed responses. Concurrent
// command/argument register edits while a transaction is active are unsupported.
//
// UPP_WD2 MMC host (0x0C120600-0x0C12063F) in 1-bit mode on CLK, CMD and DAT0,
// with the register interface of the reference model (model/hw/ngage_mmc.c,
// from epbus.dll's WD2MMC layer, RH-29 v4.60; docs/UPP_WD2.md):
//
//   +0x04 control. Writing bit 0 = 1 starts a transfer; bits 5:2 = type:
//           0 command, no response          1 R1        2 R3 (CMD1)
//           3 R2 (CID, CSD)                 4 R1 + busy ([model guess] "R1b?")
//           8 command (CMD17/18) + read a block   9 read the next block (no command)
//          10 read the last block, then the command (CMD12, R1)
//           5 command (CMD24/25) + write a block  6 write the next block (no command)
//           7 write the last block, then the command (CMD12, R1 + busy)
//         For 10 and 7 epbus loads CMD12 into +0x1C/+0x20 and the block length
//         into +0x08 first, and DMAs that block during the phase (0x503F56E4-
//         0x503F57A8; a 4 KB read is 8, six 9s, 10), as the corrected model has
//         it (model/hw/ngage_mmc.c, 71b0d8a); the command goes out after the
//         block: after its end bit (10), after the card's busy (7).
//         bit 6 = no response CRC check (set with CMD1's R3). Bit 0 reads 0:
//         the transfer is taken at once (the driver polls it, 0x503F5490).
//         Other bits and writes without bit 0 (0x40 at power-up, 0 at
//         power-down) are storage only.
//   +0x08 data length of the following data phase (0: the block length the
//         card was given with CMD16, 512 after reset; at most 4096), storage
//   +0x0C, +0x10, +0x14  storage ([model guess] time-outs 0x1DC130 and clock
//         divider 0x280; nothing here uses them)
//   +0x18 status (read): bit 3 command busy, 2 data busy, 8 response word
//         available; command errors 6 response time-out, 1 response CRC; data
//         errors 0 data CRC, 5 busy time-out, 7 data time-out, 10 other (no
//         CRC status token after a written block). Cleared by every start.
//   +0x1C command index, +0x20 argument (write; storage)
//   +0x20 read: the next response word. R1/R3: one word, response bits 39:8;
//         R2: four words, bits 127:0 most significant first. Bit 8 clears
//         when the last word is read. 0 when there is none.
//   +0x24 data FIFO (8 bits per lane; the DMA target 0x10120624, 8-bit): a
//         read takes the next bytes of the block being read (0 past its end or
//         outside a read phase), a write gives the next bytes of the block
//         being written (dropped outside a write phase).
//   other offsets: storage (the generic store in upp_periph).
// Interrupt levels from the status, as in the model (bound by name in epbus
// 0x503F6180-0x503F62E8): MMCDataIdle 21 = !data busy, MMCDataRdy 22 = data
// busy, MMCCmdIdle 23 = !command busy, MMCCmdRdy 24 = response available.
//
// Where the model is instant this is real time. Command busy lasts until the
// response and NRC (8 clocks) after it, or the busy signal on DAT0 after it
// for types 4 and 7; for 10 and 7 it covers the block before the command
// (epbus waits for command idle, data idle and the DMA in any order, with the
// DMA already running, 0x503F5888-0x503F5A94). For R2 the first three response
// words precede command idle; its fourth word follows idle, as the original
// NEM-4 driver requires. This is a register-level ordering model, not measured
// physical UPP shift-register timing. A read block's data busy lasts until the block, CRC
// included, has arrived and every byte has been read from the FIFO (the model
// clears it with the last byte read); a written block's until the card's
// busy after its CRC status token ends (the model: the last byte written).
// The FIFO holds FIFO_DEPTH bytes; the clock stops while it is full during a
// read or empty during a write, and after a read block until type 9 asks for
// the next (CMD18 then waits on the card's side), so no data is ever lost.
// The DMA is paced by rx_ready / tx_ready (upp_dma).
//
// Bus: CLK = clk / DIV, low at rest; the host changes CMD/DAT0 as CLK falls
// and samples them as it rises (as rtl/board/mmc_card.sv expects). [assumed]
// DIV = 4 (26 MHz; 12 is the phone's own rate, the service manual's 8.66 MHz,
// for an accuracy build); time-outs: 64 clocks to a response start bit (NCR
// max), 2^TIMEOUT_LOG2 clocks (~323 ms at 26 MHz; 21 at DIV = 12) to a read
// block's start bit and for busy.
module ngage_mmc_host #(
    parameter integer DIV = 4,  // 12 (8.66 MHz, the service manual's rate) for an accuracy build
    parameter integer RESP_WAIT = 64,
    parameter integer TIMEOUT_LOG2 = 23,  // ~323 ms at DIV = 4 (21 at DIV = 12)
    parameter integer FIFO_DEPTH = 16
) (
    input wire clk,
    input wire reset,

    input  wire        acc,
    input  wire        we,
    input  wire        wr,
    input  wire        rd,
    input  wire [ 5:0] off,
    input  wire [ 3:0] be,
    input  wire [31:0] wdata,
    output reg  [31:0] rmask,
    output reg  [31:0] rdata,
    output reg         busy,

    output wire       rx_ready,  // a 1-byte FIFO read would not wait
    output wire       tx_ready,  // a 1-byte FIFO write would not wait
    output wire [3:0] irq,       // {CmdRdy, CmdIdle, DataRdy, DataIdle}

    output wire mmc_clk,
    output reg  cmd_o,
    output reg  cmd_oe,
    input  wire cmd_i,
    output reg  dat_o,
    output reg  dat_oe,
    input  wire dat_i
);

    function integer clog2;
        input integer value;
        integer remaining;
        begin
            remaining = value - 1;
            clog2     = 0;
            while (remaining > 0) begin
                remaining = remaining >> 1;
                clog2     = clog2 + 1;
            end
        end
    endfunction

    localparam integer                    PHW              = clog2(DIV);
    localparam integer                    FAW              = clog2(FIFO_DEPTH);
    localparam integer                    HALF             = DIV / 2;
    localparam integer                    LAST_PHASE       = DIV - 1;
    localparam         [TIMEOUT_LOG2-1:0] TOKEN_WAIT_LIMIT = 16;

    // status bits
    localparam integer B_DATA_CRC = 0, B_RESP_CRC = 1, B_DATA_BUSY = 2, B_CMD_BUSY = 3,
                   B_BUSY_TO = 5, B_RESP_TO = 6, B_DATA_TO = 7, B_RESP = 8, B_DATA_ERR = 10;

    // Original NEM-4 response classification clears 0x5f00, 0xdf and
    // 0x02c00000 at 503f9fbc..503f9fc4: error mask 0xfd3fa020.
    // CMD16 also cannot succeed after the card reports COM_CRC_ERROR or
    // ILLEGAL_COMMAND (bits 23/22); these reject it in mmc_card.sv.
    localparam [31:0] R1_CACHE_REJECT = 32'hFDFF_A020;

    // command engine
    localparam [2:0] C_IDLE = 3'd0, C_SEND = 3'd1, C_RWAIT = 3'd2, C_RECV = 3'd3,
                           C_BUSY = 3'd4, C_TAIL = 3'd5,
                           C_AFTER = 3'd6;    // types 10 and 7: the command waits for the block
    // data engine
    localparam [3:0] D_IDLE = 4'd0, D_RWAIT = 4'd1, D_RX = 4'd2, D_RDONE = 4'd3,
                           D_TWAIT = 4'd4, D_TX = 4'd5, D_TSTAT = 4'd6, D_TBUSY = 4'd7,
                           D_TAIL = 4'd8;

    // ------------------------------------------------------------------
    // CRCs (MMC: CRC7 x^7 + x^3 + 1, CRC16 x^16 + x^12 + x^5 + 1)
    // ------------------------------------------------------------------
    function [6:0] crc7_bit;
        input [6:0] c;
        input b;
        reg fb;
        begin
            fb       = c[6] ^ b;
            crc7_bit = {c[5:3], c[2] ^ fb, c[1:0], fb};
        end
    endfunction
    function [15:0] crc16_bit;
        input [15:0] c;
        input b;
        reg fb;
        begin
            fb        = c[15] ^ b;
            crc16_bit = {c[14:12], c[11] ^ fb, c[10:5], c[4] ^ fb, c[3:0], fb};
        end
    endfunction
    function [6:0] crc7_40;
        input [39:0] v;
        reg     [6:0] c;
        integer       bit_index;
        begin
            c = 7'd0;
            for (bit_index = 39; bit_index >= 0; bit_index = bit_index - 1)
            c = crc7_bit(c, v[bit_index]);
            crc7_40 = c;
        end
    endfunction
    // Explicit zero-extension and modulo truncation replace SV sized casts.
    function [FAW-1:0] fifo_index;
        input [FAW-1:0] pointer;
        input [2:0] delta;
        reg [FAW+2:0] sum;
        begin
            sum        = {{3{1'b0}}, pointer} + {{FAW{1'b0}}, delta};
            fifo_index = sum[FAW-1:0];
        end
    endfunction
    function [FAW:0] fifo_count_value;
        input [2:0] value;
        reg [FAW+3:0] wide;
        begin
            wide             = {{(FAW + 1) {1'b0}}, value};
            fifo_count_value = wide[FAW:0];
        end
    endfunction

    // ------------------------------------------------------------------
    // Registers
    // ------------------------------------------------------------------
    reg [ 10:0] status;
    reg [  5:0] cmd_idx;
    reg [ 31:0] arg;
    reg [ 12:0] len_reg;  // +0x08, clamped to 4096
    reg [ 12:0] blocklen;  // from CMD16
    reg [127:0] resp;
    reg [2:0] resp_words, resp_pos;

    // the transfer
    reg [ 3:0] ty;
    reg        nocrc;
    reg [12:0] blen;  // bytes in the block of the data phase
    reg [12:0] nfifo;  // bytes the bus has taken from / given to the FIFO
    reg [12:0] nrx;  // bytes received from the card into the FIFO
    reg [12:0] ntx;  // bytes taken from the FIFO for the card

    reg [2:0] cstate;
    reg [3:0] dstate;

    // ------------------------------------------------------------------
    // FIFO, FIFO_DEPTH bytes in registers
    // ------------------------------------------------------------------
    reg [7:0] fmem[0:FIFO_DEPTH-1];
    reg [FAW-1:0] fwp, frp;
    reg [FAW:0] fcnt;

    integer       nbe_index;
    reg     [2:0] nbe;  // bytes the access moves
    always @* begin
        nbe = 3'd0;
        for (nbe_index = 0; nbe_index < 4; nbe_index = nbe_index + 1)
        nbe = nbe + {2'd0, be[nbe_index]};
    end

    wire         rx_phase = dstate == D_RWAIT || dstate == D_RX || dstate == D_RDONE;
    wire         rx_coming = dstate == D_RWAIT || dstate == D_RX;
    wire         tx_phase = dstate == D_TWAIT || dstate == D_TX;
    wire [ 12:0] rem = blen - nfifo;
    // the bytes an access asks for, within the block
    wire [  2:0] need = ({10'd0, nbe} < rem) ? nbe : rem[2:0];
    wire [FAW:0] need_f = fifo_count_value(need);
    wire [FAW:0] fdepth = FIFO_DEPTH[FAW:0];

    wire fifo_rd = off == 6'h24 && !we;
    wire fifo_wr = off == 6'h24 && we;

    assign rx_ready = !(rx_coming && fcnt == {(FAW + 1) {1'b0}});
    assign tx_ready = !(tx_phase && rem != 13'd0 && fcnt == fdepth);

    // a FIFO read takes the bytes it asks for that are there (busy waits
    // while more are coming), the rest of the lanes read 0
    wire    [ 2:0] fifo_take = !rx_phase ? 3'd0 : (fcnt < need_f) ? fcnt[2:0] : need[2:0];
    reg     [ 2:0] fifo_lane;
    integer        fifo_index_lane;
    reg     [31:0] fifo_word;
    always @* begin
        fifo_word = 32'd0;
        fifo_lane = 3'd0;
        for (fifo_index_lane = 0; fifo_index_lane < 4; fifo_index_lane = fifo_index_lane + 1) begin
            if (be[fifo_index_lane]) begin
                if (fifo_lane < fifo_take)
                    fifo_word[8*fifo_index_lane+:8] = fmem[fifo_index(frp, fifo_lane)];
                fifo_lane = fifo_lane + 3'd1;
            end
        end
    end

    always @* begin
        rmask = 32'd0;
        rdata = 32'd0;
        busy  = 1'b0;
        if (acc) begin
            case (off)
                6'h04: begin
                    rmask = 32'h0000_0001;
                    rdata = 32'd0;
                end
                6'h18: begin
                    rmask = 32'hffffffff;
                    rdata = {21'd0, status};
                end
                6'h20:
                if (!we) begin
                    rmask = 32'hffffffff;
                    rdata = (resp_pos < resp_words) ? resp[7'd96-{resp_pos[1:0], 5'd0}+:32] : 32'd0;
                end
                6'h24: begin
                    if (!we) begin
                        rmask = 32'hffffffff;
                        rdata = fifo_word;
                        busy  = rx_coming && fcnt < need_f;
                    end else begin
                        busy = tx_phase && fdepth - fcnt < need_f;
                    end
                end
                default: ;
            endcase
        end
    end

    // ------------------------------------------------------------------
    // The bus clock: periods of DIV clocks, run while an engine needs them
    // ------------------------------------------------------------------
    reg  [PHW-1:0] ph;
    reg            run;  // this period is clocked
    wire           fall = run && ph == {PHW{1'b0}};
    wire           rise = run && ph == HALF[PHW-1:0];
    reg cmd_need, dat_need, dat_hold;

    assign mmc_clk = run && ph >= HALF[PHW-1:0];

    // ------------------------------------------------------------------
    // The engines
    // ------------------------------------------------------------------
    reg [            47:0] csr;  // command bits to send, next in 47
    reg [             7:0] ccnt;  // bits sent / received, clocks waited
    reg [           126:0] rsr;  // response bits received, last in 0
    reg [             6:0] rcrc;
    reg                    resp_long;  // R2
    reg                    resp_busy;  // types 4, 7
    reg                    want_resp;
    reg                    resp_ok;  // the response of this transfer has arrived
    reg                    cmd_first;  // types 5, 8: the data phase needs the command's response
    reg                    blk_done;  // the data phase of a type 10 / 7 is over: the command may go
    reg [TIMEOUT_LOG2-1:0] cto;  // busy time-out after a response

    reg [TIMEOUT_LOG2-1:0] dto;  // data / busy time-out
    reg [15:0] dcrc, dcrc_rx;
    reg [7:0] dsr;  // data byte being received or sent
    reg [3:0] dbit;  // its bits so far (receive) / left (send)
    reg [4:0] dcbit;  // CRC bits so far
    reg       dend;  // the end bit has been sent
    reg [2:0] tok, tcnt;
    reg [3:0] dtail;
    reg [1:0] gap;

    wire [7:0] fifo_head = fmem[frp];

    // the start of a transfer at this edge
    wire        start = wr && off == 6'h04 && wdata[0];
    wire [ 3:0] sty = wdata[5:2];
    wire        s_cmd = !(sty == 4'd6 || sty == 4'd9);
    wire [12:0] len_eff = (len_reg != 13'd0) ? len_reg : blocklen;

    always @* begin
        cmd_need = cstate != C_IDLE && cstate != C_AFTER;
        case (dstate)
            D_RWAIT, D_RX, D_TX, D_TSTAT, D_TBUSY, D_TAIL: dat_need = 1'b1;
            D_TWAIT:                                       dat_need = fcnt != {(FAW + 1) {1'b0}};
            default:                                       dat_need = 1'b0;
        endcase
        // at a byte boundary, wait for FIFO room (receive) or a byte (send)
        dat_hold = (dstate == D_RX && dbit == 4'd0 && nrx < blen && fcnt == fdepth) ||
                   (dstate == D_TX && dbit == 4'd0 && ntx < blen && fcnt == {(FAW+1){1'b0}});
    end

    // Verilog-2001 named-block locals retain the donor's private temporaries.
    always @(posedge clk) begin : engine_step
        reg push1, pop1;
        reg [7:0] pbyte;
        reg [2:0] npush, npop, k;
        reg     [127:0] f;
        integer         write_lane;
        push1 = 1'b0;
        pop1  = 1'b0;
        pbyte = 8'd0;

        // ---- the clock ----
        if (run) ph <= (ph == LAST_PHASE[PHW-1:0]) ? {PHW{1'b0}} : ph + 1'd1;
        if ((run && ph == LAST_PHASE[PHW-1:0]) || !run) run <= (cmd_need || dat_need) && !dat_hold;

        // ---- register writes ----
        if (wr) begin
            case (off)
                6'h08:   len_reg <= (wdata[31:12] != 20'd0) ? 13'd4096 : wdata[12:0];
                6'h1C:   cmd_idx <= wdata[5:0];
                6'h20:   arg <= wdata;
                default: ;
            endcase
        end
        if (rd && off == 6'h20 && resp_pos < resp_words) begin
            resp_pos <= resp_pos + 3'd1;
            if (resp_pos + 3'd1 >= resp_words) status[B_RESP] <= 1'b0;
        end

        // ---- command engine ----
        blk_done <= 1'b0;
        case (cstate)
            C_AFTER:
            if (blk_done) begin
                ccnt   <= 8'd0;
                cstate <= C_SEND;
            end
            C_SEND:
            if (fall) begin
                if (ccnt == 8'd48) begin
                    cmd_oe <= 1'b0;
                    ccnt   <= 8'd0;
                    cstate <= want_resp ? C_RWAIT : C_TAIL;
                end else begin
                    cmd_oe <= 1'b1;
                    cmd_o  <= csr[47];
                    csr    <= {csr[46:0], 1'b1};
                    ccnt   <= ccnt + 8'd1;
                end
            end
            C_RWAIT:
            if (rise) begin
                if (!cmd_i) begin
                    rsr    <= 127'd0;
                    ccnt   <= 8'd1;
                    rcrc   <= crc7_bit(7'd0, 1'b0);
                    cstate <= C_RECV;
                end else if (ccnt == RESP_WAIT[7:0]) begin
                    status[B_RESP_TO] <= 1'b1;
                    if (cmd_first) status[B_DATA_BUSY] <= 1'b0;  // no data phase without a response
                    ccnt   <= 8'd0;
                    cstate <= C_TAIL;
                end else begin
                    ccnt <= ccnt + 8'd1;
                end
            end
            C_RECV:
            if (rise) begin
                rsr  <= {rsr[125:0], cmd_i};
                ccnt <= ccnt + 8'd1;
                // CRC7: R1 over its first 40 bits, R2 over bits 127:8
                if (resp_long ? (ccnt >= 8'd8 && ccnt < 8'd128) : (ccnt < 8'd40))
                    rcrc <= crc7_bit((resp_long && ccnt == 8'd8) ? 7'd0 : rcrc, cmd_i);
                if (ccnt == (resp_long ? 8'd135 : 8'd47)) begin
                    f = {rsr, cmd_i};
                    resp           <= resp_long ? f[127:0] : {f[39:8], 96'd0};
                    resp_words     <= resp_long ? 3'd4 : 3'd1;
                    resp_pos       <= 3'd0;
                    status[B_RESP] <= 1'b1;
                    if (!nocrc && ty != 4'd2 && f[7:1] != rcrc) status[B_RESP_CRC] <= 1'b1;
                    resp_ok <= 1'b1;
                    // Cache only a well-formed, CRC-valid successful R1. Software
                    // CRC suppression cannot establish that CMD16 was accepted.
                    // Keep response delivery/status semantics unchanged here.
                    if (cmd_idx == 6'd16 && !resp_long && ty != 4'd2 &&
                        f[47:46] == 2'b00 && f[45:40] == cmd_idx && f[0] &&
                        f[7:1] == rcrc && (f[39:8] & R1_CACHE_REJECT) == 32'd0)
                        blocklen <= (arg[31:12] != 20'd0) ? 13'd4096 : arg[12:0];
                    ccnt   <= 8'd0;
                    cto    <= {TIMEOUT_LOG2{1'b0}};
                    cstate <= resp_busy ? C_BUSY : C_TAIL;
                end
            end
            C_BUSY:
            if (rise) begin
                cto <= cto + 1'd1;
                if (dat_i || &cto) begin
                    if (!dat_i) status[B_BUSY_TO] <= 1'b1;
                    ccnt   <= 8'd0;
                    cstate <= C_TAIL;
                end
            end
            C_TAIL:
            if (fall) begin
                // The original NEM-4 R2 driver waits for three response-ready
                // words, then command-idle and the final word. Keep idle from
                // winning IRQ23 over response-ready IRQ24 before those reads.
                // Otherwise a delayed CPU observes only the idle event and
                // rejects a valid CID/CSD with native error 0x8000.
                if (ccnt == 8'd8 && (!resp_long || !status[B_RESP] ||
                    status[B_RESP_CRC] || resp_pos >= 3'd3)) begin
                    status[B_CMD_BUSY] <= 1'b0;
                    cstate             <= C_IDLE;
                end else if (ccnt != 8'd8) begin
                    ccnt <= ccnt + 8'd1;
                end
            end
            default: ;
        endcase

        // ---- data engine ----
        case (dstate)
            D_RWAIT: begin
                if (rise) begin
                    dto <= dto + 1'd1;
                    if (!dat_i) begin
                        dbit   <= 4'd0;
                        dcbit  <= 5'd0;
                        dcrc   <= 16'd0;
                        dstate <= D_RX;
                    end else if (&dto) begin
                        status[B_DATA_TO] <= 1'b1;
                        blk_done          <= 1'b1;
                        dstate            <= D_RDONE;
                    end
                end
                // a command that went unanswered has no data phase
                if (cmd_first && status[B_RESP_TO]) dstate <= D_IDLE;
            end
            D_RX:
            if (rise) begin
                if (nrx < blen) begin
                    dsr  <= {dsr[6:0], dat_i};
                    dcrc <= crc16_bit(dcrc, dat_i);
                    if (dbit == 4'd7) begin
                        push1 = 1'b1;
                        pbyte = {dsr[6:0], dat_i};
                        nrx  <= nrx + 13'd1;
                        dbit <= 4'd0;
                    end else begin
                        dbit <= dbit + 4'd1;
                    end
                end else if (dcbit < 5'd16) begin
                    dcrc_rx <= {dcrc_rx[14:0], dat_i};
                    dcbit   <= dcbit + 5'd1;
                end else begin
                    // the end bit; the clock stops here until the next transfer
                    // (or the command of a type 10)
                    if (dcrc_rx != dcrc || !dat_i) status[B_DATA_CRC] <= 1'b1;
                    blk_done <= 1'b1;
                    dstate   <= D_RDONE;
                end
            end
            D_RDONE: begin
                // every byte received has been read
                if (fcnt == {(FAW + 1) {1'b0}}) begin
                    status[B_DATA_BUSY] <= 1'b0;
                    dstate              <= D_IDLE;
                end
            end
            D_TWAIT: begin
                if (cmd_first && status[B_RESP_TO]) begin
                    dstate <= D_IDLE;
                end else if (fall && resp_ok) begin
                    if (gap != 2'd2) begin
                        gap <= gap + 2'd1;
                    end else if (fcnt != {(FAW + 1) {1'b0}}) begin
                        // NWR >= 2 clocks after the response: the start bit
                        dat_oe <= 1'b1;
                        dat_o  <= 1'b0;
                        dcrc   <= 16'd0;
                        dbit   <= 4'd0;
                        dcbit  <= 5'd0;
                        dend   <= 1'b0;
                        dstate <= D_TX;
                    end
                end
            end
            D_TX:
            if (fall) begin
                if (dbit != 4'd0) begin
                    dat_o <= dsr[7];
                    dcrc  <= crc16_bit(dcrc, dsr[7]);
                    dsr   <= {dsr[6:0], 1'b0};
                    dbit  <= dbit - 4'd1;
                end else if (ntx < blen) begin
                    // the next byte (dat_hold stops the clock while there is none)
                    pop1 = 1'b1;
                    dat_o <= fifo_head[7];
                    dcrc  <= crc16_bit(dcrc, fifo_head[7]);
                    dsr   <= {fifo_head[6:0], 1'b0};
                    dbit  <= 4'd7;
                    ntx   <= ntx + 13'd1;
                end else if (dcbit != 5'd16) begin
                    dat_o <= dcrc[4'd15-dcbit[3:0]];
                    dcbit <= dcbit + 5'd1;
                end else if (!dend) begin
                    dat_o <= 1'b1;  // the end bit
                    dend  <= 1'b1;
                end else begin
                    dat_oe <= 1'b0;
                    tcnt   <= 3'd0;
                    dto    <= {TIMEOUT_LOG2{1'b0}};
                    dstate <= D_TSTAT;
                end
            end
            D_TSTAT:
            if (rise) begin
                dto <= dto + 1'd1;
                if (tcnt == 3'd0) begin
                    if (!dat_i) begin
                        tcnt <= 3'd1;
                    end else if (dto == TOKEN_WAIT_LIMIT) begin
                        status[B_DATA_ERR] <= 1'b1;  // no CRC status token
                        dto                <= {TIMEOUT_LOG2{1'b0}};
                        dstate             <= D_TBUSY;
                    end
                end else if (tcnt != 3'd4) begin
                    tok  <= {tok[1:0], dat_i};
                    tcnt <= tcnt + 3'd1;
                end else begin
                    // the token's end bit; the card is busy while DAT0 is low
                    if (tok != 3'b010) status[B_DATA_CRC] <= 1'b1;
                    dto    <= {TIMEOUT_LOG2{1'b0}};
                    dstate <= D_TBUSY;
                end
            end
            D_TBUSY:
            if (rise) begin
                dto <= dto + 1'd1;
                if (dat_i || &dto) begin
                    if (!dat_i) status[B_BUSY_TO] <= 1'b1;
                    dtail  <= 4'd0;
                    dstate <= D_TAIL;
                end
            end
            D_TAIL:
            if (fall) begin
                if (dtail == 4'd8) begin
                    status[B_DATA_BUSY] <= 1'b0;
                    blk_done            <= 1'b1;
                    dstate              <= D_IDLE;
                end else begin
                    dtail <= dtail + 4'd1;
                end
            end
            default: ;
        endcase

        // ---- the FIFO ----
        npush = 3'd0;
        npop  = 3'd0;
        if (rd && fifo_rd && rx_phase) begin
            npop = fifo_take;
            nfifo <= nfifo + {10'd0, fifo_take};
        end
        if (wr && fifo_wr && tx_phase) begin
            k = 3'd0;
            for (write_lane = 0; write_lane < 4; write_lane = write_lane + 1) begin
                if (be[write_lane] && {10'd0, k} < rem) begin
                    fmem[fifo_index(fwp, k)] <= wdata[8*write_lane+:8];
                    k = k + 3'd1;
                end
            end
            npush = k;
            nfifo <= nfifo + {10'd0, k};
        end
        if (push1) begin
            fmem[fwp] <= pbyte;
            npush = 3'd1;
        end
        if (pop1) npop = 3'd1;
        fwp  <= fifo_index(fwp, npush);
        frp  <= fifo_index(frp, npop);
        fcnt <= fcnt + fifo_count_value(npush) - fifo_count_value(npop);

        // ---- a new transfer ----
        if (start) begin
            ty         <= sty;
            nocrc      <= wdata[6];
            status     <= 11'd0;
            resp_words <= 3'd0;
            resp_pos   <= 3'd0;
            resp_ok    <= sty == 4'd6 || sty == 4'd7;
            cmd_first  <= sty == 4'd5 || sty == 4'd8;
            blk_done   <= 1'b0;
            cmd_oe     <= 1'b0;
            dat_oe     <= 1'b0;
            fwp        <= {FAW{1'b0}};
            frp        <= {FAW{1'b0}};
            fcnt       <= {(FAW + 1) {1'b0}};
            nfifo      <= 13'd0;
            nrx        <= 13'd0;
            ntx        <= 13'd0;
            gap        <= 2'd0;
            dto        <= {TIMEOUT_LOG2{1'b0}};
            blen       <= (len_eff > 13'd4096) ? 13'd4096 : len_eff;
            resp_long  <= sty == 4'd3;
            resp_busy  <= sty == 4'd4 || sty == 4'd7;
            want_resp  <= sty != 4'd0;
            if (s_cmd) begin
                status[B_CMD_BUSY] <= 1'b1;
                csr <= {1'b0, 1'b1, cmd_idx, arg, crc7_40({1'b0, 1'b1, cmd_idx, arg}), 1'b1};
                ccnt <= 8'd0;
                cstate <= (sty == 4'd7 || sty == 4'd10) ? C_AFTER : C_SEND;
            end else begin
                cstate <= C_IDLE;
            end
            case (sty)
                4'd8, 4'd9, 4'd10: begin
                    status[B_DATA_BUSY] <= 1'b1;
                    dstate              <= D_RWAIT;
                end
                4'd5, 4'd6, 4'd7: begin
                    status[B_DATA_BUSY] <= 1'b1;
                    dstate              <= D_TWAIT;
                end
                default: dstate <= D_IDLE;
            endcase
        end

        if (reset) begin
            run        <= 1'b0;
            ph         <= {PHW{1'b0}};
            cstate     <= C_IDLE;
            dstate     <= D_IDLE;
            blk_done   <= 1'b0;
            status     <= 11'd0;
            resp_words <= 3'd0;
            resp_pos   <= 3'd0;
            cmd_oe     <= 1'b0;
            cmd_o      <= 1'b1;
            dat_oe     <= 1'b0;
            dat_o      <= 1'b1;
            fwp        <= {FAW{1'b0}};
            frp        <= {FAW{1'b0}};
            fcnt       <= {(FAW + 1) {1'b0}};
            nfifo      <= 13'd0;
            nrx        <= 13'd0;
            ntx        <= 13'd0;
            blen       <= 13'd0;
            len_reg    <= 13'd0;
            blocklen   <= 13'd512;
            cmd_idx    <= 6'd0;
            arg        <= 32'd0;
        end
    end

    assign irq = {status[B_RESP], !status[B_CMD_BUSY], status[B_DATA_BUSY], !status[B_DATA_BUSY]};


endmodule
