// SPDX-License-Identifier: GPL-3.0-or-later
// Single-line replacement bus engine. Inputs are captured on start; successful
// completion is the only point at which the caller may discard a dirty victim.
// Each bus request remains stable until ack or err. A bus error aborts the
// operation; an interrupted write-back is safe to retry with the retained line.
module arm920_cache_transfer (
    input  logic         clk,
    input  logic         reset,
    input  logic         start,
    input  logic [ 31:0] victim_address,
    input  logic [  1:0] victim_dirty,
    input  logic [255:0] victim_line,
    input  logic [ 31:0] refill_address,
    output logic         busy,
    output logic         done,
    output logic         error,
    output logic [255:0] refill_line,
    output logic         bus_valid,
    output logic         bus_write,
    output logic [ 31:0] bus_address,
    output logic [ 31:0] bus_wdata,
    input  logic         bus_ack,
    input  logic         bus_error,
    input  logic [ 31:0] bus_rdata
);
    typedef enum logic [1:0] {
        IDLE,
        WRITEBACK,
        REFILL
    } state_t;
    state_t state;
    logic [31:0] old_address, new_address;
    logic [  1:0] dirty;
    logic [255:0] old_line;
    logic [  2:0] word_index;
    assign busy        = state != IDLE;
    assign bus_valid   = busy;
    assign bus_write   = state == WRITEBACK;
    assign bus_address = (bus_write ? old_address : new_address) + {27'b0, word_index, 2'b00};
    assign bus_wdata   = old_line[word_index*32+:32];
    always_ff @(posedge clk) begin
        if (reset) begin
            state       <= IDLE;
            done        <= 0;
            error       <= 0;
            word_index  <= 0;
            old_address <= 0;
            new_address <= 0;
            dirty       <= 0;
            old_line    <= 0;
            refill_line <= 0;
        end else begin
            done  <= 0;
            error <= 0;
            case (state)
                IDLE:
                if (start) begin
                    old_address <= {victim_address[31:5], 5'b0};
                    new_address <= {refill_address[31:5], 5'b0};
                    old_line    <= victim_line;
                    dirty       <= victim_dirty;
                    refill_line <= 0;
                    word_index  <= victim_dirty[0] ? 0 : victim_dirty[1] ? 4 : 0;
                    if (|victim_dirty) state <= WRITEBACK;
                    else state <= REFILL;
                end
                WRITEBACK:
                if (bus_error) begin
                    state <= IDLE;
                    done  <= 1;
                    error <= 1;
                end else if (bus_ack) begin
                    if (word_index == 3 && dirty[1]) word_index <= 4;
                    else if (word_index == 3 || word_index == 7) begin
                        word_index <= 0;
                        state      <= REFILL;
                    end else word_index <= word_index + 1'b1;
                end
                REFILL:
                if (bus_error) begin
                    state <= IDLE;
                    done  <= 1;
                    error <= 1;
                end else if (bus_ack) begin
                    refill_line[word_index*32+:32] <= bus_rdata;
                    if (word_index == 7) begin
                        state <= IDLE;
                        done  <= 1;
                    end else word_index <= word_index + 1'b1;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
