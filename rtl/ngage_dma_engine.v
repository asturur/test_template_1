// One captured transfer, expressed as an ordered little-endian byte stream.
// Widths are byte counts (1, 2 or 4); transfer_bytes is the literal byte budget.
// The frontend converts hardware count units for its selected transfer mode.
// All addresses are physical. Register decoding, aliases and IRQs belong to
// the frontend. Fixed-side ready inputs must be tied high for unpaced memory.
// Readiness gates packet preparation; the route must reserve endpoint capacity
// at command acceptance. Once offered, a packet is stable until accepted or stop.
// Reset cancels ownership: reset/drain the downstream route at the same boundary.
module ngage_dma_engine (
    input  wire        clk,
    input  wire        reset,
    input  wire        transfer_valid,
    output wire        transfer_ready,
    input  wire [31:0] source_addr,
    input  wire [31:0] destination_addr,
    input  wire [ 2:0] source_bytes,
    input  wire [ 2:0] destination_bytes,
    input  wire        source_increment,
    input  wire        destination_increment,
    input  wire [34:0] transfer_bytes,
    input  wire        source_ready,
    input  wire        destination_ready,
    input  wire        stop,
    output wire        busy,
    output reg         done,
    output reg         error,
    output reg         aborted,
    output wire        cmd_valid,
    input  wire        cmd_ready,
    output reg         cmd_write,
    output reg  [31:0] cmd_addr,
    output reg  [31:0] cmd_data,
    output reg  [ 3:0] cmd_be,
    input  wire        rsp_valid,
    input  wire        rsp_error,
    input  wire [31:0] rsp_data
);
    localparam IDLE = 2'd0, RUN = 2'd1, OFFER = 2'd2, WAIT = 2'd3;
    reg [ 1:0] state;
    reg [31:0] src;
    reg [31:0] dst;
    reg [ 2:0] src_bytes;
    reg [ 2:0] dst_bytes;
    reg        src_inc;
    reg        dst_inc;
    reg [34:0] source_left;
    // A read can append four bytes to three waiting destination bytes.
    reg [63:0] buffer;
    reg [ 3:0] fill;
    reg [ 2:0] packet_bytes;
    reg [ 1:0] packet_lane;
    reg        stopping;

    function [31:0] byte_mask;
        input [2:0] bytes;
        begin
            case (bytes)
                3'd1:    byte_mask = 32'h000000ff;
                3'd2:    byte_mask = 32'h0000ffff;
                3'd3:    byte_mask = 32'h00ffffff;
                default: byte_mask = 32'hffffffff;
            endcase
        end
    endfunction

    function [3:0] lane_mask;
        input [2:0] bytes;
        begin
            case (bytes)
                3'd1:    lane_mask = 4'b0001;
                3'd2:    lane_mask = 4'b0011;
                3'd3:    lane_mask = 4'b0111;
                default: lane_mask = 4'b1111;
            endcase
        end
    endfunction

    wire source_width_ok = source_bytes == 1 || source_bytes == 2 || source_bytes == 4;
    wire destination_width_ok = destination_bytes == 1 || destination_bytes == 2 ||
                                destination_bytes == 4;
    // Include the carry above the entire byte budget before checking the
    // physical address range; a large budget must not wrap into a valid range.
    wire [35:0] source_last = {4'b0000, source_addr} +
        (source_increment ? {1'b0, transfer_bytes} : {33'd0, source_bytes}) - 36'd1;
    wire [35:0] destination_last = {4'b0000, destination_addr} +
        (destination_increment ? {1'b0, transfer_bytes} : {33'd0, destination_bytes}) - 36'd1;
    wire aligned_source = (source_addr & ({29'd0, source_bytes} - 32'd1)) == 0;
    wire aligned_destination = (destination_addr & ({29'd0, destination_bytes} - 32'd1)) == 0;
    wire descriptor_ok = transfer_bytes != 0 && source_width_ok && destination_width_ok &&
        aligned_source && aligned_destination && source_last <= 36'h0ffffffff &&
        destination_last <= 36'h0ffffffff;

    assign transfer_ready = !reset && !stop && state == IDLE;
    assign busy           = state != IDLE;
    assign cmd_valid      = !reset && !stop && !stopping && state == OFFER;
    wire        accepted = cmd_valid && cmd_ready;
    wire        response = rsp_valid && (state == WAIT || accepted);
    wire [ 2:0] write_bytes = fill < {1'b0, dst_bytes} ? fill[2:0] : dst_bytes;
    wire [ 2:0] read_packet_bytes = source_left < {32'd0, src_bytes} ? source_left[2:0] : src_bytes;
    wire [31:0] read_bytes = (rsp_data >> (packet_lane * 8)) & byte_mask(packet_bytes);
    wire [31:0] write_data = (buffer[31:0] & byte_mask(write_bytes)) << (dst[1:0] * 8);

    always @(posedge clk) begin
        if (reset) begin
            state        <= IDLE;
            done         <= 1'b0;
            error        <= 1'b0;
            aborted      <= 1'b0;
            stopping     <= 1'b0;
            source_left  <= 0;
            fill         <= 0;
            buffer       <= 0;
            cmd_write    <= 1'b0;
            cmd_addr     <= 0;
            cmd_data     <= 0;
            cmd_be       <= 0;
            packet_bytes <= 0;
            packet_lane  <= 0;
        end else begin
            done    <= 1'b0;
            error   <= 1'b0;
            aborted <= 1'b0;

            // Errors remain errors even if a stop coincides with the response.
            if (response) begin
                if (rsp_error) begin
                    error <= 1'b1;
                    state <= IDLE;
                end else if (stop || stopping) begin
                    aborted <= 1'b1;
                    state   <= IDLE;
                end else begin
                    if (cmd_write) begin
                        buffer <= buffer >> (packet_bytes * 8);
                        fill   <= fill - {1'b0, packet_bytes};
                        if (dst_inc && (source_left != 0 || fill > {1'b0, packet_bytes}))
                            dst <= dst + {29'd0, packet_bytes};
                    end else begin
                        buffer      <= buffer | ({32'd0, read_bytes} << (fill * 8));
                        fill        <= fill + {1'b0, packet_bytes};
                        source_left <= source_left - {32'd0, packet_bytes};
                        if (src_inc && source_left > {32'd0, packet_bytes})
                            src <= src + {29'd0, packet_bytes};
                    end
                    state <= RUN;
                end
            end else if (state != IDLE && (stop || stopping)) begin
                if (state == WAIT) stopping <= 1'b1;
                else begin
                    aborted <= 1'b1;
                    state   <= IDLE;
                end
            end else begin
                case (state)
                    IDLE: begin
                        stopping <= 1'b0;
                        if (transfer_valid && transfer_ready) begin
                            if (!descriptor_ok) error <= 1'b1;
                            else begin
                                src         <= source_addr;
                                dst         <= destination_addr;
                                src_bytes   <= source_bytes;
                                dst_bytes   <= destination_bytes;
                                src_inc     <= source_increment;
                                dst_inc     <= destination_increment;
                                source_left <= transfer_bytes;
                                buffer      <= 0;
                                fill        <= 0;
                                state       <= RUN;
                            end
                        end
                    end
                    RUN: begin
                        if (source_left == 0 && fill == 0) begin
                            done  <= 1'b1;
                            state <= IDLE;
                        end else if (fill >= {1'b0, dst_bytes} || source_left == 0) begin
                            if (dst_inc || destination_ready) begin
                                cmd_write    <= 1'b1;
                                cmd_addr     <= {dst[31:2], 2'b00};
                                cmd_data     <= write_data;
                                cmd_be       <= lane_mask(write_bytes) << dst[1:0];
                                packet_bytes <= write_bytes;
                                packet_lane  <= dst[1:0];
                                state        <= OFFER;
                            end
                        end else if (src_inc || source_ready) begin
                            cmd_write    <= 1'b0;
                            cmd_addr     <= {src[31:2], 2'b00};
                            cmd_data     <= 0;
                            cmd_be       <= lane_mask(read_packet_bytes) << src[1:0];
                            packet_bytes <= read_packet_bytes;
                            packet_lane  <= src[1:0];
                            state        <= OFFER;
                        end
                    end
                    OFFER:   if (accepted) state <= WAIT;
                    WAIT: begin
                    end
                    default: state <= IDLE;
                endcase
            end
        end
    end
endmodule
