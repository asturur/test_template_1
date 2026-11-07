// Experimental switch matrix from scratch/live-controls; pin behavior is
// inferred, not yet verified against a physical keypad.
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
    output reg  [31:0] value,
    output wire        irq
);
    // Logical row/column names follow the reference's GPIO drive banks;
    // keys retain this project's public numbering (see docs/live-controls.md).
    reg [5:0] col_drive = 0, row_drive = 6'h3f;
    reg     [25:0] keys_d = 0;
    reg     [31:0] pending = 0;
    reg     [ 4:0] cols;
    reg     [ 5:0] row_inputs;
    reg     [15:0] stick;
    reg     [31:0] press_events;
    integer        k;
    wire    [31:0] a = {addr[31:2], 2'b00};
    wire    [25:0] pressed = keys & ~keys_d;
    wire           status_write = req && commit && we && a == 32'h0c150100;
    wire    [31:0] lane_mask = {{8{sel[3]}}, {8{sel[2]}}, {8{sel[1]}}, {8{sel[0]}}};
    wire    [31:0] clear_mask = status_write ? din & lane_mask : 32'b0;
    assign irq = |pending;
    always @* begin
        press_events = 0;
        if (|pressed[24:5]) press_events[2] = 1;
        press_events[21] = pressed[0];
        press_events[17] = pressed[1];
        press_events[19] = pressed[2];
        press_events[23] = pressed[3];
        press_events[18] = pressed[4];
        press_events[22] = pressed[25];
    end
    always @(posedge clk) begin
        if (reset) begin
            col_drive <= 0;
            row_drive <= 6'h3f;
            keys_d    <= 0;
            pending   <= 0;
        end else begin
            keys_d  <= keys;
            // Set wins a simultaneous W1C. Release/held levels generate no events.
            pending <= (pending & ~clear_mask) | press_events;
            if (req && commit && we) begin
                if (a == 32'h0c15040c)
                    col_drive <=
                        (col_drive | (sel[2] ? din[21:16] : 6'b0)) & ~(sel[3] ? din[29:24] : 6'b0);
                if (a == 32'h0c150400)
                    row_drive[4:0] <= (row_drive[4:0] | (sel[2] ? din[20:16] : 5'b0)) & ~(
                        sel[3] ? din[28:24] : 5'b0);
                // Reference's GPIO30/KPC line: full-word write, inverted bit 19.
                if (a == 32'h0c120c14 && sel == 15) row_drive[5] <= !din[19];
            end
        end
    end
    always @* begin
        value      = base;
        cols       = ~row_drive[4:0];
        row_inputs = ~col_drive;
        stick      = 16'h2c06;
        if (keys[0]) stick[1] = 0;
        if (keys[1]) stick[10] = 0;
        if (keys[2]) stick[13] = 0;
        if (keys[3]) stick[2] = 0;
        if (keys[4]) stick[11] = 0;
        // The staged UEM loopback can drive GENIO1 during the I/O self-test.
        // An open rocker must not replace its low level with the idle pullup;
        // a pressed rocker can still ground a routed-high line.
        if (genio1_driven) stick[1] = base[17] & !keys[0];
        if (keys[5] && col_drive[0]) cols[0] = 0;
        if (keys[6] && col_drive[0]) cols[1] = 0;
        if (keys[7] && col_drive[1]) cols[0] = 0;
        if (keys[8] && col_drive[1]) cols[1] = 0;
        for (k = 0; k < 12; k = k + 1) if (keys[k+9] && col_drive[2+k/3]) cols[2+k%3] = 0;
        if ((keys[5] && row_drive[0]) || (keys[6] && row_drive[1])) row_inputs[0] = 0;
        if ((keys[7] && row_drive[0]) || (keys[8] && row_drive[1])) row_inputs[1] = 0;
        for (k = 0; k < 4; k = k + 1) begin
            if ((keys[9+3*k] && row_drive[2]) || (keys[10+3*k] && row_drive[3]) ||
                (keys[11+3*k] && row_drive[4]) || (keys[21+k] && row_drive[5]))
                row_inputs[2+k] = 0;
        end
        if (req && !we)
            case (a)
                32'h0c150100: value = (base & ~32'h00ee0004) | (pending & lane_mask);
                32'h0c150208:
                if (|sel[3:2]) value = (value & ~32'h2c060000) | ({16'b0, stick} << 16);
                32'h0c150400: if (|sel[1:0]) value = (value & ~32'h1f) | {27'b0, cols};
                32'h0c15040c: if (|sel[1:0]) value = (value & ~32'h3f) | {26'b0, row_inputs};
                32'h0c120c04: begin
                    value[19] = !(row_drive[5] || (keys[21] && col_drive[2]) ||
                                  (keys[22] && col_drive[3]) || (keys[23] && col_drive[4]) ||
                                  (keys[24] && col_drive[5]));
                end
                32'h0c15020c: if (|sel[1:0]) value[12] = !keys[25];
            endcase
    end
endmodule
