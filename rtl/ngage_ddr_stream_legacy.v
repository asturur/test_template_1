// SPDX-License-Identifier: GPL-3.0-or-later
// Opt-in bridge from the maintained scalar/cache/line interface to D1 stream
// transport. Existing cache and NOR ownership remain outside this module.
module ngage_ddr_stream_legacy #(
    parameter LINE_BITS = 64
) (
    input  wire                 clk,
    input  wire                 reset,
    input  wire                 req_valid,
    output wire                 req_ready,
    input  wire                 req_write,
    input  wire [         31:0] req_addr,
    input  wire [         31:0] req_wdata,
    input  wire [          3:0] req_be,
    input  wire [          7:0] req_burst,
    output wire                 rsp_valid,
    output wire [         31:0] rsp_data,
    output reg  [LINE_BITS-1:0] rsp_line,
    output wire                 rsp_beat_valid,
    output wire [         63:0] rsp_beat_data,
    output wire                 rsp_beat_last,
    output wire [         28:0] ddr_addr,
    output wire [         63:0] ddr_din,
    output wire [          7:0] ddr_be,
    output wire [          7:0] ddr_burstcount,
    output wire                 ddr_rd,
    output wire                 ddr_we,
    input  wire                 ddr_busy,
    input  wire [         63:0] ddr_dout,
    input  wire                 ddr_dout_ready
);
    reg        lane = 0;
    reg [ 6:0] received = 0;
    reg [63:0] last_data = 0;
    wire beat_valid, beat_last, done, cancelled, error;
    wire [63:0] beat_data;
    wire [ 6:0] count = req_write ? 7'd1 : req_burst[6:0];
    wire [ 7:0] mask = req_addr[2] ? {req_be, 4'b0} : {4'b0, req_be};
    assign rsp_valid      = done && !cancelled && !error && !reset;
    assign rsp_data       = lane ? last_data[63:32] : last_data[31:0];
    // The engine head is already registered. Do not add another cycle before
    // the always-ready refill consumer can copy it. The complete line/scalar
    // response still waits for the final beat to be staged and consumed.
    assign rsp_beat_valid = beat_valid && !reset;
    assign rsp_beat_data  = beat_data;
    assign rsp_beat_last  = beat_last;
    always @(posedge clk) begin
        if (req_valid && req_ready) begin
            lane     <= req_addr[2];
            received <= 0;
        end
        if (beat_valid) begin
            rsp_line[received*64+:64] <= beat_data;
            last_data                 <= beat_data;
            received                  <= received + 1'b1;
        end
    end
    ngage_ddr_stream transport (
        .clk                (clk),
        .transport_reset    (reset),
        .phone_reset        (1'b0),
        .req_valid          (req_valid),
        .req_ready          (req_ready),
        .req_owner          (2'b0),
        .req_cancel_on_phone(1'b0),
        .req_write          (req_write),
        .req_stream         (1'b0),
        .req_addr           ({req_addr[31:3], 3'b0}),
        .req_count          (count),
        .req_data           ({req_wdata, req_wdata}),
        .req_be             (mask),
        .write_valid        (1'b0),
        .write_ready        (),
        .write_data         (64'b0),
        .write_be           (8'b0),
        .write_last         (1'b0),
        .read_valid         (beat_valid),
        .read_ready         (1'b1),
        .read_owner         (),
        .read_data          (beat_data),
        .read_last          (beat_last),
        .done               (done),
        .done_owner         (),
        .error              (error),
        .cancelled          (cancelled),
        .idle               (),
        .ddr_addr           (ddr_addr),
        .ddr_din            (ddr_din),
        .ddr_be             (ddr_be),
        .ddr_burstcount     (ddr_burstcount),
        .ddr_rd             (ddr_rd),
        .ddr_we             (ddr_we),
        .ddr_busy           (ddr_busy),
        .ddr_dout           (ddr_dout),
        .ddr_dout_ready     (ddr_dout_ready)
    );
    // synthesis translate_off
    always @(posedge clk)
        if (req_valid && req_ready && !req_write)
            if (req_burst == 0 || req_burst > LINE_BITS / 64)
                $fatal(1, "invalid legacy DDR read count");
    // synthesis translate_on
endmodule
