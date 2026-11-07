// UPP LCD DMA channel, inferred from the staged C++ board. This models the
// observed SDRAM-to-LCD transfer; it is not verified hardware timing.
module ngage_lcd_dma (
    input  wire        clk,
    input  wire        reset,
    input  wire        req,
    input  wire        commit,
    input  wire        we,
    input  wire [31:0] addr,
    input  wire [31:0] din,
    input  wire [ 3:0] sel,
    output wire        claim,
    output reg         bad,
    output reg  [31:0] dout,
    output wire        mem_req,
    output wire [24:0] mem_addr,
    input  wire        mem_ack,
    input  wire [31:0] mem_data,
    output reg         lcd_valid,
    output reg         lcd_frame_full,
    output reg  [14:0] lcd_word_addr,
    output reg  [31:0] lcd_data,
    output reg         irq_pending,
    input  wire        irq_clear
);
    reg [31:0] source = 0, destination = 0, count_reg = 0, control = 0;
    reg [31:0] cursor = 0, remaining = 0;
    reg busy = 0, full_frame = 0, finishing = 0;
    wire [31:0] a = {addr[31:2], 2'b00};
    wire [31:0] frame_offset = cursor - 32'h0a000020;
    wire hit = a == 32'h0c120348 || a == 32'h0c120354 || a == 32'h0c120360 || a == 32'h0c12036c;
    wire valid_start = (destination == 32'h10121208 || destination == 32'h0c121208) &&
        source >= 32'h0a000000 && source[1:0] == 0 && count_reg < 32'h00040000 &&
        {1'b0, source} + ({1'b0, count_reg} + 1) * 4 <= 33'h00b000000;
    assign claim    = req && hit;
    assign mem_req  = busy;
    assign mem_addr = cursor[24:0];
    always @* begin
        bad = claim && (sel != 15 || (we && a == 32'h0c120348 && din == 2 &&
                                      (busy || finishing || !valid_start)));
        case (a)
            32'h0c120348: dout = control;
            32'h0c120354: dout = source;
            32'h0c120360: dout = destination;
            32'h0c12036c: dout = count_reg;
            default:      dout = 0;
        endcase
    end
    always @(posedge clk) begin
        lcd_valid      <= 0;
        lcd_frame_full <= 0;
        if (reset) begin
            source      <= 0;
            destination <= 0;
            count_reg   <= 0;
            control     <= 0;
            cursor      <= 0;
            remaining   <= 0;
            busy        <= 0;
            full_frame  <= 0;
            finishing   <= 0;
            irq_pending <= 0;
        end else begin
            if (irq_clear) irq_pending <= 0;
            if (finishing) begin
                finishing   <= 0;
                irq_pending <= 1;
            end
            if (busy && mem_ack) begin
                if (cursor >= 32'h0a000020 && cursor < 32'h0a011e20) begin
                    lcd_valid     <= 1;
                    lcd_word_addr <= frame_offset[16:2];
                    lcd_data      <= mem_data;
                end
                if (remaining == 1) begin
                    busy           <= 0;
                    remaining      <= 0;
                    finishing      <= 1;
                    lcd_frame_full <= full_frame;
                end else begin
                    cursor    <= cursor + 4;
                    remaining <= remaining - 1'b1;
                end
            end
            if (claim && commit && !bad && we)
                case (a)
                    32'h0c120348: begin
                        control <= din;
                        if (din == 2) begin
                            busy       <= 1;
                            cursor     <= source;
                            remaining  <= count_reg + 1;
                            full_frame <= source == 32'h0a000020 && count_reg == 18303;
                        end
                    end
                    32'h0c120354: source <= din;
                    32'h0c120360: destination <= din;
                    32'h0c12036c: count_reg <= din;
                endcase
        end
    end
endmodule
