// SPDX-License-Identifier: GPL-3.0-or-later
// Reset-only component overlay (NOS by default, Bluetooth with ID2). One complete package is staged in
// explicit BRAM, CRC checked, then all expected words checked before any write.
// Firmware DDR writes pass through the ordinary ROM-cache invalidation path.
module ngage_nos_overlay #(
    parameter         [31:0] BASE            = 32'h30000000,
    parameter         [31:0] OVERLAY_ID      = 1,
    parameter integer        SHARED_CHECKSUM = 0
) (
    input  wire        clk,
    input  wire        reset,
    input  wire        firmware_valid,
    input  wire        firmware_loading,
    input  wire        enabled,
    input  wire        checksum_required,
    input  wire        blocked,
    input  wire        download,
    input  wire        wr,
    input  wire [26:0] addr,
    input  wire [15:0] data,
    output wire        wait_req,
    output wire        ready,
    output reg         loaded = 0,
    output reg         applied = 0,
    output wire        busy,
    output reg  [ 3:0] error = 0,
    output wire        mem_valid,
    input  wire        mem_ready,
    output wire        mem_write,
    output wire [31:0] mem_addr,
    output wire [31:0] mem_data,
    input  wire        mem_done,
    input  wire [31:0] mem_rdata
);
    localparam IDLE=0, RECEIVE=1, FINISH=2, OFFSET_READ=3, OFFSET_TAKE=4,
               OLD_READ=5, OLD_TAKE=6, NEW_READ=7, NEW_TAKE=8,
               CHECK=9, REQUEST=10, RESPONSE=11;
    reg [3:0] state = IDLE;
    reg previous_download = 0, ending = 0, bad_file = 0, discard = 0;
    reg word_valid = 0, high_byte = 0, buffer_write = 0;
    reg [15:0] input_word = 0;
    reg [26:0] input_pos = 0;
    reg [13:0] byte_pos = 0;
    reg [31:0] assembly = 0, buffer_data = 0;
    reg [10:0] buffer_addr = 0;
    reg [31:0] header_crc = 32'hffffffff, body_crc = 32'hffffffff;
    reg [31:0] body_expected = 0, header_expected = 0, length_expected = 0;
    reg [9:0] count = 0, index = 0;
    reg verify_pass = 1, selection = 0, dirty = 0, fatal = 0;
    reg checksum_selection = 0, checksum_applied = 0;
    // With multiple components the checksum stays skipped until ALL are OFF.
    wire desired_checksum = SHARED_CHECKSUM ? checksum_required : enabled;
    wire checksum_current = !loaded || checksum_applied == desired_checksum;
    reg [31:0] offset = 0, old_word = 0, new_word = 0, previous_offset = 0;
    wire checksum_word = offset == 32'h8f18 || offset == 32'h8f1c;
    wire [7:0] byte_data = high_byte ? input_word[15:8] : input_word[7:0];
    wire [31:0] buffer_q;
    wire [10:0] record_base = 11'd16 + index * 11'd3;
    wire [10:0] read_addr = record_base +
        ((state==OLD_READ || state==OLD_TAKE) ? 11'd1 :
         (state==NEW_READ || state==NEW_TAKE) ? 11'd2 : 11'd0);
    ngage_bram #(
        .AW         (11),
        .DW         (32),
        .READ_ONLY_B(1)
    ) staging (
        .clk   (clk),
        .addr_a(buffer_addr),
        .data_a(buffer_data),
        .we_a  (buffer_write),
        .q_a   (),
        .addr_b(read_addr),
        .data_b(32'b0),
        .we_b  (1'b0),
        .q_b   (buffer_q)
    );
    function [31:0] crc_byte;
        input [31:0] c;
        input [7:0] b;
        reg     [31:0] x;
        integer        i;
        begin
            x = c ^ {24'b0, b};
            for (i = 0; i < 8; i = i + 1) x = (x >> 1) ^ (32'hedb88320 & {32{x[0]}});
            crc_byte = x;
        end
    endfunction
    assign busy = state != IDLE;
    assign wait_req = download && !discard && (state != RECEIVE || word_valid || buffer_write);
    // A parse error cannot affect the original view when the option is OFF.
    assign ready = firmware_valid && !firmware_loading && !download && !busy && !fatal &&
                   !dirty && checksum_current && (enabled ? (loaded && applied && error==0) : !applied);
    assign mem_valid = state == REQUEST && firmware_valid && !firmware_loading;
    assign mem_write = !verify_pass;
    assign mem_addr = BASE + offset;
    assign mem_data = (checksum_word ? checksum_selection : selection) ? new_word : old_word;
    task fail;
        input [3:0] reason;
        input hard;
        begin
            error      <= reason;
            fatal      <= hard;
            word_valid <= 0;
            state      <= IDLE;
        end
    endtask
    always @(posedge clk) begin
        previous_download <= download;
        buffer_write      <= 0;
        if (reset) begin
            state             <= IDLE;
            previous_download <= 0;
            ending            <= 0;
            loaded            <= 0;
            applied           <= 0;
            checksum_applied  <= 0;
            dirty             <= 0;
            fatal             <= 0;
            error             <= 0;
            discard           <= 0;
            word_valid        <= 0;
            buffer_write      <= 0;
        end else begin
            if (firmware_loading) begin
                if (loaded) dirty <= 1;
                fatal <= 0;
            end
            if (download && !previous_download) begin
                if (state != IDLE || applied || dirty) begin
                    // Preserve the old undo table; user must turn the option OFF.
                    error   <= 9;
                    discard <= 1;
                end else begin
                    state      <= RECEIVE;
                    ending     <= 0;
                    bad_file   <= 0;
                    discard    <= 0;
                    loaded     <= 0;
                    error      <= 0;
                    fatal      <= 0;
                    input_pos  <= 0;
                    byte_pos   <= 0;
                    word_valid <= 0;
                    assembly   <= 0;
                    count      <= 0;
                    header_crc <= 32'hffffffff;
                    body_crc   <= 32'hffffffff;
                end
            end
            if (!download) discard <= 0;
            if (state == RECEIVE) begin
                if (previous_download && !download) ending <= 1;
                if (wr && download && !wait_req) begin
                    if (addr != input_pos || addr >= 27'd8192) bad_file <= 1;
                    input_word <= data;
                    word_valid <= 1;
                    high_byte  <= 0;
                    input_pos  <= input_pos + 2;
                end
                if (word_valid) begin
                    if (byte_pos < 60) header_crc <= crc_byte(header_crc, byte_data);
                    if (byte_pos >= 64) body_crc <= crc_byte(body_crc, byte_data);
                    // Shift low-first incoming bytes into their final LE word.
                    assembly <= {byte_data, assembly[31:8]};
                    if (byte_pos[1:0] == 3) begin
                        buffer_write <= byte_pos < 8192;
                        buffer_addr  <= byte_pos[12:2];
                        buffer_data  <= {byte_data, assembly[31:8]};
                        case (byte_pos[13:2])
                            0:      if ({byte_data, assembly[31:8]} != 32'h314f474e) bad_file <= 1;
                            1:      if ({byte_data, assembly[31:8]} != 1) bad_file <= 1;
                            2:      if ({byte_data, assembly[31:8]} != OVERLAY_ID) bad_file <= 1;
                            3: begin
                                count <= assembly[17:8];
                                if({byte_data,assembly[31:8]}==0 || {byte_data,assembly[31:8]}>640)
                                    bad_file <= 1;
                            end
                            4:      body_expected <= {byte_data, assembly[31:8]};
                            5:      if ({byte_data, assembly[31:8]} != 32'h7bc70477) bad_file <= 1;
                            6:      if ({byte_data, assembly[31:8]} != 32'hc3b897c7) bad_file <= 1;
                            7:      if ({byte_data, assembly[31:8]} != 32'h6fc8092c) bad_file <= 1;
                            8:      if ({byte_data, assembly[31:8]} != 32'h4f4847f0) bad_file <= 1;
                            9:      if ({byte_data, assembly[31:8]} != 32'h26e2c0dc) bad_file <= 1;
                            10:     if ({byte_data, assembly[31:8]} != 32'ha9449cf4) bad_file <= 1;
                            11:     length_expected <= {byte_data, assembly[31:8]};
                            12, 14: if ({byte_data, assembly[31:8]} != 0) bad_file <= 1;
                            13:     if ({byte_data, assembly[31:8]} != 12) bad_file <= 1;
                            15:     header_expected <= {byte_data, assembly[31:8]};
                        endcase
                    end
                    if (byte_pos == 8191) bad_file <= 1;
                    else byte_pos <= byte_pos + 1'b1;
                    high_byte <= 1;
                    if (high_byte) word_valid <= 0;
                end
                if (ending && !word_valid && !buffer_write) state <= FINISH;
            end
            if (state == FINISH) begin
                ending <= 0;
                if(bad_file || {18'b0,byte_pos}!=length_expected || byte_pos!=64+count*12 || byte_pos[1:0]!=0)
                    fail(1, 0);
                else if (~header_crc != header_expected || ~body_crc != body_expected) fail(2, 0);
                else begin
                    loaded <= 1;
                    dirty  <= 1;
                    state  <= IDLE;
                end
            end
            if(state==IDLE && !download && !firmware_loading && firmware_valid &&
               loaded && !blocked && !fatal && (dirty || enabled!=applied || !checksum_current)) begin
                selection          <= enabled;
                checksum_selection <= desired_checksum;
                verify_pass        <= 1;
                index              <= 0;
                previous_offset    <= 0;
                state              <= OFFSET_READ;
            end
            case (state)
                OFFSET_READ: state <= OFFSET_TAKE;
                OFFSET_TAKE: begin
                    offset <= buffer_q;
                    state  <= OLD_READ;
                end
                OLD_READ:    state <= OLD_TAKE;
                OLD_TAKE: begin
                    old_word <= buffer_q;
                    state    <= NEW_READ;
                end
                NEW_READ:    state <= NEW_TAKE;
                NEW_TAKE: begin
                    new_word <= buffer_q;
                    state    <= CHECK;
                end
                CHECK: begin
                    if (firmware_loading || !firmware_valid) begin
                        dirty <= 1;
                        state <= IDLE;
                    end  // Shared ownership requires both audited descriptor records;
                         // a CRC-valid pack without them cannot claim checksum readiness.
                    else if (SHARED_CHECKSUM && (count < 2 ||
                        (index == 0 && (offset != 32'h8f18 || old_word != 32'h50009000 || new_word != 32'hffffffff)) ||
                        (index == 1 && (offset != 32'h8f1c || old_word != 32'h511b4fff || new_word != 32'hffffffff))))
                        fail(3, 1);
                    else if(offset[1:0]!=0 || offset>=32'h13f0000 ||
                            (index!=0 && offset<=previous_offset))
                        fail(3, 1);
                    else state <= REQUEST;
                end
                REQUEST:     if (mem_valid && mem_ready) state <= RESPONSE;
                RESPONSE:
                if (mem_done) begin
                    if (verify_pass && mem_rdata != old_word && mem_rdata != new_word) fail(4, 1);
                    else if (firmware_loading || !firmware_valid) begin
                        dirty <= 1;
                        state <= IDLE;
                    end else if (index + 1 == count) begin
                        if (verify_pass) begin
                            verify_pass     <= 0;
                            index           <= 0;
                            previous_offset <= 0;
                            state           <= OFFSET_READ;
                        end else begin
                            applied          <= selection;
                            checksum_applied <= checksum_selection;
                            dirty            <= 0;
                            error            <= 0;
                            state            <= IDLE;
                        end
                    end else begin
                        index           <= index + 1'b1;
                        previous_offset <= offset;
                        state           <= OFFSET_READ;
                    end
                end
            endcase
        end
    end
endmodule
