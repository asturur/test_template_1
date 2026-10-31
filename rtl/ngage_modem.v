/*  N-Gage ISI/Phonet modem responder - HDL twin of scratch/modem/ngage_modem.c.
    Byte-stream interface: feed one complete Phonet frame on rx (the length
    field at offset 4, little-endian, delimits it), the response frame comes
    back on tx. Reply bytes are byte-exact to the real NEM-4 v4.03 NOS
    servers (docs/modem-model.md, disassembly addresses cited in the C).

    Transport-agnostic on purpose: the ISI wire/mailbox integration point is
    whatever the real NOS turns out to use (pending auth-run evidence); this
    module only owns the protocol. Cross-checked against the C model by
    scratch/modem/tb_modem.v over directed + random vectors.

    Made with Claude, 2026-10-31.
*/

module ngage_modem(
    input  wire        rst,
    input  wire        clk,
    // request frame in, one byte per rx_v cycle
    input  wire        rx_v,
    input  wire [ 7:0] rx_d,
    // response frame out
    output reg         tx_v,
    output reg  [ 7:0] tx_d,
    input  wire        tx_ready,
    output wire        busy,         // high from frame complete until tx done
    // identity / world state (ngm_state in the C)
    input  wire [ 7:0] own_dev,      // Phonet device id, low 2 bits ignored
    input  wire [127:0] imei,        // 16 bytes, [127:120] first on the wire
    input  wire [ 7:0] chg_status,   // sb 0x13 data0 (1 = not connected)
    input  wire [ 7:0] chg_raw,      // sb 0x14 data0
    input  wire [ 7:0] bat_status,   // sb 0x15 data0
    input  wire [ 7:0] bat_bars,     // sb 0x16 data1 (data0 is the cst 7)
    input  wire [15:0] bat_mv,       // sb 0x17 u16be
    input  wire [15:0] bat_aux,      // sb 0x18 u16be
    input  wire        sim_reg       // SIM server registered yet?
);

// reply kinds (classify below)
localparam [2:0] K_NONE  = 3'd0,  // silence
                 K_SHORT = 3'd1,  // 4-byte body {utid, rid, st, 0}
                 K_CERR  = 3'd2,  // 8-byte 0xF0 body {utid,F0,code,mid,tail,0,0,0}
                 K_IMEI  = 3'd3,  // 24-byte phone-info serial reply
                 K_CHG   = 3'd4,  // charger 0x09 + subblocks by flags[1:0]
                 K_BAT   = 3'd5;  // battery 0x0B + subblocks by flags[4:0]

localparam [2:0] S_RX  = 3'd0, S_CLS = 3'd1, S_HDR = 3'd2,
                 S_BODY= 3'd3, S_SB  = 3'd4, S_LEN = 3'd5, S_TX = 3'd6;

reg [2:0] st;
reg [7:0] buf_[0:63];         // request, then reply is built over it
reg [5:0] rxn;                // received byte count
reg [6:0] total;              // 6 + length field (capped)
reg       hdr_ok;             // got the first 6 bytes, total is valid

// latched request fields
reg [7:0] q_rxdev, q_txdev, q_res, q_rxobj, q_txobj, q_utid, q_mid, q_flags;

// classification result
reg [2:0] kind;
reg [7:0] rid, rstat, code, tail;  // reply id/status, 0xF0 code + 5th byte
reg [4:0] sbmask;                  // subblocks to emit (flags, validated)
reg [5:0] wr;                      // build/write pointer
reg [2:0] sb_bit;                  // current subblock bit 0..4
reg [1:0] sb_oct;                  // byte inside the 4-byte subblock
reg [5:0] txn;                     // tx byte index

assign busy = st != S_RX;

// energy id table 0x515937ac (even req ids answered with empty-OK; 0x08/0x0A
// have real bodies and are split out)
function e_known;
    input [7:0] id;
    begin
        case (id)
            8'h00,8'h02,8'h04,8'h06,8'h0c,8'h0f,8'h11,8'h13,8'h15,8'h17,
            8'h19,8'h1b,8'h1d,8'h1f,8'h22,8'h24,8'h26,8'he0,8'he2,8'he4,
            8'hf0: e_known = 1'b1;
            default: e_known = 1'b0;
        endcase
    end
endfunction

function [2:0] popc5;
    input [4:0] v;
    begin
        popc5 = {2'd0, v[0]} + {2'd0, v[1]} + {2'd0, v[2]} +
                {2'd0, v[3]} + {2'd0, v[4]};
    end
endfunction

// subblock bytes {id, 4, d0, d1} per (kind, bit)
reg [7:0] sb_id, sb_d0, sb_d1;
always @(*) begin
    sb_id = 8'h00; sb_d0 = 8'h00; sb_d1 = 8'h00;
    if (kind == K_CHG) case (sb_bit)
        3'd0: begin sb_id = 8'h13; sb_d0 = chg_status; end
        default: begin sb_id = 8'h14; sb_d0 = chg_raw; end
    endcase
    else case (sb_bit)
        3'd0: begin sb_id = 8'h15; sb_d0 = bat_status; end
        3'd1: begin sb_id = 8'h16; sb_d0 = 8'h07;        sb_d1 = bat_bars; end
        3'd2: begin sb_id = 8'h17; sb_d0 = bat_mv[15:8]; sb_d1 = bat_mv[7:0]; end
        3'd3: begin sb_id = 8'h18; sb_d0 = bat_aux[15:8];sb_d1 = bat_aux[7:0]; end
        default: begin sb_id = 8'h25; sb_d0 = 8'hff;     sb_d1 = 8'hff; end
    endcase
end

wire [6:0] rx_total = 7'd6 + {1'b0, buf_[4][5:0]};  // capped at 63+6 by width

