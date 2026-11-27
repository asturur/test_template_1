// Transaction-level LCD read shortcut. This models no physical LCD timing.
// The caller owns descriptors/registers/IRQs and fences the display queue tail.
// SDRAM requests remain asserted from acceptance through the owned response.
// Reset must also reset/drain the connected arbiter: no transaction ID exists.
module ngage_lcd_stream #(
    parameter integer LINE_BYTES = 0
) (
    input  wire        clk,
    input  wire        reset,
    input  wire        transfer_valid,
    output wire        transfer_ready,
    input  wire [31:0] source_addr,
    input  wire [32:0] transfer_words,
    input  wire        stop,
    output reg         busy,
    output reg         done,
    output reg         error,
    output reg         aborted,
    output wire        mem_req,
    output wire [24:0] mem_addr,
    input  wire        mem_accept,
    input  wire        mem_ack,
    input  wire [31:0] mem_data,
    output wire        line_req,
    output wire [24:0] line_addr,
    input  wire        line_ready,
    input  wire        line_valid,
    input  wire [15:0] line_data,
    input  wire        line_last,
    output wire        pixel_valid,
    output wire [31:0] pixel_data,
    input  wire        pixel_ready,
    input  wire        pixel_error
);
    localparam         [22:0] LINE_WORDS      = LINE_BYTES == 16 ? 23'd4 : 23'd8;
    localparam         [ 3:0] LINE_LAST_BEAT  = LINE_BYTES == 16 ? 4'd7 : 4'd15;
    localparam integer        LINE_INDEX_BITS = LINE_BYTES == 16 ? 2 : 3;
    wire        line_enabled = LINE_BYTES != 0;
    reg  [24:0] next_addr;
    // A validated descriptor fits within 16 MiB (at most 2^22 words).
    reg  [22:0] remaining;
    // The count excludes the packet in the reservation and any issued read.
    (* dont_retime *)reg         words_available;
    (* dont_retime *)reg         line_available;
    (* dont_retime *)reg         reserved;
    (* dont_retime *)reg         reserved_line;
    (* dont_retime *)reg  [24:0] reserved_addr;
    reg         owned;
    reg  [24:0] owned_addr;
    reg         skid_valid;
    reg  [31:0] skid_data;
    reg         cancel_abort;
    reg         cancel_error;
    reg         line_owned;
    reg  [ 3:0] line_beat;
    reg  [15:0] line_low;
    reg [3:0] words_received, words_emitted;
    reg [31:0] line_words[0:(1 << LINE_INDEX_BITS)-1];

    // Keep the entire literal 33-bit word count through the range calculation.
    // One extra carry bit prevents the largest 35-bit byte extent wrapping.
    wire [35:0] end_addr = {4'b0000, source_addr} + {1'b0, transfer_words, 2'b00};
    wire descriptor_ok = source_addr >= 32'h0a000000 && source_addr < 32'h0b000000 &&
                         source_addr[1:0] == 0 && transfer_words != 0 &&
                         end_addr <= 36'h00b000000;
    wire cancelling = cancel_abort || cancel_error;
    assign transfer_ready = !reset && !busy;
    assign pixel_valid    = !reset && busy && skid_valid && !cancelling && !stop;
    assign pixel_data     = skid_data;
    wire pixel_take = pixel_valid && pixel_ready;
    wire sink_failed = pixel_take && pixel_error;
    wire offer = busy && reserved && !cancelling && !stop && !sink_failed &&
                 (!skid_valid || pixel_take);
    wire buffer_pending = line_enabled && words_received != words_emitted;
    function aligned_line;
        input [24:0] address;
        aligned_line = line_enabled && address[3:0] == 0 && (LINE_BYTES == 16 || !address[4]);
    endfunction
    wire first_line = aligned_line(source_addr[24:0]) && transfer_words[22:0] >= LINE_WORDS;
    wire next_line = aligned_line(next_addr) && line_available;
    wire buffer_take = buffer_pending && (!skid_valid || pixel_take);
    assign line_req = line_enabled && !reset && offer && reserved_line &&
                      !owned && !line_owned && !buffer_pending;
    assign line_addr = reserved_addr;
    wire take_line = line_req && line_ready;
    wire line_finished = line_enabled && line_owned && line_valid && line_last;
    assign mem_req = !reset && (owned || (offer && !reserved_line && !line_owned && !buffer_pending));
    assign mem_addr = owned ? owned_addr : reserved_addr;
    wire accepted = mem_req && !owned && mem_accept;
    wire response = mem_ack && (owned || accepted);

    always @(posedge clk) begin
        if (reset) begin
            busy            <= 0;
            done            <= 0;
            error           <= 0;
            aborted         <= 0;
            next_addr       <= 0;
            remaining       <= 0;
            words_available <= 0;
            line_available  <= 0;
            reserved        <= 0;
            reserved_line   <= 0;
            reserved_addr   <= 0;
            owned           <= 0;
            owned_addr      <= 0;
            skid_valid      <= 0;
            skid_data       <= 0;
            cancel_abort    <= 0;
            cancel_error    <= 0;
            line_owned      <= 0;
            line_beat       <= 0;
            words_received  <= 0;
            words_emitted   <= 0;
        end else begin
            done    <= 0;
            error   <= 0;
            aborted <= 0;
            if (!busy) begin
                if (transfer_valid && transfer_ready) begin
                    if (!descriptor_ok) error <= 1;
                    else begin
                        busy <= 1;
                        reserved <= 1;
                        reserved_line <= first_line;
                        reserved_addr <= source_addr[24:0];
                        next_addr <= source_addr[24:0] + (first_line ? LINE_BYTES[24:0] : 25'd4);
                        remaining <= transfer_words[22:0] - (first_line ? LINE_WORDS : 23'd1);
                        words_available <= transfer_words[22:0] != (first_line ? LINE_WORDS : 23'd1);
                        line_available  <= first_line ? transfer_words[22:0] >= (LINE_WORDS << 1) :
                                                         transfer_words[22:0] > LINE_WORDS;
                        owned <= 0;
                        skid_valid <= 0;
                        cancel_abort <= 0;
                        cancel_error <= 0;
                    end
                end
            end else begin
                // Reserve ahead while the preceding read drains. This count
                // update depends only on local state, even under contention.
                if (!reserved && words_available) begin
                    reserved <= 1;
                    reserved_line <= next_line;
                    reserved_addr <= next_addr;
                    next_addr <= next_addr + (next_line ? LINE_BYTES[24:0] : 25'd4);
                    remaining <= remaining - (next_line ? LINE_WORDS : 23'd1);
                    words_available <= remaining != (next_line ? LINE_WORDS : 23'd1);
                    line_available  <= next_line ? remaining >= (LINE_WORDS << 1) : remaining > LINE_WORDS;
                end
                if (take_line) begin
                    reserved       <= 0;
                    line_owned     <= 1;
                    line_beat      <= 0;
                    words_received <= 0;
                    words_emitted  <= 0;
                end
                if (line_enabled && line_owned && line_valid) begin
                    line_beat <= line_beat + 1'b1;
                    if (!line_beat[0]) line_low <= line_data;
                    else begin
                        line_words[line_beat[LINE_INDEX_BITS:1]] <= {line_data, line_low};
                        words_received                           <= words_received + 1'b1;
                    end
                    if (line_last) line_owned <= 0;
                end
                if (accepted) begin
                    reserved   <= 0;
                    owned      <= 1;
                    owned_addr <= reserved_addr;
                end
                if (response) owned <= 0;

                // Stop wins over the last pixel and the last memory response.
                // An accepted read drains before either cancellation terminal.
                if (stop || cancelling || sink_failed) begin
                    skid_valid      <= 0;
                    reserved        <= 0;
                    remaining       <= 0;
                    words_available <= 0;
                    line_available  <= 0;
                    if (stop) cancel_abort <= 1;
                    if (sink_failed) cancel_error <= 1;
                    words_received <= 0;
                    words_emitted  <= 0;
                    if (((!owned && !accepted) || response) &&
                        (!(line_owned || take_line) || line_finished)) begin
                        busy         <= 0;
                        cancel_abort <= 0;
                        cancel_error <= 0;
                        if (stop || cancel_abort) aborted <= 1;
                        else error <= 1;
                    end
                end else begin
                    if (pixel_take) skid_valid <= 0;
                    if (response) begin
                        skid_valid <= 1;
                        skid_data  <= mem_data;
                    end
                    if (buffer_take) begin
                        skid_valid    <= 1;
                        skid_data     <= line_words[words_emitted[LINE_INDEX_BITS-1:0]];
                        words_emitted <= words_emitted + 1'b1;
                    end
                    if (pixel_take && !words_available && !reserved &&
                        !owned && !line_owned && !buffer_pending) begin
                        busy <= 0;
                        done <= 1;
                    end
                end
            end
        end
    end
    // synthesis translate_off
    always @(posedge clk) begin
        if (!reset) begin
            if (words_available != (remaining != 0) || line_available != (remaining >= LINE_WORDS))
                $fatal(1, "LCD request eligibility disagrees with the remaining count");
            if (line_enabled && line_owned && line_valid && line_last != (line_beat == LINE_LAST_BEAT))
                $fatal(1, "LCD line ended at the wrong halfword");
        end
    end
    // synthesis translate_on
endmodule
