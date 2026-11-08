// Bounded hardware trace buffer and first fault. Readout uses 16-bit words:
// 0 magic, 1 version, 2..3 fault address, 4 reason, 5 count, 6 next slot,
// 7 wrapped, then 64 slots of six words: address, data, byte lanes, time.
// read_data follows read_word by one rising clock edge.
module ngage_diagnostics (
    input  wire        clk,
    input  wire        cold_reset,
    input  wire        freeze_trace,
    input  wire        fault,
    input  wire        fault_is_fetch,
    input  wire [31:0] fault_address,
    input  wire [ 2:0] fault_reason,
    input  wire        trace_valid,
    input  wire        trace_lost,
    input  wire [31:0] trace_addr,
    input  wire [31:0] trace_data,
    input  wire [ 3:0] trace_sel,
    input  wire [10:0] read_word,
    output reg  [15:0] read_data,
    output reg         fault_seen = 0
);
    // Fault qualifier and payload cross the same edge, then update sticky
    // history together. Trace timing and the one-clock readout are unchanged.
    reg sampled_fault = 0, sampled_fetch = 0;
    reg [31:0] sampled_address;
    reg [ 2:0] sampled_reason;
    always @(posedge clk) begin
        sampled_fault   <= !cold_reset && fault;
        sampled_fetch   <= fault_is_fetch;
        sampled_address <= fault_address;
        sampled_reason  <= fault_reason;
    end
    reg  [31:0] first_fetch_address = 0;
    reg  [ 2:0] first_fetch_reason = 0;
    reg         fetch_seen = 0;
    reg  [31:0] first_address = 0;
    reg  [ 2:0] first_reason = 0;
    reg  [31:0] ticks = 0;
    reg  [15:0] dropped = 0;
    reg  [ 5:0] next_slot = 0;
    reg  [ 6:0] count = 0;
    reg         wrapped = 0;
    // Fixed NGD layout: decode the 384 trace halfwords in parallel. Each
    // output is a reduction of constant-address matches, not a divider or a
    // priority chain. Keep the existing one-clock BRAM/readout contract.
    wire [63:0] slot_selected;
    wire [63:0] slot_bits               [0:5];
    wire [63:0] field_bits              [0:2];
    wire [ 5:0] read_slot;
    wire [ 2:0] field;
    genvar slot, bit_index;
    generate
        for (slot = 0; slot < 64; slot = slot + 1) begin : trace_decode
            wire [5:0] words;
            for (bit_index = 0; bit_index < 6; bit_index = bit_index + 1) begin : word_decode
                assign words[bit_index] = read_word == 8 + slot * 6 + bit_index;
                assign slot_bits[bit_index][slot] = slot_selected[slot] &&
                    ((slot >> bit_index) & 1);
            end
            assign slot_selected[slot] = |words;
            assign field_bits[0][slot] = words[1] | words[3] | words[5];
            assign field_bits[1][slot] = words[2] | words[3];
            assign field_bits[2][slot] = words[4] | words[5];
        end
        for (bit_index = 0; bit_index < 6; bit_index = bit_index + 1) begin : slot_encode
            assign read_slot[bit_index] = |slot_bits[bit_index];
        end
        for (bit_index = 0; bit_index < 3; bit_index = bit_index + 1) begin : field_encode
            assign field[bit_index] = |field_bits[bit_index];
        end
    endgenerate
    wire        trace_write = !cold_reset && trace_valid && !freeze_trace;
    wire [83:0] entry = {trace_sel, ticks[15:0], trace_data, trace_addr};
    wire [83:0] trace_q;
    reg         forward_trace;
    reg  [83:0] forward_entry;
    reg  [ 2:0] field_q;
    reg         trace_selected;
    reg  [15:0] metadata_q;
    reg  [15:0] metadata;
    wire [83:0] observed = forward_trace ? forward_entry : trace_q;
    ngage_bram #(
        .AW         (6),
        .DW         (84),
        .READ_ONLY_B(1)
    ) trace_ram (
        .clk   (clk),
        .addr_a(next_slot),
        .data_a(entry),
        .we_a  (trace_write),
        .q_a   (),
        .addr_b(read_slot),
        .data_b(84'b0),
        .we_b  (1'b0),
        .q_b   (trace_q)
    );
    always @(posedge clk) begin
        field_q <= field;
        metadata_q <= metadata;
        trace_selected <= !cold_reset && read_word >= 8 && read_word < 392 &&
            (count == 64 || {1'b0, read_slot} < count);
        forward_trace <= trace_write && next_slot == read_slot;
        forward_entry <= entry;
    end
    always @(posedge clk) begin
        if (cold_reset) begin
            ticks               <= 0;
            fault_seen          <= 0;
            first_address       <= 0;
            first_reason        <= 0;
            first_fetch_address <= 0;
            first_fetch_reason  <= 0;
            fetch_seen          <= 0;
            next_slot           <= 0;
            count               <= 0;
            wrapped             <= 0;
            dropped             <= 0;
        end else begin
            ticks <= ticks + 1'b1;
            if (sampled_fault && sampled_fetch && !fetch_seen) begin
                fetch_seen          <= 1;
                first_fetch_address <= sampled_address;
                first_fetch_reason  <= sampled_reason;
            end
            if (sampled_fault && !sampled_fetch && !fault_seen) begin
                fault_seen    <= 1;
                first_address <= sampled_address;
                first_reason  <= sampled_reason;
            end
            if ((trace_valid && freeze_trace) || trace_lost) begin
                if (dropped == 16'hffff ||
                    (dropped == 16'hfffe && trace_valid && freeze_trace && trace_lost))
                    dropped <= 16'hffff;
                else
                    dropped <= dropped + {15'b0, (trace_valid && freeze_trace)} +
                        {15'b0, trace_lost};
            end
            if (trace_valid && !freeze_trace) begin
                next_slot <= next_slot + 1'b1;
                if (count < 64) count <= count + 1'b1;
                else wrapped <= 1;
            end
        end
    end
    // Metadata and trace fields share the same one-clock read contract.
    always @* begin
        metadata = 0;
        case (read_word)
            0:   metadata = 16'h4e47;
            1:   metadata = 16'h0001;
            2:   metadata = first_address[15:0];
            3:   metadata = first_address[31:16];
            4:   metadata = {12'b0, fault_seen, first_reason};
            5:   metadata = {9'b0, count};
            6:   metadata = {10'b0, next_slot};
            7:   metadata = {15'b0, wrapped};
            392: metadata = dropped;
            393: metadata = first_fetch_address[15:0];
            394: metadata = first_fetch_address[31:16];
            395: metadata = {12'b0, fetch_seen, first_fetch_reason};
        endcase
        read_data = metadata_q;
        if (trace_selected) begin
            case (field_q)
                0: read_data = observed[15:0];
                1: read_data = observed[31:16];
                2: read_data = observed[47:32];
                3: read_data = observed[63:48];
                4: read_data = {12'b0, observed[83:80]};
                5: read_data = observed[79:64];
            endcase
        end
    end
endmodule
