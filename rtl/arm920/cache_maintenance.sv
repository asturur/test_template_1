// SPDX-License-Identifier: GPL-3.0-or-later
// Indexed/all data-cache maintenance. The caller serializes this controller
// against CPU accesses and translates an MVA operation to a hit index first.
// Error is local; the architecture-level response is the caller's responsibility.
module arm920_cache_maintenance (
    input  logic         clk,
    input  logic         reset,
    input  logic         start,
    input  logic         clean,
    input  logic         invalidate,
    input  logic         all,
    input  logic [  5:0] index_way,
    input  logic [  2:0] index_segment,
    output logic         busy,
    output logic         done,
    output logic         error,
    output logic         scan_read,
    output logic [  5:0] scan_way,
    output logic [  2:0] scan_segment,
    input  logic         scan_valid,
    input  logic [  1:0] scan_dirty,
    input  logic [ 31:0] scan_physical_line,
    input  logic [255:0] scan_line,
    output logic         scan_clean,
    output logic         scan_invalidate,
    output logic         bus_valid,
    output logic [ 31:0] bus_address,
    output logic [ 31:0] bus_wdata,
    input  logic         bus_ack,
    input  logic         bus_error
);
    typedef enum logic [2:0] {
        IDLE,
        TAG_WAIT,
        SELECT_LINE,
        READ_LINE,
        CAPTURE_LINE,
        WRITEBACK,
        COMMIT
    } state_t;
    state_t       state;
    logic   [8:0] index;
    logic do_clean, do_invalidate, do_all;
    logic [ 31:0] saved_pa;
    logic [255:0] saved_line;
    logic [  1:0] saved_dirty;
    logic [  2:0] word_index;
    assign busy = state != IDLE;
    assign scan_way = index[8:3];
    assign scan_segment = index[2:0];
    assign scan_read       = state == TAG_WAIT || state == SELECT_LINE || state == READ_LINE || state == CAPTURE_LINE;
    assign scan_clean = state == COMMIT && do_clean && !do_invalidate;
    assign scan_invalidate = state == COMMIT && do_invalidate;
    assign bus_valid = state == WRITEBACK;
    assign bus_address = saved_pa + {27'b0, word_index, 2'b0};
    assign bus_wdata = saved_line[word_index*32+:32];
    always_ff @(posedge clk) begin
        if (reset) begin
            state         <= IDLE;
            done          <= 0;
            error         <= 0;
            index         <= 0;
            do_clean      <= 0;
            do_invalidate <= 0;
            do_all        <= 0;
            saved_pa      <= 0;
            saved_line    <= 0;
            saved_dirty   <= 0;
            word_index    <= 0;
        end else begin
            done  <= 0;
            error <= 0;
            case (state)
                IDLE:
                if (start) begin
                    index         <= all ? 0 : {index_way, index_segment};
                    do_clean      <= clean;
                    do_invalidate <= invalidate;
                    do_all        <= all;
                    state         <= TAG_WAIT;
                end
                TAG_WAIT:  state <= SELECT_LINE;
                SELECT_LINE:
                if (scan_valid && do_clean && |scan_dirty) begin
                    saved_pa    <= scan_physical_line;
                    saved_dirty <= scan_dirty;
                    state       <= READ_LINE;
                end else state <= COMMIT;
                READ_LINE: state <= CAPTURE_LINE;
                CAPTURE_LINE: begin
                    saved_line <= scan_line;
                    word_index <= saved_dirty[0] ? 0 : 4;
                    state      <= WRITEBACK;
                end
                WRITEBACK:
                if (bus_error) begin
                    error <= 1;
                    done  <= 1;
                    state <= IDLE;
                end else if (bus_ack) begin
                    if (word_index == 3 && saved_dirty[1]) word_index <= 4;
                    else if (word_index == 3 || word_index == 7) state <= COMMIT;
                    else word_index <= word_index + 1'b1;
                end
                COMMIT:
                if (!do_all || index == 9'h1ff) begin
                    done  <= 1;
                    state <= IDLE;
                end else begin
                    index <= index + 1'b1;
                    state <= TAG_WAIT;
                end
                default:   state <= IDLE;
            endcase
        end
    end
endmodule
