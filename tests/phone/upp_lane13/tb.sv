`timescale 1ns / 1ps
module tb;
    parameter KEYPAD_ENABLE = 1;
    reg clk = 0;
    always #4.807692 clk = ~clk;
    reg reset = 1, cold_reset = 1, cyc = 0, we = 0, allow = 1, hold_reply = 0;
    reg tx_ready = 1, rx_valid = 0, card_busy = 0, cfg_keypad = 1;
    reg [ 7:0] rx_data = 0;
    reg [25:0] keys = 0;
    reg [31:0] address = 0, data = 0;
    reg [3:0] sel = 0;
    wire offered, live, cpu_ack, cpu_error, packet, wr;
    wire [31:0] cpu_data, addr, wdata, rdata;
    wire [3:0] lanes;
    wire claim, ready, error, init_done, pending, irq, fiq, tx_valid, rx_ready;
    wire [7:0] tx_data;
    reg        invalid_response = 0;
    wire       commit = packet && !reset && init_done && !invalid_response && !pending && allow;
    wire       peripheral_ack = claim && ready && !error && !hold_reply;
    integer cycle = 0, replies = 0, samples = 0, writes = 0, tx_pushes = 0, rx_pops = 0;
    integer gpio_count = 0, uart_count = 0, overlap_count = 0, nos_count = 0, loop_count = 0;
    integer k, mask, old_samples, old_pushes;
    reg [31:0] observed;

    ngage_upp_bus_bridge #(
        .REGISTERED_MASTER(1)
    ) bridge (
        .clk             (clk),
        .reset           (reset),
        .master_cyc      (cyc),
        .master_stb      (cyc),
        .master_we       (we),
        .master_code     (1'b0),
        .master_address  (address),
        .master_data     (data),
        .master_sel      (sel),
        .master_ack      (cpu_ack),
        .master_error    (cpu_error),
        .master_read_data(cpu_data),
        .bus_cyc         (offered),
        .bus_stb         (),
        .bus_live        (live),
        .bus_we          (),
        .bus_code        (),
        .bus_address     (),
        .bus_data        (),
        .bus_sel         (),
        .bus_ack         (peripheral_ack),
        .bus_error       (invalid_response),
        .bus_read_data   (rdata)
    );
    wire [6:0] select_word;
    ngage_upp_request_stage #(
`ifndef REFERENCE
        .EUART_PREDECODE(1),
`endif
        .EXPLICIT_LIVE  (1)
    ) request_stage (
        .clk             (clk),
        .reset           (reset),
        .in_cyc          (offered),
        .in_stb          (offered),
        .in_live         (live),
        .in_we           (we),
        .in_code         (1'b0),
        .in_address      (address),
        .in_data         (data),
        .in_sel          (sel),
        .out_cyc         (packet),
        .out_stb         (),
        .out_we          (wr),
        .out_code        (),
        .out_address     (addr),
        .out_data        (wdata),
`ifndef REFERENCE
        .out_euart_select(select_word),
`endif
        .out_sel         (lanes)
    );
    ngage_upp_peripherals #(
        .REGISTER_RESPONSES(1),
        .KEYPAD_ENABLE     (KEYPAD_ENABLE),
        .SIMIF_ENABLE      (1),
        .SYS_CLK_HZ        (104000000),
        .TIMER_CLK_DIV     (4),
`ifndef REFERENCE
        .EUART_PREDECODE   (1),
`endif
        .NOS_TICK_HZ       (64)
    ) dut (
        .clk                 (clk),
        .rst                 (reset),
        .init_rst            (cold_reset),
        .cyc                 (packet),
        .stb                 (packet),
        .adr                 (addr),
        .din                 (wdata),
        .we                  (wr),
        .sel                 (lanes),
        .commit              (commit),
`ifndef REFERENCE
        .euart_select        (select_word),
