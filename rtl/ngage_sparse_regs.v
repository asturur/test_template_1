// Bounded behavioral full-address register store, not a silicon register model.
// Request fields stay stable through ready. Lookup never needs commit; a ready
// result is consumed with commit, applying a write exactly once. Held requests
// retain their result until withdrawal or a different transaction identity.
module ngage_sparse_regs #(
    parameter integer ENTRIES = 64
) (
    input  wire        clk,
    input  wire        cold_reset,
    input  wire        reset,
    input  wire        req,
    input  wire        commit,
    input  wire        we,
    input  wire [31:0] addr,
    input  wire [31:0] din,
    input  wire [ 3:0] sel,
    output wire [31:0] dout,
    output wire        full,
    output wire        ready
);
    localparam integer AW = ENTRIES > 1 ? $clog2(ENTRIES) : 1;
    localparam integer LAST_INDEX = ENTRIES - 1;
    localparam [AW-1:0] LAST_SLOT = LAST_INDEX[AW-1:0];
    localparam IDLE = 3'd0, PROBE = 3'd1, RESULT = 3'd2, DONE = 3'd3, DISCARD = 3'd4;
    reg [        2:0] state;
    reg [ENTRIES-1:0] valid;
    reg [     AW-1:0] probe_count;
    reg [31:0] request_addr, request_data, held_result;
    reg [   3:0] request_sel;
    reg          request_write;
    reg [AW-1:0] selected_slot;
    reg result_hit, result_full;
    wire same_request = addr == request_addr && we == request_write &&
                        sel == request_sel && (!request_write || din == request_data);
    assign ready = !cold_reset && !reset && req && same_request &&
                   (state == RESULT || state == DONE);
    assign full = ready && result_full;
    wire [31:0] value_q;
    assign dout = !ready ? 32'b0 : state == DONE ? held_result : result_hit ? value_q : 32'b0;
    wire write_value = ready && state == RESULT && commit && request_write && !result_full;
    wire [31:0] mask = {
        {8{request_sel[3]}}, {8{request_sel[2]}}, {8{request_sel[1]}}, {8{request_sel[0]}}
    };
    // Fold every address bit, including the low byte-address bits. The
    // final subtraction bounds non-power-of-two capacities without division.
    function [AW-1:0] address_hash;
        input [31:0] address;
        reg     [AW-1:0] folded;
        reg     [  AW:0] bounded;
        integer          bit_number;
        begin
            folded = 0;
            for (bit_number = 0; bit_number < 32; bit_number = bit_number + 1) begin
                folded[bit_number%AW] = folded[bit_number%AW] ^ address[bit_number];
            end
            bounded = {1'b0, folded};
            if (bounded >= ENTRIES[AW:0]) bounded = bounded - ENTRIES[AW:0];
            address_hash = bounded[AW-1:0];
        end
    endfunction
    wire slot_valid = valid[selected_slot];
    wire [31:0] tag_q;
    wire slot_hit = slot_valid && tag_q == request_addr;
    wire last_probe = probe_count == LAST_SLOT;
    wire advance_probe = state == PROBE && slot_valid && !slot_hit && !last_probe;
    wire [AW-1:0] next_slot = selected_slot == LAST_SLOT ? {AW{1'b0}} : selected_slot + 1'b1;
    // Both RAMs sample the first hash on capture. A collision prefetches the
    // next slot while the current tag is compared, so probes cost one clock.
    wire [AW-1:0] first_slot = address_hash(addr);
    wire [AW-1:0] read_slot = state == IDLE ? first_slot :
                             advance_probe ? next_slot : selected_slot;
    ngage_bram #(
        .AW         (AW),
        .DW         (32),
        .READ_ONLY_B(1)
    ) tag_store (
        .clk   (clk),
        .addr_a(selected_slot),
        .addr_b(read_slot),
        .data_a(request_addr),
        .data_b(32'b0),
        .we_a  (write_value && !result_hit),
        .we_b  (1'b0),
        .q_a   (),
        .q_b   (tag_q)
    );
    // The chosen slot and write payload are registered before any mutation.
    // New entries zero unselected bytes; existing entries retain those bytes.
    ngage_bram #(
        .AW         (AW),
        .DW         (32),
        .BYTE_WIDTH (8),
        .READ_ONLY_B(1)
    ) payload (
        .clk   (clk),
        .addr_a(selected_slot),
        .addr_b(read_slot),
        .data_a(result_hit ? request_data : request_data & mask),
        .data_b(32'b0),
        .we_a  (write_value ? (result_hit ? request_sel : 4'hf) : 4'b0),
        .we_b  (4'b0),
        .q_a   (),
        .q_b   (value_q)
    );
    always @(posedge clk) begin
        if (cold_reset) valid <= 0;
        else if (write_value && !result_hit) begin
            valid[selected_slot] <= 1;
        end
        if (cold_reset || reset) begin
            // A reset cancels even an authorized request held across reset.
            // It must withdraw or change identity before it can be retried.
            state         <= req ? DISCARD : IDLE;
            request_addr  <= addr;
            request_data  <= din;
            request_sel   <= sel;
            request_write <= we;
        end else if (!req) begin
            state <= IDLE;
        end else if (state != IDLE && !same_request) begin
            // Withdrawal/replacement cancels uncommitted work, including a
            // resolved write waiting for authorization. No old completion leaks.
            state <= IDLE;
        end else begin
            case (state)
                IDLE: begin
                    request_addr  <= addr;
                    request_data  <= din;
                    request_sel   <= sel;
                    request_write <= we;
                    selected_slot <= first_slot;
                    probe_count   <= 0;
                    state         <= PROBE;
                end
                PROBE: begin
                    if (slot_hit || !slot_valid || last_probe) begin
                        result_hit  <= slot_hit;
                        result_full <= request_write && !slot_hit && slot_valid;
                        state       <= RESULT;
                    end else begin
                        selected_slot <= next_slot;
                        probe_count   <= probe_count + 1'b1;
                    end
                end
                RESULT:
                if (commit) begin
                    held_result <= result_hit ? value_q : 32'b0;
                    state       <= DONE;
                end
                DISCARD: state <= DISCARD;
                DONE:    state <= DONE;  // Identical held request must not execute twice.
                default: state <= IDLE;
            endcase
        end
    end
endmodule
