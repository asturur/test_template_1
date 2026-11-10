// Host diagnostic text overlay. 40x30 cells on the existing 320x240 raster.
// Read-only observations are sampled together every 16 frames (~4 Hz).
// Font and ALL video/control signals share one clock of pipeline latency.
module ngage_debug_video (
    input  wire         clk,
    input  wire         diagnostic,
    input  wire [767:0] values,
    input  wire [ 98:0] panic_report,
    input  wire [  8:0] x,
    input  wire [  8:0] y,
    input  wire         ce_in,
    input  wire         hsync_in,
    input  wire         vsync_in,
    input  wire         hblank_in,
    input  wire         vblank_in,
    input  wire [ 11:0] rgb_in,
    output reg          ce_out = 0,
    output reg          hsync_out = 1,
    output reg          vsync_out = 1,
    output reg          hblank_out = 1,
    output reg          vblank_out = 1,
    output wire [ 11:0] rgb_out
);
    reg [767:0] snapshot = 0;
    reg [ 98:0] panic_snapshot = 0;
    reg [  7:0] frames = 0;
    always @(posedge clk)
        if (ce_in && x == 0 && y == 0) begin
            frames <= frames + 1'b1;
            if (frames[3:0] == 0) begin
                snapshot       <= values;
                panic_snapshot <= panic_report;
            end
        end
    wire [  5:0] column = x[8:3];
    wire [  4:0] row = y[7:3];
    reg  [  7:0] character;
    reg  [319:0] text;
    reg  [111:0] label_text;
    reg  [ 63:0] status_label;
    reg  [ 31:0] number;
    reg status_value, status_cell;
    reg [11:0] status_ink;
    integer item, nibble;
    function [7:0] hex_digit;
        input [3:0] n;
        begin
            hex_digit = n < 10 ? 8'h30 + {4'b0, n} : 8'h41 + {4'b0, n} - 10;
        end
    endfunction
    always @* begin
        character    = " ";
        text         = {40{8'h20}};
        label_text   = {14{8'h20}};
        status_label = {8{8'h20}};
        number       = 0;
        item         = 0;
        nibble       = 0;
        status_value = 0;
        status_cell  = 0;
        status_ink   = 12'h999;
        case (row)
            0:       text = "N-GAGE LIVE DEBUG                       ";
            1:       text = "HEX VALUES - SNAPSHOT 4 HZ              ";
            2:       text = "PC IS FETCH VA                          ";
            28:      text = "FAULT FLAGS: SEE LIVE-CONTROLS DOC      ";
            29:      text = "KEYS HELD SHOWS NOKIA INPUT BITS        ";
            default: text = {40{8'h20}};
        endcase
        if (row == 27) begin
            text = "PANIC 00000000 00000000 00000000 MASK 0 ";
            if (column < 40) character = text[(39-column)*8+:8];
            if (column >= 6 && column < 14) character = hex_digit(panic_snapshot[(13-column)*4+:4]);
            else if (column >= 15 && column < 23)
                character = hex_digit(panic_snapshot[32+(22-column)*4+:4]);
            else if (column >= 24 && column < 32)
                character = hex_digit(panic_snapshot[64+(31-column)*4+:4]);
            else if (column == 38) character = hex_digit({1'b0, panic_snapshot[98:96]});
        end else if (row < 3 || row >= 28) begin
            if (column < 40) character = text[(39-column)*8+:8];
            if (row == 0 && column == 38) character = frames[4] ? "*" : ".";
        end else if (row < 27) begin
            item   = row - 3;
            number = snapshot[item*32+:32];
            case (item)
                0:  label_text = "FETCH PC      ";
                1:  label_text = "LAST FETCH PC ";
                2:  label_text = "LAST FETCH OP ";
                3:  label_text = "CPSR          ";
                4:  label_text = "CYCLES        ";
                5:  label_text = "FETCH COUNT   ";
                6:  label_text = "BUS ADDR      ";
                7:  label_text = "BUS WRITE     ";
                8:  label_text = "BUS READ      ";
                9:  label_text = "BUS FLAGS     ";
                10: label_text = "BUS ACKS      ";
                11: label_text = "BUS ERRORS    ";
                12: label_text = "WAIT NOW      ";
                13: label_text = "WAIT MAX      ";
                14: label_text = "LAST BUS ADR  ";
                15: label_text = "LAST BUS DATA ";
                16: label_text = "DATA FAULT    ";
                17: label_text = "FAULT FETCHPC ";
                18: label_text = "FAULT DATA    ";
                19: label_text = "FAULT FLAGS   ";
                20: label_text = "FAULT REASON  ";
                21: label_text = "BOOT FLAGS    ";
                22: label_text = "CPU FLAGS     ";
                23: label_text = "KEYS HELD     ";
            endcase
            if (column < 14) character = label_text[(13-column)*8+:8];
            else if (column < 22) begin
                nibble    = 21 - column;
                character = hex_digit(number[nibble*4+:4]);
            end
            if (item < 8) begin
                status_value = snapshot[21*32+item];
                case (item)
                    0: status_label = "PLL     ";
                    1: status_label = "ROM     ";
                    2: status_label = "SDRAM   ";
                    3: status_label = "BOARD   ";
                    4: status_label = "SAVE    ";
                    5: status_label = "FAULT   ";
                    6: status_label = "EXPORT  ";
                    7: status_label = "LCD/ERR ";
                endcase
            end else if (item < 17) begin
                status_value = snapshot[22*32+item-8];
                case (item)
                    8:  status_label = "RESET   ";
                    9:  status_label = "IRQ     ";
                    10: status_label = "FIQ     ";
                    11: status_label = "CLAIM   ";
                    12: status_label = "READY   ";
                    13: status_label = "MEMREQ  ";
                    14: status_label = "RAM     ";
                    15: status_label = "FLASH   ";
                    16: status_label = "FLASH IO";
                endcase
            end
            if (item >= 17) begin
                status_value = snapshot[21*32+item-9];
                case (item)
                    17: status_label = "RUN     ";
                    18: status_label = "ROM ERR ";
                    19: status_label = "SAVE ERR";
                    20: status_label = "SAVE BUS";
                    21: status_label = "RESETREQ";
                    22: status_label = "SAVING  ";
                    23: status_label = "LOAD BLK";
                endcase
            end
            if (item < 5) status_ink = status_value ? 12'h0f0 : 12'hf44;
            else if (item == 5 || item == 7 || item == 18 || item == 19 || item == 23)
                status_ink = status_value ? 12'hf44 : 12'h999;
            else if (item == 8 || item == 21) status_ink = status_value ? 12'hfa0 : 12'h0f0;
            else status_ink = status_value ? 12'h0ff : 12'h999;
            if (item < 24) begin
                if (column >= 24 && column < 32) character = status_label[(31-column)*8+:8];
                if (column == 33) begin
                    character   = status_value ? "1" : "0";
                    status_cell = 1;
                end
            end
        end
    end
    wire [7:0] glyph;
    ngage_debug_font font (
        .clk    (clk),
        .address({character[6:0], y[2:0]}),
        .pixels (glyph)
    );
    reg [2:0] bit_q;
    reg active_q = 0, diagnostic_q = 0, status_cell_q = 0, status_value_q = 0;
    reg [4:0] row_q;
    reg [5:0] column_q;
    reg [11:0] rgb_q, status_ink_q;
    always @(posedge clk) begin
        bit_q          <= x[2:0];
        row_q          <= row;
        column_q       <= column;
        active_q       <= x < 320 && y < 240 && !hblank_in && !vblank_in;
        diagnostic_q   <= diagnostic;
        status_cell_q  <= status_cell;
        status_value_q <= status_value;
        status_ink_q   <= status_ink;
        rgb_q          <= rgb_in;
        ce_out         <= ce_in;
        hsync_out      <= hsync_in;
        vsync_out      <= vsync_in;
        hblank_out     <= hblank_in;
        vblank_out     <= vblank_in;
    end
    wire [11:0] ink=status_cell_q ? status_ink_q :
        row_q<3 ? 12'h0ff : column_q<14 ? 12'h999 : 12'hfff;
    assign rgb_out = !diagnostic_q ? rgb_q : !active_q ? 12'h000 : glyph[7-bit_q] ? ink : 12'h001;
endmodule
