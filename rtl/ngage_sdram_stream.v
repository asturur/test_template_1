// SPDX-License-Identifier: GPL-2.0-or-later
// Pipelined scalar and refill port shared by the CPU, LCD and DMA.
module ngage_sdram_stream #(
    parameter        WIDE_PORT   = 1,
    parameter [24:0] SCRUB_BYTES = 25'h1000000
) (
    input  wire         clk,
    input  wire         cold,
    input  wire         phone_reset,
    // Lock sampled with this scalar packet by the bus owner.
    input  wire         lock,
    output wire         owner_ready,
    input  wire         req,
    input  wire         we,
    input  wire         write_block,
    input  wire [127:0] block_data,
    input  wire [ 24:0] addr,
    input  wire [ 31:0] din,
    input  wire [  3:0] be,
    output wire         ack,
    output wire [ 31:0] dout,
    input  wire         line_req,
    input  wire         line_short,
    input  wire [ 24:0] line_addr,
    output wire         line_ready,
    output wire         line_valid,
    output wire [ 15:0] line_data,
    output wire         line_last,
    output wire         mem_req,
    output wire         mem_we,
    output wire         mem_line,
    output wire         mem_short,
    output wire [ 24:2] mem_addr,
    output wire [127:0] mem_wdata,
    output wire [ 15:0] mem_wbe,
    output reg          scrub_done = 0,
    input  wire         mem_ready,
    input  wire         mem_busy,
    input  wire         mem_valid,
    input  wire [ 31:0] mem_rdata
);
    localparam IDLE = 0, READ_WORD = 1, WRITE_LOCKED = 2, LINE = 3;
    reg [1:0] state = IDLE;
    reg seen = 0, discard = 0;
    reg         pending = 0;
    reg [ 24:2] pending_addr;
    reg [ 31:0] pending_data;
    reg [  3:0] pending_be;
    reg         pending_block;
    reg [127:0] pending_block_data;
    reg second_line = 0, high_word = 0;
    reg [24:5] saved_line;
    reg [3:0] words_seen = 0, line_words = 0;
    reg [15:0] high_data;

    reg  [24:0] scrub_address = 0;
    reg         scrub_last_issued = 0;
    // Scrub the full guest RAM while the phone is still held in reset.
    wire        scrub = mem_ready && !cold && !scrub_last_issued && !mem_busy;

    assign owner_ready = scrub_done && mem_ready && !cold && !phone_reset && !discard;
    wire idle = state == IDLE && owner_ready;
    wire scalar = idle && req && !seen;
    wire take_pending = pending && !mem_busy;
    wire post = scalar && we && !lock && (!pending || take_pending);
    wire direct_post = post && !pending && !mem_busy;
    wire read_word = scalar && !we && !pending && !mem_busy;
    wire lock_write = scalar && we && lock && !pending && !mem_busy;
    assign line_ready = idle && !req && !pending && !mem_busy;
    wire first_line = line_req && line_ready;
    wire line_follow = state == LINE && second_line && !mem_busy;

    assign mem_req = scrub || take_pending || direct_post || read_word || lock_write || first_line || line_follow;
    assign mem_we = scrub || take_pending || direct_post || lock_write;
    wire block_write = take_pending ? pending_block : (direct_post || lock_write) && write_block;
    assign mem_line  = scrub || first_line || line_follow || block_write;
    assign mem_short = first_line && line_short;
    wire [24:2] first_addr = line_short ? {line_addr[24:4], 2'b00} : {line_addr[24:5], 3'b000};
    assign mem_addr = scrub ? scrub_address[24:2] :
                      take_pending ? pending_addr :
                      first_line ? first_addr :
                      line_follow ? {saved_line, 3'b100} : addr[24:2];
    assign mem_wdata = scrub ? 128'b0 :
                       block_write ? (take_pending ? pending_block_data : block_data) :
                       {4{take_pending ? pending_data : din}};
    wire [3:0] write_mask = take_pending ? pending_be : be;
    assign mem_wbe = (scrub || block_write) ? 16'hffff : {12'b0, write_mask} << {mem_addr[3:2], 2'b00};

    assign dout = mem_rdata;
    wire word_done = state == READ_WORD && mem_valid;
    wire locked_done = state == WRITE_LOCKED && !mem_busy;
    assign ack = owner_ready && (post || word_done || locked_done);

    assign line_valid = state == LINE && owner_ready && (high_word || mem_valid);
    assign line_data  = high_word ? high_data : mem_rdata[15:0];
    assign line_last  = line_valid && high_word && words_seen == line_words;
    wire scalar_accept = post || read_word || lock_write;
    wire drained = state == IDLE && !pending && !mem_busy;

    always @(posedge clk) begin
        if (cold) begin
            scrub_done        <= 0;
            scrub_last_issued <= 0;
            scrub_address     <= 0;
            state             <= IDLE;
            seen              <= 0;
            discard           <= 0;
            pending           <= 0;
            second_line       <= 0;
            high_word         <= 0;
            words_seen        <= 0;
        end else begin
            if (scrub) begin
                if (scrub_address + 25'd16 >= SCRUB_BYTES) scrub_last_issued <= 1;
                else scrub_address <= scrub_address + 25'd16;
            end
            if (scrub_last_issued && !mem_busy) scrub_done <= 1;

            if (!req) seen <= 0;
            if (scalar_accept) seen <= 1;
            if (phone_reset && (pending || state != IDLE)) discard <= 1;
            if (drained) discard <= 0;

            if (take_pending) pending <= 0;
            // The queue owns the payload from the posted ACK through physical
            // admission, even if the phone resets or upstream changes owners.
            if (post && !direct_post) begin
                pending       <= 1;
                pending_addr  <= addr[24:2];
                pending_data  <= din;
                pending_be    <= be;
                pending_block <= write_block;
                if (write_block) pending_block_data <= block_data;
            end

            if (read_word) state <= READ_WORD;
            if (lock_write) state <= WRITE_LOCKED;
            if (word_done || locked_done) state <= IDLE;
            if (first_line) begin
                state       <= LINE;
                saved_line  <= line_addr[24:5];
                second_line <= !WIDE_PORT && !line_short;
                line_words  <= line_short ? 4'd4 : 4'd8;
                words_seen  <= 0;
            end
            if (line_follow) second_line <= 0;
            if (high_word) begin
                high_word <= 0;
                if (words_seen == line_words) state <= IDLE;
            end
            if (state == LINE && mem_valid) begin
                words_seen <= words_seen + 1'b1;
                high_word  <= 1;
                high_data  <= mem_rdata[31:16];
            end
        end
    end
endmodule
