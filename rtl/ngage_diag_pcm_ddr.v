// Optional 48 kHz signed stereo output monitor. No backpressure to audio.
// HPS may copy an older part of the 65536-frame ring after reading the head.
// A nonzero drop count invalidates that capture.
module ngage_diag_pcm_ddr #(
    parameter [31:0] HEAD = 32'h31900000,
    parameter [31:0] RING = 32'h31940000,
    parameter integer RING_BITS = 16,
    parameter integer HEAD_BITS = 8
) (
    input  wire         clk,
    input  wire         reset,
    input  wire         sample_valid,
    input  wire [ 31:0] sample,
    input  wire [  1:0] activity,
    output wire         req_valid,
    input  wire         req_ready,
    output wire [ 31:0] req_addr,
    output wire [ 31:0] req_data,
    input  wire         rsp_valid
);
    localparam [2:0] ZERO_HEAD = 0, ZERO_DROPS = 1, IDLE = 2,
                     WRITE_FRAME = 3, WRITE_DROPS = 4, WRITE_HEAD = 5;
    reg [2:0]  state = ZERO_HEAD;
    reg        waiting = 0;
    reg [31:0] count = 0, frame = 0;
    reg [29:0] drops = 0;
    reg [ 1:0] overlap = 0;
    reg [31:0] head_drops = 0;

    assign req_valid = !reset && state != IDLE && !waiting;
    assign req_addr = state == WRITE_FRAME ?
        RING + {{(30-RING_BITS){1'b0}}, count[RING_BITS-1:0], 2'b00} :
        (state == WRITE_DROPS || state == ZERO_DROPS ? HEAD + 4 : HEAD);
    assign req_data = state == WRITE_FRAME ? frame :
        state == WRITE_DROPS ? head_drops :
        state == WRITE_HEAD ? count : 32'b0;

    always @(posedge clk) begin
        if (reset) begin
            state      <= ZERO_HEAD;
            waiting    <= 1'b0;
            count      <= 32'd0;
            drops      <= 30'd0;
            overlap    <= 2'd0;
            frame      <= 32'd0;
            head_drops <= 32'd0;
        end else begin
            if (req_valid && req_ready)
                waiting <= 1'b1;
            if (waiting && rsp_valid) begin
                waiting <= 1'b0;
                case (state)
                    ZERO_HEAD: state <= ZERO_DROPS;
                    ZERO_DROPS: state <= IDLE;
                    WRITE_FRAME: begin
                        count <= count + 1'b1;
                        if (&count[HEAD_BITS-1:0]) begin
                            head_drops <= {overlap, drops};
                            state <= WRITE_DROPS;
                        end else state <= IDLE;
                    end
                    WRITE_DROPS: state <= WRITE_HEAD;
                    WRITE_HEAD: state <= IDLE;
                    default: state <= IDLE;
                endcase
            end
            if (sample_valid) begin
                if (sample != 0)
                    overlap <= overlap | activity;
                if (state == IDLE) begin
                    frame <= sample;
                    state <= WRITE_FRAME;
                end else if (state != ZERO_HEAD && state != ZERO_DROPS && !(&drops)) begin
                    drops <= drops + 1'b1;
                end
            end
        end
    end
endmodule
