module ngage_ddr_adapter #(
    parameter ROM_CACHE       = 0,
              ROM_CACHE_BITS  = 64,
              ROM_CACHE_BYTES = 1024
) (
    input  wire        clk,
    input  wire        reset,
    input  wire        req_valid,
    output wire        req_ready,
    input  wire        req_write,
    input  wire [31:0] req_addr,
    input  wire [31:0] req_wdata,
    input  wire [ 3:0] req_be,
    output wire        rsp_valid,
    output wire [31:0] rsp_data,
    output wire [28:0] ddr_addr,
    output wire [63:0] ddr_din,
    output wire [ 7:0] ddr_be,
    output wire        ddr_rd,
    output wire        ddr_we,
    input  wire        ddr_busy,
    input  wire [63:0] ddr_dout,
    input  wire        ddr_dout_ready,
    input  wire        req_fetch,
    output wire [ 7:0] ddr_burstcount
);
    generate
        if (ROM_CACHE) begin : cached
            wire v, r, w, done;
            wire [31:0] a, d, q;
            wire [               3:0] be;
            wire [ROM_CACHE_BITS-1:0] line;
            wire [               7:0] burst;
            ngage_ddr_rom_cache #(
                .LINE_BITS  (ROM_CACHE_BITS),
                .CACHE_BYTES(ROM_CACHE_BYTES)
            ) cache (
                .clk      (clk),
                .reset    (reset),
                .req_valid(req_valid),
                .req_ready(req_ready),
                .req_write(req_write),
                .req_fetch(req_fetch),
                .req_addr (req_addr),
                .req_wdata(req_wdata),
                .req_be   (req_be),
                .rsp_valid(rsp_valid),
                .rsp_data (rsp_data),
                .mem_valid(v),
                .mem_burst(burst),
                .mem_ready(r),
                .mem_write(w),
                .mem_addr (a),
                .mem_data (d),
                .mem_be   (be),
                .mem_done (done),
                .mem_rdata(q),
                .mem_line (line)
            );
            ngage_ddr_backend #(
                .LINE_BITS(ROM_CACHE_BITS)
            ) backend (
                .clk           (clk),
                .reset         (reset),
                .req_valid     (v),
                .req_ready     (r),
                .req_write     (w),
                .req_addr      (a),
                .req_wdata     (d),
                .req_be        (be),
                .rsp_valid     (done),
                .rsp_data      (q),
                .rsp_line      (line),
                .req_burst     (burst),
                .ddr_burstcount(ddr_burstcount),
                .ddr_addr      (ddr_addr),
                .ddr_din       (ddr_din),
                .ddr_be        (ddr_be),
                .ddr_rd        (ddr_rd),
                .ddr_we        (ddr_we),
                .ddr_busy      (ddr_busy),
                .ddr_dout      (ddr_dout),
                .ddr_dout_ready(ddr_dout_ready)
            );
        end else begin : uncached
            ngage_ddr_backend backend (
                .clk           (clk),
                .reset         (reset),
                .req_valid     (req_valid),
                .req_ready     (req_ready),
                .req_write     (req_write),
                .req_addr      (req_addr),
                .req_wdata     (req_wdata),
                .req_be        (req_be),
                .rsp_valid     (rsp_valid),
                .rsp_data      (rsp_data),
                .ddr_addr      (ddr_addr),
                .ddr_din       (ddr_din),
                .ddr_be        (ddr_be),
                .ddr_rd        (ddr_rd),
                .ddr_we        (ddr_we),
                .ddr_busy      (ddr_busy),
                .ddr_dout      (ddr_dout),
                .ddr_dout_ready(ddr_dout_ready),
                .rsp_line      (),
                .req_burst     (8'd1),
                .ddr_burstcount(ddr_burstcount)
            );
        end
    endgenerate
endmodule

// Single outstanding 32-bit client request on MiSTer's 64-bit DDR port.
// req_valid must remain asserted until req_ready; responses are one-cycle pulses.
// A reset cancels an unaccepted command, but an accepted read is drained and
// discarded before a new request can be accepted.
module ngage_ddr_backend #(
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
    output reg                  rsp_valid,
    output reg  [         31:0] rsp_data,
    output wire [         28:0] ddr_addr,
    output wire [         63:0] ddr_din,
    output wire [          7:0] ddr_be,
    output wire                 ddr_rd,
    output wire                 ddr_we,
    input  wire                 ddr_busy,
    input  wire [         63:0] ddr_dout,
    input  wire                 ddr_dout_ready,
    input  wire [          7:0] req_burst,
    output wire [          7:0] ddr_burstcount,
    output reg  [LINE_BITS-1:0] rsp_line
);
    localparam IDLE = 2'd0, ISSUE = 2'd1, READ_WAIT = 2'd2;
    reg [1:0] state = IDLE;
    reg [31:0] address, data;
    reg [3:0] mask;
    reg [7:0] burst = 1, received = 0;
    assign ddr_burstcount = burst;
    reg write_op, discard = 1'b0;
    wire [31:0] lane_read;
    // synthesis translate_off
    always @(posedge clk)
        if (req_valid && req_ready && !req_write)
            if (req_burst == 0 || req_burst > LINE_BITS / 64)
                $fatal(1, "invalid DDR read burst count");
    // synthesis translate_on
    ngage_ddr_lanes lanes (
        address,
        data,
        mask,
        ddr_dout,
        ddr_addr,
        ddr_din,
        ddr_be,
        lane_read
    );
    assign req_ready = (state == IDLE) && !reset;
    assign ddr_rd    = (state == ISSUE) && !write_op && !reset;
    assign ddr_we    = (state == ISSUE) && write_op && !reset;
    always @(posedge clk) begin
        rsp_valid <= 1'b0;
        case (state)
            IDLE:
            if (req_valid && req_ready) begin
                address  <= req_addr;
                data     <= req_wdata;
                mask     <= req_be;
                write_op <= req_write;
                burst    <= req_write ? 1 : req_burst;
                received <= 0;
                discard  <= 1'b0;
                state    <= ISSUE;
            end
            ISSUE:
            if (reset) state <= IDLE;
            else if (!ddr_busy) begin
                if (write_op) begin
                    rsp_valid <= 1'b1;
                    state     <= IDLE;
                end else if (ddr_dout_ready) begin
                    rsp_line[0+:64] <= ddr_dout;
                    received        <= 1;
                    if (burst == 1) begin
                        rsp_data  <= lane_read;
                        rsp_valid <= 1;
                        state     <= IDLE;
                    end else state <= READ_WAIT;
                end else state <= READ_WAIT;
            end
            READ_WAIT: begin
                if (reset) discard <= 1'b1;
                if (ddr_dout_ready) begin
                    rsp_line[received*64+:64] <= ddr_dout;
                    received                  <= received + 1'b1;
                    if (received + 1 == burst) begin
                        if (!discard && !reset) begin
                            rsp_data  <= lane_read;
                            rsp_valid <= 1;
                        end
                        state <= IDLE;
                    end
                end
            end
            default: state <= IDLE;
        endcase
    end
endmodule
