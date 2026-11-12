// Periodic read-only observations exported into two committed DDR3 records.
// One M10K snapshots a bounded frame; capture never backpressures guest writes.
// Layout and sequence/commit rules: docs/ddr-diagnostics.md.
module ngage_diag_ddr #(
    parameter         [31:0] BASE      = 32'h313ff000,
    parameter integer        CLOCK_HZ  = 78000000,
    parameter integer        PERIOD    = CLOCK_HZ / 4,
    parameter         [63:0] BUILD_TAG = 0
) (
    input  wire         clk,
    input  wire         reset,
    input  wire         cpu_reset,
    input  wire         allow_capture,
    input  wire [767:0] values,
    output wire         capture_active,
    output wire [ 10:0] debug_word,
    input  wire [ 15:0] debug_data,
    output wire         req_valid,
    input  wire         req_ready,
    output wire         req_write,
    output wire [ 31:0] req_addr,
    output wire [ 31:0] req_data,
    input  wire         rsp_valid,
    input  wire [ 31:0] rsp_data
);
    localparam [31:0] MAGIC = 32'h3244474e, SEAL = 32'h4344474e;
    localparam BOOT0=0, BOOT0_WAIT=1, BOOT1=2, BOOT1_WAIT=3,
        CLEAR0=4, CLEAR0_WAIT=5, CLEAR1=6, CLEAR1_WAIT=7,
        IDLE=8, MONITOR=9, DEBUG_WAIT=10, DEBUG_SAMPLE=11,
        TAIL=12, END_CAPTURE=13, INVALIDATE=14, INVALIDATE_WAIT=15,
        LOAD=16, OFFER=17, WRITE_WAIT=18, COMMIT=19, COMMIT_WAIT=20;
    localparam integer PERIOD_BITS = PERIOD > 1 ? $clog2(PERIOD) : 1;
    reg [4:0] state = BOOT0;
    localparam integer PERIOD_RELOAD = PERIOD - 1;
    reg [PERIOD_BITS-1:0] period_left = 0;
    reg [31:0] seq_number = 0, seed = 0, generation = 0, start_cycle = 0, end_cycle = 0;
    reg reset_previous = 1;
    reg [7:0] index = 0;
    reg [8:0] half_index = 0;
    reg [15:0] low_half = 0;
    wire [31:0] cycles = values[159:128];
    wire [31:0] snapshot_q;
    reg [31:0] snapshot_data;
    wire snapshot_write = state == MONITOR || (state == DEBUG_SAMPLE && half_index[0]) ||
        state == TAIL || state == END_CAPTURE;
    wire [7:0] snapshot_address = state == END_CAPTURE ? 8'd5 :
        state == DEBUG_SAMPLE ? 8'd32 + half_index[8:1] : index;
    assign capture_active = state == MONITOR || state == DEBUG_WAIT ||
        state == DEBUG_SAMPLE || state == TAIL || state == END_CAPTURE;
    assign debug_word = {2'b0, half_index};
    always @* begin
        snapshot_data = 0;
        if (state == DEBUG_SAMPLE) snapshot_data = {debug_data, low_half};
        else if (state == END_CAPTURE) snapshot_data = end_cycle;
        else if (state == MONITOR) begin
            case (index)
                0:       snapshot_data = MAGIC;
                1:       snapshot_data = 1;
                2:       snapshot_data = seq_number;
                3:       snapshot_data = CLOCK_HZ;
                4:       snapshot_data = start_cycle;
                5:       snapshot_data = 0;
                6:       snapshot_data = generation;
                7:       snapshot_data = 32'd406;
                default: snapshot_data = values[(index-8)*32+:32];
            endcase
        end else if (state == TAIL) begin
            case (index)
                240:     snapshot_data = BUILD_TAG[31:0];
                241:     snapshot_data = BUILD_TAG[63:32];
                default: snapshot_data = 0;
            endcase
        end
    end
    ngage_bram #(
        .AW         (8),
        .DW         (32),
        .READ_ONLY_B(1)
    ) snapshot (
        .clk   (clk),
        .addr_a(snapshot_address),
        .data_a(snapshot_data),
        .we_a  (!reset && snapshot_write),
        .q_a   (),
        .addr_b(index),
        .data_b(32'b0),
        .we_b  (1'b0),
        .q_b   (snapshot_q)
    );
    wire boot_read = state == BOOT0 || state == BOOT1;
    wire clear_first = state == CLEAR0;
    wire clear_second = state == CLEAR1;
    wire clear_record = state == INVALIDATE || clear_first || clear_second;
    assign req_valid = !reset && (boot_read || clear_record || state == OFFER || state == COMMIT);
    assign req_write = !boot_read;
    wire slot = state == BOOT0 || clear_first ? 1'b0 :
        state == BOOT1 || clear_second ? 1'b1 : seq_number[0];
    assign req_addr = BASE + {21'b0, slot, 10'b0} +
        (state == OFFER ? {22'b0, index, 2'b0} : 32'd1020);
    assign req_data = clear_record ? 32'b0 : state == COMMIT ? seq_number ^ SEAL : snapshot_q;
    wire accepted = req_valid && req_ready;
    function [31:0] advance;
        input [31:0] previous;
        reg     [31:0] next_value;
        integer        n;
        begin
            next_value = previous + 1'b1;
            for (n = 0; n < 2; n = n + 1)
            if (next_value == 0 || next_value == SEAL) next_value = next_value + 1'b1;
            advance = next_value;
        end
    endfunction
    always @(posedge clk) begin
        if (reset) begin
            state          <= BOOT0;
            seq_number     <= 0;
            seed           <= 0;
            generation     <= 0;
            reset_previous <= 1;
            period_left    <= 0;
            index          <= 0;
            half_index     <= 0;
            low_half       <= 0;
            start_cycle    <= 0;
            end_cycle      <= 0;
        end else begin
            reset_previous <= cpu_reset;
            if (cpu_reset && !reset_previous) generation <= generation + 1'b1;
            if (period_left != 0) period_left <= period_left - 1'b1;
            case (state)
                BOOT0:           if (accepted) state <= BOOT0_WAIT;
                BOOT0_WAIT:
                if (rsp_valid) begin
                    seed  <= rsp_data == 0 ? 0 : rsp_data ^ SEAL;
                    state <= BOOT1;
                end
                BOOT1:           if (accepted) state <= BOOT1_WAIT;
                BOOT1_WAIT:
                if (rsp_valid) begin
                    // Continue beyond retained seals across core reloads; do
                    // not reuse a recently committed seq_number after reset.
                    if (rsp_data != 0 && (rsp_data ^ SEAL) > seed)
                        seq_number <= advance(rsp_data ^ SEAL);
                    else seq_number <= advance(seed);
                    state <= CLEAR0;
                end
                CLEAR0:          if (accepted) state <= CLEAR0_WAIT;
                CLEAR0_WAIT:     if (rsp_valid) state <= CLEAR1;
                CLEAR1:          if (accepted) state <= CLEAR1_WAIT;
                CLEAR1_WAIT:     if (rsp_valid) state <= IDLE;
                IDLE:
                if (period_left == 0 && allow_capture) begin
                    start_cycle <= cycles;
                    index       <= 0;
                    half_index  <= 0;
                    period_left <= PERIOD_RELOAD[PERIOD_BITS-1:0];
                    state       <= MONITOR;
                end
                MONITOR: begin
                    if (index == 31) state <= DEBUG_WAIT;
                    else index <= index + 1'b1;
                end
                DEBUG_WAIT:      state <= DEBUG_SAMPLE;
                DEBUG_SAMPLE: begin
                    if (!half_index[0]) low_half <= debug_data;
                    if (half_index == 405) begin
                        end_cycle <= cycles;
                        index     <= 235;
                        state     <= TAIL;
                    end else begin
                        half_index <= half_index + 1'b1;
                        state      <= DEBUG_WAIT;
                    end
                end
                TAIL:            if (index == 254) state <= END_CAPTURE;
 else index <= index + 1'b1;
                END_CAPTURE: begin
                    index <= 0;
                    state <= INVALIDATE;
                end
                INVALIDATE:      if (accepted) state <= INVALIDATE_WAIT;
                INVALIDATE_WAIT: if (rsp_valid) state <= LOAD;
                LOAD:            state <= OFFER;
                OFFER:           if (accepted) state <= WRITE_WAIT;
                WRITE_WAIT:
                if (rsp_valid) begin
                    if (index == 254) state <= COMMIT;
                    else begin
                        index <= index + 1'b1;
                        state <= LOAD;
                    end
                end
                COMMIT:          if (accepted) state <= COMMIT_WAIT;
                COMMIT_WAIT:
                if (rsp_valid) begin
                    seq_number <= advance(seq_number);
                    state      <= IDLE;
                end
                default:         state <= BOOT0;
            endcase
        end
    end
endmodule

// Share the existing service-loader requester. No extra arbiter or pipeline
// is placed in the CPU/flash path. Responses follow the accepted owner even
// when a new firmware download starts while telemetry is outstanding.
module ngage_diag_loader_port (
    input  wire        clk,
    input  wire        reset,
    input  wire        load_valid,
    output wire        load_ready,
    input  wire [31:0] load_addr,
    input  wire [31:0] load_data,
    input  wire [ 3:0] load_be,
    output wire        load_done,
    input  wire        diag_valid,
    output wire        diag_ready,
    input  wire        diag_write,
    input  wire [31:0] diag_addr,
    input  wire [31:0] diag_data,
    output wire        diag_done,
    output wire [31:0] diag_rdata,
    output wire        mem_valid,
    input  wire        mem_ready,
    output wire        mem_write,
    output wire [31:0] mem_addr,
    output wire [31:0] mem_data,
    output wire [ 3:0] mem_be,
    input  wire        mem_done,
    input  wire [31:0] mem_rdata
);
    reg outstanding = 0, owner_diag = 0;
    assign mem_valid  = !reset && !outstanding && (load_valid || diag_valid);
    assign mem_write  = load_valid || diag_write;
    assign mem_addr   = load_valid ? load_addr : diag_addr;
    assign mem_data   = load_valid ? load_data : diag_data;
    assign mem_be     = load_valid ? load_be : 4'hf;
    assign load_ready = mem_valid && load_valid && mem_ready;
    assign diag_ready = mem_valid && !load_valid && mem_ready;
    assign load_done  = !reset && outstanding && !owner_diag && mem_done;
    assign diag_done  = !reset && outstanding && owner_diag && mem_done;
    assign diag_rdata = mem_rdata;
    always @(posedge clk) begin
        if (reset) begin
            outstanding <= 0;
            owner_diag  <= 0;
        end else begin
            if (mem_valid && mem_ready) begin
                outstanding <= 1;
                owner_diag  <= !load_valid;
            end
            if (mem_done) outstanding <= 0;
        end
    end
endmodule
