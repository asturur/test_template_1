// Reproduces the staged C++ MDI announcement/consumption hypothesis only.
// This does not implement a DSP or fabricate a self-test response.
module ngage_mdi_stub #(
    parameter integer ANNOUNCE_TICKS = 20
) (
    input  wire        clk,
    input  wire        reset,
    input  wire        tick,
    input  wire        periodic_active,
    input  wire        req,
    input  wire        commit,
    input  wire        we,
    input  wire [31:0] addr,
    input  wire [31:0] din,
    input  wire [ 3:0] sel,
    output wire        claim,
    output wire        bad,
    output reg  [31:0] dout,
    output reg  [15:0] irq_events
);
    reg [31:0] control, pointers, receive_ptr, frame0, frame1;
    reg control_seen, pointers_seen, receive_seen, armed, sent;
    localparam integer ELAPSED_BITS = ANNOUNCE_TICKS > 1 ? $clog2(ANNOUNCE_TICKS) : 1;
    reg [ELAPSED_BITS-1:0] elapsed;
    reg [31:0] n_control, n_pointers, n_receive, n_frame0, n_frame1;
    reg [31:0] bus_control, bus_pointers, bus_receive, bus_frame0, bus_frame1;
    wire [31:0] a = {addr[31:2], 2'b00};
    wire accepted = commit && claim && !bad;
    wire control_present = control_seen || (accepted && a == 32'h0c14b004);
    wire pointers_present = pointers_seen || (accepted && a == 32'h0c1003e8);
    wire receive_present = receive_seen || (accepted && a == 32'h0c1003ec);
    wire valid_sel=sel==1 || sel==2 || sel==4 || sel==8 || sel==3 || sel==12 || sel==15;
    wire [31:0] mask = {{8{sel[3]}}, {8{sel[2]}}, {8{sel[1]}}, {8{sel[0]}}};
    assign claim=req && (a==32'h0c14b004 || a==32'h0c1003e8 || a==32'h0c1003ec || a==32'h0c1001f4 || a==32'h0c1001f8);
    assign bad = claim && !valid_sel;
    always @* begin
        dout = 0;
        case (a)
            32'h0c14b004: dout = control;
            32'h0c1003e8: dout = pointers;
            32'h0c1003ec: dout = receive_ptr;
            32'h0c1001f4: dout = frame0;
            32'h0c1001f8: dout = frame1;
        endcase
        dout         = dout & mask;
        bus_control  = control;
        bus_pointers = pointers;
        bus_receive  = receive_ptr;
        bus_frame0   = frame0;
        bus_frame1   = frame1;
        if (accepted && we)
            case (a)
                32'h0c14b004: bus_control = (control & ~mask) | (din & mask);
                32'h0c1003e8: bus_pointers = (pointers & ~mask) | (din & mask);
                32'h0c1003ec: bus_receive = (receive_ptr & ~mask) | (din & mask);
                32'h0c1001f4: bus_frame0 = (frame0 & ~mask) | (din & mask);
                32'h0c1001f8: bus_frame1 = (frame1 & ~mask) | (din & mask);
            endcase
        n_control  = bus_control;
        n_pointers = bus_pointers;
        n_receive  = bus_receive;
        n_frame0   = bus_frame0;
        n_frame1   = bus_frame1;
        irq_events = 0;
        if (tick && periodic_active && !reset) begin
            if (control_present && bus_control[15:0] == 16'h0500 &&
                pointers_present && receive_present && !sent && armed &&
                elapsed == ANNOUNCE_TICKS-1) begin
                n_frame0       = 32'h7cd00000;
                n_frame1       = 32'h04000001;
                n_receive      = {bus_receive[31:16], 16'd4};
                irq_events[10] = 1;
            end
            if (pointers_present && bus_pointers[15:0] != bus_pointers[31:16]) begin
                n_pointers    = {bus_pointers[15:0], bus_pointers[15:0]};
                irq_events[9] = 1;
            end
        end
    end
    always @(posedge clk) begin
        if (reset) begin
            control       <= 0;
            pointers      <= 0;
            receive_ptr   <= 0;
            frame0        <= 0;
            frame1        <= 0;
            control_seen  <= 0;
            pointers_seen <= 0;
            receive_seen  <= 0;
            armed         <= 0;
            sent          <= 0;
            elapsed       <= 0;
        end else begin
            control     <= n_control;
            pointers    <= n_pointers;
            receive_ptr <= n_receive;
            frame0      <= n_frame0;
            frame1      <= n_frame1;
            if (commit && claim && !bad)
                case (a)
                    32'h0c14b004: control_seen <= 1;
                    32'h0c1003e8: pointers_seen <= 1;
                    32'h0c1003ec: receive_seen <= 1;
                endcase
            if (tick && periodic_active) begin
                if(control_present && bus_control[15:0]==16'h0500 && pointers_present && receive_present && !sent)begin
                    if (!armed) begin
                        armed   <= 1;
                        elapsed <= 0;
                    end else if (elapsed == ANNOUNCE_TICKS - 1) begin
                        sent <= 1;
                    end else elapsed <= elapsed + 1;
                end
            end
        end
    end
endmodule
