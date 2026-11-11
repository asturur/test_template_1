// Read-only production image admission and owned HPS transport for MMC slot 2.
// The caller selects only slot 2 mount/ACK; the halfword buffer bus is shared.
// This is a transaction-level backing-store adapter, not D550/AMA pin routing.
// Advertised work survives resets until ACK and the hps_io write pipeline drain.
module ngage_mmc_hps (
    input  wire        clk,
    input  wire        init_reset,
    input  wire        guest_reset,
    input  wire        hps_img_mounted,
    input  wire        hps_img_readonly,
    input  wire [63:0] hps_img_size,
    output wire        card_reset,
    output reg         card_img_mounted,
    output wire        card_img_readonly,
    output wire [63:0] card_img_size,
    input  wire [31:0] card_sd_lba,
    input  wire [ 5:0] card_sd_blk_cnt,
    input  wire        card_sd_rd,
    input  wire        card_sd_wr,
    output wire        card_sd_ack,
    output wire [12:0] card_sd_buff_addr,
    output wire [15:0] card_sd_buff_dout,
    input  wire [15:0] card_sd_buff_din,
    output wire        card_sd_buff_wr,
    output wire [31:0] hps_sd_lba,
    output wire [ 5:0] hps_sd_blk_cnt,
    output wire        hps_sd_rd,
    output wire        hps_sd_wr,
    input  wire        hps_sd_ack,
    input  wire [12:0] hps_buff_addr,
    input  wire [15:0] hps_buff_dout,
    input  wire        hps_buff_wr,
    output wire [15:0] hps_buff_din,
    output wire        busy,
    output reg         fault
);
    localparam IDLE = 0, REQUEST = 1, ACTIVE = 2, TAIL = 3, VERIFY = 4;
    reg [2:0] state;
    reg init_prev, guest_prev, mount_prev;
    reg ack_prev;
    reg [1:0] quiet, tail;
    reg mount_known, mount_pending, admitted, cancelled;
    reg [63:0] image_size;
    reg [31:0] generation, request_generation;
    reg [31:0] owned_lba;
    reg [ 5:0] owned_count;
    reg [14:0] expected_words, received_words;
    reg [63:0] footer_magic;
    reg [ 7:0] footer_version;
    reg [127:0] footer_cid, footer_csd;
    reg [31:0] footer_ocr;
    reg [119:0] cid_shift, csd_shift;
    reg [6:0] cid_crc, csd_crc;
    reg [3:0] crc_left;

    // Configuration-time initialization is distinct from init_reset: hps_io
    // has no guest-reset input, so even global reset must drain advertised work.
    initial begin
        card_img_mounted   = 0;
        fault              = 0;
        state              = IDLE;
        init_prev          = 0;
        guest_prev         = 0;
        mount_prev         = 0;
        ack_prev           = 0;
        quiet              = 0;
        tail               = 0;
        mount_known        = 0;
        mount_pending      = 0;
        admitted           = 0;
        cancelled          = 0;
        image_size         = 0;
        generation         = 0;
        request_generation = 0;
        owned_lba          = 0;
        owned_count        = 0;
        expected_words     = 0;
        received_words     = 0;
        footer_magic       = 0;
        footer_version     = 0;
        footer_cid         = 0;
        footer_csd         = 0;
        footer_ocr         = 0;
        cid_shift          = 0;
        csd_shift          = 0;
        cid_crc            = 0;
        csd_crc            = 0;
        crc_left           = 0;
    end

    wire init_event = init_reset && !init_prev;
    wire guest_event = guest_reset && !guest_prev;
    wire mount_event = hps_img_mounted && !mount_prev;
    wire changed = init_event || guest_event || mount_event;
    wire size_ok = hps_img_size >= 64'd1024 &&
                   hps_img_size <= 64'd1073742336 && hps_img_size[8:0] == 0;
    wire [6:0] request_blocks = {1'b0, card_sd_blk_cnt} + 7'd1;
    wire [64:0] request_end = {24'd0, card_sd_lba, 9'd0} + {49'd0, request_blocks, 9'd0};
    // The native card uses up to eight sectors per read (4 KiB). Actual WIDE
    // hps_io supports 32 sectors / 16 KiB; no unsupported larger card burst is
    // advertised. The first read must be the original image's metadata footer.
    wire request_ok = card_sd_blk_cnt <= 6'd7 &&
                      (admitted ? request_end <= {1'b0, image_size - 64'd512} :
                       (request_end <= {1'b0, image_size} &&
                        card_sd_lba == image_size[40:9] - 32'd1 && card_sd_blk_cnt == 0));
    wire owns_buffer = state == REQUEST || state == ACTIVE || state == TAIL;
    wire selected_word = owns_buffer && (hps_sd_ack || ack_prev) && hps_buff_wr;
    wire word_ok = {2'b0, hps_buff_addr} == received_words && received_words < expected_words;
    wire current_request = !cancelled && request_generation == generation;
    wire blocked = init_reset || guest_reset || hps_img_mounted ||
                   !mount_known || mount_pending || fault;
    wire malformed_word = selected_word && !word_ok && current_request && !blocked;
    assign card_reset = blocked || malformed_word;
    assign card_img_readonly = 1'b1;
    assign card_img_size = image_size;
    assign card_sd_ack = !card_reset && current_request &&
                         ((state == REQUEST && hps_sd_ack) || state == ACTIVE ||
                          state == TAIL || state == VERIFY);
    assign card_sd_buff_addr = hps_buff_addr;
    assign card_sd_buff_dout = hps_buff_dout;
    assign card_sd_buff_wr = selected_word && word_ok && current_request && !card_reset;
    assign hps_sd_lba = owned_lba;
    assign hps_sd_blk_cnt = owned_count;
    assign hps_sd_rd = state == REQUEST;
    assign hps_sd_wr = 1'b0;
    assign hps_buff_din = 16'hffff;
    assign busy = state != IDLE || mount_pending || hps_sd_ack || ack_prev || quiet != 3;

    function [6:0] crc7_byte;
        input [6:0] crc;
        input [7:0] data;
        reg     [6:0] value;
        integer       bit_index;
        begin
            value = crc;
            for (bit_index = 7; bit_index >= 0; bit_index = bit_index - 1)
            value = {value[5:0], 1'b0} ^ ((value[6] ^ data[bit_index]) ? 7'h09 : 7'd0);
            crc7_byte = value;
        end
    endfunction
    wire [63:0] csd_capacity = ({52'd0, footer_csd[73:62]} + 64'd1) <<
                              ({61'd0, footer_csd[49:47]} + 64'd11);
    wire metadata_ok = footer_magic == 64'h4e474147454d4d43 && footer_version == 1 &&
                       footer_cid[0] && footer_csd[0] &&
                       footer_cid[7:1] == cid_crc && footer_csd[7:1] == csd_crc &&
                       footer_csd[127:126] == 2 && footer_csd[125:122] == 3 &&
                       footer_csd[83:80] == 9 && footer_ocr[30:29] == 0 &&
                       csd_capacity != 0 && image_size - 64'd512 <= csd_capacity;

    always @(posedge clk) begin
        init_prev        <= init_reset;
        guest_prev       <= guest_reset;
        mount_prev       <= hps_img_mounted;
        ack_prev         <= hps_sd_ack;
        card_img_mounted <= 0;
        if (hps_sd_ack || ack_prev) quiet <= 0;
        else if (quiet != 3) quiet <= quiet + 1'b1;

        if (changed) begin
            generation <= generation + 1'b1;
            admitted   <= 0;
            if (state != IDLE) cancelled <= 1;
        end
        if (init_event) begin
            mount_known   <= 0;
            mount_pending <= 0;
            fault         <= 0;
        end
        if (guest_event && mount_known && !fault && !init_event) mount_pending <= 1;
        if (mount_event) begin
            image_size    <= hps_img_size;
            mount_known   <= size_ok;
            mount_pending <= size_ok;
            fault         <= !size_ok && hps_img_size != 0;
        end
        if (malformed_word) begin
            fault     <= 1;
            cancelled <= 1;
        end
        if (selected_word && word_ok) begin
            received_words <= received_words + 1'b1;
            // Prefixes enter the native card as they arrive. Only the initial
            // metadata ACK fall is fenced by strict original-byte admission.
            if (!admitted && current_request && !card_reset) begin
                case (hps_buff_addr)
                    0, 1, 2, 3:
                    footer_magic <= {footer_magic[47:0], hps_buff_dout[7:0], hps_buff_dout[15:8]};
                    4: footer_version <= hps_buff_dout[7:0];
                    8, 9, 10, 11, 12, 13, 14, 15:
                    footer_cid <= {footer_cid[111:0], hps_buff_dout[7:0], hps_buff_dout[15:8]};
                    16, 17, 18, 19, 20, 21, 22, 23:
                    footer_csd <= {footer_csd[111:0], hps_buff_dout[7:0], hps_buff_dout[15:8]};
                    24, 25:
                    footer_ocr <= {footer_ocr[15:0], hps_buff_dout[7:0], hps_buff_dout[15:8]};
                    default: ;
                endcase
            end
        end
        case (state)
            IDLE: begin
                cancelled <= 0;
                if (mount_pending && mount_known && quiet == 3 && !hps_sd_ack && !ack_prev && !init_reset && !guest_reset &&
                    !hps_img_mounted && !fault && !changed) begin
                    mount_pending    <= 0;
                    card_img_mounted <= 1;
                end else if (!card_reset && !changed && quiet == 3 && !hps_sd_ack && !ack_prev &&
                             (card_sd_rd || card_sd_wr)) begin
                    if (card_sd_wr || !request_ok) fault <= 1;
                    else begin
                        owned_lba          <= card_sd_lba;
                        owned_count        <= card_sd_blk_cnt;
                        expected_words     <= {request_blocks, 8'd0};
                        received_words     <= 0;
                        request_generation <= generation;
                        state              <= REQUEST;
                    end
                end
            end
            REQUEST: if (hps_sd_ack) state <= ACTIVE;
            ACTIVE:
            if (!hps_sd_ack) begin
                state <= TAIL;
                tail  <= 3;
            end
            TAIL: begin
                if (hps_sd_ack) begin
                    // A second, unexpected selected-slot transfer must drain.
                    if (current_request && !blocked) fault <= 1;
                    cancelled <= 1;
                    state     <= ACTIVE;
                end else if (tail != 0) tail <= tail - 1'b1;
                else if (!current_request || changed || fault) state <= IDLE;
                else if (received_words != expected_words) begin
                    fault <= 1;
                    state <= IDLE;
                end else if (!admitted) begin
                    cid_shift <= footer_cid[127:8];
                    csd_shift <= footer_csd[127:8];
                    cid_crc   <= 0;
                    csd_crc   <= 0;
                    crc_left  <= 15;
                    state     <= VERIFY;
                end else state <= IDLE;
            end
            VERIFY: begin
                if (!current_request || changed || fault) state <= IDLE;
                else if (crc_left != 0) begin
                    cid_crc   <= crc7_byte(cid_crc, cid_shift[119:112]);
                    csd_crc   <= crc7_byte(csd_crc, csd_shift[119:112]);
                    cid_shift <= {cid_shift[111:0], 8'd0};
                    csd_shift <= {csd_shift[111:0], 8'd0};
                    crc_left  <= crc_left - 1'b1;
                end else begin
                    admitted <= metadata_ok;
                    if (!metadata_ok) fault <= 1;
                    state <= IDLE;
                end
            end
            default: begin
                state <= IDLE;
                fault <= 1;
            end
        endcase
    end
endmodule
