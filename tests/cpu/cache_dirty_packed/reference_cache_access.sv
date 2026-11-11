// SPDX-License-Identifier: GPL-3.0-or-later
// ARM920T cache with serialized CPU requests and buffered writes.
// One request at a time. The caller supplies already translated addresses and
// attributes; MMU checks, CP15 maintenance, CPU pipeline and Wishbone adapting
// remain outside this block. Live cached and buffered operations retry bus
// errors without an architectural external abort. An instruction request
// superseded by a queued redirect may discard a failed refill below.
module reference_cache_access #(parameter LINE_REFILL=0, parameter READ_ONLY=0) (

    output wire line_req,
    output wire [31:0] line_addr,
    input wire line_ready,
    input wire line_reject,
    input wire line_valid,
    input wire [63:0] line_data,
    input wire line_wide,
    input wire line_last,
    input wire line_error,

    // Only an instruction fetch superseded by a queued redirect may discard
    // a failed refill. No line is installed and the CPU suppresses its data.
    input wire discard_refill,
    input  logic         clk,
    input  logic         reset,
    input  logic         req_valid,
    output logic         req_ready,
    input  logic [ 31:0] req_mva,
    input  logic [ 31:0] req_physical,
    input  logic         req_write,
    input  logic         req_cache_enable,
    input  logic         req_cacheable,
    input  logic         req_bufferable,
    input  logic [ 31:0] req_wdata,
    input  logic [  3:0] req_byte_enable,
    output logic         response_valid,
    output logic         response_error,
    output logic [ 31:0] response_data,
    output logic         write_buffer_empty,
    output logic         write_buffer_error,
    input  logic         fast_lookup_enable,
    input  logic [ 31:0] fast_lookup_address,
    output logic         fast_lookup_valid,
    output logic [ 31:0] fast_lookup_checked,
    output logic [255:0] fast_lookup_line,
    input  logic         invalidate_all,
    input  logic         lock_write,
    input  logic [  5:0] lock_base_in,
    input  logic         round_robin,
    input  logic         maint_valid,
    input  logic         maint_clean,
    input  logic         maint_invalidate,
    input  logic         maint_all,
    input  logic         maint_by_mva,
    input  logic [ 31:0] maint_address,
    input  logic [  5:0] maint_way,
    input  logic [  2:0] maint_segment,
    output logic         maint_ready,
    output logic         maint_done,
    output logic         maint_error,
    output logic         bus_valid,
    output logic         bus_write,
    output logic [ 31:0] bus_address,
    output logic [ 31:0] bus_wdata,
    output logic [  3:0] bus_byte_enable,
    input  logic         bus_ack,
    input  logic         bus_error,
    input  logic [ 31:0] bus_rdata
);
    typedef enum logic [3:0] {
        IDLE,
        LOOKUP,
        READ_LINE,
        STORE_HIT,
        BYPASS,
        WAIT_REFILL,
        MAINTAIN,
        MAINT_LOOKUP,
        BUFFER_STORE,
        WAIT_DRAIN,
        LOOKUP_WAIT,
        MAINT_WAIT,
        STORE_COMMIT,
        LOOKUP_CAPTURE,
        MAINT_CAPTURE
    } state_t;
    state_t state;
    logic [31:0] mva, pa, wdata;
    logic [3:0] ben;
    logic wr, enabled, cacheable, bufferable;
    logic hit, victim_valid, need, refill_ready, read_valid;
    logic [5:0] hit_way, lock_base;
    logic [1:0] victim_dirty;
    logic [31:0] victim_pa, refill_mva, fill_pa;
    logic [255:0] line, fill_line;
    logic read_victim, fill, wb_done, refill_busy, refill_done, refill_error;
    logic refill_bus_valid, refill_bus_write;
    logic [31:0] refill_bus_address, refill_bus_data;
    logic store_request;
    logic scan_read, scan_valid, scan_clean, scan_invalidate, maint_bus_valid;
    logic [5:0] scan_way;
    logic [2:0] scan_segment;
    logic [1:0] scan_dirty;
    logic [31:0] scan_pa, maint_bus_address, maint_bus_data;
    logic maintenance_busy, maintenance_done, maintenance_error;
    logic saved_maint_clean, saved_maint_invalidate, saved_maint_all, saved_maint_by_mva;
    logic [31:0] saved_maint_address;
    logic [5:0] saved_maint_way;
    logic [2:0] saved_maint_segment;
    // L0 owns the bank address before any tag RAM or flag snapshot reads it.
    // A serialized owner remains fixed through store/refill/retry/maintenance.
    // Resident-only lookahead may replace L0 each idle clock; it never starts
    // a refill or any bus request. Maintenance acceptance has first priority.
    localparam [1:0] LOOKUP_DEMAND = 2'd0, LOOKUP_AHEAD = 2'd1, LOOKUP_MAINT = 2'd2;
    reg lookup_owner_valid, lookup_owner_epoch, fast_epoch, fast_enabled_q;
    reg [1:0] lookup_owner_kind;
    reg [31:0] lookup_owner_mva;
    reg [7:0] lookup_owner_segment_select;
    wire accept_demand = req_valid && req_ready;
    wire accept_maintenance = maint_valid && maint_ready;
    wire fast_read = fast_lookup_enable && state == IDLE && !req_valid &&
                     !maint_valid && !invalidate_all && !lock_write;
    wire capture_lookup = accept_maintenance || accept_demand || fast_read;
    wire [31:0] capture_lookup_mva = accept_maintenance ? maint_address :
                                   accept_demand ? req_mva : fast_lookup_address;
    wire cancel_fast = !fast_lookup_enable || state != IDLE || accept_demand ||
                       maint_valid || invalidate_all || lock_write;
    wire change_epoch = accept_demand || accept_maintenance || invalidate_all ||
                        lock_write || (fast_enabled_q && !fast_lookup_enable);
    always @(posedge clk) begin
        if (reset) begin
            lookup_owner_valid <= 0;
            lookup_owner_kind <= LOOKUP_DEMAND;
            lookup_owner_mva <= 0;
            lookup_owner_segment_select <= 8'b1;
            lookup_owner_epoch <= 0;
            fast_epoch <= 0;
            fast_enabled_q <= 0;
        end else begin
            fast_enabled_q <= fast_lookup_enable;
            if (change_epoch) fast_epoch <= !fast_epoch;
            if (capture_lookup) begin
                lookup_owner_valid <= 1;
                lookup_owner_kind <= accept_maintenance ? LOOKUP_MAINT :
                                     accept_demand ? LOOKUP_DEMAND : LOOKUP_AHEAD;
                lookup_owner_mva <= capture_lookup_mva;
                lookup_owner_segment_select <= 8'b1 << capture_lookup_mva[7:5];
                lookup_owner_epoch <= fast_epoch ^ change_epoch;
            end else if (state == IDLE) lookup_owner_valid <= 0;
        end
    end
    // Address/epoch tokens follow the existing tag-read, compare and line-read
    // edges. Every cancel clears ALL tokens, so the one-bit epoch cannot alias
    // a surviving old request even if cancellations occur on adjacent clocks.
    reg fast_read_pending, fast_compare_pending, fast_result_valid;
    reg fast_read_epoch, fast_compare_epoch, fast_result_epoch;
    reg [31:0] fast_read_address, fast_compare_address, fast_result_address;
    // Two streaming lines still bridge the lookup pipeline at one word/clock.
    logic [1:0] stream_valid, stream_epoch;
    logic [26:0] stream_tag[0:1];
    logic [255:0] stream_line[0:1];
    wire stream_hit = stream_valid[req_mva[5]] && stream_epoch[req_mva[5]] == fast_epoch &&
                      stream_tag[req_mva[5]] == req_mva[31:5];
    wire result_hit = fast_result_valid && fast_result_epoch == fast_epoch &&
                      fast_result_address[31:5] == req_mva[31:5];
    // Do not qualify this output with req_valid: the adapter derives req_valid
    // from !fast_hit, so that would introduce a combinational ACK loop.
    assign fast_lookup_valid=fast_lookup_enable && state==IDLE && !reset && !maint_valid &&
                          !invalidate_all && !lock_write && (stream_hit || result_hit);
    assign fast_lookup_checked = req_mva;
    assign fast_lookup_line = result_hit ? line : stream_line[req_mva[5]];
    always_ff @(posedge clk) begin
        if (reset) begin
            fast_result_valid <= 0;
            fast_read_pending <= 0;
            fast_compare_pending <= 0;
            fast_read_address <= 0;
            fast_compare_address <= 0;
            fast_result_address <= 0;
            fast_read_epoch <= 0;
            fast_compare_epoch <= 0;
            fast_result_epoch <= 0;
            stream_valid <= 0;
            stream_epoch <= 0;
        end else begin
            fast_read_pending <= lookup_owner_valid && lookup_owner_kind == LOOKUP_AHEAD;
            fast_read_address <= lookup_owner_mva;
            fast_read_epoch <= lookup_owner_epoch;
            fast_compare_pending <= fast_read_pending;
            fast_compare_address <= fast_read_address;
            fast_compare_epoch <= fast_read_epoch;
            fast_result_valid <= fast_compare_pending && hit && fast_compare_epoch == fast_epoch;
            fast_result_address <= fast_compare_address;
            fast_result_epoch <= fast_compare_epoch;
            if (cancel_fast) begin
                fast_read_pending <= 0;
                fast_compare_pending <= 0;
                fast_result_valid <= 0;
                stream_valid <= 0;
            end else if (fast_result_valid && fast_result_epoch == fast_epoch) begin
                stream_valid[fast_result_address[5]] <= 1;
                stream_epoch[fast_result_address[5]] <= fast_result_epoch;
                stream_tag[fast_result_address[5]] <= fast_result_address[31:5];
                stream_line[fast_result_address[5]] <= line;
            end
            // A serialized read seeds its own returned line, after all older
            // speculative tokens have been killed. Other stream slot stays dead.
            if (state == READ_LINE && enabled && cacheable) begin
                stream_valid[mva[5]] <= 1;
                stream_epoch[mva[5]] <= fast_epoch;
                stream_tag[mva[5]] <= mva[31:5];
                stream_line[mva[5]] <= line;
            end
        end
    end
    assign maint_done=(maintenance_done && !maintenance_error) || (state==MAINT_LOOKUP && saved_maint_by_mva && !hit);
    assign maint_error = maintenance_error;

    logic [31:0] store_mask;
    logic buffer_ready, buffer_bus_valid, buffer_full, buffer_line_hazard;
    logic refill_line_hazard;
    logic bus_held, bus_held_refill;
    wire        choose_refill;
    // Queue dirty replacement data before allowing the refill read to issue.
    wire        refill_buffer_push = state == WAIT_REFILL && refill_bus_valid && refill_bus_write;
    wire buffer_push_valid = state == BUFFER_STORE ||
                             (state == MAINTAIN && maint_bus_valid) || refill_buffer_push;
    // Refill arbitration consumes a registered hazard snapshot. A simultaneous
    // offered enqueue conservatively blocks reads for another clock, so a new
    // dirty-victim alias cannot pass through the old empty-buffer snapshot.
    // Retiring groups may delay release by one clock; offered bus beats retain
    // the existing held-owner contract. No change to FIFO capacity or ready.
    always_ff @(posedge clk) begin
        if (reset) refill_line_hazard <= 1;
        else refill_line_hazard <= buffer_line_hazard || buffer_push_valid;
    end
    logic [2:0] buffer_entries;
    logic [31:0] buffer_bus_address, buffer_bus_data;
    logic [3:0] buffer_bus_sel;
    arm920_write_buffer write_buffer (
        .clk(clk),
        .reset(reset),
        .push_valid(buffer_push_valid),
        .push_ready(buffer_ready),
        .push_address(state==MAINTAIN ? maint_bus_address : refill_buffer_push ? refill_bus_address : pa),
        .push_words(3'd1),
        .push_data({
            96'b0,
            (state == MAINTAIN ? maint_bus_data : refill_buffer_push ? refill_bus_data : wdata)
        }),
        .push_byte_enable({12'b0, ((state == MAINTAIN || refill_buffer_push) ? 4'hf : ben)}),
        .empty(write_buffer_empty),
        .full(buffer_full),
        .entries(buffer_entries),
        .query_line_address(pa),
        .query_line_pending(buffer_line_hazard),
        .bus_valid(buffer_bus_valid),
        .bus_address(buffer_bus_address),
        .bus_data(buffer_bus_data),
        .bus_byte_enable(buffer_bus_sel),
        .bus_ack(bus_ack && buffer_bus_valid && !choose_refill),
        .bus_error(bus_error && buffer_bus_valid && !choose_refill),
        .error_latched(write_buffer_error),
        .clear_error(1'b1)
    );
    assign maint_ready = (state == IDLE) && write_buffer_empty && !invalidate_all && !lock_write;
    // Cached CPU hits can proceed while buffered writes drain; maintenance waits.
    assign req_ready = (state == IDLE) && !invalidate_all && !lock_write && !maint_valid;
    // Offer a cache-store request independently of the live global hit tree.
    // Bank data writes and each metadata way apply their own hit validation.
    // A write-through miss still queues its bus write without allocating.
    assign store_request=(state==STORE_HIT) || (state==BUFFER_STORE && buffer_ready && wr && enabled && cacheable && !bufferable);
    assign store_mask = {28'b0, ben} << {mva[4:2], 2'b00};
    // Never switch an offered beat until it has completed. Between beats an
    // unrelated replacement read can precede queued writes; an overlapping line
    // must wait until those writes retire.
    wire refill_read = state==WAIT_REFILL && refill_bus_valid && !refill_bus_write && !refill_line_hazard;
    assign choose_refill = bus_held ? bus_held_refill : refill_read;
    assign bus_valid = choose_refill ? refill_read : (buffer_bus_valid || state == BYPASS);
    assign bus_write = choose_refill ? 1'b0 : buffer_bus_valid ? 1'b1 : wr;
    assign bus_address=choose_refill ? refill_bus_address : buffer_bus_valid ? buffer_bus_address : pa;
    assign bus_wdata = choose_refill ? refill_bus_data : buffer_bus_valid ? buffer_bus_data : wdata;
    assign bus_byte_enable = choose_refill ? 4'hf : buffer_bus_valid ? buffer_bus_sel : ben;
    always_ff @(posedge clk) begin
        if (reset) begin
            bus_held        <= 0;
            bus_held_refill <= 0;
        end else if (bus_valid && (bus_ack || bus_error)) bus_held <= 0;
        else if (bus_valid && !bus_held) begin
            bus_held        <= 1;
            bus_held_refill <= choose_refill;
        end
    end
    reference_cache_bank #(.READ_ONLY(READ_ONLY)) bank (
        .clk                 (clk),
        .reset               (reset),
        .mva                 (lookup_owner_mva),
        .lookup_segment_select(lookup_owner_segment_select),
        .hit                 (hit),
        .hit_way             (hit_way),
        .read_victim         (read_victim),
        .read_valid          (read_valid),
        .read_line           (line),
        .victim_valid        (victim_valid),
        .victim_dirty        (victim_dirty),
        .victim_physical_line(victim_pa),
        .needs_writeback     (need),
        .writeback_done      (wb_done),
        .refill              (fill),
        .refill_physical     (fill_pa),
        .refill_line         (fill_line),
        .refill_ready        (refill_ready),
        .store               (store_request),
        .store_dirty         (bufferable),
        .store_enable        (store_mask),
        .store_line          ({8{wdata}}),
        .invalidate_all      (invalidate_all),
        .lock_write          (lock_write),
        .lock_base_in        (lock_base_in),
        .lock_base           (lock_base),
        .round_robin         (round_robin),
        .scan_read           (scan_read),
        .scan_segment        (scan_segment),
        .scan_way            (scan_way),
        .scan_valid          (scan_valid),
        .scan_dirty          (scan_dirty),
        .scan_physical_line  (scan_pa),
        .scan_clean          (scan_clean),
        .scan_invalidate     (scan_invalidate)
    );
    // A maintenance write is acknowledged when the write buffer accepts it,
    // not when external memory eventually accepts the corresponding bus beat.
    reference_cache_maintenance maintenance (
        .clk               (clk),
        .reset             (reset),
        .start             (state == MAINT_LOOKUP && (!saved_maint_by_mva || hit)),
        .clean             (saved_maint_clean),
        .invalidate        (saved_maint_invalidate),
        .all               (saved_maint_all),
        .index_way         (saved_maint_by_mva ? hit_way : saved_maint_way),
        .index_segment     (saved_maint_by_mva ? saved_maint_address[7:5] : saved_maint_segment),
        .busy              (maintenance_busy),
        .done              (maintenance_done),
        .error             (maintenance_error),
        .scan_read         (scan_read),
        .scan_way          (scan_way),
        .scan_segment      (scan_segment),
        .scan_valid        (scan_valid),
        .scan_dirty        (scan_dirty),
        .scan_physical_line(scan_pa),
        .scan_line         (line),
        .scan_clean        (scan_clean),
        .scan_invalidate   (scan_invalidate),
        .bus_valid         (maint_bus_valid),
        .bus_address       (maint_bus_address),
        .bus_wdata         (maint_bus_data),
        .bus_ack           (state == MAINTAIN && buffer_ready),
        .bus_error         (1'b0)
    );
    arm920_cache_refill #(.LINE_REFILL(LINE_REFILL)) refill (
.line_req(line_req),.line_addr(line_addr),.line_ready(line_ready),
    .line_reject(line_reject),.line_valid(line_valid),.line_data(line_data),
    .line_wide(line_wide),.line_last(line_last),.line_error(line_error),

        .clk(clk),
        .reset(reset),
        .start(state == LOOKUP && enabled && cacheable && !wr && !hit && !buffer_line_hazard),
        .request_mva(mva),
        .request_physical(pa),
        .busy(refill_busy),
        .done(refill_done),
        .error(refill_error),
        .bank_mva(refill_mva),
        .bank_hit(hit),
        .bank_victim_valid(victim_valid),
        .bank_victim_dirty(victim_dirty),
        .bank_victim_physical(victim_pa),
        .bank_read_line(line),
        .bank_read_victim(read_victim),
        .bank_refill(fill),
        .bank_writeback_done(wb_done),
        .bank_refill_physical(fill_pa),
        .bank_refill_line(fill_line),
        .bank_refill_ready(refill_ready),
        .bus_valid(refill_bus_valid),
        .bus_write(refill_bus_write),
        .bus_address(refill_bus_address),
        .bus_wdata(refill_bus_data),
        .bus_ack(state==WAIT_REFILL && (refill_bus_write ? buffer_ready : (choose_refill && bus_ack))),
        .bus_error(state == WAIT_REFILL && !refill_bus_write && choose_refill && bus_error),
        .bus_rdata(bus_rdata)
    );
    always_ff @(posedge clk) begin
        if (reset) begin
            state                  <= IDLE;
            response_valid         <= 0;
            response_error         <= 0;
            response_data          <= 0;
            mva                    <= 0;
            pa                     <= 0;
            wdata                  <= 0;
            ben                    <= 0;
            wr                     <= 0;
            enabled                <= 0;
            cacheable              <= 0;
            bufferable             <= 0;
            saved_maint_clean      <= 0;
            saved_maint_invalidate <= 0;
            saved_maint_all        <= 0;
            saved_maint_by_mva     <= 0;
            saved_maint_address    <= 0;
            saved_maint_way        <= 0;
            saved_maint_segment    <= 0;
        end else begin
            response_valid <= 0;
            response_error <= 0;
            case (state)
                IDLE:
                if (maint_valid && maint_ready) begin
                    saved_maint_clean      <= maint_clean;
                    saved_maint_invalidate <= maint_invalidate;
                    saved_maint_all        <= maint_all;
                    saved_maint_by_mva     <= maint_by_mva;
                    saved_maint_address    <= maint_address;
                    saved_maint_way        <= maint_way;
                    saved_maint_segment    <= maint_segment;
                    state                  <= maint_by_mva ? MAINT_CAPTURE : MAINT_WAIT;
                end else if (req_valid && req_ready) begin
                    mva        <= req_mva;
                    pa         <= req_physical;
                    wdata      <= req_wdata;
                    ben        <= req_byte_enable;
                    wr         <= req_write;
                    enabled    <= req_cache_enable;
                    cacheable  <= req_cacheable;
                    bufferable <= req_bufferable;
                    // Uncached reads need no tag/data lookup. Keep the owned
                    // request registers and older-store drain before bus issue.
                    if (!req_write && !(req_cache_enable && req_cacheable))
                        state <= write_buffer_empty ? BYPASS : WAIT_DRAIN;
                    else
                        state <= req_cache_enable && req_cacheable ? LOOKUP_CAPTURE : LOOKUP_WAIT;
                end
                LOOKUP_CAPTURE: state <= LOOKUP_WAIT;
                MAINT_CAPTURE: state <= MAINT_WAIT;
                LOOKUP_WAIT: state <= LOOKUP;
                MAINT_WAIT: state <= MAINT_LOOKUP;
                LOOKUP:
                if (wr) begin
                    if (enabled && cacheable && hit && bufferable) state <= STORE_HIT;
                    else if (bufferable || (enabled && cacheable)) state <= BUFFER_STORE;
                    else if (!write_buffer_empty) state <= WAIT_DRAIN;
                    else state <= BYPASS;
                end else if (enabled && cacheable && hit) state <= READ_LINE;
                else if (enabled && cacheable && !buffer_line_hazard) state <= WAIT_REFILL;
                else if (!write_buffer_empty) state <= WAIT_DRAIN;
                else if (enabled && cacheable) state <= WAIT_REFILL;
                else state <= BYPASS;
                READ_LINE: begin
                    response_data  <= line[mva[4:2]*32+:32];
                    response_valid <= 1;
                    state          <= IDLE;
                end
                STORE_HIT: state <= STORE_COMMIT;
                STORE_COMMIT: begin
                    response_valid <= 1;
                    state          <= IDLE;
                end
                BUFFER_STORE: if (buffer_ready) state <= STORE_COMMIT;
                WAIT_DRAIN:
                if (write_buffer_empty)
                    state <= !wr && !(enabled && cacheable) ? BYPASS : LOOKUP;
                BYPASS:
                if ((bus_ack || bus_error) && !buffer_bus_valid) begin
                    response_data  <= bus_rdata;
                    response_error <= bus_error;
                    response_valid <= 1;
                    state          <= IDLE;
                end
                MAINT_LOOKUP:
                if (saved_maint_by_mva && !hit) state <= IDLE;
                else state <= MAINTAIN;
                MAINTAIN:
                if (maintenance_done) begin
                    if (maintenance_error) state <= MAINT_LOOKUP;
                    else state <= IDLE;
                end
                WAIT_REFILL:
                if (refill_done) begin
                    // A queued instruction redirect cannot wait forever for an
                    // abandoned speculative line. Finish only that failed request;
                    // the CPU's registered shelve flag inhibits instruction acceptance.
                    // Live cached demands and data accesses retain the retry policy.
                    if (refill_error && discard_refill) begin
                        response_valid <= 1;
                        state <= IDLE;
                    end else state <= LOOKUP_WAIT;
                end
                default: state <= IDLE;
            endcase
        end
    end
