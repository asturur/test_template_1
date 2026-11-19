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
    localparam         [32:0] LINE_WORDS      = LINE_BYTES == 16 ? 33'd4 : 33'd8;
    localparam         [ 3:0] LINE_LAST_BEAT  = LINE_BYTES == 16 ? 4'd7 : 4'd15;
    localparam integer        LINE_INDEX_BITS = LINE_BYTES == 16 ? 2 : 3;
    wire        line_enabled = LINE_BYTES != 0;
    reg  [24:0] next_addr;
    reg  [32:0] remaining;
    reg         owned;
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
    wire offer = busy && !cancelling && !stop && !sink_failed && remaining != 0 &&
                 (!skid_valid || pixel_take);
    wire buffer_pending = line_enabled && words_received != words_emitted;
    wire line_aligned = next_addr[3:0] == 0 && (LINE_BYTES == 16 || !next_addr[4]);
    wire choose_line = line_enabled && line_aligned && remaining >= LINE_WORDS;
    wire buffer_take = buffer_pending && (!skid_valid || pixel_take);
    assign line_req = line_enabled && !reset && offer && choose_line &&
                      !owned && !line_owned && !buffer_pending;
    assign line_addr = next_addr;
    wire take_line = line_req && line_ready;
    wire line_finished = line_enabled && line_owned && line_valid && line_last;
    assign mem_req = !reset && (owned || (offer && !choose_line && !line_owned && !buffer_pending));
    assign mem_addr = next_addr;
    wire accepted = mem_req && !owned && mem_accept;
    wire response = mem_ack && (owned || accepted);

    always @(posedge clk) begin
        if (reset) begin
            busy           <= 0;
            done           <= 0;
            error          <= 0;
            aborted        <= 0;
            next_addr      <= 0;
            remaining      <= 0;
            owned          <= 0;
            skid_valid     <= 0;
            skid_data      <= 0;
            cancel_abort   <= 0;
            cancel_error   <= 0;
            line_owned     <= 0;
            line_beat      <= 0;
            words_received <= 0;
            words_emitted  <= 0;
        end else begin
            done    <= 0;
            error   <= 0;
            aborted <= 0;
            if (!busy) begin
                if (transfer_valid && transfer_ready) begin
                    if (!descriptor_ok) error <= 1;
                    else begin
                        busy         <= 1;
                        next_addr    <= source_addr[24:0];
                        remaining    <= transfer_words;
                        owned        <= 0;
                        skid_valid   <= 0;
                        cancel_abort <= 0;
                        cancel_error <= 0;
                    end
                end
            end else begin
                if (take_line) begin
                    line_owned     <= 1;
                    line_beat      <= 0;
                    words_received <= 0;
                    words_emitted  <= 0;
                    next_addr      <= next_addr + LINE_BYTES[24:0];
                    remaining      <= remaining - LINE_WORDS;
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
                if (accepted) owned <= 1;
                if (response) begin
                    owned     <= 0;
                    next_addr <= next_addr + 25'd4;
                    remaining <= remaining - 1'b1;
                end

                // Stop wins over the last pixel and the last memory response.
                // An accepted read drains before either cancellation terminal.
                if (stop || cancelling || sink_failed) begin
                    skid_valid <= 0;
                    if (stop) cancel_abort <= 1;
                    if (sink_failed) cancel_error <= 1;
                    words_received <= 0;
                    words_emitted  <= 0;
                    if (((!owned && !accepted) || response) &&
                        (!(line_owned || take_line) || line_finished)) begin
                        busy         <= 0;
                        remaining    <= 0;
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
                    if (pixel_take && remaining == 0 && !owned && !line_owned && !buffer_pending) begin
                        busy <= 0;
                        done <= 1;
                    end
                end
            end
        end
    end
    // synthesis translate_off
    always @(posedge clk)
        if (line_enabled && !reset && line_owned && line_valid && line_last != (line_beat == LINE_LAST_BEAT))
            $fatal(1, "LCD line ended at the wrong halfword");
    // synthesis translate_on
endmodule
