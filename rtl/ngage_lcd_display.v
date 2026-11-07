// Transaction-level LCD controller: native 176x208 phone video,
// with a separate 320x240 diagnostic active area. The LCD
// header/RGB444 assumptions follow scratch/current-boot/direct_lcd.py; these
// signals do not model the physical LCD serial bus or verified scan timing.
module ngage_lcd_display (
    input  wire        clk,
    input  wire        reset,
    input  wire        diagnostic,
    input  wire [ 7:0] status,
    input  wire [ 2:0] save_state,
    input  wire        write_valid,
    input  wire [31:0] write_addr,
    input  wire [31:0] write_data,
    input  wire        dma_valid,
    input  wire        dma_frame_full,
    input  wire [14:0] dma_word_addr,
    input  wire [31:0] dma_data,
    output reg         ce_pix = 0,
    output wire        hsync,
    output wire        vsync,
    output wire        hblank,
    output wire        vblank,
    output reg  [11:0] rgb,
    output reg         frame_complete = 0,
    output reg         incomplete = 0,
    output reg         unsupported = 0,
    output reg         unsupported_valid = 0,
    output reg  [31:0] unsupported_data = 0,
    output reg  [31:0] unsupported_header = 0,
    output reg  [ 7:0] unsupported_command = 0
);
    // Decoded UPP parameter framing. End coordinates are retained, not
    // invented: only the two observed full-panel row endpoints are accepted.
    reg [7:0] last_command = 0, row_start = 0, row_end = 208, col_start = 2, col_end = 177;
    reg [1:0] window_words = 0;
    reg [31:0] window_first = 0;
    wire full_window = row_start == 0 && (row_end == 207 || row_end == 208) && col_start == 2 &&
        col_end == 177;
    task unknown;
        input [31:0] context_header, context_data;
        input [7:0] context_command;
        begin
            unsupported         <= 1;
            unsupported_valid   <= 1;
            unsupported_data    <= context_data;
            unsupported_header  <= context_header;
            unsupported_command <= context_command;
        end
    endtask
    reg [3:0] div = 0;
    reg [8:0] x = 0, y = 0;
    wire [23:0] pixel_word, pixel_q;
    reg        pixel_forward;
    reg [23:0] forwarded_pixel;
    assign pixel_word = pixel_forward ? forwarded_pixel : pixel_q;
    reg [31:0] header = 0;
    reg memory_write = 0, display_on = 0;
    reg  [ 14:0] cursor = 0;
    // A row is known only after observing all 88 words in order. This tracks
    // complete line bands without pretending sparse fragments form a full frame.
    reg  [207:0] valid_rows = 0;
    reg  [  7:0] row_number = 0;
    reg  [  6:0] row_progress = 0;
    reg  [ 14:0] next_dma_word = 0;
    wire [207:0] row_bit = 208'b1 << row_number;
    wire [ 14:0] dma_row = dma_word_addr / 15'd88;
    // As in MiSTer Game Boy, retain a larger centered timing raster for
    // analog black padding, while DE encloses only the native phone pixels.
    wire         in_phone = x >= 72 && x < 248 && y >= 16 && y < 224;
    wire [  8:0] px = x - 72, py = y - 16;
    wire [ 14:0] read_index = ({6'b0, py} * 15'd88) + {7'b0, px[8:1]};
    reg [8:0] scan_x = 0, scan_y = 0;
    reg [11:0] phone_rgb;
    // Native DE rectangle goes directly to MiSTer's scaler. Blanking is
    // outside the source picture, never black padding inside active video.
    assign hblank = diagnostic ? scan_x >= 320 : !(scan_x >= 72 && scan_x < 248);
    assign vblank = diagnostic ? scan_y >= 240 : !(scan_y >= 16 && scan_y < 224);
    assign hsync  = !(scan_x >= 336 && scan_x < 368);
    assign vsync  = !(scan_y >= 244 && scan_y < 247);
    // Pack only the two RGB444 pixels; unused bus bits need no storage.
    wire direct_pixel = write_valid && write_addr == 32'h0c121208 &&
                        header == 32'h8924d67f && memory_write;
    wire [31:0] pixel_data = direct_pixel ? write_data : dma_data;
    wire [14:0] pixel_address = direct_pixel ? cursor : dma_word_addr;
    wire pixel_write = !reset && (direct_pixel || (dma_valid && dma_word_addr < 18304));
    always @(posedge clk) begin
        pixel_forward   <= pixel_write && pixel_address == (in_phone ? read_index : 15'b0);
        forwarded_pixel <= {pixel_data[27:16], pixel_data[11:0]};
    end
    ngage_bram #(
        .AW         (15),
        .DW         (24),
        .DEPTH      (18304),
        .READ_ONLY_B(1)
    ) framebuffer (
        .clk   (clk),
        .addr_a(pixel_address),
        .addr_b(in_phone ? read_index : 15'b0),
        .data_a({pixel_data[27:16], pixel_data[11:0]}),
        .data_b(24'b0),
        .we_a  (pixel_write),
        .we_b  (1'b0),
        .q_a   (),
        .q_b   (pixel_q)
    );
    always @(posedge clk) begin
        div               <= div + 1'b1;
        ce_pix            <= div == 0;
        unsupported_valid <= 0;
        if (div == 0) begin
            if (x == 399) begin
                x <= 0;
                if (y == 261) y <= 0;
                else y <= y + 1'b1;
            end else x <= x + 1'b1;
            scan_x <= x;
            scan_y <= y;
        end
        if (reset) begin
            last_command        <= 0;
            row_start           <= 0;
            row_end             <= 208;
            col_start           <= 2;
            col_end             <= 177;
            window_words        <= 0;
            window_first        <= 0;
            unsupported_header  <= 0;
            unsupported_command <= 0;
            unsupported_data    <= 0;
            header              <= 0;
            memory_write        <= 0;
            display_on          <= 0;
            cursor              <= 0;
            frame_complete      <= 0;
            incomplete          <= 0;
            unsupported         <= 0;
            valid_rows          <= 0;
            row_progress        <= 0;
            next_dma_word       <= 0;
            row_number          <= 0;
        end else begin
            if (dma_valid && dma_word_addr < 18304) begin
                if (!frame_complete) incomplete <= 1;
                if (dma_word_addr % 15'd88 == 0) begin
                    row_number    <= dma_row[7:0];
                    row_progress  <= 1;
                    next_dma_word <= dma_word_addr + 1'b1;
                end else if (row_progress != 0 && dma_word_addr == next_dma_word) begin
                    next_dma_word <= next_dma_word + 1'b1;
                    if (row_progress == 87) begin
                        valid_rows   <= valid_rows | row_bit;
                        row_progress <= 0;
                        if (&(valid_rows | row_bit)) begin
                            frame_complete <= 1;
                            incomplete     <= 0;
                        end
                    end else row_progress <= row_progress + 1'b1;
                end else row_progress <= 0;
            end
            if (dma_frame_full) begin
                frame_complete <= 1;
                incomplete     <= 0;
            end
            if (write_valid) begin
                if (write_addr == 32'h0c121200) begin
                    header <= write_data;
                    if (window_words != 0) unknown(header, window_first, last_command);
                    window_words <= 0;
                    if (write_data == 32'h09240003 &&
                        (last_command == 8'h15 || last_command == 8'h75))
                        window_words <= 2;
                end else if (write_addr == 32'h0c121208) begin
                    if (header == 32'h09200000) begin
                        last_command <= write_data[7:0];
                        // A new command terminates the previous direct memory-write phase.
                        memory_write <= 0;
                        case (write_data)
                            32'h5c: begin
                                if (full_window) begin
                                    memory_write   <= 1;
                                    cursor         <= 0;
                                    incomplete     <= 1;
                                    frame_complete <= 0;
                                    valid_rows     <= 0;
                                    row_progress   <= 0;
                                end else unknown(header, write_data, write_data[7:0]);
                            end
                            32'haf:  display_on <= 1;
                            // Window opcodes are understood; geometry is checked after payload.
                            32'h15, 32'h75: begin
                            end
                            default: unknown(header, write_data, write_data[7:0]);
                        endcase
                    end else if (header == 32'h09240003 && window_words != 0) begin
                        window_words <= window_words - 1'b1;
                        if (window_words == 2) window_first <= write_data;
                        else begin
                            if (last_command == 8'h75) begin
                                row_start <= window_first[7:0];
                                row_end   <= window_first[27:20];
                            end else begin
                                col_start <= window_first[7:0];
                                col_end   <= window_first[27:20];
                            end
                            // The second zero word is explicitly emitted by stock firmware.
                            // Partial-window endpoint/wrap semantics remain unresolved: flag them.
                            if (write_data != 0 || (window_first & 32'hf00fff00) != 0 ||
                                (last_command == 8'h75 &&
                                 !(window_first[7:0] == 0 &&
                                   (window_first[27:20] == 207 || window_first[27:20] == 208))) ||
                                (last_command == 8'h15 && window_first != 32'h0b100002))
                                unknown(header, window_first, last_command);
                        end
                    end else if (header == 32'h8924d67f && memory_write) begin
                        if (cursor == 18303) begin
                            memory_write   <= 0;
                            frame_complete <= 1;
                            incomplete     <= 0;
                        end else cursor <= cursor + 1'b1;
                    end else if (header[31:16] == 16'h8924 || header[31:16] == 16'h0924)
                        unknown(header, write_data, last_command);
                end
            end

        end
    end
    always @* begin
        phone_rgb = scan_x[0] ? pixel_word[23:12] : pixel_word[11:0];
        rgb       = 0;
        if (scan_x < 320 && scan_y < 240) begin
            if (diagnostic) begin
                // Distinct bars plus eight live state cells make this explicitly a test screen.
                case (scan_x[8:5])
                    0:       rgb = 12'hf00;
                    1:       rgb = 12'h0f0;
                    2:       rgb = 12'h00f;
                    3:       rgb = 12'hff0;
                    4:       rgb = 12'h0ff;
                    5:       rgb = 12'hf0f;
                    6:       rgb = 12'hfff;
                    default: rgb = 12'h555;
                endcase
                if (scan_y >= 208 && scan_y < 224 && scan_x < 256) begin
                    if (scan_x[7:5] == 4)
                        case (save_state)
                            1:       rgb = 12'hf90;  // dirty
                            2:       rgb = 12'h0cf;  // saving
                            3:       rgb = 12'h0f0;  // saved
                            4:       rgb = 12'hf00;  // error
                            default: rgb = 12'h333;  // unmounted
                        endcase
                    else rgb = status[scan_x[7:5]] ? 12'h0f0 : 12'h200;
                end
            end else if (display_on && frame_complete && scan_x >= 72 && scan_x < 248 &&
                         scan_y >= 16 && scan_y < 224)
                rgb = phone_rgb;
        end
        // Phone mode contains only guest pixels. Unsupported/incomplete state
        // remains in the diagnostic page, exported flags and bounded command log.
    end
endmodule
