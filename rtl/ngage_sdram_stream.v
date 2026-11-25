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
    // Read-only offer from this clock's irrevocable scalar arbiter grant.
    input  wire         grant_read,
    input  wire [ 24:0] grant_addr,
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
    input  wire         mem_cmd_ready,
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
    (* dont_retime *)reg        read_reply = 0;
    (* dont_retime *)reg [31:0] read_data;

    reg  [24:0] scrub_address = 0;
    reg         scrub_last_issued = 0;
    // Scrub the full guest RAM while the phone is still held in reset.
    wire        scrub_packet = !scrub_last_issued;
    wire        scrub = mem_ready && !cold && scrub_packet && mem_cmd_ready;

    assign owner_ready = scrub_done && mem_ready && !cold && !phone_reset && !discard;
    wire idle = state == IDLE && owner_ready;
    wire scalar = idle && req && !seen;
    wire take_pending = pending && mem_cmd_ready;
    wire post = scalar && we && !lock && (!pending || take_pending);
    wire direct_post = post && !pending && mem_cmd_ready;
    wire scalar_read = scalar && !we && !pending && mem_cmd_ready;
    wire lock_write = scalar && we && lock && !pending && mem_cmd_ready;
    // A scalar reply retires to the held arbiter owner while an independent
    // line can take the command slot. The scalar grant still waits for !req.
    wire scalar_port_free = !req || read_reply;
    assign line_ready = idle && scalar_port_free && !pending && mem_cmd_ready;
    wire first_line = line_req && line_ready;
    // The arbiter captures the owner on this same edge. If a line or an
    // older packet owns the slot, the arbiter's held read can issue later.
    wire grant_read_word = idle && !req && !pending && mem_cmd_ready && grant_read && !first_line;
    wire read_word = scalar_read || grant_read_word;
    wire line_owned = state == LINE;
    wire line_follow = line_owned && second_line && mem_cmd_ready;

    assign mem_req = scrub || take_pending || direct_post || read_word || lock_write || first_line || line_follow;
    assign mem_we = scrub || take_pending || direct_post || lock_write;
    wire write_is_block = pending ? pending_block : write_block;
    assign mem_line  = scrub || first_line || line_follow || (mem_we && write_is_block);
    assign mem_short = first_line && line_short;
    // Select packet fields from their owner while arbitration decides
    // whether they can be captured. A read address never selects write lanes.
    wire [24:2] first_addr = line_short ? {line_addr[24:4], 2'b00} : {line_addr[24:5], 3'b000};
    assign mem_addr = scrub_packet ? scrub_address[24:2] :
                      pending ? pending_addr :
                      line_owned ? {saved_line, 3'b100} :
                      (scalar_port_free && line_req) ? first_addr :
                      req ? addr[24:2] : grant_addr[24:2];
    wire [ 31:0] word_data = pending ? pending_data : din;
    wire [127:0] line_write_data = pending ? pending_block_data : block_data;
    assign mem_wdata = scrub_packet ? 128'b0 : write_is_block ? line_write_data : {4{word_data}};
    wire [3:0] write_mask = pending ? pending_be : be;
    wire [1:0] write_lane = pending ? pending_addr[3:2] : addr[3:2];
    assign mem_wbe = (scrub_packet || write_is_block) ? 16'hffff : {12'b0, write_mask} << {write_lane, 2'b00};

    assign dout = read_data;
    wire word_done = state == READ_WORD && mem_valid;
    wire locked_done = state == WRITE_LOCKED && !mem_busy;
    assign ack = owner_ready && (post || read_reply || locked_done);

    assign line_valid = state == LINE && owner_ready && (high_word || mem_valid);
    assign line_data  = high_word ? high_data : mem_rdata[15:0];
    assign line_last  = line_valid && high_word && words_seen == line_words;
    wire scalar_accept = post || read_word || lock_write;
    wire drained = state == IDLE && !pending && !mem_busy;

    // Sample data and its reply on the same edge. ACK qualifies which data
    // belongs to a scalar read; lines retain their early halfword path.
    always @(posedge clk) read_data <= mem_rdata;

    always @(posedge clk) begin
        if (cold) begin
            scrub_done        <= 0;
            scrub_last_issued <= 0;
            scrub_address     <= 0;
            state             <= IDLE;
            seen              <= 0;
            discard           <= 0;
            pending           <= 0;
            read_reply        <= 0;
            second_line       <= 0;
            high_word         <= 0;
            words_seen        <= 0;
        end else begin
            read_reply <= word_done && owner_ready;
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
