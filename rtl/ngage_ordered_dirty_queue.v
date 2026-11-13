// SPDX-License-Identifier: GPL-3.0-or-later
// One queued generation per sector, plus a separately held in-flight entry.
// A mark after dequeue belongs at the tail. A failed transfer keeps its
// in-flight entry and stops the queue so an uncertain host write cannot retry.
module ngage_ordered_dirty_queue #(
    parameter integer SECTORS = 8320,
    parameter integer AW      = 14,
    parameter integer DEPTH   = SECTORS
) (
    input  wire          clk,
    input  wire          cold_reset,
    input  wire          dirty_valid,
    input  wire [AW-1:0] dirty_sector,
    input  wire          flush_start,
    input  wire [  AW:0] flush_limit,
    input  wire          abort_flush,
    output wire [  31:0] debug_state,
    output reg           init_done = 0,
    output reg           flushing = 0,
    output reg           flush_error = 0,
    output reg           queue_fault = 0,
    output wire          pending,
    output reg           sector_valid = 0,
    output reg  [AW-1:0] sector_index = 0,
    input  wire          sector_accept,
    input  wire          sector_done,
    input  wire          sector_ok
);
    localparam [  AW:0] SECTOR_COUNT = SECTORS;
    localparam [  AW:0] QUEUE_DEPTH  = DEPTH;
    localparam [AW-1:0] LAST_SECTOR  = SECTOR_COUNT[AW-1:0] - 1'b1;
    localparam [AW-1:0] LAST_ENTRY   = QUEUE_DEPTH [AW-1:0] - 1'b1;
    reg [AW-1:0] scrub = 0, head = 0, tail = 0;
    reg [AW:0] count = 0, remaining = 0;
    reg limited = 0, in_flight = 0, head_ready = 0;
    reg          mark_valid = 0;
    reg [AW-1:0] mark_sector = 0;
    reg push_forward = 0, pop_forward = 0;
    reg push_generation = 0, pop_generation = 0;
    reg [1:0] fault_cause = 0;
    wire enqueue_bit, dequeue_bit;
    wire [AW:0] entry;
    wire head_generation = entry[AW];
    wire [AW-1:0] head_sector = entry[AW-1:0];
    wire input_valid = {1'b0, dirty_sector} < SECTOR_COUNT;
    wire invalid_mark = dirty_valid && !input_valid;
    wire active = init_done && !cold_reset && !queue_fault && !flush_error && !abort_flush;
    wire take = active && !invalid_mark && flushing && !in_flight && head_ready && (!limited || remaining != 0);
    wire enqueued = push_forward ? push_generation : enqueue_bit;
    wire dequeued = take && head_sector == mark_sector ? head_generation :
        pop_forward ? pop_generation : dequeue_bit;
    wire new_entry = active && mark_valid && enqueued == dequeued;
    wire push = new_entry && (count < QUEUE_DEPTH || take);
    wire overflow = new_entry && !push;
    wire clearing = !init_done && !cold_reset;
    wire [AW-1:0] lookup_sector = input_valid ? dirty_sector : {AW{1'b0}};
    // Passive tagged DDR observation. Count already freezes after a fault;
    // retain only its two cause bits, not another copy of the queue payload.
    wire [14:0] observed_count = count;
    assign debug_state = {
        8'h51,
        observed_count,
        init_done,
        queue_fault,
        flush_error,
        flushing,
        in_flight,
        mark_valid,
        head_ready,
        fault_cause
    };
    assign pending = count != 0 || in_flight || mark_valid || (init_done && dirty_valid);

    // Separate generation RAMs allow one mark lookup and both state updates
    // per clock. The matching write is forwarded past mixed-port collisions.
    ngage_bram #(
        .AW   (AW),
        .DW   (1),
        .DEPTH(SECTORS)
    ) enqueued_bits (
        .clk   (clk),
        .addr_a(clearing ? scrub : mark_sector),
        .data_a(!clearing && !enqueued),
        .we_a  (clearing || push),
        .q_a   (),
        .addr_b(lookup_sector),
        .data_b(1'b0),
        .we_b  (1'b0),
        .q_b   (enqueue_bit)
    );
    ngage_bram #(
        .AW   (AW),
        .DW   (1),
        .DEPTH(SECTORS)
    ) dequeued_bits (
        .clk   (clk),
        .addr_a(clearing ? scrub : head_sector),
        .data_a(!clearing && head_generation),
        .we_a  (clearing || take),
        .q_a   (),
        .addr_b(lookup_sector),
        .data_b(1'b0),
        .we_b  (1'b0),
        .q_b   (dequeue_bit)
    );
    ngage_bram #(
        .AW   (AW),
        .DW   (AW + 1),
        .DEPTH(DEPTH)
    ) fifo (
        .clk   (clk),
        .addr_a(tail),
        .data_a({!enqueued, mark_sector}),
        .we_a  (push),
        .q_a   (),
        .addr_b(head),
        .data_b({(AW + 1) {1'b0}}),
        .we_b  (1'b0),
        .q_b   (entry)
    );

    always @(posedge clk) begin
        if (cold_reset) begin
            init_done    <= 0;
            scrub        <= 0;
            head         <= 0;
            tail         <= 0;
            count        <= 0;
            mark_valid   <= 0;
            head_ready   <= 0;
            flushing     <= 0;
            flush_error  <= 0;
            queue_fault  <= 0;
            fault_cause  <= 0;
            in_flight    <= 0;
            sector_valid <= 0;
            limited      <= 0;
            remaining    <= 0;
        end else if (!init_done) begin
            if (scrub == LAST_SECTOR) init_done <= 1;
            else scrub <= scrub + 1'b1;
        end else begin
            mark_valid      <= dirty_valid && input_valid;
            mark_sector     <= lookup_sector;
            push_forward    <= push && mark_sector == lookup_sector;
            push_generation <= !enqueued;
            pop_forward     <= take && head_sector == lookup_sector;
            pop_generation  <= head_generation;
            head_ready      <= count != 0 && !take;
            if (push) tail <= tail == LAST_ENTRY ? {AW{1'b0}} : tail + 1'b1;
            if (take) head <= head == LAST_ENTRY ? {AW{1'b0}} : head + 1'b1;
            case ({
                push, take
            })
                2'b10:   count <= count + 1'b1;
                2'b01:   count <= count - 1'b1;
                default: ;
            endcase

            if (overflow || invalid_mark) queue_fault <= 1;
            if (!queue_fault && (overflow || invalid_mark)) fault_cause <= {overflow, invalid_mark};
            if (abort_flush || queue_fault || overflow || invalid_mark) begin
                flushing     <= 0;
                flush_error  <= 1;
                sector_valid <= 0;
            end else if (!flush_error) begin
                if (flush_start && !flushing) begin
                    flushing  <= 1;
                    limited   <= flush_limit != 0;
                    remaining <= flush_limit;
                end
                if (take) begin
                    sector_index <= head_sector;
                    sector_valid <= 1;
                    in_flight    <= 1;
                    if (limited) remaining <= remaining - 1'b1;
                end else if (in_flight) begin
                    if (sector_valid && sector_accept) sector_valid <= 0;
                    if (!sector_valid && sector_done) begin
                        if (sector_ok) in_flight <= 0;
                        else begin
                            flushing    <= 0;
                            flush_error <= 1;
                        end
                    end
                end else if (flushing && ((limited && remaining == 0) || !pending)) flushing <= 0;
            end
        end
    end
endmodule
