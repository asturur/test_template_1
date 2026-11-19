// SPDX-License-Identifier: GPL-3.0-or-later
// Phone RAM service on ngage2's open-row SDRAM controller
// (rtl/sdram/ngage2_sdram.sv). It takes the place of ngage_sdram_adapter
// and jtframe_sdram64 behind the same request ports.
//
// Scalar port (from ngage_sdram_arbiter): req is held with addr/we/din/be
// until the one-clock ack. A write is acknowledged in the clock after the
// controller takes it (its data is latched there); a read when its word
// arrives. After ack the service waits for req to fall.
//
// Line port: line_req && line_ready hands over one aligned 32-byte read.
// It is one chained 32-byte burst of the controller; the sixteen halfwords
// come back in order on line_valid/line_data, line_last with the sixteenth.
//
// Cold start: every word of RAM_BYTES is written zero (16 bytes a write)
// before scrub_done. phone_reset drops the answer of the operation in
// flight (the operation itself completes) and holds off new ones;
// owner_ready is low until that operation has drained.
module ngage_sdram_fast #(
    parameter integer        CLK_HZ      = 78000000,
    parameter                LINE_REFILL = 1,
    parameter         [24:0] RAM_BYTES   = 25'h1000000
) (
    input  wire clk,
    input  wire rst,
    input  wire phone_reset,
    output wire init,

    input  wire        req,
    input  wire        we,
    input  wire [24:0] addr,
    input  wire [31:0] din,
    input  wire [ 3:0] be,
    output reg         ack = 0,
    output reg  [31:0] dout = 0,

    input  wire        line_req,
    input  wire [24:0] line_addr,
    output wire        line_ready,
    output reg         line_valid = 0,
    output reg  [15:0] line_data = 0,
    output reg         line_last = 0,

    output reg  scrub_done = 0,
    output wire owner_ready,

    output wire        sdram_cke,
    output wire        sdram_cs_n,
    output wire        sdram_ras_n,
    output wire        sdram_cas_n,
    output wire        sdram_we_n,
    output wire [ 1:0] sdram_ba,
    output wire [12:0] sdram_a,
    output wire        sdram_dqml,
    output wire        sdram_dqmh,
    output wire [15:0] sdram_dq_o,
    output wire [15:0] sdram_dq_oe,
    input  wire [15:0] sdram_dq_i
);
    localparam [2:0] IDLE = 0, SCRUB = 1, WORD_RD = 2, LINE = 3, TAIL = 4, DROP = 5;
    reg [ 2:0] state = IDLE;
    reg [24:0] scrub_address = 0;
    reg [ 2:0] words = 0;
    reg [ 3:0] beat = 0;
    reg        high_pending = 0;
    reg [15:0] high_half = 0;
    reg        discard = 0;

    wire c_ready, c_busy, c_rvalid;
    wire [ 1:0] c_rword;
    wire [31:0] c_rdata;
    assign init = !c_ready;

    wire idle = state == IDLE && c_ready && !rst;
    wire scrub_start = idle && !scrub_done;
    assign line_ready = LINE_REFILL && idle && scrub_done && !req && !phone_reset && !c_busy;
    wire line_start = line_req && line_ready;
    wire word_start = idle && scrub_done && req && !phone_reset && !line_start;

    wire c_req = scrub_start || line_start || word_start;
    wire c_line = scrub_start || line_start;
    wire c_we = scrub_start || (word_start && we);
    wire [24:2] c_addr  = scrub_start ? scrub_address[24:2] :
                          line_start  ? {line_addr[24:5], 3'b000} : addr[24:2];
    wire [127:0] c_wdata = scrub_start ? 128'd0 : {4{din}};
    wire [15:0] c_wbe = scrub_start ? 16'hffff : {4{be}};
    wire c_take = c_req && !c_busy;

    assign owner_ready = !rst && c_ready && !phone_reset && !discard;

    always @(posedge clk) begin
        ack        <= 0;
        line_valid <= 0;
        line_last  <= 0;
        if (rst) begin
            state         <= IDLE;
            scrub_done    <= 0;
            scrub_address <= 0;
            discard       <= 0;
            high_pending  <= 0;
        end else begin
            if (phone_reset && state != IDLE && state != SCRUB) discard <= 1;
            // the second half of a line word follows its first by one clock
            if (high_pending) begin
                high_pending <= 0;
                line_valid   <= !discard && !phone_reset;
                line_data    <= high_half;
                line_last    <= beat == 4'd15;
                beat         <= beat + 4'd1;
            end
            case (state)
                IDLE: begin
                    discard <= 0;
                    if (c_take) begin
                        if (scrub_start) state <= SCRUB;
                        else if (line_start) begin
                            words <= 0;
                            beat  <= 0;
                            state <= LINE;
                        end else if (we) begin
                            ack   <= 1;
                            state <= DROP;
                        end else state <= WORD_RD;
                    end
                end
                SCRUB: begin
                    if (scrub_address + 25'd16 >= RAM_BYTES) scrub_done <= 1;
                    else scrub_address <= scrub_address + 25'd16;
                    state <= IDLE;
                end
                WORD_RD:
                if (c_rvalid) begin
                    dout <= c_rdata;
                    if (discard || phone_reset) state <= IDLE;
                    else begin
                        ack   <= 1;
                        state <= DROP;
                    end
                end
                LINE:
                if (c_rvalid) begin
                    line_valid   <= !discard && !phone_reset;
                    line_data    <= c_rdata[15:0];
                    high_half    <= c_rdata[31:16];
                    high_pending <= 1;
                    beat         <= beat + 4'd1;
                    words        <= words + 3'd1;
                    if (words == 3'd7) state <= TAIL;
                end
                TAIL:    state <= IDLE;
                DROP:    if (!req || phone_reset) state <= IDLE;
                default: state <= IDLE;
            endcase
        end
    end

    ngage2_sdram #(
        .CLK_HZ(CLK_HZ)
    ) controller (
        .clk        (clk),
        .init       (rst),
        .ready      (c_ready),
        .req        (c_req),
        .busy       (c_busy),
        .we         (c_we),
        .line       (c_line),
        .line32     (line_start),
        .addr       (c_addr),
        .wdata      (c_wdata),
        .wbe        (c_wbe),
        .rvalid     (c_rvalid),
        .rword      (c_rword),
        .rdata      (c_rdata),
        .sdram_cke  (sdram_cke),
        .sdram_cs_n (sdram_cs_n),
        .sdram_ras_n(sdram_ras_n),
        .sdram_cas_n(sdram_cas_n),
        .sdram_we_n (sdram_we_n),
        .sdram_ba   (sdram_ba),
        .sdram_a    (sdram_a),
        .sdram_dqml (sdram_dqml),
        .sdram_dqmh (sdram_dqmh),
        .sdram_dq_o (sdram_dq_o),
        .sdram_dq_oe(sdram_dq_oe),
        .sdram_dq_i (sdram_dq_i)
    );
    wire unused = &{1'b0, c_rword, addr[1:0], line_addr[4:0]};
endmodule
