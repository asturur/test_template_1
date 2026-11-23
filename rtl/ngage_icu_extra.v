// Staged ICU configuration, DMA programming latches, and epbus clock bank.
// Starting LCD DMA requires a real engine and is rejected rather than
// acknowledging a transfer that did not occur.
module ngage_icu_extra #(
    parameter PROBE_PREFETCH = 0
) (
    input  wire        clk,
    input  wire        reset,
    input  wire        req,
    input  wire        commit,
    input  wire        we,
    input  wire        periodic_active,
    input  wire [31:0] addr,
    input  wire [31:0] lookup_addr,
    input  wire [31:0] din,
    input  wire [ 3:0] sel,
    output reg         claim,
    output reg         bad,
    output reg  [31:0] dout,
    input  wire        cbus8d_written,
    output reg         sysc74_seen,
    output wire        ready
);
    wire [31:0] a = {addr[31:2], 2'b00};
    wire low = periodic_active && a >= 32'h0c120040 && a < 32'h0c120100 && a != 32'h0c120050 &&
        a != 32'h0c120064 && a != 32'h0c120068 && a != 32'h0c120074;
    wire dma = a >= 32'h0c120300 && a < 32'h0c120400;
    wire sysc74 = a == 32'h0c120074;
    wire probe14d = a >= 32'h0c14d000 && a <= 32'h0c14d010;
    wire epbus = a >= 32'h0c120600 && a < 32'h0c120700;
    // Warm reset zeros these programming latches. Scrub runs after reset
    // releases, independently of the board's cold-RAM init_done handshake.
    reg scrubbing = 1;
    reg [5:0] scrub_index = 0;
    reg read_valid = 0;
    reg [31:0] read_addr;
    wire [5:0] low_index = a[7:2] - 6'd16;
    wire [31:0] low_q, dma_q, epbus_q, probe_q;
    wire bank = low || dma || epbus;
    assign ready = !reset && !scrubbing && (!bank || we || bad || (read_valid && read_addr == a));
    wire bank_write = commit && claim && ready && !bad && we;
    // Low ICU offsets use rows 0..47. Store the five probe registers in
    // rows 48..52, which already clear during the low bank's warm scrub.
    wire [5:0] probe_index = {3'b110, a[4:2]};
    wire [31:0] low_lookup = PROBE_PREFETCH ? lookup_addr : a;
    wire lookup_probe = PROBE_PREFETCH &&
        low_lookup[31:5] == (32'h0c14d000 >> 5) && low_lookup[4:2] <= 4;
    wire [5:0] low_read_index = lookup_probe ? {3'b110, low_lookup[4:2]} : low_lookup[7:2] - 6'd16;
    wire [5:0] low_write_index = PROBE_PREFETCH && probe14d ? probe_index : low_index;
    wire [3:0] low_write_enable = reset ? 4'h0 : scrubbing ? 4'hf :
        bank_write && low ? 4'hf : bank_write && PROBE_PREFETCH && probe14d ? sel : 4'h0;
    ngage_bram #(
        .AW         (6),
        .DW         (32),
        .BYTE_WIDTH (8),
        .READ_ONLY_B(1)
    ) low_ram (
        .clk   (clk),
        .addr_a(scrubbing ? scrub_index : low_write_index),
        .data_a(scrubbing ? 32'b0 : din),
        .we_a  (low_write_enable),
        .q_a   (),
        .addr_b(low_read_index),
        .data_b(32'b0),
        .we_b  (4'b0),
        .q_b   (low_q)
    );
    ngage_bram #(
        .AW         (6),
        .DW         (32),
        .READ_ONLY_B(1)
    ) dma_ram (
        .clk   (clk),
        .addr_a(scrubbing ? scrub_index : a[7:2]),
        .data_a(scrubbing ? 32'b0 : din),
        .we_a  (!reset && (scrubbing || (bank_write && dma))),
        .q_a   (),
        .addr_b(a[7:2]),
        .data_b(32'b0),
        .we_b  (1'b0),
        .q_b   (dma_q)
    );
    ngage_bram #(
        .AW         (6),
        .DW         (32),
        .READ_ONLY_B(1)
    ) epbus_ram (
        .clk   (clk),
        .addr_a(scrubbing ? scrub_index : a[7:2]),
        .data_a(scrubbing ? 32'b0 : din),
        .we_a  (!reset && (scrubbing || (bank_write && epbus))),
        .q_a   (),
        .addr_b(a[7:2]),
        .data_b(32'b0),
        .we_b  (1'b0),
        .q_b   (epbus_q)
    );
    always @(posedge clk) begin
        if (reset) begin
            scrubbing   <= 1;
            scrub_index <= 0;
            read_valid  <= 0;
        end else begin
            if (scrubbing) begin
                if (scrub_index == 63) scrubbing <= 0;
                else scrub_index <= scrub_index + 1'b1;
            end
            read_valid <= req && !we && !scrubbing;
            read_addr  <= a;
        end
    end
    wire [31:0] mask = {{8{sel[3]}}, {8{sel[2]}}, {8{sel[1]}}, {8{sel[0]}}};
    generate
        if (PROBE_PREFETCH) begin : g_probe_ram
            assign probe_q = low_q;
        end else begin : g_probe_immediate
            // Unstaged callers can still inspect the addressed word in
            // the same cycle as presenting the request.
            reg     [31:0] probe_regs[0:4];
            integer        i;
            assign probe_q = probe_regs[a[4:2]];
            always @(posedge clk) begin
                if (reset) begin
                    for (i = 0; i < 5; i = i + 1) probe_regs[i] <= 0;
                end else if (bank_write && probe14d) begin
                    probe_regs[a[4:2]] <= (probe_q & ~mask) | (din & mask);
                end
            end
        end
    endgenerate
    always @* begin
        claim = req && (low || dma || epbus || sysc74 || probe14d);
        bad = claim && ((sysc74 && (!cbus8d_written || sel != 15 || !we || din != 3)) ||
                        (probe14d && !sysc74_seen) || (!probe14d && !sysc74 && sel != 15) ||
                        (dma && a == 32'h0c120348 && we && din == 2));
        dout = 0;
        if (claim && !bad) begin
            if (low) dout = low_q;
            else if (dma) dout = dma_q;
            else if (epbus) dout = epbus_q;
            else if (probe14d) dout = probe_q & mask;
        end
    end
    always @(posedge clk) begin
        if (reset) sysc74_seen <= 0;
        else if (bank_write && sysc74) sysc74_seen <= 1;
    end
endmodule
