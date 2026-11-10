// SPDX-License-Identifier: GPL-3.0-or-later
// Cache-free DDR transport candidate. Inspired by ngage2 ddram_flash's held
// commands, ordered bulk reads and reset drain; no donor cache/geometry copied.
// Addresses are aligned byte addresses; count is 1..64 64-bit beats. Reads
// reserve the entire BRAM before issue because physical DDR cannot be stalled.
// Writes use individually accepted burstcount=1 commands, never write bursts.
module ngage_ddr_stream (
    input  wire        clk,
    input  wire        transport_reset,
    input  wire        phone_reset,
    input  wire        req_valid,
    output wire        req_ready,
    input  wire [ 1:0] req_owner,
    input  wire        req_cancel_on_phone,
    input  wire        req_write,
    input  wire        req_stream,
    input  wire [31:0] req_addr,
    input  wire [ 6:0] req_count,
    input  wire [63:0] req_data,
    input  wire [ 7:0] req_be,
    input  wire        write_valid,
    output wire        write_ready,
    input  wire [63:0] write_data,
    input  wire [ 7:0] write_be,
    input  wire        write_last,
    output wire        read_valid,
    input  wire        read_ready,
    output wire [ 1:0] read_owner,
    output wire [63:0] read_data,
    output wire        read_last,
    output reg         done = 0,
    output wire [ 1:0] done_owner,
    output reg         error = 0,
    output reg         cancelled = 0,
    output wire        idle,
    output wire [28:0] ddr_addr,
    output wire [63:0] ddr_din,
    output wire [ 7:0] ddr_be,
    output wire [ 7:0] ddr_burstcount,
    output wire        ddr_rd,
    output wire        ddr_we,
    input  wire        ddr_busy,
    input  wire [63:0] ddr_dout,
    input  wire        ddr_dout_ready
);
    localparam IDLE=0, READ_ISSUE=1, READ_WAIT=2, READ_FINISH=3,
        WRITE_NEED=5, WRITE_ISSUE=6;
    reg [2:0] state = IDLE;
    reg [1:0] owner = 0;
    reg cancel_on_phone = 0, discard = 0, stream_op = 0;
    reg [28:0] address = 0;
    reg [6:0] count = 0, received = 0, index = 0;
    reg [63:0] data = 0;
    reg [ 7:0] mask = 0;
    reg head_valid = 0, head_forward = 0;
    reg [63:0] forwarded_head = 0;
    wire [63:0] buffer_head;
    wire read_active = state == READ_ISSUE || state == READ_WAIT || state == READ_FINISH;
    wire cancel_now = transport_reset || (phone_reset && cancel_on_phone);
    wire [32:0] request_end = {1'b0, req_addr} + ({26'b0, req_count} << 3);
    wire valid_request = req_count != 0 && req_count <= 64 && req_addr[2:0] == 0 &&
        request_end <= 33'h100000000 && (!req_write || req_stream || req_count == 1);
    assign idle           = state == IDLE;
    assign req_ready      = idle && !transport_reset;
    assign ddr_addr       = address;
    assign ddr_din        = data;
    assign ddr_be         = state == READ_ISSUE || state == READ_WAIT ? 8'hff : mask;
    assign ddr_burstcount = state == READ_ISSUE || state == READ_WAIT ? {1'b0, count} : 8'd1;
    assign ddr_rd         = state == READ_ISSUE;
    assign ddr_we         = state == WRITE_ISSUE;
    assign write_ready    = state == WRITE_NEED && !cancel_now;
    assign read_valid     = read_active && head_valid && !discard && !cancel_now;
    assign read_owner     = owner;
    assign done_owner     = owner;
    assign read_last      = index + 1'b1 == count;
    wire       capture_first = state == READ_ISSUE && !ddr_busy && ddr_dout_ready;
    wire       capture_rest = state == READ_WAIT && ddr_dout_ready;
    wire       capture = capture_first || capture_rest;
    wire       consume = read_valid && read_ready;
    wire [6:0] next_index = index + (consume ? 7'd1 : 7'd0);
    wire [6:0] next_received = received + (capture ? 7'd1 : 7'd0);
    wire [5:0] buffer_read_address = next_index[5:0];
    // Both mux inputs are registered. A same-edge mixed-port RAM collision
    // is bypassed explicitly; no DDR-to-client combinational data path exists.
    assign read_data = head_forward ? forwarded_head : buffer_head;
    ngage_bram #(
        .AW(6),
        .DW(64)
    ) response_buffer (
        .clk   (clk),
        .addr_a(received[5:0]),
        .data_a(ddr_dout),
        .we_a  (capture),
        .q_a   (),
        .addr_b(buffer_read_address),
        .data_b(64'b0),
        .we_b  (1'b0),
        .q_b   (buffer_head)
    );
    always @(posedge clk) begin
        done      <= 0;
        error     <= 0;
        cancelled <= 0;
        if (read_active) begin
            index        <= next_index;
            head_valid   <= next_received > next_index;
            head_forward <= capture && received[5:0] == buffer_read_address;
            if (capture && received[5:0] == buffer_read_address) forwarded_head <= ddr_dout;
        end
        case (state)
            IDLE:
            if (req_valid && req_ready) begin
                owner           <= req_owner;
                cancel_on_phone <= req_cancel_on_phone;
                stream_op       <= req_stream;
                address         <= req_addr[31:3];
                count           <= req_count;
                received        <= 0;
                index           <= 0;
                discard         <= 0;
                head_valid      <= 0;
                head_forward    <= 0;
                data            <= req_data;
                mask            <= req_be;
                if (!valid_request) begin
                    done  <= 1;
                    error <= 1;
                end else if (phone_reset && req_cancel_on_phone) begin
                    done      <= 1;
                    cancelled <= 1;
                end else state <= req_write ? (req_stream ? WRITE_NEED : WRITE_ISSUE) : READ_ISSUE;
            end
            READ_ISSUE: begin
                // Once offered, a DDR command cannot be withdrawn while busy,
                // including during reset. Accept it once, then drain/discard.
                if (cancel_now) discard <= 1;
                if (!ddr_busy) begin
                    if (ddr_dout_ready) begin
                        received <= 1;
                        if (count == 1 && (discard || cancel_now)) begin
                            done      <= 1;
                            cancelled <= 1;
                            state     <= IDLE;
                        end else state <= count == 1 ? READ_FINISH : READ_WAIT;
                    end else state <= READ_WAIT;
                end
            end
            READ_WAIT: begin
                if (cancel_now) discard <= 1;
                if (ddr_dout_ready) begin
                    received <= received + 1'b1;
                    if (received + 1'b1 == count) begin
                        if (discard || cancel_now) begin
                            done      <= 1;
                            cancelled <= 1;
                            state     <= IDLE;
                        end else state <= READ_FINISH;
                    end
                end
            end
            READ_FINISH: begin
                if (cancel_now || discard) begin
                    done      <= 1;
                    cancelled <= 1;
                    state     <= IDLE;
                end else if (consume && read_last) begin
                    done  <= 1;
                    state <= IDLE;
                end
            end
            WRITE_NEED: begin
                if (cancel_now) begin
                    done      <= 1;
                    cancelled <= 1;
                    state     <= IDLE;
                end else if (write_valid) begin
                    // Reject the offending beat before any DDR side effect.
                    // Already committed prefix writes remain committed.
                    if (write_last != (index + 1'b1 == count)) begin
                        done  <= 1;
                        error <= 1;
                        state <= IDLE;
                    end else begin
                        data  <= write_data;
                        mask  <= write_be;
                        state <= WRITE_ISSUE;
                    end
                end
            end
            WRITE_ISSUE: begin
                if (cancel_now) discard <= 1;
                if (!ddr_busy) begin
                    if (discard || cancel_now) begin
                        done      <= 1;
                        cancelled <= 1;
                        state     <= IDLE;
                    end else if (!stream_op || index + 1'b1 == count) begin
                        done  <= 1;
                        state <= IDLE;
                    end else begin
                        index   <= index + 1'b1;
                        address <= address + 1'b1;
                        state   <= WRITE_NEED;
                    end
                end
            end
            default: begin
                state <= IDLE;
                done  <= 1;
                error <= 1;
            end
        endcase
    end
endmodule
