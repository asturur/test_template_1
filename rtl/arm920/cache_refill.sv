// SPDX-License-Identifier: GPL-3.0-or-later
// Replacement coordinator for arm920_cache_bank + arm920_cache_transfer.
// The caller must exclude all other bank operations until done.
module arm920_cache_refill (
    input  logic         clk,
    input  logic         reset,
    input  logic         start,
    input  logic [ 31:0] request_mva,
    input  logic [ 31:0] request_physical,
    output logic         busy,
    output logic         done,
    output logic         error,
    output logic [ 31:0] bank_mva,
    input  logic         bank_hit,
    input  logic         bank_victim_valid,
    input  logic [  1:0] bank_victim_dirty,
    input  logic [ 31:0] bank_victim_physical,
    input  logic [255:0] bank_read_line,
    output logic         bank_read_victim,
    output logic         bank_refill,
    output logic         bank_writeback_done,
    output logic [ 31:0] bank_refill_physical,
    output logic [255:0] bank_refill_line,
    input  logic         bank_refill_ready,
    output logic         bus_valid,
    output logic         bus_write,
    output logic [ 31:0] bus_address,
    output logic [ 31:0] bus_wdata,
    input  logic         bus_ack,
    input  logic         bus_error,
    input  logic [ 31:0] bus_rdata
);
    typedef enum logic [3:0] {
        IDLE,
        TAG_WAIT,
        SELECT_VICTIM,
        READ_VICTIM,
        START_TRANSFER,
        WAIT_TRANSFER,
        INSTALL,
        COMPARE_WAIT,
        COMMIT
    } state_t;
    state_t        state;
    logic   [31:0] saved_pa;
    logic transfer_start, transfer_busy, transfer_done, transfer_error;
    logic [255:0] transfer_line;
    assign busy = state != IDLE;
    assign bank_read_victim=(state==SELECT_VICTIM || state==READ_VICTIM || state==START_TRANSFER);
    assign transfer_start = state == START_TRANSFER;
    assign bank_refill = state == INSTALL;
    assign bank_writeback_done = state == INSTALL;
    assign bank_refill_physical = saved_pa;
    assign bank_refill_line = transfer_line;
    arm920_cache_transfer transfer (
        .clk           (clk),
        .reset         (reset),
        .start         (transfer_start),
        .victim_address(bank_victim_physical),
        .victim_dirty  (bank_victim_valid ? bank_victim_dirty : 2'b0),
        .victim_line   (bank_read_line),
        .refill_address(saved_pa),
        .busy          (transfer_busy),
        .done          (transfer_done),
        .error         (transfer_error),
        .refill_line   (transfer_line),
        .bus_valid     (bus_valid),
        .bus_write     (bus_write),
        .bus_address   (bus_address),
        .bus_wdata     (bus_wdata),
        .bus_ack       (bus_ack),
        .bus_error     (bus_error),
        .bus_rdata     (bus_rdata)
    );
    always_ff @(posedge clk) begin
        if (reset) begin
            state    <= IDLE;
            done     <= 0;
            error    <= 0;
            bank_mva <= 0;
            saved_pa <= 0;
        end else begin
            done  <= 0;
            error <= 0;
            case (state)
                IDLE:
                if (start) begin
                    bank_mva <= request_mva;
                    saved_pa <= request_physical;
                    state    <= TAG_WAIT;
                end
                TAG_WAIT:       state <= COMPARE_WAIT;
                COMPARE_WAIT:   state <= SELECT_VICTIM;
                SELECT_VICTIM:
                if (bank_hit) begin
                    done  <= 1;
                    state <= IDLE;
                end else state <= READ_VICTIM;
                READ_VICTIM:    state <= START_TRANSFER;
                START_TRANSFER: state <= WAIT_TRANSFER;
                WAIT_TRANSFER:
                if (transfer_done) begin
                    if (transfer_error) begin
                        done  <= 1;
                        error <= 1;
                        state <= IDLE;
                    end else state <= INSTALL;
                end
                INSTALL:        if (bank_refill_ready) state <= COMMIT;
                COMMIT: begin
                    done  <= 1;
                    state <= IDLE;
                end
                default:        state <= IDLE;
            endcase
        end
    end
endmodule
