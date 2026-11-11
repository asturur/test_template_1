// Transaction-level LCD read shortcut. This models no physical LCD timing.
// The caller owns descriptors/registers/IRQs and fences the display queue tail.
// SDRAM requests remain asserted from acceptance through the owned response.
// Reset must also reset/drain the connected arbiter: no transaction ID exists.
module ngage_lcd_stream (
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
    output wire        pixel_valid,
    output wire [31:0] pixel_data,
    input  wire        pixel_ready,
    input  wire        pixel_error
);
    reg [24:0] next_addr;
    reg [32:0] remaining;
    reg        owned;
    reg        skid_valid;
    reg [31:0] skid_data;
    reg        cancel_abort;
    reg        cancel_error;

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
    assign mem_req  = !reset && (owned || offer);
    assign mem_addr = next_addr;
    wire accepted = mem_req && !owned && mem_accept;
    wire response = mem_ack && (owned || accepted);

    always @(posedge clk) begin
        if (reset) begin
            busy         <= 0;
            done         <= 0;
            error        <= 0;
            aborted      <= 0;
            next_addr    <= 0;
            remaining    <= 0;
            owned        <= 0;
            skid_valid   <= 0;
            skid_data    <= 0;
            cancel_abort <= 0;
            cancel_error <= 0;
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
                    if ((!owned && !accepted) || response) begin
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
                    if (pixel_take && remaining == 0 && !owned) begin
                        busy <= 0;
                        done <= 1;
                    end
                end
            end
        end
    end
endmodule
