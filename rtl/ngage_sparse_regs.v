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
    localparam integer LEAVES = 1 << AW;
    localparam IDLE = 3'd0, COMPARE = 3'd1, SELECT = 3'd2, READ = 3'd3, RESULT = 3'd4, DONE = 3'd5, DISCARD = 3'd6;
    reg [2:0] state;
    reg [ENTRIES-1:0] valid, matched, vacant;
    reg [31:0] tags[0:ENTRIES-1];
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
    wire [ENTRIES-1:0] hit_mask;
    wire [2*LEAVES-2:0] hit_present, free_present;
    wire [AW-1:0] hit_index[0:2*LEAVES-2], free_index[0:2*LEAVES-2];
    wire write_value = ready && state == RESULT && commit && request_write && !result_full;
    wire [31:0] mask = {
        {8{request_sel[3]}}, {8{request_sel[2]}}, {8{request_sel[1]}}, {8{request_sel[0]}}
    };
    // Balanced lowest-index trees preserve lookup/allocation order. Padding
    // leaves are absent in both trees, including non-power-of-two capacities.
    genvar slot;
    generate
        for (slot = 0; slot < LEAVES; slot = slot + 1) begin : leaves
            if (slot < ENTRIES) begin : active_slot
                assign hit_mask[slot]              = matched[slot];
                assign hit_present[LEAVES-1+slot]  = hit_mask[slot];
                assign free_present[LEAVES-1+slot] = vacant[slot];
            end else begin : padding_slot
                assign hit_present[LEAVES-1+slot]  = 0;
                assign free_present[LEAVES-1+slot] = 0;
            end
            assign hit_index[LEAVES-1+slot]  = slot;
            assign free_index[LEAVES-1+slot] = slot;
        end
        for (slot = 0; slot < LEAVES - 1; slot = slot + 1) begin : nodes
            assign hit_present[slot] = hit_present[2*slot+1] | hit_present[2*slot+2];
            assign free_present[slot] = free_present[2*slot+1] | free_present[2*slot+2];
            assign hit_index[slot] = hit_present[2*slot+1] ?
                hit_index[2*slot+1] : hit_index[2*slot+2];
            assign free_index[slot] = free_present[2*slot+1] ?
                free_index[2*slot+1] : free_index[2*slot+2];
        end
    endgenerate
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
        .addr_b(selected_slot),
        .data_a(result_hit ? request_data : request_data & mask),
        .data_b(32'b0),
        .we_a  (write_value ? (result_hit ? request_sel : 4'hf) : 4'b0),
        .we_b  (4'b0),
        .q_a   (),
        .q_b   (value_q)
    );
    integer i;
    always @(posedge clk) begin
        if (cold_reset) valid <= 0;
        else if (write_value && !result_hit) begin
            valid[selected_slot] <= 1;
            tags[selected_slot]  <= request_addr;
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
                    state         <= COMPARE;
                end
                COMPARE: begin
                    for (i = 0; i < ENTRIES; i = i + 1) begin
                        matched[i] <= valid[i] && tags[i] == request_addr;
                        vacant[i]  <= !valid[i];
                    end
                    state <= SELECT;
                end
                SELECT: begin
                    selected_slot <= hit_present[0] ? hit_index[0] : free_index[0];
                    result_hit    <= hit_present[0];
                    result_full   <= request_write && !hit_present[0] && !free_present[0];
                    state         <= READ;
                end
                READ:    state <= RESULT;  // Payload RAM samples the registered slot.
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
