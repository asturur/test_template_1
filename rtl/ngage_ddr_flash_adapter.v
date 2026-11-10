// SPDX-License-Identifier: GPL-3.0-or-later
// Shared flash backing cache in front of the scalar/line transport.
module ngage_ddr_flash_adapter #(
    parameter integer FLASH_CACHE_BYTES = 0,
    parameter integer BULK_PERSISTENCE  = 0,
    parameter         STREAM_TRANSPORT  = 0,
                      ROM_CACHE         = 0,
                      ROM_CACHE_BITS    = 64,
                      ROM_CACHE_BYTES   = 1024,
                      LINE_REFILL       = 0
) (
    input  wire        clk,
    input  wire        reset,
    input  wire        req_bulk,
    input  wire        bulk_cancel,
    input  wire        bulk_write_valid,
    output wire        bulk_write_ready,
    input  wire [63:0] bulk_write_data,
    input  wire        bulk_write_last,
    output wire        bulk_read_valid,
    input  wire        bulk_read_ready,
    output wire [63:0] bulk_read_data,
    output wire        bulk_read_last,
    output wire        bulk_error,
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
    output wire [ 7:0] ddr_burstcount,
    input  wire        req_line,
    output wire        rsp_beat_valid,
    output wire [63:0] rsp_beat_data,
    output wire        rsp_beat_last
);

    wire normal_valid, normal_ready, normal_done, normal_beat_valid, normal_beat_last;
    wire [31:0] normal_data;
    wire [63:0] normal_beat_data;
    wire transport_idle, invalidate_sector;
    wire [28:0] normal_ddr_addr;
    wire [63:0] normal_ddr_din;
    wire [7:0] normal_ddr_be, normal_ddr_burstcount;
    wire normal_ddr_rd, normal_ddr_we, normal_ddr_busy, normal_ddr_dout_ready;
    wire sector_active, sector_done, sector_ready;
    wire [28:0] sector_ddr_addr;
    wire [63:0] sector_ddr_din;
    wire [7:0] sector_ddr_be, sector_ddr_burstcount;
    wire sector_ddr_rd, sector_ddr_we;
    wire bulk_offer = BULK_PERSISTENCE != 0 && req_bulk;
    assign normal_valid = req_valid && !bulk_offer && !sector_active;
    assign req_ready = !sector_active && normal_ready && (!bulk_offer || (transport_idle && sector_ready));
    assign rsp_valid = sector_active ? sector_done && !reset : normal_done;
    assign rsp_data = normal_data;
    assign rsp_beat_valid = !sector_active && normal_beat_valid;
    assign rsp_beat_data = normal_beat_data;
    assign rsp_beat_last = normal_beat_last;
    assign normal_ddr_busy = ddr_busy || sector_active;
    assign normal_ddr_dout_ready = ddr_dout_ready && !sector_active;
    assign ddr_addr = sector_active ? sector_ddr_addr : normal_ddr_addr;
    assign ddr_din = sector_active ? sector_ddr_din : normal_ddr_din;
    assign ddr_be = sector_active ? sector_ddr_be : normal_ddr_be;
    assign ddr_burstcount = sector_active ? sector_ddr_burstcount : normal_ddr_burstcount;
    assign ddr_rd = sector_active ? sector_ddr_rd : normal_ddr_rd;
    assign ddr_we = sector_active ? sector_ddr_we : normal_ddr_we;

    generate
        if (BULK_PERSISTENCE != 0) begin : sector_port
            reg active = 0;
            wire engine_idle, cancelled, failed;
            wire accept_sector = req_valid && req_ready && bulk_offer;
            // The mux owner survives transport reset until accepted DDR
            // activity has drained. No bulk return can feed the scalar path.
            always @(posedge clk) begin
                if (accept_sector) active <= 1;
                else if (engine_idle) active <= 0;
            end
            assign sector_active     = active;
            assign bulk_error        = failed || cancelled;
            assign invalidate_sector = accept_sector && req_write;
            ngage_ddr_stream engine (
                .clk                (clk),
                .transport_reset    (reset),
                .phone_reset        (bulk_cancel),
                .req_valid          (accept_sector),
                .req_ready          (sector_ready),
                .req_owner          (2'b0),
                .req_cancel_on_phone(1'b1),
                .req_write          (req_write),
                .req_stream         (req_write),
                .req_addr           (req_addr),
                .req_count          (7'd64),
                .req_data           (64'b0),
                .req_be             (8'hff),
                .write_valid        (bulk_write_valid),
                .write_ready        (bulk_write_ready),
                .write_data         (bulk_write_data),
                .write_be           (8'hff),
                .write_last         (bulk_write_last),
                .read_valid         (bulk_read_valid),
                .read_ready         (bulk_read_ready),
                .read_owner         (),
                .read_data          (bulk_read_data),
                .read_last          (bulk_read_last),
                .done               (sector_done),
                .done_owner         (),
                .error              (failed),
                .cancelled          (cancelled),
                .idle               (engine_idle),
                .ddr_addr           (sector_ddr_addr),
                .ddr_din            (sector_ddr_din),
                .ddr_be             (sector_ddr_be),
                .ddr_burstcount     (sector_ddr_burstcount),
                .ddr_rd             (sector_ddr_rd),
                .ddr_we             (sector_ddr_we),
                .ddr_busy           (ddr_busy),
                .ddr_dout           (ddr_dout),
                .ddr_dout_ready     (ddr_dout_ready && active)
            );
            // synthesis translate_off
            always @(posedge clk)
                if (req_valid && req_ready && bulk_offer)
                    if (req_addr[8:0] != 0 || req_addr < 32'h31400000 || req_addr >= 32'h31810000)
                        $fatal(1, "invalid bulk DDR admission");
            // synthesis translate_on
        end else begin : no_sector_port
            assign sector_active         = 0;
            assign sector_done           = 0;
            assign sector_ready          = 0;
            assign sector_ddr_addr       = 0;
            assign sector_ddr_din        = 0;
            assign sector_ddr_be         = 0;
            assign sector_ddr_burstcount = 0;
            assign sector_ddr_rd         = 0;
            assign sector_ddr_we         = 0;
            assign bulk_write_ready      = 0;
            assign bulk_read_valid       = 0;
            assign bulk_read_data        = 0;
            assign bulk_read_last        = 0;
            assign bulk_error            = 0;
            assign invalidate_sector     = 0;
        end
    endgenerate
    wire request, ready, write_op, line_op, done, beat_valid, beat_last;
    wire [31:0] address, data, read_data;
    wire [ 3:0] mask;
    wire [63:0] beat_data;
    generate
        if (FLASH_CACHE_BYTES != 0) begin : shared_cache
            wire cache_line = LINE_REFILL && req_line;
            ngage_ddr_flash_cache #(
                .CACHE_BYTES(FLASH_CACHE_BYTES)
            ) cache (
                .clk              (clk),
                .reset            (reset),
                .invalidate_sector(invalidate_sector),
                .req_valid        (normal_valid),
                .req_ready        (normal_ready),
                .req_write        (req_write),
                .req_line         (cache_line),
                .req_addr         (req_addr),
                .req_wdata        (req_wdata),
                .req_be           (req_be),
                .rsp_valid        (normal_done),
                .rsp_data         (normal_data),
                .rsp_beat_valid   (normal_beat_valid),
                .rsp_beat_data    (normal_beat_data),
                .rsp_beat_last    (normal_beat_last),
                .mem_valid        (request),
                .mem_ready        (ready),
                .mem_write        (write_op),
                .mem_line         (line_op),
                .mem_addr         (address),
                .mem_wdata        (data),
                .mem_be           (mask),
                .mem_done         (done),
                .mem_rdata        (read_data),
                .mem_beat_valid   (beat_valid),
                .mem_beat_data    (beat_data),
                .mem_beat_last    (beat_last)
            );
        end else begin : bypass
            assign request           = normal_valid;
            assign write_op          = req_write;
            assign line_op           = req_line;
            assign address           = req_addr;
            assign data              = req_wdata;
            assign mask              = req_be;
            assign normal_ready      = ready;
            assign normal_done       = done;
            assign normal_data       = read_data;
            assign normal_beat_valid = beat_valid;
            assign normal_beat_data  = beat_data;
            assign normal_beat_last  = beat_last;
        end
    endgenerate
    ngage_ddr_adapter #(
        .STREAM_TRANSPORT(STREAM_TRANSPORT),
        .ROM_CACHE       (ROM_CACHE && FLASH_CACHE_BYTES == 0),
        .ROM_CACHE_BITS  (ROM_CACHE_BITS),
        .ROM_CACHE_BYTES (ROM_CACHE_BYTES),
        .LINE_REFILL     (LINE_REFILL || FLASH_CACHE_BYTES != 0)
    ) transport (
        .clk           (clk),
        .reset         (reset),
        .req_fetch     (req_fetch),
        .req_valid     (request),
        .req_ready     (ready),
        .req_write     (write_op),
        .req_line      (line_op),
        .req_addr      (address),
        .req_wdata     (data),
        .req_be        (mask),
        .rsp_valid     (done),
        .rsp_data      (read_data),
        .rsp_beat_valid(beat_valid),
        .rsp_beat_data (beat_data),
        .rsp_beat_last (beat_last),
        .ddr_addr      (normal_ddr_addr),
        .ddr_din       (normal_ddr_din),
        .ddr_be        (normal_ddr_be),
        .ddr_rd        (normal_ddr_rd),
        .ddr_we        (normal_ddr_we),
        .ddr_busy      (normal_ddr_busy),
        .ddr_dout      (ddr_dout),
        .ddr_dout_ready(normal_ddr_dout_ready),
        .ddr_burstcount(normal_ddr_burstcount),
        .transport_idle(transport_idle)
    );
endmodule