always @(posedge clk or posedge rst) begin
    if (rst) begin
        st <= S_RX; rxn <= 6'd0; hdr_ok <= 1'b0; total <= 7'd0;
        tx_v <= 1'b0; tx_d <= 8'd0; wr <= 6'd0; txn <= 6'd0;
        kind <= K_NONE; sb_bit <= 3'd0; sb_oct <= 2'd0; sbmask <= 5'd0;
        rid <= 8'd0; rstat <= 8'd0; code <= 8'd0; tail <= 8'd0;
        q_rxdev <= 8'd0; q_txdev <= 8'd0; q_res <= 8'd0; q_rxobj <= 8'd0;
        q_txobj <= 8'd0; q_utid <= 8'd0; q_mid <= 8'd0; q_flags <= 8'd0;
    end else case (st)

    // ---- receive one frame; length (LE u16 @4, here low byte only: all
    //      modeled frames are < 64 bytes) delimits it -------------------
    S_RX: begin
        tx_v <= 1'b0;
        if (rx_v) begin
            buf_[rxn] <= rx_d;
            case (rxn)   // latch as they fly by
                6'd1: q_rxdev <= rx_d;
                6'd2: q_txdev <= rx_d;
                6'd3: q_res   <= rx_d;
                6'd6: q_rxobj <= rx_d;
                6'd7: q_txobj <= rx_d;
                6'd8: q_utid  <= rx_d;
                6'd9: q_mid   <= rx_d;
                6'd10: q_flags <= rx_d;
                default: ;
            endcase
            if (rxn == 6'd5) begin
                // buf_[4] latched at rxn==4 is stable here; clamp a corrupt
                // length claim to the buffer so the FSM cannot hang
                total <= rx_total > 7'd63 ? 7'd63 : rx_total;
                if (rx_total == 7'd6) begin        // empty body: runt
                    st <= S_CLS; rxn <= 6'd0; q_flags <= 8'd0;
                end else begin
                    hdr_ok <= 1'b1;
                    rxn <= rxn + 6'd1;
                end
            end else if (hdr_ok && {1'b0, rxn} == total - 7'd1) begin
                st  <= S_CLS;
                rxn <= 6'd0;
                hdr_ok <= 1'b0;
                if (rxn <= 6'd9) q_flags <= 8'd0;  // short frame: no flags byte
            end else
                rxn <= rxn + 6'd1;
        end
    end

    // ---- classify (ngm_handle dispatch) ------------------------------
    S_CLS: begin
        wr <= 6'd0; sb_bit <= 3'd0; sb_oct <= 2'd0;
        st <= S_HDR; kind <= K_CERR; code <= 8'h14; tail <= 8'h01; // router err
        if (total < 7'd10 || (q_rxdev & 8'hfc) != own_dev) begin
            st <= S_RX; kind <= K_NONE;             // silence
        end else case (q_res)
        8'h17: // energy server 0x515937ac
            if (q_mid == 8'h08) begin
                if (q_flags == 8'd0 || (q_flags & 8'hfc) != 8'd0) begin
                    kind <= K_SHORT; rid <= 8'h09; rstat <= 8'h02; // 0x51594c00
                end else begin
                    kind <= K_CHG; rid <= 8'h09; rstat <= 8'h01;
                    sbmask <= {3'b000, q_flags[1:0]};
                end
            end else if (q_mid == 8'h0a) begin
                if (q_flags == 8'd0 || (q_flags & 8'he0) != 8'd0) begin
                    kind <= K_SHORT; rid <= 8'h0b; rstat <= 8'h02;
                end else begin
                    kind <= K_BAT; rid <= 8'h0b; rstat <= 8'h01;
                    sbmask <= q_flags[4:0];
                end
            end else if (e_known(q_mid)) begin      // empty-OK 0x51594bdc
                kind <= K_SHORT; rid <= q_mid + 8'd1; rstat <= 8'h01;
            end else begin                          // 0x51594c44
                kind <= K_CERR; code <= 8'h01; tail <= 8'h00;
            end
        8'h1b: // phone info 0x51591bd0
            if (q_mid == 8'h00 && q_flags == 8'h41)
                kind <= K_IMEI;
            else begin
                kind <= K_CERR; code <= 8'h01; tail <= 8'h00;
            end
        8'h1c: // accessory (body inferred)
            if (q_mid == 8'h10 || q_mid == 8'h12) begin
                kind <= K_SHORT; rid <= q_mid + 8'd1; rstat <= 8'h01;
            end else begin
                kind <= K_CERR; code <= 8'h01; tail <= 8'h00;
            end
        8'h09: // SIM: unroutable until it registers (0x515305c4)
            if (sim_reg) begin
                if (q_mid == 8'h1d) begin   // resp 0x1E body unknown: fail
                    kind <= K_SHORT; rid <= 8'h1e; rstat <= 8'h02;
                end else begin
                    kind <= K_CERR; code <= 8'h01; tail <= 8'h00;
                end
            end
            // else keep the router-error default
        default: ;  // router error 0xF0 0x14 (0x51530fa0)
        endcase
    end

    // ---- write reply header: devices/objects swapped (0x51530fa0) ----
    S_HDR: begin
        case (wr)
            6'd0: buf_[0] <= 8'h00;      // media
            6'd1: buf_[1] <= q_txdev;
            6'd2: buf_[2] <= q_rxdev;
            6'd3: buf_[3] <= q_res;
            6'd4: buf_[4] <= 8'h00;      // length patched in S_LEN
            6'd5: buf_[5] <= 8'h00;
            6'd6: buf_[6] <= q_txobj;
            default: buf_[7] <= q_rxobj;
        endcase
        wr <= wr + 6'd1;
        if (wr == 6'd7) st <= S_BODY;
    end

    // ---- fixed body bytes per kind ------------------------------------
    S_BODY: begin
        wr <= wr + 6'd1;
        case (kind)
        K_SHORT: begin   // {utid, rid, st, 0}
            case (wr)
                6'd8:  buf_[wr] <= q_utid;
                6'd9:  buf_[wr] <= rid;
                6'd10: buf_[wr] <= rstat;
                default: buf_[wr] <= 8'h00;
            endcase
            if (wr == 6'd11) st <= S_LEN;
        end
        K_CERR: begin    // {utid, F0, code, mid, tail, 0, 0, 0}
            case (wr)
                6'd8:  buf_[wr] <= q_utid;
                6'd9:  buf_[wr] <= 8'hf0;
                6'd10: buf_[wr] <= code;
                6'd11: buf_[wr] <= q_mid;
                6'd12: buf_[wr] <= tail;
                default: buf_[wr] <= 8'h00;
            endcase
            if (wr == 6'd15) st <= S_LEN;
        end
        K_IMEI: begin    // {utid,01,00,01, 41,14,00,10, imei[16]} (0x5164bc80)
            case (wr)
                6'd8:  buf_[wr] <= q_utid;
                6'd9:  buf_[wr] <= 8'h01;
                6'd10: buf_[wr] <= 8'h00;   // INFO server: 0 = OK
                6'd11: buf_[wr] <= 8'h01;
                6'd12: buf_[wr] <= 8'h41;
                6'd13: buf_[wr] <= 8'h14;
                6'd14: buf_[wr] <= 8'h00;
                6'd15: buf_[wr] <= 8'h10;
                default: // bytes 16..31 <- imei, [127:120] first
                    buf_[wr] <= imei[{~wr[3:0], 3'b000} +: 8];
            endcase
            if (wr == 6'd31) st <= S_LEN;
        end
        default: begin   // K_CHG / K_BAT: {utid, rid, 01, popcount}
            case (wr)
                6'd8:  buf_[wr] <= q_utid;
                6'd9:  buf_[wr] <= rid;
                6'd10: buf_[wr] <= rstat;
                default: buf_[wr] <= {5'd0, popc5(sbmask)};
            endcase
            if (wr == 6'd11) st <= S_SB;
        end
        endcase
    end

    // ---- subblocks {id, 4, d0, d1} for set flag bits -------------------
    S_SB: begin
        if (sb_bit >= (kind == K_CHG ? 3'd2 : 3'd5))
            st <= S_LEN;
        else if (!sbmask[sb_bit]) begin
            sb_bit <= sb_bit + 3'd1;
        end else begin
            case (sb_oct)
                2'd0: buf_[wr] <= sb_id;
                2'd1: buf_[wr] <= 8'h04;
                2'd2: buf_[wr] <= sb_d0;
                default: buf_[wr] <= sb_d1;
            endcase
            wr <= wr + 6'd1;
            sb_oct <= sb_oct + 2'd1;
            if (sb_oct == 2'd3) sb_bit <= sb_bit + 3'd1;
        end
    end

    // ---- patch length = bytes after offset 6, LE u16 @4 (0x51530fce) ---
    S_LEN: begin
        buf_[4] <= {2'd0, wr} - 8'd6;
        buf_[5] <= 8'h00;
        total   <= {1'b0, wr};
        txn     <= 6'd0;
        st      <= S_TX;
    end

    // ---- stream the reply ----------------------------------------------
    S_TX: begin
        if (!tx_v || tx_ready) begin
            if ({1'b0, txn} == total) begin
                tx_v <= 1'b0;
                st   <= S_RX;
            end else begin
                tx_v <= 1'b1;
                tx_d <= buf_[txn];
                txn  <= txn + 6'd1;
            end
        end
    end

    default: st <= S_RX;
    endcase
end

endmodule
