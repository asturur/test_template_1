// GPIO set/clear and UEM-routed loopbacks from the staged board model.
// Routing and pin assignments are diagnostic hypotheses, not verified pins.
module ngage_gpio_loopback (
    input  wire        clk,
    input  wire        reset,
    input  wire        req,
    input  wire        commit,
    input  wire        we,
    input  wire [31:0] addr,
    input  wire [31:0] din,
    input  wire [ 3:0] sel,
    input  wire [15:0] route2a,
    input  wire [15:0] route2c,
    input  wire [15:0] route3b,
    output wire        claim,
    output wire        bad,
    output reg  [31:0] dout
);
    reg [31:0] r200, r204, r208, r20c, r21c;
    wire [31:0] a = {addr[31:2], 2'b00};
    wire [31:0] mask = {{8{sel[3]}}, {8{sel[2]}}, {8{sel[1]}}, {8{sel[0]}}};
    wire width_ok = sel == 1 || sel == 2 || sel == 4 || sel == 8 || sel == 3 || sel == 12 ||
        sel == 15;
    assign claim = req && (a == 32'h0c150200 || a == 32'h0c150204 || a == 32'h0c150208 ||
                           a == 32'h0c15020c || a == 32'h0c15021c);
    assign bad = claim && !width_ok;
    always @* begin
        dout = 0;
        case (a)
            32'h0c150200: dout = r200;
            32'h0c150204: dout = r204;
            32'h0c150208: begin
                dout     = r208;
                dout[19] = route3b[10] && r200[18];
                dout[17] = route2a[3] && r200[16];
            end
            32'h0c15020c: begin
                dout    = r20c;
                dout[1] = route2c[5] && r204[18] && r204[16];
            end
            32'h0c15021c: begin
                dout = {r21c[31:16], 16'b0};
                if (r21c[23]) dout[22] = 1;
            end
        endcase
        dout = dout & mask;
    end
    always @(posedge clk) begin
        if (reset) begin
            r200 <= 0;
            r204 <= 0;
            r208 <= 0;
            r20c <= 0;
            r21c <= 0;
        end else if (req && commit && we && !bad)
            case (a)
                32'h0c150200: begin
                    r200 <= (r200 & ~mask) | (din & mask) | (r200 & mask & 32'hffff0000);
                    if (|mask[31:16]) r204[15:0] <= r204[15:0] & ~(din[31:16] & mask[31:16]);
                end
                32'h0c150204: begin
                    r204 <= (r204 & ~mask) | (din & mask) | (r204 & mask & 32'hffff0000);
                    if (|mask[15:0]) r200[31:16] <= r200[31:16] & ~(din[15:0] & mask[15:0]);
                    if (|mask[31:16]) r208[15:0] <= r208[15:0] & ~(din[31:16] & mask[31:16]);
                end
                32'h0c150208: begin
                    r208 <= (r208 & ~mask) | (din & mask);
                    if (|mask[15:0]) r204[31:16] <= r204[31:16] & ~(din[15:0] & mask[15:0]);
                end
                32'h0c15020c: r20c <= (r20c & ~mask) | (din & mask);
                32'h0c15021c: r21c <= (r21c & ~mask) | (din & mask);
            endcase
    end
endmodule
