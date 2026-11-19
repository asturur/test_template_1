// Share the SDRAM line port between CPU refills and LCD uploads.
module ngage_sdram_line_mux #(
    parameter integer LCD_LINE_BYTES = 32
) (
    input  wire        clk,
    input  wire        reset,
    input  wire        cpu_lock,
    input  wire        scalar_waiting,
    input  wire        scalar_accept,
    input  wire        scalar_active,
    output wire        hold_scalar,
    input  wire        cpu_req,
    input  wire [24:0] cpu_addr,
    output wire        cpu_ready,
    output wire        cpu_valid,
    output wire        cpu_last,
    input  wire        lcd_req,
    input  wire [24:0] lcd_addr,
    output wire        lcd_ready,
    output wire        lcd_valid,
    output wire        lcd_last,
    output wire        ram_req,
    output wire        ram_short,
    output wire [24:0] ram_addr,
    input  wire        ram_ready,
    input  wire        ram_valid,
    input  wire        ram_last
);
    reg owned = 0, owner_lcd = 0, prefer_lcd = 0;
    reg [1:0] scalar_slots = 0;
    reg [1:0] scalar_idle = 2;
    wire scalar_due = scalar_slots != 0 && (scalar_waiting || scalar_active || scalar_idle < 2);
    wire offer = !reset && !cpu_lock && !owned;
    wire select_lcd = lcd_req && (!cpu_req || prefer_lcd) && !scalar_due;
    assign hold_scalar = offer && select_lcd;
    assign ram_req     = offer && (cpu_req || select_lcd);
    assign ram_addr    = select_lcd ? lcd_addr : cpu_addr;
    assign ram_short   = select_lcd && LCD_LINE_BYTES == 16;
    assign cpu_ready   = offer && !select_lcd && ram_ready;
    assign lcd_ready   = offer && select_lcd && ram_ready;
    assign cpu_valid   = !reset && owned && !owner_lcd && ram_valid;
    assign lcd_valid   = !reset && owned && owner_lcd && ram_valid;
    assign cpu_last    = cpu_valid && ram_last;
    assign lcd_last    = lcd_valid && ram_last;

    always @(posedge clk) begin
        if (reset) begin
            owned        <= 0;
            owner_lcd    <= 0;
            prefer_lcd   <= 0;
            scalar_slots <= 0;
            scalar_idle  <= 2;
        end else begin
            if (scalar_waiting || scalar_active) scalar_idle <= 0;
            else if (scalar_idle < 2) scalar_idle <= scalar_idle + 1'b1;
            if (scalar_accept && scalar_slots != 0) scalar_slots <= scalar_slots - 1'b1;
            if (ram_req && ram_ready) begin
                owned      <= 1;
                owner_lcd  <= select_lcd;
                prefer_lcd <= !select_lcd;
                // Give two scalar grants a chance between LCD lines. The
                // idle grace covers a request dropping between adjacent words.
                if (select_lcd) scalar_slots <= 2;
            end
            if (owned && ram_valid && ram_last) owned <= 0;
        end
    end
endmodule
