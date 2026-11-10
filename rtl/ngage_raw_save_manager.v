// Two raw persistent images sharing the save transport. Mount metadata
// is captured at each slot event, even before firmware verification. Only one
// slot owns the shared sector buffer/DDR path at a time.
module ngage_raw_save_manager #(
    parameter integer C_SECTORS           = 8192,
    parameter integer PMM_SECTORS         = 128,
    parameter integer SD_TIMEOUT          = 104000000,
    parameter integer BULK                = 0,
    parameter integer ORDERED             = BULK,
    parameter integer AUTO_QUIET_CYCLES   = 78000000,
    parameter integer AUTO_MAX_AGE_CYCLES = 390000000,
    parameter integer AUTO_BATCH_SECTORS  = 16
) (
    input  wire        clk,
    input  wire        reset,
    input  wire [ 1:0] mount,
    input  wire        readonly_image,
    input  wire [63:0] image_size,
    input  wire        bundle_verified,
    input  wire        dirty_valid,
    input  wire [13:0] dirty_sector,
    input  wire        flush_start,
    input  wire        autosave_enable,
    input  wire        pause_autosave,
    output wire [ 1:0] slot_error,
    output wire        mounted,
    output wire        saving,
    output reg         saved,
    output wire        error,
    output wire        busy,
    output wire        mem_valid,
    input  wire        mem_ready,
    output wire        mem_write,
    output wire [31:0] mem_addr,
    output wire [31:0] mem_data,
    output wire [ 3:0] mem_be,
    input  wire        mem_done,
    input  wire [31:0] mem_rdata,
    output wire        bulk_cancel,
    input  wire        bulk_error,
    input  wire        bulk_read_valid,
    output wire        bulk_read_ready,
    input  wire [63:0] bulk_read_data,
    input  wire        bulk_read_last,
    output wire        bulk_write_valid,
    input  wire        bulk_write_ready,
    output wire [63:0] bulk_write_data,
    output wire        bulk_write_last,
    output wire [31:0] sd_lba0,
    output wire [31:0] sd_lba1,
    output wire [ 1:0] sd_rd,
    output wire [ 1:0] sd_wr,
    input  wire [ 1:0] sd_ack,
    input  wire [12:0] hps_addr,
    input  wire [15:0] hps_dout,
    input  wire        hps_we,
    output wire [15:0] hps_din,
    input  wire        flash_quiescent
);
    localparam IDLE = 0, LOAD_START = 1, LOAD_WAIT = 2, FLUSH_WAIT = 3, FAILED = 4;
    reg [2:0] state = IDLE;
    reg [1:0] mount_prev = 0, pending = 0, restored = 0, media_error = 0;
    reg       terminal_error = 0;
    reg [1:0] transfer_error = 0;
    assign error      = terminal_error || (|media_error);
    assign slot_error = media_error | transfer_error;
    wire [ 1:0] mount_event = mount & ~mount_prev;
    wire        any_mount = |mount_event;
    reg  [13:0] cursor = 0;
    reg         active_slot = 0;
    reg was_flushing = 0, flush_pending = 0, dirty_latched = 0;
    wire selected_ack = sd_ack[active_slot];
    reg  selected_ack_prev = 0;
    always @(posedge clk) begin
        if (reset) selected_ack_prev <= 0;
        else selected_ack_prev <= selected_ack;
    end
    wire tracker_flushing, tracker_error, tracker_init, tracker_valid;
    wire tracker_pending, tracker_fault;
    wire start_flush, autosave_due;
    reg manual_batch = 0;
    wire unsafe_change = state == FAILED || state == FLUSH_WAIT ||
        ((state == LOAD_START || state == LOAD_WAIT) && mount_event[active_slot]) ||
        tracker_flushing || tracker_valid || flush_pending || dirty_valid ||
        !flash_quiescent || dirty_latched;
    wire bridge_mem_valid;
    wire bridge_host_write = hps_we && (selected_ack || selected_ack_prev) &&
        state != FAILED && !(any_mount && unsafe_change);
    assign bulk_cancel = BULK != 0 && (state == FAILED || (any_mount && unsafe_change));
    assign mounted     = &restored;
    assign mem_valid   = bridge_mem_valid && state != FAILED && !(any_mount && unsafe_change);
    wire b_ready, b_done, b_error, b_rd, b_wr;
    wire [31:0] b_lba;
    wire [15:0] b_din;
    wire [13:0] tracker_index;
    wire        accept_dirty = (state == IDLE && mounted && tracker_valid && b_ready && !any_mount);
    wire        start_bridge = (state == LOAD_START || accept_dirty);
    ngage_save_sector_bridge #(
        .C_SECTORS  (C_SECTORS),
        .PMM_SECTORS(PMM_SECTORS),
        .RAW_IMAGES (1),
        .BULK       (BULK),
        .SD_TIMEOUT (SD_TIMEOUT)
    ) bridge (
        .clk             (clk),
        .reset           (reset),
        .start           (start_bridge),
        .load_from_disk  (state == LOAD_START),
        .sector_index    (state == LOAD_START ? cursor : tracker_index),
        .ready           (b_ready),
        .done            (b_done),
        .error           (b_error),
        .mem_valid       (bridge_mem_valid),
        .mem_ready       (mem_ready),
        .mem_write       (mem_write),
        .mem_addr        (mem_addr),
        .mem_data        (mem_data),
        .mem_be          (mem_be),
        .mem_done        (mem_done),
        .mem_rdata       (mem_rdata),
        .bulk_error      (bulk_error),
        .bulk_read_valid (bulk_read_valid),
        .bulk_read_ready (bulk_read_ready),
        .bulk_read_data  (bulk_read_data),
        .bulk_read_last  (bulk_read_last),
        .bulk_write_valid(bulk_write_valid),
        .bulk_write_ready(bulk_write_ready),
        .bulk_write_data (bulk_write_data),
        .bulk_write_last (bulk_write_last),
        .sd_lba          (b_lba),
        .sd_rd           (b_rd),
        .sd_wr           (b_wr),
        .sd_ack          (selected_ack),
        .hps_addr        (hps_addr),
        .hps_dout        (hps_dout),
        .hps_we          (bridge_host_write),
        .hps_din         (b_din)
    );
    assign start_flush = !any_mount && state == IDLE && mounted &&
        flash_quiescent && !tracker_flushing && (flush_pending || autosave_due);
    generate
        if (ORDERED != 0) begin : ordered
            localparam [14:0] BATCH_LIMIT = AUTO_BATCH_SECTORS;
            reg [31:0] quiet_cycles = 0, age_cycles = 0;
            always @(posedge clk) begin
                if (reset || !mounted || !tracker_pending) begin
                    quiet_cycles <= 0;
                    age_cycles   <= 0;
                end else begin
                    if (dirty_valid) quiet_cycles <= 0;
                    else if (quiet_cycles < AUTO_QUIET_CYCLES) quiet_cycles <= quiet_cycles + 1'b1;
                    if (age_cycles < AUTO_MAX_AGE_CYCLES) age_cycles <= age_cycles + 1'b1;
                end
            end
            assign autosave_due = autosave_enable && !pause_autosave && bundle_verified &&
                tracker_pending && (quiet_cycles >= AUTO_QUIET_CYCLES ||
                                    age_cycles >= AUTO_MAX_AGE_CYCLES);
            ngage_ordered_dirty_queue #(
                .SECTORS(C_SECTORS + PMM_SECTORS),
                .AW     (14)
            ) queue (
                .clk          (clk),
                .cold_reset   (reset),
                .dirty_valid  (dirty_valid),
                .dirty_sector (dirty_sector),
                .flush_start  (start_flush),
                .flush_limit  (flush_pending ? 15'd0 : BATCH_LIMIT),
                .abort_flush  (any_mount && unsafe_change),
                .init_done    (tracker_init),
                .flushing     (tracker_flushing),
                .flush_error  (tracker_error),
                .queue_fault  (tracker_fault),
                .pending      (tracker_pending),
                .sector_valid (tracker_valid),
                .sector_index (tracker_index),
                .sector_accept(accept_dirty),
                .sector_done  (state == FLUSH_WAIT && b_done),
                .sector_ok    (!b_error)
            );
        end else begin : legacy_scan
            assign tracker_pending = 0;
            assign tracker_fault   = 0;
            assign autosave_due    = 0;
            ngage_dirty_tracker #(
                .SECTORS(C_SECTORS + PMM_SECTORS),
                .AW     (14)
            ) tracker (
                .clk          (clk),
                .cold_reset   (reset),
                .dirty_valid  (dirty_valid),
                .dirty_sector (dirty_sector),
                .flush_start  (start_flush),
                .flushing     (tracker_flushing),
                .flush_error  (tracker_error),
                .init_done    (tracker_init),
                .sector_valid (tracker_valid),
                .sector_accept(accept_dirty),
                .sector_index (tracker_index),
                .sector_done  (state == FLUSH_WAIT && b_done),
                .sector_ok    (!b_error),
                .abort_flush  (any_mount && unsafe_change)
            );
        end
    endgenerate

    assign sd_lba0 = b_lba;
    assign sd_lba1 = b_lba;
    assign sd_rd = state == FAILED || (any_mount && unsafe_change) ? 2'b00 :
        active_slot ? {b_rd, 1'b0} : {1'b0, b_rd};
    assign sd_wr = state == FAILED || (any_mount && unsafe_change) ? 2'b00 :
        active_slot ? {b_wr, 1'b0} : {1'b0, b_wr};
    assign hps_din = b_din;
    assign saving = tracker_flushing || state == FLUSH_WAIT || flush_pending;
    assign busy = state != IDLE && state != FAILED;
    integer slot;
    always @(posedge clk) begin
        if (reset) begin
            mount_prev     <= 0;
            pending        <= 0;
            restored       <= 0;
            state          <= IDLE;
            cursor         <= 0;
            active_slot    <= 0;
            saved          <= 0;
            terminal_error <= 0;
            transfer_error <= 0;
            manual_batch   <= 0;
            media_error    <= 0;
            dirty_latched  <= 0;
            was_flushing   <= 0;
            flush_pending  <= 0;
        end else begin
            if (dirty_valid || (mounted && !flash_quiescent)) dirty_latched <= 1;
            mount_prev   <= mount;
            was_flushing <= tracker_flushing;
            if (dirty_valid || (mounted && !flash_quiescent) || (flush_start && mounted))
                saved <= 0;
            if (start_flush) begin
                manual_batch  <= flush_pending;
                flush_pending <= 0;
            end
            if (flush_start && mounted) flush_pending <= 1;
            if (was_flushing && !tracker_flushing && !tracker_error && mounted) begin
                if (flash_quiescent && !dirty_valid && !tracker_pending && !flush_start && !flush_pending) begin
                    saved         <= 1;
                    dirty_latched <= 0;
                end else if (manual_batch && !start_flush) flush_pending <= 1;
            end

            if (tracker_fault && state != FAILED) begin
                restored       <= 0;
                pending        <= 0;
                saved          <= 0;
                terminal_error <= 1;
                transfer_error <= 2'b11;
                flush_pending  <= 0;
                state          <= FAILED;
            end else if (any_mount && unsafe_change) begin
                // Fail closed, preserving all DDR/dirty state. Media changed
                // underneath an active or dirty handset: cold reset required.
                restored <= 0;
                pending <= 0;
                saved <= 0;
                terminal_error <= 1;
                transfer_error <= transfer_error | mount_event |
                    ((state == LOAD_WAIT || state == FLUSH_WAIT) ? (2'b01 << active_slot) : 2'b00);
                flush_pending <= 0;
                state <= FAILED;
            end else if (state != FAILED) begin
                // Event metadata is shared by hps_io; consume it now, never
                // consult it later while another slot owns a restore.
                for (slot = 0; slot < 2; slot = slot + 1) begin
                    if (mount_event[slot]) begin
                        restored[slot] <= 0;
                        pending[slot]  <= 0;
                        saved          <= 0;
                        if (image_size == 0) media_error[slot] <= 0;
                        else if (readonly_image || image_size !=
                            (slot == 0 ? C_SECTORS * 512 : PMM_SECTORS * 512))
                            media_error[slot] <= 1;
                        else begin
                            pending[slot]     <= 1;
                            media_error[slot] <= 0;
                        end
                    end
                end
                case (state)
                    IDLE: begin
                        if (!any_mount && |pending && tracker_init && bundle_verified) begin
                            active_slot <= !pending[0];
                            cursor      <= pending[0] ? 0 : C_SECTORS;
                            state       <= LOAD_START;
                        end else if (!any_mount && accept_dirty) begin
                            active_slot <= tracker_index >= C_SECTORS;
                            state       <= FLUSH_WAIT;
                        end
                    end
                    LOAD_START: if (b_ready) state <= LOAD_WAIT;
                    LOAD_WAIT:
                    if (b_done) begin
                        if (b_error) begin
                            terminal_error              <= 1;
                            transfer_error[active_slot] <= 1;
                            saved                       <= 0;
                            state                       <= FAILED;
                        end else if (cursor == (active_slot ?
                            C_SECTORS + PMM_SECTORS - 1 : C_SECTORS - 1)) begin
                            restored[active_slot] <= 1;
                            pending[active_slot] <= 0;
                            saved <= (active_slot ? restored[0] : restored[1]) &&
                                !dirty_valid && flash_quiescent && !any_mount;
                            state <= IDLE;
                        end else begin
                            cursor <= cursor + 1'b1;
                            state  <= LOAD_START;
                        end
                    end
                    FLUSH_WAIT:
                    if (b_done) begin
                        if (b_error) begin
                            terminal_error              <= 1;
                            transfer_error[active_slot] <= 1;
                            flush_pending               <= 0;
                            restored                    <= 0;
                            saved                       <= 0;
                            state                       <= FAILED;
                        end else state <= IDLE;
                    end
                    default:    state <= FAILED;
                endcase
            end
        end
    end
endmodule