`endif
        .upp_ddr_ack         (1'b0),
        .upp_ddr_rdata       (32'b0),
        .upp_ddr_clear_done  (1'b0),
        .cfg_lcd             (1'b0),
        .cfg_keypad          (cfg_keypad),
        .cfg_clocks          (1'b0),
        .dma_irq_pending     (1'b0),
        .pcm_irq             (1'b0),
        .general_dma_irq     (8'b0),
        .sim_fiq_pending     (1'b0),
        .keys                (keys),
        .sim_present         (1'b1),
        .card_rx_valid       (1'b0),
        .card_tx_will_emit   (1'b0),
        .card_overflow       (1'b0),
        .card_rx_data        (8'b0),
        .card_available      (7'b0),
        .card_busy           (card_busy),
        .claim               (claim),
        .ready               (ready),
        .dout                (rdata),
        .unmodeled           (error),
        .irq                 (irq),
        .fiq                 (fiq),
        .init_done           (init_done),
        .cbus_claim          (1'b0),
        .cbus_bad            (1'b0),
        .cbus_irq            (1'b0),
        .cbus_data           (32'b0),
        .route2a             (16'h0008),
        .route2c             (16'b0),
        .route3b             (16'b0),
        .cbus8d_written      (1'b0),
        .adsp_tx_valid       (tx_valid),
        .adsp_tx_ready       (tx_ready),
        .adsp_tx_data        (tx_data),
        .adsp_rx_valid       (rx_valid),
        .adsp_rx_ready       (rx_ready),
        .adsp_rx_data        (rx_data),
        .mdi_claim           (1'b0),
        .mdi_bad             (1'b0),
        .mdi_ready           (1'b1),
        .mdi_data            (32'b0),
        .mdi_events          (16'b0),
        .lcd_sink_ready      (1'b1),
        .lcd_dma_access      (1'b0),
        .lcd_pixel_mode      (1'b0),
        .dma_shadow_claim    (1'b0),
        .lcd_direct_collision(1'b0),
        .mmc_cmd_i           (1'b1),
        .mmc_dat_i           (1'b1),
        .response_pending    (pending)
    );
    always @(posedge clk) begin
        cycle <= cycle + 1;
        if (reset) invalid_response <= 0;
        else begin
            // Board-register the selected peripheral error, as in ngage_mister.
            invalid_response <= !invalid_response && packet && claim && ready && error;
            if (init_done && (packet || offered || cpu_ack || cpu_error))
                $display(
                    "TRACE %0d %b%b%b%b%b%b %h %h %h %b%b%b%b %h",
                    cycle,
                    offered,
                    packet,
                    commit,
                    pending,
                    cpu_ack,
                    cpu_error,
                    packet ? addr : address,
                    packet ? lanes : sel,
                    pending && packet ? rdata : 32'd0,
                    irq,
                    fiq,
                    tx_valid,
                    rx_ready,
                    tx_valid ? tx_data : 8'd0
                );
            if (commit && claim && dut.local_ready) begin
                samples       <= samples + 1;
                writes        <= writes + wr;
                gpio_count    <= gpio_count + (dut.selected_owner[13] && !dut.uart_claim);
                uart_count    <= uart_count + (dut.selected_owner[13] && dut.uart_claim);
                overlap_count <= overlap_count + (dut.selected_owner[0] && dut.uart_claim);
                nos_count     <= nos_count + dut.selected_owner[8];
                loop_count    <= loop_count + dut.selected_owner[2];
                $display("SAMPLE %0d addr=%h owner=%h wr=%b lanes=%h", cycle, addr,
                         dut.selected_owner, wr, lanes);
            end
            if (dut.euart1.tx_push) tx_pushes <= tx_pushes + 1;
            if (dut.euart1.rx_pop) rx_pops <= rx_pops + 1;
            if (cpu_ack && cpu_error) $fatal(1, "Duplicate status");
        end
        if (cycle > 25000) $fatal(1, "Peripheral trace timeout");
    end

    task tick;
        @(negedge clk);
    endtask

    task offer;
        input write_op;
        input [31:0] dest, value;
        input [3:0] lane_mask;
        begin
            cyc     = 1;
            we      = write_op;
            address = dest;
            data    = value;
            sel     = lane_mask;
        end
    endtask

    task finish;
        input expect_error;
        input [31:0] compare_mask, expected;
        input integer start, expected_edges;
        begin
            while (!cpu_ack && !cpu_error) tick;
            if (cpu_error !== expect_error || cpu_ack === expect_error)
                $fatal(1, "Unexpected completion addr=%h error=%b", address, cpu_error);
            if (!we && ((cpu_data & compare_mask) !== expected))
                $fatal(
                    1,
                    "Read %h mask %h got %h expected %h",
                    address,
                    compare_mask,
                    cpu_data,
                    expected
                );
            if (expected_edges != 0 && cycle - start != expected_edges)
                $fatal(
                    1,
                    "Response edge moved for %h, expected %0d clocks got %0d",
                    address,
                    expected_edges,
                    cycle - start
                );
            observed = cpu_data;
            replies  = replies + 1;
            $display("DONE %0d duration=%0d addr=%h result=%h err=%b", cycle, cycle - start,
                     address, cpu_data, cpu_error);
            tick;  // The CPU consumes the response on this edge.
        end
    endtask

    task access;
        input write_op, expect_error;
        input [31:0] dest, value;
        input [3:0] lanes;
        input [31:0] compare_mask, expected;
        input integer expected_edges;
        integer start;
        begin
            start = cycle;
            offer(write_op, dest, value, lanes);
            finish(expect_error, compare_mask, expected, start, expected_edges);
            // The next access can follow with no extra idle edge, retaining CYC.
        end
    endtask

    task push_rx;
        input [7:0] value;
        begin
            cyc      = 0;
            rx_data  = value;
            rx_valid = 1;
            if (!rx_ready) $fatal(1, "Unexpected RX backpressure");
            tick;
            rx_valid = 0;
        end
    endtask

    function [31:0] euart_address;
        input integer index;
        begin
            case (index)
                0: euart_address = 32'h0c150510;
                1: euart_address = 32'h0c150514;
                2: euart_address = 32'h0c150554;
                3: euart_address = 32'h0c150558;
                4: euart_address = 32'h0c15055c;
                5: euart_address = 32'h0c150560;
                6: euart_address = 32'h0c1500b8;
                7: euart_address = 32'h0c150508;  // Neighbor is plain GPIO RAM.
            endcase
        end
    endfunction
    function valid_lanes;
        input [3:0] lanes;
        begin
            valid_lanes = lanes == 1 || lanes == 2 || lanes == 4 || lanes == 8 ||
                lanes == 3 || lanes == 12 || lanes == 15;
        end
    endfunction

    initial begin
        repeat (3) tick;
        cold_reset = 0;
        wait (init_done);
        tick;
        reset = 0;
        access (1, 0, 'h0c150510, 'h01234567, 15, 0, 0, 3);
        access (0, 0, 'h0c150511, 0, 15, 'hffffffff, 'h01234567, 3);
        access (1, 0, 'h0c150511, 'h0000aa00, 2, 0, 0, 3);
        access (0, 0, 'h0c150510, 0, 15, 'hffffffff, 'h0123aa67, 3);
        access (0, 1, 'h0c150510, 0, 5, 0, 0, 4);
        access (1, 0, 'h0c150508, 'h76543210, 15, 0, 0, 3);
        access (0, 0, 'h0c150508, 0, 15, 'hffffffff, 'h76543210, 4);
        access (1, 0, 'h0c150508, 'h0000bb00, 2, 0, 0, 3);
        access (0, 0, 'h0c150508, 0, 15, 'hffffffff, 'h7654bb10, 4);

        // SIMIF owns the full-word status read while EUART supplies high bits.
        access (1, 0, 'h0c150808, 1, 3, 0, 0, 3);
        push_rx(8'ha5);
        access (0, 0, 'h0c1500b8, 0, 3, 'hffffffff, 4, 3);
        access (0, 0, 'h0c1500b8, 0, 12, 'hffffffff, 'h00080000, 3);
        access (0, 0, 'h0c1500b8, 0, 15, 'hffffffff, 'h00080004, 3);
        access (0, 0, 'h0c150554, 0, 12, 'hffffffff, 'ha5000000, 3);
        access (0, 1, 'h0c150554, 0, 12, 0, 0, 4);
        // A byte arriving just before presentation still waits for RX RAM.
        push_rx(8'h39);
        access (0, 0, 'h0c150555, 0, 12, 'hffffffff, 'h39000000, 0);

        // An incoming byte on the status sample edge changes the next
        // read, not the just-captured result. Card busy on the shared
        // SIMIF read delays both sources until the common sample.
        offer(0, 'h0c1500b8, 0, 12);
        tick;
        rx_valid = 1;
        rx_data  = 8'h7e;
        tick;
        rx_valid = 0;
        finish(0, 'hffffffff, 0, cycle, 1);
        card_busy = 1;
        offer(0, 'h0c1500b8, 0, 15);
        repeat (4) tick;
        if (!packet || pending || cpu_ack) $fatal(1, "SIMIF ignored card busy");
        card_busy = 0;
        finish(0, 'hffffffff, 'h00080004, cycle, 2);
        cfg_keypad = 0;
        access (0, 0, 'h0c1500b8, 0, 15, 'hffffffff, 4, 3);
        cfg_keypad = 1;
        access (0, 0, 'h0c150554, 0, 12, 'hffffffff, 'h7e000000, 3);

        access (1, 0, 'h0c150010, 'h10000000, 15, 0, 0, 3);
        access (1, 0, 'h0c150200, 'h00010000, 12, 0, 0, 3);
        access (0, 0, 'h0c150208, 0, 12, 'h00020000, 'h00020000, 3);
        keys[0] = 1;
        access (0, 0, 'h0c150208, 0, 12, 'h00020000, KEYPAD_ENABLE ? 0 : 'h00020000, 3);
        keys[0] = 0;
        access (0, 0, 'h0c150100, 0, 15, 'h00001000, 'h00001000, 3);
        access (1, 0, 'h0c150100, 'h1000, 3, 0, 0, 3);
        access (0, 0, 'h0c150100, 0, 15, 'h00001000, 0, 3);

        // Read live keyboard pins only on authorized completion, then hold data.
        access (1, 0, 'h0c15040c, 0, 3, 0, 0, 3);
        access (1, 0, 'h0c15040c, 'h00010000, 4, 0, 0, 3);
        access (1, 0, 'h0c150400, 'h1f000000, 8, 0, 0, 3);
        allow      = 0;
        hold_reply = 1;
        offer(0, 'h0c150400, 0, 3);
        repeat (3) tick;
        if (pending || cpu_ack || !packet) $fatal(1, "Commit guard failed");
        keys[5] = 1;
        tick;
        allow = 1;
        tick;
        if (!pending || (KEYPAD_ENABLE && (rdata & 31) != 30))
            $fatal(1, "Key wasn't sampled on the live response edge");
        observed    = rdata;
        old_samples = samples;
        keys[5]     = 0;
        repeat (4) begin
            tick;
            if (!pending || rdata !== observed || samples != old_samples || cpu_ack)
                $fatal(1, "Held response recomputed or committed twice");
        end
        hold_reply = 0;
        finish(0, 'hffffffff, observed, cycle, 1);

        // A stalled TX write must commit once, even if the result is held.
        tx_ready = 0;
        for (k = 0; k < 16; k = k + 1) access (1, 0, 'h0c150554, k << 8, 3, 0, 0, 3);
        old_pushes = tx_pushes;
        offer(1, 'h0c150554, 'h00009900, 3);
        repeat (6) tick;
        if (pending || cpu_ack || tx_pushes != old_pushes) $fatal(1, "Full TX accepted");
        cyc      = 0;
        tx_ready = 1;
        repeat (6) tick;
        if (tx_pushes != old_pushes || cpu_ack) $fatal(1, "Cancelled TX accepted");
        access (1, 0, 'h0c150554, 'h00009900, 3, 0, 0, 3);
        if (tx_pushes != old_pushes + 1) $fatal(1, "Lost TX write");

        // Every mask/direction and aligned word, including invalid lanes,
        // across the status overlap and a GPIO address next to EUART.
        for (k = 0; k < 8; k = k + 1) begin
            for (mask = 0; mask < 16; mask = mask + 1) begin
                access (1, !valid_lanes(mask[3:0]), euart_address(k) + (mask & 3), 'ha5b6c7d8 | k,
                        mask[3:0], 0, 0, 0);
                access (0, !valid_lanes(mask[3:0]) || (k == 2 && (mask & 12) != 0), euart_address(k
                        ) + (mask & 3), 0, mask[3:0], 0, 0, 0);
            end
        end

        // Cancel a GPIO write before authorization. A queued response and
        // stale valid address must also clear across warm reset.
        allow       = 0;
        old_samples = samples;
        offer(1, 'h0c150508, 'hfeedface, 15);
        tick;
        cyc = 0;
        tick;
        allow = 1;
        if (samples != old_samples || cpu_ack) $fatal(1, "Cancelled GPIO wrote");
        access (0, 0, 'h0c150508, 0, 15, 'hffffffff, 'ha5b6c7df, 4);
        hold_reply = 1;
        offer(0, 'h0c150510, 0, 15);
        repeat (2) tick;
        if (!pending) $fatal(1, "Warm-reset fixture missed response");
        reset = 1;
        cyc   = 0;
        tick;
        reset      = 0;
        hold_reply = 0;
        if (pending || cpu_ack || cpu_error) $fatal(1, "Warm-reset stale response");
        access (0, 0, 'h0c150510, 0, 15, 'hffffffff, 0, 3);
        access (0, 0, 'h0c150508, 0, 15, 'hffffffff, 'ha5b6c7df, 4);
        cyc = 0;
        tick;
        if (gpio_count == 0 || uart_count == 0 || overlap_count == 0 ||
            nos_count == 0 || loop_count == 0 || rx_pops != 3)
            $fatal(1, "Missing owner or FIFO coverage");
        $display(
            "PASS lane13 keypad=%0d replies=%0d samples=%0d writes=%0d gpio=%0d uart=%0d overlap=%0d nos=%0d loop=%0d tx=%0d rx=%0d",
            KEYPAD_ENABLE, replies, samples, writes, gpio_count, uart_count, overlap_count,
            nos_count, loop_count, tx_pushes, rx_pops);
        $finish;
    end
endmodule
