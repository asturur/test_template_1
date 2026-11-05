// Single outstanding 32-bit client request on MiSTer's 64-bit DDR port.
// req_valid must remain asserted until req_ready; responses are one-cycle pulses.
// A reset cancels an unaccepted command, but an accepted read is drained and
// discarded before a new request can be accepted.
module ngage_ddr_adapter (
    input wire clk, input wire reset,
    input wire req_valid, output wire req_ready,
    input wire req_write, input wire [31:0] req_addr,
    input wire [31:0] req_wdata, input wire [3:0] req_be,
    output reg rsp_valid, output reg [31:0] rsp_data,
    output wire [28:0] ddr_addr, output wire [63:0] ddr_din,
    output wire [7:0] ddr_be, output wire ddr_rd, output wire ddr_we,
    input wire ddr_busy, input wire [63:0] ddr_dout,
    input wire ddr_dout_ready
);
    localparam IDLE=2'd0, ISSUE=2'd1, READ_WAIT=2'd2;
    reg [1:0] state = IDLE;
    reg [31:0] address, data;
    reg [3:0] mask;
    reg write_op, discard = 1'b0;
    wire [31:0] lane_read;
    ngage_ddr_lanes lanes(address, data, mask, ddr_dout,
                          ddr_addr, ddr_din, ddr_be, lane_read);
    assign req_ready = (state == IDLE) && !reset;
    assign ddr_rd = (state == ISSUE) && !write_op && !reset;
    assign ddr_we = (state == ISSUE) && write_op && !reset;
    always @(posedge clk) begin
        rsp_valid <= 1'b0;
        case (state)
            IDLE: if (req_valid && req_ready) begin
                address <= req_addr; data <= req_wdata; mask <= req_be;
                write_op <= req_write; discard <= 1'b0; state <= ISSUE;
            end
            ISSUE: if (reset) state <= IDLE;
            else if (!ddr_busy) begin
                if (write_op) begin rsp_valid <= 1'b1; state <= IDLE; end
                else if (ddr_dout_ready) begin
                    rsp_data <= lane_read; rsp_valid <= 1'b1; state <= IDLE;
                end else state <= READ_WAIT;
            end
            READ_WAIT: begin
                if (reset) discard <= 1'b1;
                if (ddr_dout_ready) begin
                    if (!discard && !reset) begin rsp_data <= lane_read; rsp_valid <= 1'b1; end
                    state <= IDLE;
                end
            end
            default: state <= IDLE;
        endcase
    end
endmodule
