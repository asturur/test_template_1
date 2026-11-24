`timescale 1ns / 1ps
module program_predecode_tb;
    reg clk = 0;
    always #5 clk = !clk;
    reg reset = 1, offered = 0, live = 0, commit = 0, in_we = 0;
    reg [31:0] in_addr = 0, in_data = 0;
    reg [3:0] in_sel = 0;
    wire req, we;
    wire [31:0] addr, data;
    wire [3:0] sel;
    wire [4:0] fields;
    wire [7:0] control_channel;
    ngage_upp_request_stage #(
        .EXPLICIT_LIVE(1),
        .DMA_PREDECODE(1)
    ) stage (
        .clk        (clk),
        .reset      (reset),
        .in_cyc     (offered),
        .in_stb     (offered),
        .in_live    (live),
        .in_we      (in_we),
        .in_code    (1'b0),
        .in_address (in_addr),
        .in_data    (in_data),
        .in_sel     (in_sel),
        .out_cyc    (req),
        .out_stb    (),
        .out_we     (we),
        .out_code   (),
        .out_address(addr),
        .out_data   (data),
        .out_sel    (sel),
        .out_dma_ctl(fields),
        .out_dma_ch (control_channel)
    );
    reg cmd_ready = 0, rsp_valid = 0, rsp_error = 0;
    wire [1:0] claim, bad, ready, cmd_valid, cmd_write, lcd_req, lcd_line, lcd_pixel;
    wire [31:0] dout[0:1], cmd_addr[0:1], cmd_data[0:1], pixels[0:1];
    wire [3:0] cmd_be[0:1];
    wire [7:0] irq[0:1], errors[0:1], active[0:1];
    wire [24:0] lcd_addr[0:1], lcd_line_addr[0:1];
    wire [1:0] wait_mmc_rx, wait_mmc_tx, wait_lcd;
    reg lcd_grant = 0, lcd_line_ready = 0, mmc_grant = 0;

    // Use identical endpoint inputs. No reference outputs drive the candidate.
    `define DMA_PORTS(i) \
        .clk(clk), .reset(reset), .req(req), .commit(commit), .we(we), \
        .addr(addr), .din(data), .sel(sel), .source_ready(8'hff), .destination_ready(8'hff), \
        .claim(claim[i]), .bad(bad[i]), .ready(ready[i]), .dout(dout[i]), \
        .irq_pending(irq[i]), .error_pending(errors[i]), .active_channels(active[i]), \
        .cmd_valid(cmd_valid[i]), .cmd_ready(cmd_ready), .cmd_write(cmd_write[i]), \
        .cmd_addr(cmd_addr[i]), .cmd_data(cmd_data[i]), .cmd_be(cmd_be[i]), \
        .rsp_valid(rsp_valid), .rsp_error(rsp_error), .rsp_data(32'h932c51a6), \
        .lcd_mem_req(lcd_req[i]), .lcd_mem_addr(lcd_addr[i]), \
        .lcd_mem_accept(1'b0), .lcd_mem_ack(1'b0), .lcd_mem_data(32'b0), \
        .lcd_line_req(lcd_line[i]), .lcd_line_addr(lcd_line_addr[i]), \
        .lcd_line_ready(lcd_line_ready), .lcd_line_valid(1'b0), .lcd_line_last(1'b0), .lcd_line_data(16'b0), \
        .lcd_pixel_valid(lcd_pixel[i]), .lcd_pixel_data(pixels[i]), .lcd_pixel_ready(1'b0), \
        .lcd_pixel_error(1'b0), .lcd_waiting(wait_lcd[i]), .lcd_ready(lcd_grant), .lcd_drained(1'b1), \
        .mmc_rx_ready(1'b1), .mmc_tx_ready(1'b1), .mmc_ready(mmc_grant), \
        .mmc_read_waiting(wait_mmc_rx[i]), .mmc_write_waiting(wait_mmc_tx[i])

    ngage_dma_channels_reference #(
        .ENGINES       (2),
        .PRODUCTION    (1),
        .LCD_LINE_BYTES(16)
    ) reference (
        `DMA_PORTS(0)
    );
    ngage_dma_channels #(
        .ENGINES       (2),
        .PRODUCTION    (1),
        .LCD_LINE_BYTES(16),
        .PREDECODED    (1)
    ) candidate (
        `DMA_PORTS(1),
        .dma_decode (fields),
        .dma_targets(control_channel)
    );
    `undef DMA_PORTS

    integer cycles = 0, requests = 0, rejected = 0, starts = 0, stops = 0;
    integer blocked_offer = 0, taken = 0, drained = 0, held_uncommitted = 0;
    integer offer_stops = 0, owned_stops = 0;
    always @(posedge clk) begin
        cycles = cycles + 1;
        if (cycles >= 60000) $fatal(1, "test timed out");
        if (!reset) begin
            if ({claim[0], bad[0], ready[0], cmd_valid[0], irq[0], errors[0], active[0],
                 lcd_req[0], lcd_line[0], lcd_pixel[0], wait_mmc_rx[0], wait_mmc_tx[0], wait_lcd[0]} !==
                {claim[1], bad[1], ready[1], cmd_valid[1], irq[1], errors[1], active[1],
                 lcd_req[1], lcd_line[1], lcd_pixel[1], wait_mmc_rx[1], wait_mmc_tx[1], wait_lcd[1]})
                $fatal(1, "DMA control differs at clock %0d", cycles);
            if ({reference.start_request, reference.start_write, reference.stop_write,
                 reference.fast_cancel, reference.engines[0].cancel_here, reference.engines[1].cancel_here} !==
                {candidate.start_request, candidate.start_write, candidate.stop_write,
                 candidate.fast_cancel, candidate.engines[0].cancel_here, candidate.engines[1].cancel_here})
                $fatal(1, "DMA programming edge differs at clock %0d", cycles);
            if (req && claim[0] && !bad[0] && !we && ready[0] && dout[0] !== dout[1])
                $fatal(1, "register read differs at clock %0d", cycles);
            if (cmd_valid[0] && {cmd_write[0], cmd_addr[0], cmd_data[0], cmd_be[0]} !==
                                {cmd_write[1], cmd_addr[1], cmd_data[1], cmd_be[1]})
                $fatal(1, "DMA command differs at clock %0d", cycles);
            if (lcd_req[0] && lcd_addr[0] !== lcd_addr[1]) $fatal(1, "LCD word differs");
            if (lcd_line[0] && lcd_line_addr[0] !== lcd_line_addr[1]) $fatal(1, "LCD line differs");
            if (lcd_pixel[0] && pixels[0] !== pixels[1]) $fatal(1, "LCD pixel differs");
            if (req && claim[0]) requests = requests + 1;
            if (req && bad[0]) rejected = rejected + 1;
            if (reference.start_write) starts = starts + 1;
            if (reference.stop_write) stops = stops + 1;
            if (cmd_valid[0] && !cmd_ready) blocked_offer = blocked_offer + 1;
            if (cmd_valid[0] && cmd_ready) taken = taken + 1;
            if (reference.bus_owned && rsp_valid) drained = drained + 1;
            if (reference.stop_write && reference.bus_owned) owned_stops = owned_stops + 1;
            if (reference.stop_write && reference.ch == 0 && reference.reserved && !reference.bus_owned)
                offer_stops = offer_stops + 1;
            if (req && claim[0] && !commit && !offered) held_uncommitted = held_uncommitted + 1;
        end
    end

    task offer;
        input [31:0] address, value;
        input [3:0] lanes;
        input wr;
        begin
            @(negedge clk);
            offered = 1;
            live    = 1;
            in_addr = address;
            in_data = value;
            in_sel  = lanes;
            in_we   = wr;
            @(negedge clk);
            if (!req || addr != address || data != value || sel != lanes || we != wr)
                $fatal(1, "UPP did not capture the offered packet");
            offered = 0;
            in_addr = 32'h0c1204c9;
            in_data = ~value;
            in_sel  = ~lanes;
            in_we   = !wr;
        end
    endtask

    task release_request;
        begin
            live = 0;
            @(negedge clk);
            commit = 0;
        end
    endtask

    task put;
        input [31:0] address, value;
        begin
            offer(address, value, 4'hf, 1);
            while (!ready[0]) @(negedge clk);
            if (!claim[0] || bad[0]) $fatal(1, "test generated an illegal MMIO write %h", address);
            commit = 1;
            @(negedge clk);
            release_request();
        end
    endtask

    task setup;
        input [31:0] base, source_addr, destination;
        input [31:0] destination_bits, destination_increment;
        begin
            put(base + 'h14, source_addr);
            put(base + 'h18, 4);
            put(base + 'h1c, 32);
            put(base + 'h20, destination);
            put(base + 'h24, destination_increment);
            put(base + 'h28, destination_bits);
            put(base + 'h2c, 7);
        end
    endtask

    localparam [31:0] CH0 = 32'h0c120300, CH1 = 32'h0c120340;
    integer channel, word, mask, alignment, value;
    initial begin
        repeat (3) @(negedge clk);
        reset = 0;
        // Exhaust window and lane classification. No request commits in this
        // sweep. The live packet and poisoned new offer differ throughout.
        for (channel = 0; channel < 8; channel = channel + 1)
        for (word = 0; word < 16; word = word + 1)
        for (mask = 0; mask < 16; mask = mask + 1)
        for (alignment = 0; alignment < 4; alignment = alignment + 1) begin
            value = (mask + alignment + channel) % 6;
            offer(CH0 + channel * 64 + word * 4 + alignment, value, mask[3:0], mask[0]);
            @(negedge clk);
            release_request();
        end
        offer(32'h0c1202fc, 0, 4'hf, 1);
        @(negedge clk);
        release_request();
        offer(32'h0c120500, 1, 4'hf, 1);
        @(negedge clk);
        release_request();
        offer(32'h10120308, 1, 4'hf, 1);
        @(negedge clk);
        release_request();
        put(32'h0c120064, 32'h27);
        put(32'h0c120068, 32'h20);
        setup(CH0, 32'h0a000100, 32'h0a000200, 16, 1);

        put(CH0 + 8, 1);
        wait (cmd_valid[0]);
        // A sampled-but-uncommitted stop cannot withdraw an OFFER. A commit
        // after liveness has dropped cannot act on the retained packet.
        offer(CH0 + 8, 0, 4'hf, 1);
        repeat (4) @(negedge clk);
        if (!cmd_valid[0]) $fatal(1, "uncommitted stop withdrew the DMA offer");
        live   = 0;
        commit = 1;
        @(negedge clk);
        commit = 0;
        if (!cmd_valid[0]) $fatal(1, "dead MMIO request withdrew the DMA offer");
        // Invalid start data, a partial access and another channel must differ
        // from this channel's legal committed stop.
        offer(CH0 + 8, 32'h80000001, 4'hf, 1);
        commit = 1;
        @(negedge clk);
        release_request();
        offer(CH0 + 8, 0, 4'h7, 1);
        commit = 1;
        @(negedge clk);
        release_request();
        put(CH1 + 8, 0);
        if (!cmd_valid[0]) $fatal(1, "wrong-channel or bad stop withdrew the offer");
        offer(CH0 + 8, 0, 4'hf, 1);
        cmd_ready = 1;
        commit    = 1;
        #1;
        if (cmd_valid[0] || cmd_valid[1])
            $fatal(1, "committed stop failed to withdraw on the grant edge");
        @(negedge clk);
        cmd_ready = 0;
        release_request();
        wait (active[0] == 0);
        if (taken || irq[0] || errors[0]) $fatal(1, "unaccepted stop changed ownership");

        // A restart while a command is in WAIT must drain the response and
        // then use the new descriptor. Let its first read complete so the
        // next offer carries the destination's partial byte mask.
        put(CH0 + 8, 1);
        wait (cmd_valid[0]);
        @(negedge clk);
        cmd_ready = 1;
        @(negedge clk);
        cmd_ready = 0;
        put(CH0 + 8, 0);
        repeat (3) @(negedge clk);
        if (active[0] != 1) $fatal(1, "physical owner cleared before draining");
        rsp_valid = 1;
        @(negedge clk);
        rsp_valid = 0;
        wait (active[0] == 0);
        put(CH0 + 8, 1);
        wait (cmd_valid[0]);
        @(negedge clk);
        cmd_ready = 1;
        @(negedge clk);
        cmd_ready = 0;
        rsp_valid = 1;
        @(negedge clk);
        rsp_valid = 0;
        wait (cmd_valid[0] && cmd_write[0]);
        if (cmd_be[0] != 4'h3) $fatal(1, "expected partial SDRAM word");
        // The sampled start receives the same next-cycle descriptor credit;
        // its commit coincides with the old write's potential accept.
        offer(CH0 + 8, 1, 4'hf, 1);
        while (!ready[0]) @(negedge clk);
        cmd_ready = 1;
        commit    = 1;
        #1;
        if (cmd_valid[0] || cmd_valid[1]) $fatal(1, "same-edge restart failed to withdraw offer");
        @(negedge clk);
        cmd_ready = 0;
        release_request();
        wait (cmd_valid[0] && !cmd_write[0]);
        @(negedge clk);
        cmd_ready = 1;
        @(negedge clk);
        cmd_ready = 0;
        reset     = 1;
        rsp_valid = 1;
        rsp_error = 1;
        repeat (2) @(negedge clk);
        reset = 0;
        @(negedge clk);
        rsp_valid = 0;
        repeat (4) @(negedge clk);
        if (cmd_valid[0] || active[0] || irq[0] || errors[0])
            $fatal(1, "old owner leaked across reset");

        if (requests < 1000 || rejected < 1000 || starts != 4 || stops != 3 ||
            taken != 3 || drained != 2 || !blocked_offer || !held_uncommitted ||
            offer_stops != 1 || owned_stops != 1)
            $fatal(
                1,
                "incomplete coverage starts=%0d stops=%0d take=%0d drain=%0d offer_stops=%0d owned_stops=%0d",
                starts,
                stops,
                taken,
                drained,
                offer_stops,
                owned_stops
            );
        $display(
            "PASS DMA predecode clocks=%0d requests=%0d rejected=%0d starts=%0d stops=%0d blocked=%0d taken=%0d drained=%0d",
            cycles, requests, rejected, starts, stops, blocked_offer, taken, drained);
        $finish;
    end
endmodule
