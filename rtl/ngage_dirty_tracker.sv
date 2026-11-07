// 512-byte C:/PMM sector dirtiness. A write arriving during a flush keeps
// that sector dirty, including one coincident with the completion pulse.
// A failed flush leaves it dirty and stops the scan for explicit retry.
module ngage_dirty_tracker #(
    parameter integer SECTORS = 8320,
    parameter integer AW      = $clog2(SECTORS)
) (
    input  wire          clk,
    input  wire          cold_reset,
    input  wire          dirty_valid,
    input  wire [AW-1:0] dirty_sector,
    input  wire          flush_start,
    output reg           flushing,
    output reg           flush_error,
    output reg           init_done,
    output reg           sector_valid,
    input  wire          sector_accept,
    output reg  [AW-1:0] sector_index,
    input  wire          sector_done,
    input  wire          sector_ok,
    input  wire          abort_flush
);
    // Two independent write ports: mark on A, successful clear/scrub on B.
    // The scan is synchronous; forwarding makes mixed-port collisions defined.
    wire        scan_dirty;
    reg         scan_mark;
    reg  [AW:0] cursor = 0;
    reg active = 0, again = 0, rescan = 0;
    reg [2:0] state = 0;
    localparam        CLEAR       = 0, IDLE = 1, SCAN = 2, WAIT = 3, READ = 4;
    localparam [AW:0] NUM_SECTORS = SECTORS                                   [AW:0];
    wire mark = !cold_reset && state != CLEAR && dirty_valid && {1'b0, dirty_sector} < NUM_SECTORS;
    wire clear_done = !cold_reset && !abort_flush && state == WAIT &&
        !sector_valid && sector_done && sector_ok && !again &&
        !(mark && dirty_sector == sector_index);
    wire [AW-1:0] ram_address = state == WAIT ? sector_index :
        cursor < NUM_SECTORS ? cursor[AW-1:0] : {AW{1'b0}};
    ngage_bram #(
        .AW(AW),
        .DW(1)
    ) bitmap (
        .clk   (clk),
        .addr_a(dirty_sector),
        .data_a(1'b1),
        .we_a  (mark),
        .q_a   (),
        .addr_b(ram_address),
        .data_b(1'b0),
        .we_b  (!cold_reset && (state == CLEAR || clear_done)),
        .q_b   (scan_dirty)
    );
    always @(posedge clk) scan_mark <= mark && dirty_sector == ram_address;
    always @(posedge clk) begin
        if (cold_reset) begin
            state        <= CLEAR;
            cursor       <= 0;
            init_done    <= 0;
            flushing     <= 0;
            flush_error  <= 0;
            sector_valid <= 0;
            active       <= 0;
            again        <= 0;
            rescan       <= 0;
        end else if (abort_flush && state != CLEAR) begin
            state        <= IDLE;
            flushing     <= 0;
            flush_error  <= 1;
            sector_valid <= 0;
            active       <= 0;
            again        <= 0;
            rescan       <= 0;
        end else
            case (state)
                CLEAR: begin
                    if (cursor == NUM_SECTORS - 1'b1) begin
                        cursor    <= 0;
                        init_done <= 1;
                        state     <= IDLE;
                    end else cursor <= cursor + 1'b1;
                end
                default: begin
                    if (dirty_valid && {1'b0, dirty_sector} < NUM_SECTORS) begin
                        if (flushing) rescan <= 1;
                        if (active && dirty_sector == sector_index) again <= 1;
                    end
                    case (state)
                        IDLE:
                        if (flush_start) begin
                            flushing    <= 1;
                            flush_error <= 0;
                            cursor      <= 0;
                            rescan      <= 0;
                            state       <= READ;
                        end
                        READ:    state <= SCAN;
                        SCAN: begin
                            if (cursor == NUM_SECTORS) begin
                                if (rescan || dirty_valid) begin
                                    cursor <= 0;
                                    rescan <= 0;
                                    state  <= READ;
                                end else begin
                                    flushing <= 0;
                                    state    <= IDLE;
                                end
                            end else if (scan_dirty || scan_mark || (mark && dirty_sector == cursor[AW-1:0])) begin
                                sector_index <= cursor[AW-1:0];
                                sector_valid <= 1;
                                active       <= 1;
                                again        <= 0;
                                state        <= WAIT;
                            end else begin
                                cursor <= cursor + 1'b1;
                                state  <= READ;
                            end
                        end
                        WAIT: begin
                            if (sector_valid && sector_accept) sector_valid <= 0;
                            if (!sector_valid && sector_done) begin
                                active <= 0;
                                if (!sector_ok) begin
                                    flushing    <= 0;
                                    flush_error <= 1;
                                    state       <= IDLE;
                                end else begin
                                    cursor <= cursor + 1'b1;
                                    state  <= READ;
                                end
                            end
                        end
                        default: state <= IDLE;
                    endcase
                end
            endcase
    end
endmodule
