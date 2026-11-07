// Bounded hardware trace buffer and first fault. Readout uses 16-bit words:
// 0 magic, 1 version, 2..3 fault address, 4 reason, 5 count, 6 next slot,
// 7 wrapped, then 64 slots of six words: address, data, byte lanes, time.
module ngage_diagnostics (
    input  wire        clk,
    input  wire        cold_reset,
    input  wire        freeze_trace,
    input  wire        fault,
    input  wire        fault_is_fetch,
    input  wire [31:0] fault_address,
    input  wire [ 2:0] fault_reason,
    input  wire        trace_valid,
    input  wire        trace_lost,
    input  wire [31:0] trace_addr,
    input  wire [31:0] trace_data,
    input  wire [ 3:0] trace_sel,
    input  wire [10:0] read_word,
    output reg  [15:0] read_data,
    output reg         fault_seen = 0
);
    reg [31:0] first_fetch_address = 0;
    reg [ 2:0] first_fetch_reason = 0;
    reg        fetch_seen = 0;
    reg [31:0] first_address = 0;
    reg [ 2:0] first_reason = 0;
    reg [31:0] ticks = 0;
    reg [15:0] dropped = 0;
    reg [ 5:0] next_slot = 0;
    reg [ 6:0] count = 0;
    reg        wrapped = 0;
    reg [31:0] addresses[0:63], values[0:63];
    reg [19:0] info[0:63];
    integer slot, field;
    always @(posedge clk) begin
        if (cold_reset) begin
            ticks               <= 0;
            fault_seen          <= 0;
            first_address       <= 0;
            first_reason        <= 0;
            first_fetch_address <= 0;
            first_fetch_reason  <= 0;
            fetch_seen          <= 0;
            next_slot           <= 0;
            count               <= 0;
            wrapped             <= 0;
            dropped             <= 0;
        end else begin
            ticks <= ticks + 1'b1;
            if (fault && fault_is_fetch && !fetch_seen) begin
                fetch_seen          <= 1;
                first_fetch_address <= fault_address;
                first_fetch_reason  <= fault_reason;
            end
            if (fault && !fault_is_fetch && !fault_seen) begin
                fault_seen    <= 1;
                first_address <= fault_address;
                first_reason  <= fault_reason;
            end
            if ((trace_valid && freeze_trace) || trace_lost) begin
                if (dropped == 16'hffff ||
                    (dropped == 16'hfffe && trace_valid && freeze_trace && trace_lost))
                    dropped <= 16'hffff;
                else
                    dropped <= dropped + {15'b0, (trace_valid && freeze_trace)} +
                        {15'b0, trace_lost};
            end
            if (trace_valid && !freeze_trace) begin
                addresses[next_slot] <= trace_addr;
                values[next_slot]    <= trace_data;
                info[next_slot]      <= {trace_sel, ticks[15:0]};
                next_slot            <= next_slot + 1'b1;
                if (count < 64) count <= count + 1'b1;
                else wrapped <= 1;
            end
        end
    end
    always @* begin
        slot      = 0;
        field     = 0;
        read_data = 0;
        case (read_word)
            0:   read_data = 16'h4e47;
            1:   read_data = 16'h0001;
            2:   read_data = first_address[15:0];
            3:   read_data = first_address[31:16];
            4:   read_data = {12'b0, fault_seen, first_reason};
            5:   read_data = {9'b0, count};
            6:   read_data = {10'b0, next_slot};
            7:   read_data = {15'b0, wrapped};
            392: read_data = dropped;
            393: read_data = first_fetch_address[15:0];
            394: read_data = first_fetch_address[31:16];
            395: read_data = {12'b0, fetch_seen, first_fetch_reason};
            default:
            if (read_word >= 8 && read_word < 392) begin
                slot  = ({21'b0, read_word} - 32'd8) / 32'd6;
                field = ({21'b0, read_word} - 32'd8) % 32'd6;
                if (count == 64 || slot < count)
                    case (field)
                        0: read_data = addresses[slot][15:0];
                        1: read_data = addresses[slot][31:16];
                        2: read_data = values[slot][15:0];
                        3: read_data = values[slot][31:16];
                        4: read_data = {12'b0, info[slot][19:16]};
                        5: read_data = info[slot][15:0];
                    endcase
            end
        endcase
    end
endmodule
