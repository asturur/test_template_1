// Fixed-profile NEM-4 4.03 service-container loader. Original scrambled bytes
// go to DDR; normal flash reads retain the existing descrambler. No C:/PMM
// writes are possible here. The host oracle is tools/service_firmware.py.
module ngage_service_loader #(
    parameter [31:0] BASE = 32'h30000000
) (
    input  wire        clk,
    input  wire        reset,
    input  wire        download,
    input  wire        ppm,
    input  wire        wr,
    input  wire [26:0] addr,
    input  wire [15:0] data,
    output wire        wait_req,
    output wire        valid,
    output wire        failed,
    output wire        mem_valid,
    input  wire        mem_ready,
    output wire [31:0] mem_addr,
    output wire [31:0] mem_data,
    output wire [ 3:0] mem_be,
    input  wire        mem_done,
    output reg  [ 3:0] failure_reason = 0
);
    localparam CLEAR = 0, STREAM = 1;
    reg state = CLEAR;
    reg prev = 0, active = 0, slot = 0, initialized = 0;
    reg [1:0] slot_valid = 0, slot_bad = 0;
    reg        load_error = 0;
    reg [24:0] clear_pos = 0;
    reg        clear_all = 0;
    reg pending = 0, issued = 0;
    reg [31:0] target_addr = 0, target_data = 0;
    reg [3:0] target_be = 0;
    reg word_valid = 0, high_byte = 0;
    reg [15:0] word_data = 0;
    reg [26:0] input_pos = 0;
    reg [31:0] position = 0, crc = 32'hffffffff;
    reg [ 3:0] header_pos = 0;
    reg [31:0] physical = 0;
    reg [23:0] record_length = 0, remaining = 0;
    reg [7:0] header_sum = 0, payload_sum = 0, payload_check = 0;
    reg  [11:0] records = 0;
    wire [ 7:0] byte_data = high_byte ? word_data[15:8] : word_data[7:0];
    wire [31:0] file_length = slot ? 32'd1361703 : 32'd18777938;
    wire [31:0] first_record = slot ? 32'hd9 : 32'h2def2;
    wire [31:0] expected_crc = slot ? 32'hc3b897c7 : 32'h7bc70477;
    wire [11:0] expected_records = slot ? 12'd167 : 12'd2268;
    wire [31:0] transport_length = (file_length + 1) & 32'hfffffffe;

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
    function ppm_owned;
        input [31:0] a;
        begin
            ppm_owned = a < 32'h12c || (a >= 32'h164 && a < 32'h10000) ||
                        (a >= 32'h700000 && a < 32'h76c000) ||
                        (a >= 32'h4730000 && a < 32'h4800000);
        end
    endfunction
    // Whole-record check uses subtraction, so an overflowing end cannot wrap
    // into an allowed bank. Writable flash and PMM are deliberately excluded.
    function firmware_record;
        input [31:0] a;
        input [23:0] n;
        begin
            firmware_record = (a < 32'h700000 && {8'b0, n} <= 32'h700000 - a) ||
                (a >= 32'h700000 && a < 32'h7f0000 && {8'b0, n} <= 32'h7f0000 - a) ||
                (a >= 32'h2000000 && a < 32'h2400000 && {8'b0, n} <= 32'h2400000 - a) ||
                (a >= 32'h4000000 && a < 32'h4800000 && {8'b0, n} <= 32'h4800000 - a);
        end
    endfunction
    function [31:0] backing;
        input [31:0] a;
        begin
            if (a < 32'h700000) backing = a;
            else if (a < 32'h7f0000) backing = 32'h1300000 + a - 32'h700000;
            else if (a < 32'h2400000) backing = 32'h700000 + a - 32'h2000000;
            else backing = 32'hb00000 + a - 32'h4000000;
        end
    endfunction
    function [31:0] physical_from_backing;
        input [24:0] a;
        begin
            if (a < 25'h700000) physical_from_backing = {7'b0, a};
            else if (a < 25'hb00000) physical_from_backing = 32'h2000000 + {7'b0, a} - 32'h700000;
            else if (a < 25'h1300000) physical_from_backing = 32'h4000000 + {7'b0, a} - 32'hb00000;
            else physical_from_backing = 32'h700000 + {7'b0, a} - 32'h1300000;
        end
    endfunction
    wire        clear_owned = clear_all || ppm_owned(physical_from_backing(clear_pos)) == slot;
    wire [31:0] payload_offset = backing(physical);
    assign valid = &slot_valid;
    assign failed = |slot_bad;
    assign wait_req = download && !load_error &&
                      (!active || state == CLEAR || word_valid || pending);
    assign mem_valid = pending && !issued;
    assign mem_addr = target_addr;
    assign mem_data = target_data;
    assign mem_be = target_be;

    // Error invalidates the selected slot. Streamed bytes are not rolled back;
    // the phone stays held until a complete valid reload. Outstanding DDR
    // traffic still drains before active drops or another file can start.
    task reject;
        input [3:0] reason;
        begin
            load_error       <= 1;
            slot_valid[slot] <= 0;
            slot_bad[slot]   <= 1;
            word_valid       <= 0;
            failure_reason   <= reason;
        end
    endtask

    always @(posedge clk) begin
        prev <= download;
        if (reset) begin
            prev           <= 0;
            active         <= 0;
            initialized    <= 0;
            slot           <= 0;
            slot_valid     <= 0;
            slot_bad       <= 0;
            load_error     <= 0;
            pending        <= 0;
            issued         <= 0;
            word_valid     <= 0;
            failure_reason <= 0;
        end else begin
            if (mem_valid && mem_ready) issued <= 1;
            if (pending && mem_done) begin
                pending <= 0;
                issued  <= 0;
            end
            if (download && !prev) begin
                if (active || pending) reject(4'd1);
                else begin
                    active          <= 1;
                    slot            <= ppm;
                    slot_valid[ppm] <= 0;
                    slot_bad[ppm]   <= 0;
                    failure_reason  <= 0;
                    load_error      <= 0;
                    state           <= CLEAR;
                    clear_pos       <= 0;
                    clear_all       <= !initialized;
                    input_pos       <= 0;
                    position        <= 0;
                    crc             <= 32'hffffffff;
                    header_pos      <= 0;
                    physical        <= 0;
                    record_length   <= 0;
                    remaining       <= 0;
                    records         <= 0;
                    word_valid      <= 0;
                    high_byte       <= 0;
                end
            end else if (active) begin
                if (download && ppm != slot && !load_error) reject(4'd2);
                else if (!load_error) begin
                    if (download && state == CLEAR && !pending) begin
                        if (clear_pos == 25'h13f0000) begin
                            initialized <= 1;
                            state       <= STREAM;
                        end else begin
                            clear_pos <= clear_pos + 4;
                            if (clear_owned) begin
                                target_addr <= BASE + {7'b0, clear_pos};
                                target_data <= 32'hffffffff;
                                target_be   <= 4'hf;
                                pending     <= 1;
                                issued      <= 0;
                            end
                        end
                    end
                    if (download && wr && !wait_req) begin
                        if (addr != input_pos || addr[0] || {5'b0, input_pos} >= transport_length)
                            reject(4'd3);
                        else begin
                            word_data  <= data;
                            word_valid <= 1;
                            high_byte  <= 0;
                            input_pos  <= input_pos + 2;
                        end
                    end
                    if (state == STREAM && word_valid && !pending) begin
                        if (high_byte) word_valid <= 0;
                        high_byte <= !high_byte;
                        position  <= position + 1;
                        if (position >= file_length) begin
                            // WIDE=1 pads only the final odd PPM byte with zero.
                            // The pad is transport, never CRC or DDR payload.
                            if (!slot || position != file_length || byte_data != 0) reject(4'd4);
                        end else begin
                            crc <= crc_byte(crc, byte_data);
                            if (position < first_record) begin
                                // Exact-profile bounded skip: metadata + host
                                // flashing algorithm are covered by file CRC.
                                // No marker search and no algorithm execution.
                                if (position == 0 && byte_data != 8'ha2) reject(4'd5);
                            end else if (remaining != 0) begin
                                if (slot && !ppm_owned(physical)) reject(4'd6);
                                else if (slot || !ppm_owned(physical)) begin
                                    target_addr <= BASE + (payload_offset & 32'hfffffffc);
                                    target_data <= {4{byte_data}};
                                    target_be   <= 4'b0001 << payload_offset[1:0];
                                    pending     <= 1;
                                    issued      <= 0;
                                end
                                physical    <= physical + 1;
                                remaining   <= remaining - 1;
                                payload_sum <= payload_sum + byte_data;
                                if (remaining == 1) begin
                                    if (((payload_sum + byte_data + payload_check) & 8'hff) != 0)
                                        reject(4'd7);
                                    records <= records + 1;
                                end
                            end else if (header_pos == 0) begin
                                if (byte_data != 8'h14) reject(4'd8);
                                header_pos    <= 1;
                                header_sum    <= 0;
                                physical      <= 0;
                                record_length <= 0;
                                payload_sum   <= 0;
                            end else begin
                                header_sum <= header_sum + byte_data;
                                header_pos <= header_pos + 1;
                                case (header_pos)
                                    1, 2, 3, 4: physical <= {physical[23:0], byte_data};
                                    5:          payload_check <= byte_data;
                                    6, 7, 8:    record_length <= {record_length[15:0], byte_data};
                                    9: begin
                                        header_pos <= 0;
                                        if (((header_sum + byte_data) & 8'hff) != 8'hff ||
                                            record_length == 0 || record_length > 8192 ||
                                            !firmware_record(
                                                physical, record_length
                                            ))
                                            reject(4'd9);
                                        else remaining <= record_length;
                                    end
                                    default:    reject(4'd9);
                                endcase
                            end
                        end
                    end
                end
                if (!download && !pending && !word_valid) begin
                    active <= 0;
                    if (!load_error && state == STREAM && position == transport_length &&
                        header_pos == 0 && remaining == 0 && records == expected_records &&
                        (crc ^ 32'hffffffff) == expected_crc) begin
                        slot_valid[slot] <= 1;
                        slot_bad[slot]   <= 0;
                    end else if (!load_error) reject(4'd10);
                end
            end
        end
    end
endmodule
