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
    input  wire [31:0] rsp_data,
    output wire        ready
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

    // Full programming words are retained in one M10K for arbitrary readback.
    // Only descriptor inputs needed at start remain live: addresses/count,
    // zero/nonzero modes and validated byte-width codes. Dispatch never waits
    // for readback RAM and snapshots exactly the same accepted start edge.
    reg [31:0] src_reg[0:7], dst_reg[0:7], count_reg[0:7];
    reg [7:0] source_increment, destination_increment;
    reg [2:0] source_bytes[0:7], destination_bytes[0:7];
    reg [63:0] programming_valid;
    reg [ 2:0] programming_index;
    reg        programming_word;
    always @* begin
        programming_word  = 1;
        programming_index = 0;
        case (offset)
            6'h04:   programming_index = 0;
            6'h14:   programming_index = 1;
            6'h18:   programming_index = 2;
            6'h1c:   programming_index = 3;
            6'h20:   programming_index = 4;
            6'h24:   programming_index = 5;
            6'h28:   programming_index = 6;
            6'h2c:   programming_index = 7;
            default: programming_word = 0;
        endcase
    end
    wire [ 5:0] programming_address = {ch, programming_index};
    wire        programming_write = write && programming_word && !reset;
    wire        programming_read = claim && !bad && !we && !selector && programming_word;
    wire [31:0] programming_data;
    ngage_bram #(
        .AW         (6),
        .DW         (32),
        .READ_ONLY_B(1)
    ) programming_ram (
        .clk   (clk),
        .addr_a(programming_address),
        .addr_b(programming_address),
        .data_a(din),
        .data_b(32'b0),
        .we_a  (programming_write),
        .we_b  (1'b0),
        .q_a   (),
        .q_b   (programming_data)
    );
    reg read_pending, read_word_valid;
    reg [5:0] read_address;
    always @(posedge clk) begin
        if (reset) begin
            programming_valid <= 0;
            read_pending      <= 0;
            read_word_valid   <= 0;
            read_address      <= 0;
        end else begin
            if (programming_write) programming_valid[programming_address] <= 1;
            read_pending    <= programming_read;
            read_address    <= programming_address;
            read_word_valid <= programming_valid[programming_address];
        end
    end
    assign ready = !programming_read || (read_pending && read_address == programming_address);
    reg [7:0] pending, cancel;
    // Only the fast-path classification remains live for queue arbitration.
    // The immutable start snapshot is read from four M10Ks before dispatch.
    reg       descriptor_loaded = 0;
    reg [2:0] descriptor_channel;
    localparam ENGINE_BITS = ENGINES > 1 ? $clog2(ENGINES) : 1;
    reg  [ENGINE_BITS-1:0] descriptor_engine;
    wire [          127:0] descriptor_data;
    wire [           31:0] descriptor_src = descriptor_data[31:0];
    wire [           31:0] descriptor_dst = descriptor_data[63:32];
    wire [           34:0] descriptor_bytes = descriptor_data[98:64];
    wire [            2:0] descriptor_dw = descriptor_data[101:99];
    wire [            2:0] descriptor_sw = descriptor_data[104:102];
    wire                   descriptor_di = descriptor_data[105];
    wire                   descriptor_si = descriptor_data[106];
    wire [            3:0] descriptor_request = descriptor_data[110:107];
    reg [7:0] completion_wait, completion_cancel;
    reg [7:0] queued_fast;
    reg       fast_owned;
    reg [2:0] fast_channel;
    wire fast_ready, fast_busy, fast_done, fast_error, fast_aborted;
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
    wire [2:0] source_width = source_bytes[ch];
    wire [2:0] destination_width = destination_bytes[ch];
    wire source_fixed = !source_increment[ch];
    wire destination_fixed = !destination_increment[ch];
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
    // A start snapshots all fields on its committing edge. Reprogramming the
    // live registers cannot change queued work. A restart/stop invalidates a
    // sampled old descriptor before any engine sees it, including RAM RDW.
    wire descriptor_select = !reset && !descriptor_loaded && next_channel >= 0 &&
        !((start_write || stop_write) && ch == next_channel[2:0]);
    wire descriptor_write = start_write && !reset;
    wire [2:0] descriptor_read_address = descriptor_loaded ? descriptor_channel :
        next_channel < 0 ? 3'd0 : next_channel[2:0];
    wire [127:0] descriptor_input = {
        17'b0,
        request_select[ch*4+:4],
        source_increment[ch],
        destination_increment[ch],
        source_bytes[ch],
        destination_bytes[ch],
        programmed_bytes,
        dst_reg[ch],
        src_reg[ch]
    };
    genvar descriptor_word;
    generate
        for (
            descriptor_word = 0; descriptor_word < 4; descriptor_word = descriptor_word + 1
        ) begin : queued_descriptor
            ngage_bram #(
                .AW         (3),
                .DW         (32),
                .READ_ONLY_B(1)
            ) ram (
                .clk   (clk),
                .addr_a(ch),
                .addr_b(descriptor_read_address),
                .data_a(descriptor_input[descriptor_word*32+:32]),
                .data_b(32'b0),
                .we_a  (descriptor_write),
                .we_b  (1'b0),
                .q_a   (),
                .q_b   (descriptor_data[descriptor_word*32+:32])
            );
        end
    endgenerate
    wire dispatch = !reset && descriptor_loaded && pending[descriptor_channel] &&
        !running[descriptor_channel] && !completion_wait[descriptor_channel] &&
        !((start_write || stop_write) && ch == descriptor_channel);
    wire fast_dispatch = dispatch && queued_fast[descriptor_channel];
    wire generic_dispatch = dispatch && !queued_fast[descriptor_channel];
    always @(posedge clk) begin
        if (reset) begin
            descriptor_loaded  <= 0;
            descriptor_channel <= 0;
            descriptor_engine  <= 0;
        end else begin
            descriptor_loaded <= descriptor_select;
            if (descriptor_select) begin
                descriptor_channel <= next_channel[2:0];
                descriptor_engine  <= free_engine < 0 ? 0 : free_engine;
            end
        end
    end
    wire fast_cancel = fast_owned && (cancel[fast_channel] ||
        ((start_write || stop_write) && ch == fast_channel));
    generate
        if (PRODUCTION) begin : fast_lcd
            ngage_lcd_stream stream (
                .clk           (clk),
                .reset         (reset),
                .transfer_valid(fast_dispatch),
                .transfer_ready(fast_ready),
                .source_addr   (descriptor_src),
                .transfer_words(descriptor_bytes[34:2]),
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
            wire dispatch_here = generic_dispatch && descriptor_engine == e;
            wire cancel_here = owned[e] && (cancel[engine_channel[e]] ||
                ((start_write || stop_write) && ch == engine_channel[e]));
            assign engine_ready[e] = reserved && !bus_owned && bus_engine == e && cmd_ready && packet_ready;
            ngage_dma_engine engine (
                .clk(clk),
                .reset(reset),
                .transfer_valid(dispatch_here),
                .transfer_ready(transfer_ready[e]),
                .source_addr(descriptor_src),
                .destination_addr(descriptor_dst),
                .source_bytes(descriptor_sw),
                .destination_bytes(descriptor_dw),
                .source_increment(descriptor_si),
                .destination_increment(descriptor_di),
                .transfer_bytes(descriptor_bytes),
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
        if (programming_word && !selector) begin
            if (ready && read_word_valid) dout = programming_data;
        end else if (offset == 6'h08) dout = active_channels[ch] ? {30'd0, run_code[ch]} : 0;
        if (selector) dout = request_select;
    end

    integer i;
    always @(posedge clk) begin
        if (reset) begin
            source_increment      <= 0;
            destination_increment <= 0;
            queued_fast           <= 0;
            fast_owned            <= 0;
            fast_channel          <= 0;
            completion_wait       <= 0;
            completion_cancel     <= 0;
            request_select        <= 0;
            pending               <= 0;
            cancel                <= 0;
            owned                 <= 0;
            irq_pending           <= 0;
            error_pending         <= 0;
            dispatch_rr           <= 0;
            reserved              <= 0;
            bus_owned             <= 0;
            bus_engine            <= 0;
            bus_rr                <= 0;
            for (i = 0; i < 8; i = i + 1) begin
                src_reg[i]           <= 0;
                dst_reg[i]           <= 0;
                count_reg[i]         <= 0;
                source_bytes[i]      <= 0;
                destination_bytes[i] <= 0;
                run_code[i]          <= 0;
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
                fast_owned                  <= 1;
                fast_channel                <= descriptor_channel;
                pending[descriptor_channel] <= 0;
                cancel[descriptor_channel]  <= 0;
                dispatch_rr                 <= descriptor_channel + 3'd1;
            end
            if (generic_dispatch) begin
                owned[descriptor_engine]          <= 1;
                engine_channel[descriptor_engine] <= descriptor_channel;
                engine_code[descriptor_engine]    <= run_code[descriptor_channel];
                engine_request[descriptor_engine] <= descriptor_request;
                pending[descriptor_channel]       <= 0;
                cancel[descriptor_channel]        <= 0;
                dispatch_rr                       <= descriptor_channel + 3'd1;
            end
            if (write) begin
                case (offset)
                    6'h04: begin
                        if (din == 0) begin
                            irq_pending[ch]   <= 0;
                            error_pending[ch] <= 0;
                        end
                    end
                    6'h14: src_reg[ch] <= din;
                    6'h18: source_increment[ch] <= din != 0;
                    6'h1c: source_bytes[ch] <= width_bytes(din);
                    6'h20: dst_reg[ch] <= din;
                    6'h24: destination_increment[ch] <= din != 0;
                    6'h28: destination_bytes[ch] <= width_bytes(din);
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
                end
            end
        end
    end
endmodule
