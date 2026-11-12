// LINE_REFILL requires BA0/BA1_LEN=128 and DYNAMIC_LINE=1 in jtframe_sdram64.
// ba_line stays stable through the selected bank read; each line uses two BL8s.
// One 32-bit request at a time. Reads use one two-beat SDRAM burst; writes
// retain two masked single-halfword operations. dst captures the low read
// halfword and rdy captures the high halfword, never the acceptance ack.
// The initial scrub is a cold-start operation; phone_reset discards CPU responses, not RAM.
module ngage_sdram_adapter #(
    parameter                LINE_REFILL    = 0,
    parameter         [24:0] RAM_BYTES      = 25'h1000000,
    parameter integer        REFRESH_PERIOD = 6800
) (
    input  wire        line_req,
    input  wire [24:0] line_addr,
    output wire        line_ready,
    output reg         line_valid = 0,
    output reg  [15:0] line_data = 0,
    output reg         line_last = 0,
    output wire [ 1:0] ba_line,
    input  wire        clk,
    input  wire        rst,
    input  wire        phone_reset,
    input  wire        init,
    input  wire        req,
    input  wire        we,
    input  wire [24:0] addr,
    input  wire [31:0] din,
    input  wire [ 3:0] be,
    output reg         ack,
    output reg  [31:0] dout,
    output reg         scrub_done,
    output wire [21:0] ba_addr,
    output wire [15:0] ba_din,
    output wire [ 1:0] ba_dsn,
    output wire [ 3:0] rd,
    output wire [ 3:0] wr,
    input  wire [ 3:0] ba_ack,
    input  wire [ 3:0] ba_dst,
    input  wire [ 3:0] ba_rdy,
    input  wire [15:0] ba_dout,
    output reg         rfsh
);
    localparam IDLE = 0, ISSUE = 1, WAIT_READY = 2, GAP = 3, RESP = 4, WAIT_DROP = 5;
    reg [2:0] state = IDLE;
    reg       line_op = 0;
    reg [3:0] line_half = 0;
    reg [2:0] capture_beat = 0;
    reg       capturing = 0;
    assign line_ready=LINE_REFILL && state==IDLE && scrub_done && !req && !phone_reset && !rst && !init;
    assign ba_line = {2{line_op}};
    reg [24:0] address = 0, scrub_address = 0;
    reg [31:0] data = 0;
    reg [ 3:0] mask = 0;
    reg write_op = 0, high = 0, scrub = 0, discard = 0;
    reg [1:0] gap = 0;
    localparam integer REFRESH_BITS = REFRESH_PERIOD > 1 ? $clog2(REFRESH_PERIOD) : 1;
    reg  [REFRESH_BITS-1:0] refresh_count = 0;
    wire                    bank = address[23];
    wire                    selected_ack = ba_ack[{1'b0, bank}];
    wire                    selected_dst = ba_dst[{1'b0, bank}];
    wire                    selected_rdy = ba_rdy[{1'b0, bank}];
    wire                    read_beat = selected_dst || capturing;
    assign ba_addr = line_op ? address[22:1] : {address[22:2], high};
    assign ba_din  = high ? data[31:16] : data[15:0];
    assign ba_dsn  = high ? ~mask[3:2] : ~mask[1:0];
    assign rd      = (state == ISSUE && !write_op) ? (bank ? 4'b0010 : 4'b0001) : 0;
    assign wr      = (state == ISSUE && write_op) ? (bank ? 4'b0010 : 4'b0001) : 0;
    // synthesis translate_off
    always @(posedge clk)
        if (LINE_REFILL && !rst && !init && line_op && state == WAIT_READY && selected_rdy)
            if (capture_beat != 7) $fatal(1, "SDRAM line port requires eight-halfword reads");
    // synthesis translate_on
    always @(posedge clk) begin
        ack        <= 0;
        line_valid <= 0;
        line_last  <= 0;
        rfsh       <= 0;
        if (rst || init) begin
            state         <= IDLE;
            line_op       <= 0;
            capturing     <= 0;
            line_half     <= 0;
            scrub_done    <= 0;
            scrub_address <= 0;
            refresh_count <= 0;
            discard       <= 0;
        end else begin
            if (refresh_count == REFRESH_PERIOD - 1) begin
                refresh_count <= 0;
                rfsh          <= 1;
            end else refresh_count <= refresh_count + 1;
            if (phone_reset && !scrub && state != IDLE) discard <= 1;
            case (state)
                IDLE: begin
                    high      <= 0;
                    line_op   <= 0;
                    capturing <= 0;
                    discard   <= 0;
                    if (!scrub_done) begin
                        scrub    <= 1;
                        address  <= scrub_address;
                        data     <= 0;
                        mask     <= 4'hf;
                        write_op <= 1;
                        state    <= ISSUE;
                    end else if (line_req && line_ready) begin
                        scrub        <= 0;
                        line_op      <= 1;
                        line_half    <= 0;
                        capture_beat <= 0;
                        address      <= {line_addr[24:5], 5'b0};
                        write_op     <= 0;
                        state        <= ISSUE;
                    end else if (req && !phone_reset) begin
                        scrub    <= 0;
                        address  <= {addr[24:2], 2'b00};
                        data     <= din;
                        mask     <= be;
                        write_op <= we;
                        state    <= ISSUE;
                    end
                end
                ISSUE:     if (selected_ack) state <= WAIT_READY;
                WAIT_READY: begin
                    if (!write_op) begin
                        if (read_beat) begin
                            if (selected_dst) begin
                                capturing    <= 1;
                                capture_beat <= 1;
                            end else capture_beat <= capture_beat + 1'b1;
                            if (line_op) begin
                                line_valid <= !discard && !phone_reset;
                                line_data  <= ba_dout;
                                line_last  <= line_half == 15;
                                line_half  <= line_half + 1'b1;
                            end else begin
                                if (selected_dst) dout[15:0] <= ba_dout;
                                else if (capture_beat == 1) dout[31:16] <= ba_dout;
                            end
                        end
                        if (selected_rdy) begin
                            capturing <= 0;
                            if (line_op && line_half != 15) begin
                                address <= address + 16;
                                state   <= ISSUE;
                            end else state <= line_op ? IDLE : RESP;
                        end
                    end else if (selected_rdy) begin
                        gap   <= 2;
                        state <= GAP;
                    end
                end
                GAP:
                if (gap != 0) gap <= gap - 1'b1;
                else if (!high) begin
                    high  <= 1;
                    state <= ISSUE;
                end else if (scrub) begin
                    if (scrub_address + 4 >= RAM_BYTES) scrub_done <= 1;
                    else scrub_address <= scrub_address + 4;
                    state <= IDLE;
                end else state <= RESP;
                RESP: begin
                    if (discard || phone_reset) state <= IDLE;
                    else begin
                        ack   <= 1;
                        state <= WAIT_DROP;
                    end
                end
                WAIT_DROP: if (!req || phone_reset) state <= IDLE;
                default:   state <= IDLE;
            endcase
        end
    end
endmodule
