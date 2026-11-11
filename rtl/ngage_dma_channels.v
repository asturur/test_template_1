// NEM-4 DMA programming frontend and bounded execution pool.
// Register evidence: ekern 503212c0..50321864, helpers 50324b8c..50324ce4.
// IRQ bits are channel-relative; physical ICU assignments belong to UPP.
// An error stops the channel and latches error_pending, without asserting a
// success IRQ: the original ISR returns a constant success status. This is
// an explicit model diagnostic, not an invented guest-visible error register.
module ngage_dma_channels #(
    parameter ENGINES    = 3,
              PRODUCTION = 0
) (
    input  wire        clk,
    input  wire        reset,
    input  wire        req,
    input  wire        commit,
    input  wire        we,
    input  wire [31:0] addr,
    input  wire [31:0] din,
    input  wire [ 3:0] sel,
    output wire        claim,
    output wire        bad,
    output reg  [31:0] dout,
    output reg  [ 7:0] irq_pending,
    output reg  [ 7:0] error_pending,
    output wire [ 7:0] active_channels,
    output wire        lcd_mem_req,
    output wire [24:0] lcd_mem_addr,
    input  wire        lcd_mem_accept,
    input  wire        lcd_mem_ack,
    input  wire [31:0] lcd_mem_data,
    output wire        lcd_pixel_valid,
    output wire [31:0] lcd_pixel_data,
    input  wire        lcd_pixel_ready,
    input  wire        lcd_pixel_error,
    output reg         lcd_waiting,
    input  wire        lcd_ready,
    input  wire        lcd_drained,
    input  wire        mmc_rx_ready,
    input  wire        mmc_tx_ready,
    input  wire        mmc_ready,
    output reg         mmc_read_waiting,
    output reg         mmc_write_waiting,
    input  wire [ 7:0] source_ready,
    input  wire [ 7:0] destination_ready,
    output wire        cmd_valid,
    input  wire        cmd_ready,
    output wire        cmd_write,
    output wire [31:0] cmd_addr,
    output wire [31:0] cmd_data,
    output wire [ 3:0] cmd_be,
    input  wire        rsp_valid,
    input  wire        rsp_error,
    input  wire [31:0] rsp_data
);
    wire [31:0] a = {addr[31:2], 2'b00};
    wire [2:0] channel = a[8:6];
    wire [5:0] offset = a[5:0];
    wire decoded = a >= 32'h0c120300 && a < 32'h0c120500;
    // The base is 0x300, not 0: subtract its channel-index contribution.
    wire [2:0] ch = channel - 3'd4;
    wire known = offset == 6'h04 || offset == 6'h08 || offset == 6'h0c ||
        offset == 6'h10 || offset == 6'h14 || offset == 6'h18 || offset == 6'h1c ||
        offset == 6'h20 || offset == 6'h24 || offset == 6'h28 || offset == 6'h2c;
    wire selector = PRODUCTION && (a == 32'h0c120064 || a == 32'h0c120068);
    reg [31:0] request_select;
    assign claim = req && ((decoded && known) || selector);
    assign bad   = claim && (sel != 4'hf || addr[1:0] != 0 || (we && offset == 6'h08 && din > 3));
    wire write = claim && commit && we && !bad && !selector;
    wire selector_write = claim && commit && we && !bad && selector;
    wire start_write = write && offset == 6'h08 && (din == 1 || din == 2 || din == 3);
    wire stop_write = write && offset == 6'h08 && din == 0;

    reg [31:0] enable_reg[0:7];
    reg [31:0] src_reg[0:7], dst_reg[0:7], count_reg[0:7];
    reg [31:0] smode_reg[0:7], dmode_reg[0:7];
    reg [31:0] swidth_reg[0:7], dwidth_reg[0:7];
    reg [31:0] queued_src[0:7], queued_dst[0:7];
    reg [34:0] queued_bytes[0:7];
    reg [2:0] queued_sw[0:7], queued_dw[0:7];
    reg [7:0] queued_si, queued_di, pending, cancel;
    reg [7:0] completion_wait, completion_cancel;
    reg [7:0] queued_fast;
    reg       fast_owned;
    reg [2:0] fast_channel;
    wire fast_ready, fast_busy, fast_done, fast_error, fast_aborted;
    reg [3:0] queued_request[        0:7];
    reg [3:0] engine_request[0:ENGINES-1];
    reg [1:0] run_code      [        0:7];
    reg [2:0] dispatch_rr;

    reg [ENGINES-1:0] owned;
    reg [        2:0] engine_channel[0:ENGINES-1];
    reg [        1:0] engine_code   [0:ENGINES-1];
    wire [ENGINES-1:0] transfer_ready, engine_busy, engine_done, engine_error, engine_aborted;
    wire [ENGINES-1:0] engine_valid, engine_ready;
    wire [ENGINES-1:0] engine_write;
    wire [31:0] engine_addr[0:ENGINES-1], engine_data[0:ENGINES-1];
    wire    [3:0] engine_be[0:ENGINES-1];
    reg     [7:0] running;
    integer       n;
    always @* begin
        running = 0;
        if (fast_owned) running[fast_channel] = 1;
        for (n = 0; n < ENGINES; n = n + 1) if (owned[n]) running[engine_channel[n]] = 1;
    end
    assign active_channels = pending | running | completion_wait;

    function [2:0] width_bytes;
        input [31:0] code;
        begin
            case (code)
                8:       width_bytes = 1;
                16:      width_bytes = 2;
                32:      width_bytes = 4;
                default: width_bytes = 0;
            endcase
        end
    endfunction

    // NEM-4 control 1 counts halfwords, including its 32-bit memory path.
    // Control 2 counts units of the fixed peripheral, not the memory source.
    // Both come from original caller byte lengths; the engine consumes bytes.
    wire [2:0] source_width = width_bytes(swidth_reg[ch]);
    wire [2:0] destination_width = width_bytes(dwidth_reg[ch]);
    wire source_fixed = smode_reg[ch] == 0;
    wire destination_fixed = dmode_reg[ch] == 0;
    wire paced_count_known = source_fixed != destination_fixed;
    wire [2:0] count_width = din == 1 ? 3'd2 : !paced_count_known ? 3'd0 :
        source_fixed ? source_width : destination_width;
    wire [34:0] programmed_units = {3'd0, count_reg[ch]} + 35'd1;
    // Production admits the evidenced LCD and byte-wide MMC request lines.
    // Unknown paced descriptors fail before any traffic; no fake ready line.
    wire source_lcd = src_reg[ch] == 32'h0c121208 || src_reg[ch] == 32'h10121208;
    wire destination_lcd = dst_reg[ch] == 32'h0c121208 || dst_reg[ch] == 32'h10121208;
    wire lcd_supported = destination_lcd && !source_fixed && destination_fixed &&
        source_width == 4 && destination_width == 4 && request_select[ch*4+:4] == 7;
    wire source_mmc = src_reg[ch] == 32'h0c120624 || src_reg[ch] == 32'h10120624;
    wire destination_mmc = dst_reg[ch] == 32'h0c120624 || dst_reg[ch] == 32'h10120624;
    wire mmc_supported = request_select[ch*4+:4] == 2 &&
        ((din == 2 && destination_mmc && !source_fixed && destination_fixed &&
          source_width == 4 && destination_width == 1) ||
         (din == 3 && source_mmc && source_fixed && !destination_fixed &&
          source_width == 1 && destination_width == 4));
    wire production_supported = !PRODUCTION ||
        (din == 1 ? (!source_lcd && !destination_lcd && !source_mmc && !destination_mmc) :
         ((din == 2 && lcd_supported) || mmc_supported));
    wire [34:0] programmed_bytes = !production_supported ? 35'd0 : count_width == 4 ? programmed_units << 2 :
        count_width == 2 ? programmed_units << 1 : count_width == 1 ? programmed_units : 35'd0;

    integer free_engine, next_channel, scan, candidate;
    always @* begin
        free_engine  = -1;
        next_channel = -1;
        for (scan = 0; scan < ENGINES; scan = scan + 1)
        if (free_engine < 0 && !owned[scan] && !engine_busy[scan] && transfer_ready[scan])
            free_engine = scan;
        for (scan = 0; scan < 8; scan = scan + 1) begin
            candidate = ({29'd0, dispatch_rr} + scan) & 7;
            if (next_channel < 0 && pending[candidate] && !running[candidate] && !completion_wait[candidate] &&
                (queued_fast[candidate] ? (!fast_owned && !fast_busy && fast_ready) : free_engine >= 0))
                next_channel = candidate;
        end
    end
    // A programming write takes precedence over dispatch of its old queue.
    wire dispatch = !reset && next_channel >= 0 &&
        !((start_write || stop_write) && ch == next_channel[2:0]);

    wire fast_dispatch = dispatch && queued_fast[next_channel < 0 ? 0 : next_channel];
    wire generic_dispatch = dispatch && !queued_fast[next_channel < 0 ? 0 : next_channel];
    wire fast_cancel = fast_owned && (cancel[fast_channel] ||
        ((start_write || stop_write) && ch == fast_channel));
    generate
        if (PRODUCTION) begin : fast_lcd
            ngage_lcd_stream stream (
                .clk           (clk),
                .reset         (reset),
                .transfer_valid(fast_dispatch),
                .transfer_ready(fast_ready),
                .source_addr   (queued_src[next_channel < 0 ? 0 : next_channel]),
                .transfer_words(queued_bytes[next_channel < 0 ? 0 : next_channel][34:2]),
                .stop          (fast_cancel),
                .busy          (fast_busy),
                .done          (fast_done),
                .error         (fast_error),
                .aborted       (fast_aborted),
                .mem_req       (lcd_mem_req),
                .mem_addr      (lcd_mem_addr),
                .mem_accept    (lcd_mem_accept),
                .mem_ack       (lcd_mem_ack),
                .mem_data      (lcd_mem_data),
                .pixel_valid   (lcd_pixel_valid),
                .pixel_data    (lcd_pixel_data),
                .pixel_ready   (lcd_pixel_ready),
                .pixel_error   (lcd_pixel_error)
            );
        end else begin : no_lcd_stream
            assign fast_ready      = 0;
            assign fast_busy       = 0;
            assign fast_done       = 0;
            assign fast_error      = 0;
            assign fast_aborted    = 0;
            assign lcd_mem_req     = 0;
            assign lcd_mem_addr    = 0;
            assign lcd_pixel_valid = 0;
            assign lcd_pixel_data  = 0;
        end
    endgenerate
    function lcd_packet;
        input write_word;
        input [31:0] address;
        begin
            lcd_packet = write_word && (address == 32'h0c121208 || address == 32'h10121208);
        end
    endfunction
    reg reserved, bus_owned;
    integer bus_engine, bus_rr, choice, bus_scan, bus_candidate;
    integer lcd_scan;
    always @* begin
        lcd_waiting       = 0;
        mmc_read_waiting  = 0;
        mmc_write_waiting = 0;
        for (lcd_scan = 0; lcd_scan < ENGINES; lcd_scan = lcd_scan + 1) begin
            if (owned[lcd_scan] && engine_request[lcd_scan] == 7 && engine_code[lcd_scan] == 2 && engine_busy[lcd_scan])
                lcd_waiting = 1;
            if (owned[lcd_scan] && engine_valid[lcd_scan] && mmc_packet(
                    engine_addr[lcd_scan]
                )) begin
                if (engine_write[lcd_scan]) mmc_write_waiting = 1;
                else mmc_read_waiting = 1;
            end
        end
    end
    function mmc_packet;
        input [31:0] address;
        begin
            mmc_packet = address == 32'h0c120624 || address == 32'h10120624;
        end
    endfunction
    function endpoint_ready;
        input wr;
        input [31:0] address;
        input lcd_grant, mmc_grant, rx_capacity, tx_capacity;
        begin
            endpoint_ready = !PRODUCTION ||
                (mmc_packet(address) ? (mmc_grant && (wr ? tx_capacity : rx_capacity)) :
                 (!lcd_packet(wr, address) || lcd_grant));
        end
    endfunction
    always @* begin
        choice = -1;
        for (bus_scan = 0; bus_scan < ENGINES; bus_scan = bus_scan + 1) begin
            bus_candidate = bus_rr + bus_scan;
            if (bus_candidate >= ENGINES) bus_candidate = bus_candidate - ENGINES;
            if (choice < 0 && engine_valid[bus_candidate] && endpoint_ready(
                    engine_write[bus_candidate],
                    engine_addr[bus_candidate],
                    lcd_ready,
                    mmc_ready,
                    mmc_rx_ready,
                    mmc_tx_ready
                ))
                choice = bus_candidate;
        end
    end
    wire packet_ready = endpoint_ready(
        engine_write[bus_engine],
        engine_addr[bus_engine],
        lcd_ready,
        mmc_ready,
        mmc_rx_ready,
        mmc_tx_ready
    );
    assign cmd_valid = !reset && reserved && !bus_owned && engine_valid[bus_engine] && packet_ready;
    assign cmd_write = engine_write[bus_engine];
    assign cmd_addr = engine_addr[bus_engine];
    assign cmd_data = engine_data[bus_engine];
    assign cmd_be = engine_be[bus_engine];
    wire accepted = cmd_valid && cmd_ready;
    wire response = rsp_valid && reserved && (bus_owned || accepted);

    genvar e;
    generate
        for (e = 0; e < ENGINES; e = e + 1) begin : engines
            wire dispatch_here = generic_dispatch && free_engine == e;
            wire cancel_here = owned[e] && (cancel[engine_channel[e]] ||
                ((start_write || stop_write) && ch == engine_channel[e]));
            assign engine_ready[e] = reserved && !bus_owned && bus_engine == e && cmd_ready && packet_ready;
            ngage_dma_engine engine (
                .clk(clk),
                .reset(reset),
                .transfer_valid(dispatch_here),
                .transfer_ready(transfer_ready[e]),
                .source_addr(queued_src[next_channel < 0 ? 0 : next_channel]),
                .destination_addr(queued_dst[next_channel < 0 ? 0 : next_channel]),
                .source_bytes(queued_sw[next_channel < 0 ? 0 : next_channel]),
                .destination_bytes(queued_dw[next_channel < 0 ? 0 : next_channel]),
                .source_increment(queued_si[next_channel < 0 ? 0 : next_channel]),
                .destination_increment(queued_di[next_channel < 0 ? 0 : next_channel]),
                .transfer_bytes(queued_bytes[next_channel < 0 ? 0 : next_channel]),
                .source_ready(engine_code[e] == 1 || (PRODUCTION ?
                    (engine_request[e] != 2 || engine_code[e] != 3 || mmc_rx_ready) : source_ready[engine_channel[e]])),
                .destination_ready    (engine_code[e] == 1 ||
                    (PRODUCTION ? (engine_request[e] == 2 ? (engine_code[e] != 2 || mmc_tx_ready) : lcd_ready) : destination_ready[engine_channel[e]])),
                .stop(cancel_here),
                .busy(engine_busy[e]),
                .done(engine_done[e]),
                .error(engine_error[e]),
                .aborted(engine_aborted[e]),
                .cmd_valid(engine_valid[e]),
                .cmd_ready(engine_ready[e]),
                .cmd_write(engine_write[e]),
                .cmd_addr(engine_addr[e]),
                .cmd_data(engine_data[e]),
                .cmd_be(engine_be[e]),
                .rsp_valid(response && bus_engine == e),
                .rsp_error(rsp_error),
                .rsp_data(rsp_data)
            );
        end
    endgenerate

    always @* begin
        dout = 0;
        case (offset)
            6'h04:   dout = enable_reg[ch];
            6'h08:   dout = active_channels[ch] ? {30'd0, run_code[ch]} : 0;
            6'h14:   dout = src_reg[ch];
            6'h18:   dout = smode_reg[ch];
            6'h1c:   dout = swidth_reg[ch];
            6'h20:   dout = dst_reg[ch];
            6'h24:   dout = dmode_reg[ch];
            6'h28:   dout = dwidth_reg[ch];
            6'h2c:   dout = count_reg[ch];
            default: dout = 0;
        endcase
        if (selector) dout = request_select;
    end

    integer i;
    always @(posedge clk) begin
        if (reset) begin
            queued_fast       <= 0;
            fast_owned        <= 0;
            fast_channel      <= 0;
            completion_wait   <= 0;
            completion_cancel <= 0;
            request_select    <= 0;
            pending           <= 0;
            cancel            <= 0;
            owned             <= 0;
            queued_si         <= 0;
            queued_di         <= 0;
            irq_pending       <= 0;
            error_pending     <= 0;
            dispatch_rr       <= 0;
            reserved          <= 0;
            bus_owned         <= 0;
            bus_engine        <= 0;
            bus_rr            <= 0;
            for (i = 0; i < 8; i = i + 1) begin
                enable_reg[i]     <= 0;
                src_reg[i]        <= 0;
                dst_reg[i]        <= 0;
                count_reg[i]      <= 0;
                smode_reg[i]      <= 0;
                dmode_reg[i]      <= 0;
                swidth_reg[i]     <= 0;
                dwidth_reg[i]     <= 0;
                run_code[i]       <= 0;
                queued_request[i] <= 0;
            end
            for (i = 0; i < ENGINES; i = i + 1) begin
                engine_channel[i] <= 0;
                engine_code[i]    <= 0;
                engine_request[i] <= 0;
            end
        end else begin
            if (selector_write) begin
                // Original software clears a field at +68 then ORs its value
                // at +64. This is the driver contract, not verified pin polarity.
                if (a == 32'h0c120068) request_select <= request_select & ~din;
                else request_select <= request_select | din;
            end
            if (!reserved && choice >= 0) begin
                reserved   <= 1;
                bus_engine <= choice;
            end else if (reserved) begin
                if (response) begin
                    reserved  <= 0;
                    bus_owned <= 0;
                    bus_rr    <= bus_engine == ENGINES - 1 ? 0 : bus_engine + 1;
                end else if (accepted) bus_owned <= 1;
                else if (!bus_owned && (!engine_valid[bus_engine] || !packet_ready)) reserved <= 0;
            end
            for (i = 0; i < ENGINES; i = i + 1) begin
                if (owned[i] && (engine_done[i] || engine_error[i] || engine_aborted[i])) begin
                    owned[i]                  <= 0;
                    cancel[engine_channel[i]] <= 0;
                    if (PRODUCTION && engine_code[i] == 2 && engine_request[i] == 7 && !lcd_drained) begin
                        completion_wait[engine_channel[i]] <= 1;
                        completion_cancel[engine_channel[i]] <= !engine_done[i] || cancel[engine_channel[i]];
                    end else if (engine_done[i] && !cancel[engine_channel[i]])
                        irq_pending[engine_channel[i]] <= 1;
                    if (engine_error[i]) error_pending[engine_channel[i]] <= 1;
                end
            end
            for (i = 0; i < 8; i = i + 1) begin
                if (completion_wait[i] && lcd_drained) begin
                    completion_wait[i] <= 0;
                    if (!completion_cancel[i]) irq_pending[i] <= 1;
                end
            end
            if (fast_owned && (fast_done || fast_error || fast_aborted)) begin
                fast_owned           <= 0;
                cancel[fast_channel] <= 0;
                if (!lcd_drained) begin
                    completion_wait[fast_channel]   <= 1;
                    completion_cancel[fast_channel] <= !fast_done || cancel[fast_channel];
                end else if (fast_done && !cancel[fast_channel]) irq_pending[fast_channel] <= 1;
                if (fast_error) error_pending[fast_channel] <= 1;
            end
            if (fast_dispatch) begin
                fast_owned            <= 1;
                fast_channel          <= next_channel[2:0];
                pending[next_channel] <= 0;
                cancel[next_channel]  <= 0;
                dispatch_rr           <= next_channel[2:0] + 3'd1;
            end
            if (generic_dispatch) begin
                owned[free_engine]          <= 1;
                engine_channel[free_engine] <= next_channel[2:0];
                engine_code[free_engine]    <= run_code[next_channel];
                engine_request[free_engine] <= queued_request[next_channel];
                pending[next_channel]       <= 0;
                cancel[next_channel]        <= 0;
                dispatch_rr                 <= next_channel[2:0] + 3'd1;
            end
            if (write) begin
                case (offset)
                    6'h04: begin
                        enable_reg[ch] <= din;
                        if (din == 0) begin
                            irq_pending[ch]   <= 0;
                            error_pending[ch] <= 0;
                        end
                    end
                    6'h14: src_reg[ch] <= din;
                    6'h18: smode_reg[ch] <= din;
                    6'h1c: swidth_reg[ch] <= din;
                    6'h20: dst_reg[ch] <= din;
                    6'h24: dmode_reg[ch] <= din;
                    6'h28: dwidth_reg[ch] <= din;
                    6'h2c: count_reg[ch] <= din;
                    default: begin
                    end
                endcase
            end
            if (start_write || stop_write) begin
                completion_cancel[ch] <= 1;
                pending[ch]           <= start_write;
                cancel[ch]            <= running[ch];
                irq_pending[ch]       <= 0;
                error_pending[ch]     <= 0;
                if (start_write) begin
                    queued_fast[ch] <= PRODUCTION && din == 2 && lcd_supported &&
                        src_reg[ch][31:24] == 8'h0a && src_reg[ch][1:0] == 0;
                    run_code[ch] <= din[1:0];
                    queued_request[ch] <= request_select[ch*4+:4];
                    queued_src[ch] <= src_reg[ch];
                    queued_dst[ch] <= dst_reg[ch];
                    queued_bytes[ch] <= programmed_bytes;
                    queued_sw[ch] <= width_bytes(swidth_reg[ch]);
                    queued_dw[ch] <= width_bytes(dwidth_reg[ch]);
                    queued_si[ch] <= smode_reg[ch] != 0;
                    queued_di[ch] <= dmode_reg[ch] != 0;
                end
            end
        end
    end
endmodule
