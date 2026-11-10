// SPDX-License-Identifier: GPL-3.0-or-later
// Direct-mapped raw flash backing cache. The caller serializes every DDR
// writer through this port. NOR commands and descrambling live upstream.
module ngage_ddr_flash_cache #(
    parameter integer CACHE_BYTES = 8192
) (
    input  wire        clk,
    input  wire        reset,
    input  wire        invalidate_sector,
    input  wire        req_valid,
    output wire        req_ready,
    input  wire        req_write,
    input  wire        req_line,
    input  wire [31:0] req_addr,
    input  wire [31:0] req_wdata,
    input  wire [ 3:0] req_be,
    output wire        rsp_valid,
    output reg  [31:0] rsp_data = 0,
    output wire        rsp_beat_valid,
    output wire [63:0] rsp_beat_data,
    output wire        rsp_beat_last,
    output wire        mem_valid,
    input  wire        mem_ready,
    output wire        mem_write,
    output wire        mem_line,
    output wire [31:0] mem_addr,
    output wire [31:0] mem_wdata,
    output wire [ 3:0] mem_be,
    input  wire        mem_done,
    input  wire [31:0] mem_rdata,
    input  wire        mem_beat_valid,
    input  wire [63:0] mem_beat_data,
    input  wire        mem_beat_last
);
    localparam integer INDEX_BITS = CACHE_BYTES == 32768 ? 10 : CACHE_BYTES == 16384 ? 9 : 8;
    localparam integer TAG_BITS = 27 - INDEX_BITS;
    localparam         CLEAR      = 0, IDLE = 1, LOOKUP = 2, HIT_LINE = 3, ISSUE = 4, WAIT_MEM = 5, CLEAR_SECTOR = 6;
    reg [           2:0] state = CLEAR;
    reg [INDEX_BITS-1:0] clear_index = 0;
    reg [31:0] address = 0, write_data = 0;
    reg [3:0] mask = 0;
    reg writing = 0, line_request = 0, cacheable = 0, fill = 0;
    reg [2:0] beat = 0;
    reg       response_valid = 0;
    reg hit_beat_valid = 0, hit_beat_last = 0;
    reg [63:0] hit_beat_data = 0;

    // Each region begins and ends on a 32-byte boundary.
    wire in_flash = (req_addr >= 32'h30000000 && req_addr < 32'h313f0000) ||
                    (req_addr >= 32'h31400000 && req_addr < 32'h31810000);
    wire [INDEX_BITS-1:0] index = address[INDEX_BITS+4:5];
    wire [TAG_BITS-1:0] tag = address[31:INDEX_BITS+5];
    wire [TAG_BITS:0] tag_read;
    wire tag_hit = tag_read == {1'b1, tag};
    wire [63:0] data_read;
    wire fill_beat = state == WAIT_MEM && fill && mem_beat_valid && beat < 4;
    wire [2:0] received = beat + {2'b0, fill_beat};
    wire fill_done = state == WAIT_MEM && fill && mem_done && received == 4;
    wire invalidate = state == LOOKUP && writing && cacheable && tag_hit && |mask;
    wire clearing = state == CLEAR || state == CLEAR_SECTOR;
    wire tag_write = !reset && (clearing || invalidate || fill_done);
    wire [INDEX_BITS-1:0] tag_write_addr = clearing ? clear_index : index;
    wire [TAG_BITS:0] tag_write_data = fill_done ? {1'b1, tag} : {(TAG_BITS + 1) {1'b0}};
    wire [1:0] next_hit_beat = state == LOOKUP ? 2'd1 : beat[1:0] + 2'd1;
    wire [INDEX_BITS+1:0] read_addr = state == IDLE ?
        req_addr[INDEX_BITS+4:3] : {index, next_hit_beat};
    wire wanted_beat = fill_beat && beat[1:0] == address[4:3];
    wire [31:0] incoming_word = address[2] ? mem_beat_data[63:32] : mem_beat_data[31:0];

    ngage_bram #(
        .AW(INDEX_BITS),
        .DW(TAG_BITS + 1)
    ) tags (
        .clk   (clk),
        .addr_a(tag_write_addr),
        .data_a(tag_write_data),
        .we_a  (tag_write),
        .q_a   (),
        .addr_b(req_addr[INDEX_BITS+4:5]),
        .data_b({(TAG_BITS + 1) {1'b0}}),
        .we_b  (1'b0),
        .q_b   (tag_read)
    );
    ngage_bram #(
        .AW(INDEX_BITS + 2),
        .DW(64)
    ) data (
        .clk   (clk),
        .addr_a({index, beat[1:0]}),
        .data_a(mem_beat_data),
        .we_a  (fill_beat && !reset),
        .q_a   (),
        .addr_b(read_addr),
        .data_b(64'b0),
        .we_b  (1'b0),
        .q_b   (data_read)
    );

    assign req_ready = state == IDLE && !reset;
    assign rsp_valid = response_valid && !reset;
    assign mem_valid = state == ISSUE && !reset;
    assign mem_write = writing;
    assign mem_line  = fill || line_request;
    assign mem_addr  = fill ? {address[31:5], 5'b0} : address;
    assign mem_wdata = write_data;
    assign mem_be    = mask;
    // The backend supplies registered beats. Forward them while filling RAM.
    wire forward = state == WAIT_MEM && line_request && mem_beat_valid;
    assign rsp_beat_valid = !reset && (hit_beat_valid || forward);
    assign rsp_beat_data  = forward ? mem_beat_data : hit_beat_data;
    assign rsp_beat_last  = forward ? mem_beat_last : hit_beat_last;

    always @(posedge clk) begin
        response_valid <= 0;
        hit_beat_valid <= 0;
        if (reset) begin
            state       <= CLEAR;
            clear_index <= 0;
        end else begin
            case (state)
                CLEAR: begin
                    clear_index <= clear_index + 1'b1;
                    if (&clear_index) state <= IDLE;
                end
                CLEAR_SECTOR: begin
                    clear_index <= clear_index + 1'b1;
                    if (&clear_index[3:0]) state <= IDLE;
                end
                IDLE:
                if (invalidate_sector) begin
                    // Each sector is sixteen aligned lines. Invalidate
                    // the indices conservatively, including any aliases.
                    clear_index <= req_addr[INDEX_BITS+4:5];
                    state       <= CLEAR_SECTOR;
                end else if (req_valid && req_ready) begin
                    address      <= req_addr;
                    write_data   <= req_wdata;
                    mask         <= req_be;
                    writing      <= req_write;
                    line_request <= req_line;
                    cacheable    <= in_flash && (!req_line || req_addr[4:0] == 0);
                    fill         <= 0;
                    beat         <= 0;
                    state        <= LOOKUP;
                end
                LOOKUP:
                if (cacheable && tag_hit && !writing) begin
                    if (line_request) begin
                        hit_beat_data  <= data_read;
                        hit_beat_valid <= 1;
                        hit_beat_last  <= 0;
                        beat           <= 1;
                        state          <= HIT_LINE;
                    end else begin
                        rsp_data       <= address[2] ? data_read[63:32] : data_read[31:0];
                        response_valid <= 1;
                        state          <= IDLE;
                    end
                end else begin
                    fill  <= cacheable && !writing;
                    state <= ISSUE;
                end
                HIT_LINE: begin
                    hit_beat_data  <= data_read;
                    hit_beat_valid <= 1;
                    hit_beat_last  <= beat == 3;
                    beat           <= beat + 1'b1;
                    if (beat == 3) begin
                        response_valid <= 1;
                        state          <= IDLE;
                    end
                end
                ISSUE:   if (mem_ready) state <= WAIT_MEM;
                WAIT_MEM: begin
                    if (fill_beat) beat <= received;
                    // Complete a scalar read on its requested beat. Keep
                    // the fill descriptor and admission blocked until the
                    // backend finishes and the entire line can be installed.
                    if (wanted_beat && !line_request) begin
                        rsp_data       <= incoming_word;
                        response_valid <= 1;
                    end
                    if (mem_done) begin
                        if (!fill || line_request) begin
                            rsp_data       <= mem_rdata;
                            response_valid <= 1;
                        end
                        state <= IDLE;
                    end
                end
                default: state <= CLEAR;
            endcase
        end
    end

    // synthesis translate_off
    initial
        if (CACHE_BYTES != 8192 && CACHE_BYTES != 16384 && CACHE_BYTES != 32768)
            $fatal(1, "unsupported flash cache size");
    always @(posedge clk) begin
        if (!reset && state == WAIT_MEM && fill) begin
            if (mem_beat_valid && (!fill_beat || mem_beat_last != (beat == 3)))
                $fatal(1, "incorrect flash cache fill beat count");
            if (mem_done && !fill_done) $fatal(1, "short flash cache fill");
        end
    end
    // synthesis translate_on
endmodule
