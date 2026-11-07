// Snapshot 512 diagnostic words, then write exactly two sectors to a dedicated
// mounted virtual disk. This uses standard MiSTer SD block traffic rather than
// core-specific ioctl upload handling. Snapshot freezes trace insertion only.
module ngage_diag_export #(
    parameter integer TIMEOUT = 104000000
) (
    input  wire        clk,
    input  wire        reset,
    input  wire        mount,
    input  wire        readonly_image,
    input  wire [63:0] image_size,
    input  wire        start,
    output reg         mounted = 0,
    output reg         busy = 0,
    output reg         error = 0,
    output reg         done = 0,
    output wire        freeze_trace,
    output wire [10:0] debug_word,
    input  wire [15:0] debug_data,
    output wire [31:0] sd_lba,
    output wire        sd_rd,
    output wire        sd_wr,
    input  wire        sd_ack,
    input  wire [12:0] hps_addr,
    input  wire [15:0] hps_dout,
    input  wire        hps_we,
    output wire [15:0] hps_din
);
    localparam IDLE = 0, CAPTURE = 1, FILL = 2, START = 3, WAIT_SD = 4;
    reg  mount_prev = 0;
    wire mount_event = mount && !mount_prev;
    always @(posedge clk) begin
        if (reset) mount_prev <= 0;
        else mount_prev <= mount;
    end
    reg [ 2:0] state = IDLE;
    reg [ 8:0] index = 0;
    reg        part = 0;
    reg [15:0] snapshot     [0:511];
    wire sector_ready, sector_done, sector_error;
    wire [8:0] capture_word = index == 511 ? 9'd392 : index >= 392 ? index + 1'b1 : index;
    assign debug_word   = {2'b0, capture_word};
    assign freeze_trace = state == CAPTURE;
    ngage_sd_sector #(
        .TIMEOUT(TIMEOUT)
    ) sector (
        .clk         (clk),
        .reset       (reset),
        .start       (state == START),
        .write_sector(1'b1),
        .start_lba   ({31'b0, part}),
        .ready       (sector_ready),
        .done        (sector_done),
        .error       (sector_error),
        .local_addr  (index[7:0]),
        .local_din   (snapshot[{part, index[7:0]}]),
        .local_we    (state == FILL),
        .local_dout  (),
        .sd_lba      (sd_lba),
        .sd_rd       (sd_rd),
        .sd_wr       (sd_wr),
        .sd_ack      (sd_ack),
        .hps_addr    (hps_addr),
        .hps_dout    (hps_dout),
        .hps_we      (hps_we),
        .hps_din     (hps_din)
    );
    always @(posedge clk) begin
        done <= 0;
        if (reset) begin
            state   <= IDLE;
            mounted <= 0;
            busy    <= 0;
            error   <= 0;
            index   <= 0;
            part    <= 0;
        end else begin
            if (mount_event) begin
                mounted <= !readonly_image && image_size >= 1024;
                if (busy) begin
                    state <= IDLE;
                    busy  <= 0;
                    error <= 1;
                end
            end else
                case (state)
                    IDLE:
                    if (start) begin
                        error <= 0;
                        if (!mounted || !sector_ready) begin
                            error <= 1;
                            done  <= 1;
                        end else begin
                            busy  <= 1;
                            index <= 0;
                            part  <= 0;
                            state <= CAPTURE;
                        end
                    end
                    CAPTURE: begin
                        snapshot[capture_word] <= debug_data;
                        if (index == 511) begin
                            index <= 0;
                            state <= FILL;
                        end else index <= index + 1'b1;
                    end
                    FILL:
                    if (index[7:0] == 255) begin
                        index <= 0;
                        state <= START;
                    end else index <= index + 1'b1;
                    START: if (sector_ready) state <= WAIT_SD;
                    WAIT_SD:
                    if (sector_done) begin
                        if (sector_error) begin
                            error <= 1;
                            busy  <= 0;
                            done  <= 1;
                            state <= IDLE;
                        end else if (!part) begin
                            part  <= 1;
                            index <= 0;
                            state <= FILL;
                        end else begin
                            busy  <= 0;
                            done  <= 1;
                            state <= IDLE;
                        end
                    end
                    default: begin
                        state <= IDLE;
                        busy  <= 0;
                        error <= 1;
                    end
                endcase
        end
    end
endmodule
