// NEM-4 GPIO configuration follows original ekeyb.dll operations. The switch
// contacts, reset direction and pullups remain inferred, not measured pins.
module ngage_keypad (
    input  wire        clk,
    input  wire        reset,
    input  wire [25:0] keys,
    input  wire        req,
    input  wire        commit,
    input  wire        we,
    input  wire [31:0] addr,
    input  wire [31:0] din,
    input  wire [ 3:0] sel,
    input  wire [31:0] base,
    input  wire        genio1_driven,
    input  wire        genio1_level,
    output reg  [31:0] value,
    output wire        irq
);
    // Logical row/column names follow the reference's GPIO drive banks;
    // keys retain this project's public numbering (see docs/live-controls.md).
    reg [5:0] col_drive = 0, row_drive = 6'h3f;
    reg [4:0] row_data = 0;
    reg [5:0] col_data = 0;
    reg [4:0] row_ien = 0;
    reg [5:0] col_ien = 0;
    reg [15:0] genio_dir = 0, genio_out = 0;
    reg [7:0] genio_ien = 0;
    reg music_dir = 0, music_out = 0;
    reg            gpio30_data = 0;
    reg     [ 5:0] last_cols = 6'h3f;
    reg     [15:0] last_genio = 16'h3c06;
    reg     [15:0] genio_inputs;
    wire    [ 4:0] row_low = row_drive[4:0] & ~row_data;
    wire    [ 5:0] col_low = col_drive & ~col_data;
    reg     [31:0] pending = 0;
    reg     [ 4:0] cols;
    reg     [ 5:0] row_inputs;
    reg     [15:0] stick;
    reg     [31:0] press_events;
    integer        k;
    wire    [31:0] a = {addr[31:2], 2'b00};
    wire    [ 5:0] col_falls = last_cols & ~row_inputs & col_ien & ~col_drive;
    wire    [15:0] genio_falls = last_genio & ~genio_inputs & ~genio_dir;
    wire           status_write = req && commit && we && a == 32'h0c150100;
    wire    [31:0] lane_mask = {{8{sel[3]}}, {8{sel[2]}}, {8{sel[1]}}, {8{sel[0]}}};
    wire    [31:0] clear_mask = status_write ? din & lane_mask : 32'b0;
    assign irq = |pending;
    always @* begin
        press_events     = 0;
        press_events[2]  = |col_falls;
        // NEM-4's shared ISR tests E/bit2 only. Its ACK includes bit3,
        // but that alone does not establish a port-D interrupt producer.
        press_events[21] = genio_falls[1] & genio_ien[5];
        press_events[17] = genio_falls[10] & genio_ien[1];
        press_events[19] = genio_falls[13] & genio_ien[3];
        press_events[23] = genio_falls[2] & genio_ien[7];
        press_events[18] = genio_falls[11] & genio_ien[2];
        press_events[22] = last_genio[12] & ~genio_inputs[12] & ~music_dir & genio_ien[6];
    end
    always @(posedge clk) begin
        if (reset) begin
            col_drive   <= 0;
            row_drive   <= 6'h3f;
            row_data    <= 0;
            col_data    <= 0;
            row_ien     <= 0;
            col_ien     <= 0;
            genio_dir   <= 0;
            genio_out   <= 0;
            genio_ien   <= 0;
            music_dir   <= 0;
            music_out   <= 0;
            gpio30_data <= 0;
            last_cols   <= 6'h3f;
            last_genio  <= 16'h3c06;
            pending     <= 0;
        end else begin
            // Track pin levels even when masked: enabling a held low input is
            // not a new falling edge. No CPU transaction waits on this logic.
            last_cols  <= row_inputs;
            last_genio <= genio_inputs;
            // Set wins a simultaneous W1C. Release/held levels generate no events.
            pending    <= (pending & ~clear_mask) | press_events;
            if (req && commit && we) begin
                if (a == 32'h0c15040c)
                    col_drive <=
                        (col_drive | (sel[2] ? din[21:16] : 6'b0)) & ~(sel[3] ? din[29:24] : 6'b0);
                if (a == 32'h0c150400)
                    row_drive[4:0] <= (row_drive[4:0] | (sel[2] ? din[20:16] : 5'b0)) & ~(
                        sel[3] ? din[28:24] : 5'b0);
                // NEM-4 data is a plain low-halfword latch. Direction and
                // per-pin IRQ enable are low-byte set/high-byte clear pairs.
                if (a == 32'h0c150400 && sel[0]) row_data <= din[4:0];
                if (a == 32'h0c15040c && sel[0]) col_data <= din[5:0];
                if (a == 32'h0c150404)
                    row_ien <= (row_ien | (sel[0] ? din[4:0] : 5'b0)) &
                               ~(sel[1] ? din[12:8] : 5'b0);
                if (a == 32'h0c150410)
                    col_ien <= (col_ien | (sel[0] ? din[5:0] : 6'b0)) &
                               ~(sel[1] ? din[13:8] : 6'b0);
                // GENIO's direction is a regular 16-bit field at +20e.
                if (a == 32'h0c15020c)
                    genio_dir <= (genio_dir & ~lane_mask[31:16]) | (din[31:16] & lane_mask[31:16]);
                if (a == 32'h0c150200) genio_out <= genio_out | (din[31:16] & lane_mask[31:16]);
                if (a == 32'h0c150204) genio_out <= genio_out & ~(din[15:0] & lane_mask[15:0]);
                // Music is GENIO28, in the next 16-pin bank, not GENIO12.
                if (a == 32'h0c150210 && sel[1]) music_dir <= din[12];
                if (a == 32'h0c150204 && sel[3] && din[28]) music_out <= 1;
                if (a == 32'h0c150208 && sel[1] && din[12]) music_out <= 0;
                // Original op4 sets at +16; op5 clears at +14.
                if (a == 32'h0c150014)
                    genio_ien <= (genio_ien | (sel[2] ? din[23:16] : 8'b0)) &
                                 ~(sel[0] ? din[7:0] : 8'b0);
                // GPIO30/KPC has separate clear/set output aliases and an
                // inverted direction bit. Other GPIO30 modes remain unmodeled.
                if (a == 32'h0c120c10 && sel[2] && din[19]) gpio30_data <= 0;
                if (a == 32'h0c120c0c && sel[2] && din[19]) gpio30_data <= 1;
                // Full-word direction update from the original Modify32 leaf.
                if (a == 32'h0c120c14 && sel == 15) row_drive[5] <= !din[19];
            end
        end
    end
    always @* begin
        value      = base;
        cols       = ~row_low;
        row_inputs = ~col_low;
        stick      = 16'h3c06;
        if (keys[0]) stick[1] = 0;
        if (keys[1]) stick[10] = 0;
        if (keys[2]) stick[13] = 0;
        if (keys[3]) stick[2] = 0;
        if (keys[4]) stick[11] = 0;
        genio_inputs     = (stick & ~genio_dir) | (genio_out & genio_dir);
        genio_inputs[12] = music_dir ? music_out : !keys[25];
        // The staged UEM loopback can drive GENIO1 during the I/O self-test.
        // An open rocker must not replace its low level with the idle pullup;
        // a pressed rocker can still ground a routed-high line.
        if (genio1_driven && !genio_dir[1]) genio_inputs[1] = genio1_level & !keys[0];
        if (keys[5] && col_low[0]) cols[0] = 0;
        if (keys[6] && col_low[0]) cols[1] = 0;
        if (keys[7] && col_low[1]) cols[0] = 0;
        if (keys[8] && col_low[1]) cols[1] = 0;
        for (k = 0; k < 12; k = k + 1) if (keys[k+9] && col_low[2+k/3]) cols[2+k%3] = 0;
        if ((keys[5] && row_low[0]) || (keys[6] && row_low[1])) row_inputs[0] = 0;
        if ((keys[7] && row_low[0]) || (keys[8] && row_low[1])) row_inputs[1] = 0;
        for (k = 0; k < 4; k = k + 1) begin
            if ((keys[9+3*k] && row_low[2]) || (keys[10+3*k] && row_low[3]) ||
                (keys[11+3*k] && row_low[4]) || (keys[21+k] && row_drive[5] && !gpio30_data))
                row_inputs[2+k] = 0;
        end
        // Driven GPIOs return their own latch rather than the opposite pin.
        cols       = (cols & ~row_drive[4:0]) | (row_data & row_drive[4:0]);
        row_inputs = (row_inputs & ~col_drive) | (col_data & col_drive);
        if (req && !we)
            case (a)
                32'h0c150100: value = (base & ~32'h00ee0004) | (pending & lane_mask);
                32'h0c150208:
                value = (value & ~32'h2c060000) |
                        (({16'b0, genio_inputs} << 16) & 32'h2c060000 & lane_mask);
                32'h0c150400: begin
                    value = (value & ~32'h001f001f) |
                            (({11'b0, row_drive[4:0], 11'b0, cols}) & lane_mask);
                end
                32'h0c15040c: begin
                    value = (value & ~32'h003f003f) |
                            (({10'b0, col_drive, 10'b0, row_inputs}) & lane_mask);
                end
                32'h0c150404: value = (value & ~32'h1f) | ({27'b0, row_ien} & lane_mask);
                32'h0c150410: value = (value & ~32'h3f) | ({26'b0, col_ien} & lane_mask);
                32'h0c150210:
                value = (value & ~32'h1000) | (music_dir ? (32'h1000 & lane_mask) : 32'b0);
                32'h0c150014:
                value = (value & ~32'h00ee00ee) |
                                      ({8'b0, genio_ien, 8'b0, genio_ien} &
                                       32'h00ee00ee & lane_mask);
                32'h0c120c04: begin
                    value[19] = sel[2] && (row_drive[5] ? gpio30_data :
                                !((keys[21] && col_low[2]) ||
                                  (keys[22] && col_low[3]) || (keys[23] && col_low[4]) ||
                                  (keys[24] && col_low[5])));
                end
                32'h0c15020c: begin
                    value = (value & ~32'h2c061000) | ({genio_dir & 16'h2c06, 16'b0} & lane_mask);
                    if (sel[1]) value[12] = genio_inputs[12];
                end
            endcase
    end
endmodule