// Quartus 17 may parse simulation guards without SYNTHESIS defined.
// synthesis translate_off
`ifndef SYNTHESIS
    always @(posedge clk) begin
        if (!reset) begin
            if (lookup_owner_valid && lookup_owner_segment_select != (8'b1 << lookup_owner_mva[7:5]))
                $fatal(1, "cache lookup segment/address owner mismatch");
            if (state != IDLE && (!lookup_owner_valid || lookup_owner_kind == LOOKUP_AHEAD))
                $fatal(1, "serialized cache operation lost lookup ownership");
            if (state != IDLE && lookup_owner_mva !=
                (lookup_owner_kind == LOOKUP_MAINT ? saved_maint_address : mva))
                $fatal(1, "serialized cache lookup address changed");
            if (state == LOOKUP && enabled && cacheable && bank.lookup_address != mva)
                $fatal(1, "cache decision consumed another lookup address");
            if (state == MAINT_LOOKUP && saved_maint_by_mva && bank.lookup_address != saved_maint_address)
                $fatal(1, "MVA maintenance consumed another lookup address");
            if (fast_compare_pending && !cancel_fast &&
                (bank.lookup_address != fast_compare_address || fast_compare_epoch != fast_epoch))
                $fatal(1, "lookahead compare token lost address/epoch association");
        end
    end
    always @(posedge clk)
        if (!reset && state != IDLE && (invalidate_all || lock_write))
            $fatal(1, "cache maintenance must not overlap an access");
`endif
// synthesis translate_on
endmodule
