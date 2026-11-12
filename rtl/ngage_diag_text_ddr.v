// Nonblocking committed guest debug bytes -> bounded FIFO -> DDR text ring.
// Up to12 bytes per32-byte record. Full queues drop bytes and count losses;
// there is no ready output to the phone and no dependence on a host reader.
module ngage_diag_text_ddr #(
    parameter         [31:0] BASE       = 32'h313f0000,
    parameter integer        CLOCK_HZ   = 78000000,
    parameter integer        RING_BITS  = 10,
    parameter integer        GAP_CYCLES = 256
) (
    input  wire        clk,
    input  wire        reset,
    input  wire        cpu_reset,
    input  wire        char_valid,
    input  wire [ 7:0] char_data,
    input  wire [31:0] cycles,
    output reg  [31:0] dropped = 0,
    output wire        req_valid,
    input  wire        req_ready,
    output wire        req_write,
    output wire [31:0] req_addr,
    output reg  [31:0] req_data,
    input  wire        rsp_valid,
    input  wire [31:0] rsp_data
);
    localparam [31:0] MAGIC = 32'h3154474e, SEAL = 32'h4354474e;
    localparam READ_MAGIC=0, MAGIC_WAIT=1, READ_SEQUENCE=2, SEQUENCE_WAIT=3,
        INIT=4, INIT_WAIT=5, PUBLISH=6, PUBLISH_WAIT=7, PACK=8,
        FIFO_READ=9, FIFO_CAPTURE=10, APPEND=11, INVALIDATE=12,
        INVALIDATE_WAIT=13, WRITE=14, WRITE_WAIT=15, COMMIT=16,
        COMMIT_WAIT=17, HEAD=18, HEAD_WAIT=19, LOSS=20, LOSS_WAIT=21;
    localparam integer GAP_BITS = GAP_CYCLES > 1 ? $clog2(GAP_CYCLES) : 1;
    reg [4:0] state = READ_MAGIC;
    reg [31:0] seq_number = 1, first_cycle = 0;
    reg [23:0] generation = 0, packet_generation = 0;
    reg reset_previous = 1, known_header = 0;
    reg [7:0] write_pointer = 0, read_pointer = 0;
    reg [ 8:0] fill = 0;
    reg [63:0] pending = 0;
    reg        pending_valid = 0;
    reg [95:0] payload = 0;
    reg [ 3:0] length = 0;
    reg [ 2:0] word_index = 0;
    localparam integer GAP_LAST = GAP_CYCLES - 1;
    reg  [GAP_BITS-1:0] gap = 0;
    wire [        63:0] fifo_data;
    wire                pop = state == FIFO_CAPTURE && !reset;
    wire                push = char_valid && !reset && (fill < 256 || pop);
    ngage_bram #(
        .AW         (8),
        .DW         (64),
        .READ_ONLY_B(1)
    ) fifo (
        .clk   (clk),
        .addr_a(write_pointer),
        .data_a({generation, char_data, cycles}),
        .we_a  (push),
        .q_a   (),
        .addr_b(read_pointer),
        .data_b(64'b0),
        .we_b  (1'b0),
        .q_b   (fifo_data)
    );
    function [31:0] advance;
        input [31:0] previous;
        reg     [31:0] n;
        integer        i;
        begin
            n = previous + 1'b1;
            for (i = 0; i < 2; i = i + 1) if (n == 0 || n == SEAL) n = n + 1'b1;
            advance = n;
        end
    endfunction
    wire reading = state == READ_MAGIC || state == READ_SEQUENCE;
    assign req_valid = !reset && (reading || state == INIT || state == PUBLISH ||
        state == INVALIDATE || state == WRITE || state == COMMIT || state == HEAD || state == LOSS);
    assign req_write = !reading;
    wire header_access = reading || state == INIT || state == PUBLISH || state == HEAD || state == LOSS;
    wire [31:0] header_offset = state == READ_SEQUENCE || state == HEAD ? 32'd12 :
        state == LOSS ? 32'd16 : state == INIT ? {27'b0,word_index,2'b0} : 32'b0;
    wire [31:0] record_offset = 32'h100 + ({{(32-RING_BITS){1'b0}},seq_number[RING_BITS-1:0]} << 5) +
        (state == WRITE ? {27'b0,word_index,2'b0} : 32'd28);
    assign req_addr = BASE + (header_access ? header_offset : record_offset);
    always @* begin
        req_data = 0;
        if (state == PUBLISH) req_data = MAGIC;
        else if (state == HEAD) req_data = seq_number;
        else if (state == LOSS) req_data = dropped;
        else if (state == COMMIT) req_data = seq_number ^ SEAL;
        else if (state == INIT) begin
            case (word_index)
                1:       req_data = 1;
                2:       req_data = 1 << RING_BITS;
                5:       req_data = seq_number;
                6:       req_data = CLOCK_HZ;
                7:       req_data = 32;
                default: req_data = 0;
            endcase
        end else if (state == WRITE) begin
            case (word_index)
                0:       req_data = seq_number;
                1:       req_data = first_cycle;
                2:       req_data = {packet_generation, 4'b0, length};
                3:       req_data = payload[31:0];
                4:       req_data = payload[63:32];
                5:       req_data = payload[95:64];
                6:       req_data = dropped;
                default: req_data = 0;
            endcase
        end
    end
    always @(posedge clk) begin
        if (reset) begin
            state             <= READ_MAGIC;
            seq_number        <= 1;
            first_cycle       <= 0;
            generation        <= 0;
            packet_generation <= 0;
            reset_previous    <= 1;
            known_header      <= 0;
            write_pointer     <= 0;
            read_pointer      <= 0;
            fill              <= 0;
            pending           <= 0;
            pending_valid     <= 0;
            payload           <= 0;
            length            <= 0;
            word_index        <= 0;
            gap               <= 0;
            dropped           <= 0;
        end else begin
            reset_previous <= cpu_reset;
            if (cpu_reset && !reset_previous) generation <= generation + 1'b1;
            if (char_valid && !push && dropped != 32'hffffffff) dropped <= dropped + 1'b1;
            if (push) write_pointer <= write_pointer + 1'b1;
            if (pop) read_pointer <= read_pointer + 1'b1;
            case ({
                push, pop
            })
                2'b10: fill <= fill + 1'b1;
                2'b01: fill <= fill - 1'b1;
                default: begin
                end
            endcase
            case (state)
                READ_MAGIC:    if (req_ready) state <= MAGIC_WAIT;
                MAGIC_WAIT:
                if (rsp_valid) begin
                    known_header <= rsp_data == MAGIC;
                    state        <= READ_SEQUENCE;
                end
                READ_SEQUENCE: if (req_ready) state <= SEQUENCE_WAIT;
                SEQUENCE_WAIT:
                if (rsp_valid) begin
                    seq_number <= known_header ? advance(rsp_data) : 1;
                    word_index <= 0;
                    state      <= INIT;
                end
                INIT:          if (req_ready) state <= INIT_WAIT;
                INIT_WAIT:
                if (rsp_valid) begin
                    if (word_index == 7) state <= PUBLISH;
                    else begin
                        word_index <= word_index + 1'b1;
                        state      <= INIT;
                    end
                end
                PUBLISH:       if (req_ready) state <= PUBLISH_WAIT;
                PUBLISH_WAIT:  if (rsp_valid) state <= PACK;
                PACK: begin
                    if (pending_valid) state <= APPEND;
                    else if (fill != 0) state <= FIFO_READ;
                    else if (length != 0) begin
                        if (gap == GAP_LAST[GAP_BITS-1:0]) state <= INVALIDATE;
                        else gap <= gap + 1'b1;
                    end
                end
                FIFO_READ:     state <= FIFO_CAPTURE;
                FIFO_CAPTURE: begin
                    pending       <= fifo_data;
                    pending_valid <= 1;
                    state         <= APPEND;
                end
                APPEND: begin
                    if (length != 0 && pending[63:40] != packet_generation) state <= INVALIDATE;
                    else begin
                        if (length == 0) begin
                            first_cycle       <= pending[31:0];
                            packet_generation <= pending[63:40];
                            payload           <= 0;
                        end
                        payload[length*8+:8] <= pending[39:32];
                        length <= length + 1'b1;
                        pending_valid <= 0;
                        gap <= 0;
                        state <= length == 11 || pending[39:32] == 10 ? INVALIDATE : PACK;
                    end
                end
                INVALIDATE:    if (req_ready) state <= INVALIDATE_WAIT;
                INVALIDATE_WAIT:
                if (rsp_valid) begin
                    word_index <= 0;
                    state      <= WRITE;
                end
                WRITE:         if (req_ready) state <= WRITE_WAIT;
                WRITE_WAIT:
                if (rsp_valid) begin
                    if (word_index == 6) state <= COMMIT;
                    else begin
                        word_index <= word_index + 1'b1;
                        state      <= WRITE;
                    end
                end
                COMMIT:        if (req_ready) state <= COMMIT_WAIT;
                COMMIT_WAIT:   if (rsp_valid) state <= HEAD;
                HEAD:          if (req_ready) state <= HEAD_WAIT;
                HEAD_WAIT:     if (rsp_valid) state <= LOSS;
                LOSS:          if (req_ready) state <= LOSS_WAIT;
                LOSS_WAIT:
                if (rsp_valid) begin
                    seq_number <= advance(seq_number);
                    length     <= 0;
                    gap        <= 0;
                    state      <= PACK;
                end
                default:       state <= READ_MAGIC;
            endcase
        end
    end
endmodule
