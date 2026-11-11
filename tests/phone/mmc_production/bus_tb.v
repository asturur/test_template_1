`timescale 1ns / 1ps
`ifndef HOST_MODULE
`define HOST_MODULE ngage_mmc_host
`endif
// Authored register/native-pin peer. No hierarchy reads, force or state restore.
module tb;
    parameter DIV = 4, FIFO_DEPTH = 16;
    reg clk = 0, reset = 1;
    always #5 clk = ~clk;
    reg acc = 0, we = 0, wr = 0, rd = 0;
    reg [ 5:0] off = 0;
    reg [ 3:0] be = 15;
    reg [31:0] wdata = 0;
    wire [31:0] rmask, rdata;
    wire busy, rx_ready, tx_ready;
    wire [3:0] irq;
    wire mmc_clk, cmd_o, cmd_oe, dat_o, dat_oe;
    reg peer_cmd = 1, peer_dat = 1;
    wire cmd_i = cmd_oe ? cmd_o : peer_cmd;
    wire dat_i = dat_oe ? dat_o : peer_dat;
    integer cycles = 0, edges = 0, cases = 0, seed = 0, tx_seen = 0;
    integer length, observed, saved_edges;
    reg rx_finished = 0, tx_finished = 0;
    reg [31:0] status, value;
    reg [31:0] bus_base = 32'h0c120600;
    wire claim, ready, bad, initialized;
    wire irq_line, mmc_prefetch_stop;
    reg last_block = 0;
    // Raw native IRQ is observed only to reuse the independent pin peer's
    // timing assertions. All register traffic uses the public captured bus.
    assign irq = dut.mmc_enabled.host.irq;
    ngage_upp_peripherals #(
        .MMC_ENABLE        (1),
        .MMC_CLK_DIV       (DIV),
        .MMC_TIMEOUT_LOG2  (10),
        .REGISTER_RESPONSES(1)
    ) dut (
        .clk                 (clk),
        .rst                 (reset),
        .init_rst            (reset),
        .cyc                 (acc),
        .stb                 (acc),
        .commit              (acc),
        .adr                 (bus_base + off),
        .we                  (we),
        .din                 (wdata),
        .sel                 (be),
        .claim               (claim),
        .ready               (ready),
        .unmodeled           (bad),
        .dout                (rdata),
        .init_done           (initialized),
        .irq                 (irq_line),
        .cfg_lcd             (1'b0),
        .cfg_keypad          (1'b0),
        .cfg_clocks          (1'b0),
        .dma_irq_pending     (1'b0),
        .general_dma_irq     (8'd0),
        .sim_fiq_pending     (1'b0),
        .keys                (26'd0),
        .sim_present         (1'b0),
        .card_rx_valid       (1'b0),
        .card_tx_will_emit   (1'b0),
        .card_overflow       (1'b0),
        .card_rx_data        (8'd0),
        .card_available      (7'd0),
        .card_busy           (1'b0),
        .cbus_claim          (1'b0),
        .cbus_bad            (1'b0),
        .cbus_irq            (1'b0),
        .cbus_data           (32'd0),
        .route2a             (16'd0),
        .route2c             (16'd0),
        .route3b             (16'd0),
        .cbus8d_written      (1'b0),
        .mdi_claim           (1'b0),
        .mdi_bad             (1'b0),
        .mdi_data            (32'd0),
        .mdi_events          (16'd0),
        .lcd_sink_ready      (1'b1),
        .lcd_dma_access      (1'b0),
        .lcd_pixel_mode      (1'b0),
        .dma_shadow_claim    (1'b0),
        .lcd_direct_collision(1'b0),
        .mmc_prefetch_stop   (mmc_prefetch_stop),
        .mmc_clk             (mmc_clk),
        .mmc_cmd_o           (cmd_o),
        .mmc_cmd_oe          (cmd_oe),
        .mmc_cmd_i           (cmd_i),
        .mmc_dat_o           (dat_o),
        .mmc_dat_oe          (dat_oe),
        .mmc_dat_i           (dat_i),
        .mmc_rx_ready        (rx_ready),
        .mmc_tx_ready        (tx_ready)
    );
    always @(posedge clk) begin
        cycles <= cycles + 1;
        if (cycles > 1500000) $fatal(1, "host peer timeout case%0d", cases);
    end
    always @(posedge mmc_clk) edges = edges + 1;
    function [7:0] pattern;
        input integer index, tag;
        begin
            pattern = ((index * 37) ^ (tag * 17) ^ 166) & 255;
        end
    endfunction
    function [6:0] crc7;
        input [39:0] bits;
        reg     [46:0] division;
        integer        i;
        begin
            division = {bits, 7'd0};
            for (i = 46; i >= 7; i = i - 1)
            if (division[i]) division = division ^ (47'h89 << (i - 7));
            crc7 = division[6:0];
        end
    endfunction
    function [15:0] data_crc;
        input integer count, tag;
        reg     [8191:0] division;
        integer          i;
        begin
            division = 0;
            for (i = 0; i < count; i = i + 1) division = (division << 8) | pattern(i, tag);
            division = division << 16;
            for (i = count * 8 + 15; i >= 16; i = i - 1)
            if (division[i]) division = division ^ (8192'h11021 << (i - 16));
            data_crc = division[15:0];
        end
    endfunction
    task bus_transfer;
        input write_access;
        input [5:0] address;
        input [31:0] data;
        input [3:0] lanes;
        output [31:0] response;
        integer wait_cycles;
        begin
            @(negedge clk);
            acc         = 1;
            we          = write_access;
            off         = address;
            be          = lanes;
            wdata       = data;
            wait_cycles = 0;
            #1;
            while (!ready) begin
                @(negedge clk);
                #1;
                wait_cycles = wait_cycles + 1;
                if (wait_cycles > 100000) $fatal(1, "captured bus timeout off%h", address);
            end
            if (!claim || bad) $fatal(1, "captured bus rejected off%h lanes%h", address, lanes);
            response = rdata;
            // Hold a completed request to prove FIFO/response effects do not repeat.
            repeat (3) @(negedge clk);
            if (rdata !== response || !ready) $fatal(1, "captured response changed under hold");
            acc = 0;
            repeat (2) @(negedge clk);
        end
    endtask
    task write_register;
        input [5:0] address;
        input [31:0] data;
        reg [31:0] unused;
        begin
            bus_transfer(1, address, data, 15, unused);
        end
    endtask
    task read_register;
        input [5:0] address;
        output [31:0] data;
        begin
            bus_transfer(0, address, 0, 15, data);
        end
    endtask
    task fifo_write;
        input [31:0] data;
        reg [31:0] unused;
        begin
            bus_transfer(1, 6'h24, data, 15, unused);
        end
    endtask
    task fifo_read;
        output [31:0] data;
        begin
            bus_transfer(0, 6'h24, 0, 15, data);
        end
    endtask
    task finish_status;
        input [31:0] expected;
        begin
            wait (irq[0] && irq[2]);
            read_register(6'h18, status);
            if (status !== expected)
                $fatal(1, "status %h expected%h case%0d", status, expected, cases);
            if (irq !== 4'b0101) $fatal(1, "idle IRQ mapping %b", irq);
            if (mmc_prefetch_stop !== 1'b0) $fatal(1, "prefetch held after command/data idle");
            cases = cases + 1;
        end
    endtask
    task irq_check;
        input [31:0] mask;
        input [31:0] expected;
        reg [31:0] returned;
        begin
            bus_base = 32'h0c120100;
            write_register(6'h0c, 32'h01e00000);
            write_register(6'h08, mask);
            read_register(6'h14, returned);
            if (returned !== expected)
                $fatal(1, "MMC ICU mask%h got%0d expected%0d", mask, returned, expected);
            write_register(6'h0c, mask);
            bus_base = 32'h0c120600;
        end
    endtask
    task lane_cases;
        reg [31:0] word, unused;
        begin
            write_register(6'h08, 3);
            fork
                card_collect_write(3, 25, 0, 0);
                begin
                    write_register(6'h04, 25);
                    bus_transfer(1, 6'h24, {pattern(0, 25), 24'd0}, 8, unused);
                    bus_transfer(1, 6'h24, {16'd0, pattern(1, 25), 8'd0}, 2, unused);
                    bus_transfer(1, 6'h24, {8'd0, pattern(2, 25), 16'd0}, 4, unused);
                end
            join
            finish_status(0);
            write_register(6'h08, 3);
            fork
                card_read_data(3, 26, 0, 0);
                begin
                    write_register(6'h04, 37);
                    bus_transfer(0, 6'h24, 0, 2, word);
                    if (word !== {16'd0, pattern(0, 26), 8'd0}) $fatal(1, "RX lane1");
                    bus_transfer(0, 6'h24, 0, 8, word);
                    if (word !== {pattern(1, 26), 24'd0}) $fatal(1, "RX lane3");
                    bus_transfer(0, 6'h24, 0, 1, word);
                    if (word !== {24'd0, pattern(2, 26)}) $fatal(1, "RX lane0");
                end
            join
            finish_status(0);
        end
    endtask
    task command_peer;
        input integer command, ordering;
        reg [47:0] packet, reply;
        reg     [39:0] head;
        integer        bit_index;
        begin
            wait (cmd_oe);
            if (ordering != 0 && mmc_prefetch_stop !== 1'b1)
                $fatal(1, "queued final command lost prefetch stop");
            if (ordering == 1 && !rx_finished)
                $fatal(1, "type10 command preceded final RX end bit");
            if (ordering == 2 && !tx_finished) $fatal(1, "type7 command preceded TX busy release");
            packet = 0;
            for (bit_index = 0; bit_index < 48; bit_index = bit_index + 1) begin
                @(posedge mmc_clk);
                packet = {packet[46:0], cmd_o};
            end
            if(packet[47:46]!==2'b01||packet[45:40]!==command[5:0]||packet[39:8]!==32'h12340000||
                packet[7:1]!==crc7(
                    packet[47:8]
                ) || !packet[0])
                $fatal(1, "command wire frame %h", packet);
            wait (!cmd_oe);
            repeat (2) @(posedge mmc_clk);
            head  = {2'b00, command[5:0], 32'h00000900};
            reply = {head, crc7(head), 1'b1};
            for (bit_index = 47; bit_index >= 0; bit_index = bit_index - 1) begin
                @(negedge mmc_clk);
                peer_cmd = reply[bit_index];
            end
            @(negedge mmc_clk);
            peer_cmd = 1;
            if (ordering != 0) begin
                // The command has reached its end bit but NRC has not elapsed.
                // A premature release would permit an unnecessary stream fetch.
                repeat (7) begin
                    @(posedge mmc_clk);
                    if (mmc_prefetch_stop !== 1'b1) $fatal(1, "prefetch released before NRC");
                end
            end
        end
    endtask
    task card_read_data;
        input integer count, tag, damage, wait_command;
        reg [ 7:0] byte_value;
        reg [15:0] checksum;
        integer i, k;
        begin
            if (wait_command) begin
                wait (cmd_oe);
                wait (!cmd_oe);
                repeat (52) @(posedge mmc_clk);
            end else repeat (2) @(posedge mmc_clk);
            @(negedge mmc_clk);
            if (last_block && mmc_prefetch_stop !== 1'b1)
                $fatal(1, "final RX block started without queued-command hint");
            peer_dat = 0;
            for (i = 0; i < count; i = i + 1) begin
                byte_value = pattern(i, tag);
                for (k = 7; k >= 0; k = k - 1) begin
                    @(negedge mmc_clk);
                    peer_dat = byte_value[k];
                end
            end
            checksum = data_crc(count, tag);
            if (damage == 1) checksum = checksum ^ 16'h1;
            for (k = 15; k >= 0; k = k - 1) begin
                @(negedge mmc_clk);
                peer_dat = checksum[k];
            end
            @(negedge mmc_clk);
            peer_dat = damage == 2 ? 0 : 1;
            @(posedge mmc_clk);
            rx_finished = 1;
            @(negedge mmc_clk);
            peer_dat = 1;
        end
    endtask
    task host_read_fifo;
        input integer count, tag, stall;
        reg [31:0] word, expected;
        integer i, k, start_edges;
        begin
            if (stall) begin
                repeat ((FIFO_DEPTH * 8 + 12) * DIV) @(negedge clk);
                start_edges = edges;
                repeat (DIV * 12) @(negedge clk);
                if (edges != start_edges || mmc_clk || !rx_ready || irq[0])
                    $fatal(1, "RX did not stall safely on full FIFO");
            end
            for (i = 0; i < ((count + 3) / 4); i = i + 1) begin
                fifo_read(word);
                expected = 0;
                for (k = 0; k < 4; k = k + 1)
                if (i * 4 + k < count) expected[k*8+:8] = pattern(i * 4 + k, tag);
                if (word !== expected)
                    $fatal(
                        1, "RX/padding count%0d word%0d got%h expected%h", count, i, word, expected
                    );
            end
            fifo_read(word);
            if (word !== 0) $fatal(1, "RX overread not zero");
        end
    endtask
    task host_write_fifo;
        input integer count, tag, stall;
        reg [31:0] word;
        integer i, k, start_edges;
        begin
            if (stall) begin
                repeat (DIV * 12) @(negedge clk);
                start_edges = edges;
                repeat (DIV * 12) @(negedge clk);
                if (edges != start_edges || mmc_clk || irq[0])
                    $fatal(1, "TX empty FIFO did not stop clock");
            end
            for (i = 0; i < ((count + 3) / 4); i = i + 1) begin
                word = 32'hdeadbeef;
                for (k = 0; k < 4; k = k + 1)
                if (i * 4 + k < count) word[k*8+:8] = pattern(i * 4 + k, tag);
                fifo_write(word);
                if (stall && i == 0 && count > 4) begin
                    wait (tx_seen >= 33);
                    repeat (DIV * 6) @(negedge clk);
                    start_edges = edges;
                    repeat (DIV * 12) @(negedge clk);
                    if (edges != start_edges || mmc_clk)
                        $fatal(1, "TX mid-block empty FIFO did not stall");
                end
            end
            // These must not create extra wire bytes after the logical tail.
            fifo_write(32'h76543210);
        end
    endtask
    task card_collect_write;
        input integer count, tag, token_mode, busy_clocks;
        reg [8191:0] bits, division;
        reg [4:0] token;
        integer n, i, k;
        begin
            wait (dat_oe);
            if (last_block && mmc_prefetch_stop !== 1'b1)
                $fatal(1, "final TX block started without queued-command hint");
            bits    = 0;
            n       = 0;
            tx_seen = 0;
            while (dat_oe) begin
                @(posedge mmc_clk);
                if (dat_oe) begin
                    bits    = {bits[8190:0], dat_o};
                    n       = n + 1;
                    tx_seen = n;
                end
            end
            if (n != count * 8 + 18 || bits[n-1] !== 0 || bits[0] !== 1)
                $fatal(1, "TX logical length%0d wirebits%0d", count, n);
            for (k = 0; k < count; k = k + 1)
            if (bits[n-2-k*8-:8] !== pattern(k, tag))
                $fatal(1, "TX data/padding changed byte%0d", k);
            division = bits >> 1;
            for (i = n - 2; i >= 16; i = i - 1)
            if (division[i]) division = division ^ (8192'h11021 << (i - 16));
            if (division[15:0] !== 0) $fatal(1, "TX CRC16");
            if (token_mode != 2) begin
                token = token_mode == 1 ? 5'b01011 : 5'b00101;
                for (i = 4; i >= 0; i = i - 1) begin
                    @(negedge mmc_clk);
                    peer_dat = token[i];
                end
                @(negedge mmc_clk);
                peer_dat = busy_clocks ? 0 : 1;
                if (busy_clocks < 0) wait (irq[0]);
                else
                    repeat (busy_clocks) begin
                        @(posedge mmc_clk);
                        if (last_block && mmc_prefetch_stop !== 1'b1)
                            $fatal(1, "prefetch released during final TX busy");
                    end
                @(negedge clk);
                peer_dat = 1;
            end
            tx_finished = 1;
        end
    endtask
    task reset_host;
        begin
            @(negedge clk);
            reset    = 1;
            acc      = 0;
            wr       = 0;
            rd       = 0;
            peer_cmd = 1;
            peer_dat = 1;
            repeat (3) @(negedge clk);
            reset = 0;
            wait (initialized);
            repeat (2) @(negedge clk);
            if (cmd_oe || dat_oe || mmc_clk || irq !== 4'b0101)
                $fatal(1, "reset leaked pin/IRQ ownership");
            read_register(6'h18, status);
            if (status !== 0) $fatal(1, "reset retained status");
            fifo_read(value);
            if (value !== 0) $fatal(1, "reset retained readable FIFO data");
            cases = cases + 1;
        end
    endtask
    task rx_case;
        input integer count, tag, damage, stall, kind;
        begin
            rx_finished = 0;
            last_block  = kind == 10;
            write_register(6'h08, count);
            if (kind == 8 || kind == 10) begin
                write_register(6'h1c, kind == 8 ? 17 : 12);
                write_register(6'h20, 32'h12340000);
            end
            fork
                card_read_data(count, tag, damage, kind == 8);
                begin
                    write_register(6'h04, kind * 4 + 1);
                    host_read_fifo(count, tag, stall);
                end
                begin
                    if (kind == 8 || kind == 10)
                        command_peer(kind == 8 ? 17 : 12, kind == 10 ? 1 : 0);
                end
            join
            if (kind == 8 || kind == 10) begin
                irq_check(32'h01000000, 25);
                irq_check(32'h00400000, 0);
                read_register(6'h20, value);
                if (value !== 32'h900) $fatal(1, "RX command response FIFO");
            end
            finish_status(damage ? 1 : 0);
            last_block = 0;
        end
    endtask
    task tx_case;
        input integer count, tag, token_mode, busy_clocks, stall, kind;
        reg [31:0] wanted;
        begin
            tx_finished = 0;
            last_block  = kind == 7;
            tx_seen     = 0;
            write_register(6'h08, count);
            if (kind == 5 || kind == 7) begin
                write_register(6'h1c, kind == 5 ? 24 : 12);
                write_register(6'h20, 32'h12340000);
            end
            fork
                card_collect_write(count, tag, token_mode, busy_clocks);
                begin
                    write_register(6'h04, kind * 4 + 1);
                    host_write_fifo(count, tag, stall);
                end
                begin
                    if (kind == 5 || kind == 7)
                        command_peer(kind == 5 ? 24 : 12, kind == 7 ? 2 : 0);
                end
            join
            if (kind == 5 || kind == 7) begin
                read_register(6'h20, value);
                if (value !== 32'h900) $fatal(1, "TX response FIFO");
            end
            wanted = token_mode == 1 ? 1 : token_mode == 2 ? 1024 : busy_clocks < 0 ? 32 : 0;
            finish_status(wanted);
            last_block = 0;
        end
    endtask
    initial begin
        repeat (4) @(negedge clk);
        reset = 0;
        wait (initialized);
        irq_check(32'h00200000, 22);
        irq_check(32'h00800000, 24);
        irq_check(32'h00400000, 0);
        lane_cases();
        for (seed = 0; seed < 6; seed = seed + 1) begin
            case (seed)
                0:       length = 1;
                1:       length = 2;
                2:       length = 3;
                3:       length = 5;
                4:       length = 511;
                default: length = 512;
            endcase
            tx_case(length, seed, 0, 0, length >= 5, 6);
            rx_case(length, seed, 0, length >= 511, 9);
        end
        rx_case(5, 7, 1, 0, 9);
        rx_case(3, 8, 2, 0, 9);
        tx_case(5, 9, 1, 0, 0, 6);
        tx_case(2, 10, 2, 0, 0, 6);
        tx_case(3, 11, 0, -1, 0, 6);
        // Native multiblock sequences: command first, middle data-only, then
        // final block before CMD12 (and, for TX, after its card-busy release).
        tx_case(3, 12, 0, 3, 0, 5);
        tx_case(5, 13, 0, 0, 0, 6);
        tx_case(2, 14, 0, 6, 0, 7);
        rx_case(3, 15, 0, 0, 8);
        rx_case(5, 16, 0, 0, 9);
        rx_case(2, 17, 0, 0, 10);
        write_register(6'h08, 5);
        write_register(6'h04, 37);  // type9: data start timeout
        finish_status(128);
        fifo_read(value);
        if (value !== 0) $fatal(1, "timeout RX FIFO not zero");
        // Reset while TX awaits bytes, then while RX is stalled on full FIFO.
        write_register(6'h08, 5);
        write_register(6'h04, 25);
        repeat (DIV * 20) @(negedge clk);
        reset_host();
        begin : abandoned_rx
            write_register(6'h08, 511);
            write_register(6'h04, 37);
            fork
                card_read_data(511, 18, 0, 0);
                begin
                    repeat ((FIFO_DEPTH * 8 + 24) * DIV) @(negedge clk);
                    reset_host();
                    disable abandoned_rx;
                end
            join
        end
        // Fresh transactions must progress after either canceled phase.
        tx_case(5, 19, 0, 0, 0, 6);
        rx_case(5, 20, 0, 0, 9);
        $display(
            "PASS MMC captured bus/pin peer DIV=%0d FIFO=%0d cases=%0d clocks=%0d: exact TX/RX lengths, rounded4 padding, stalls, CRC/token/busy/start errors, reset, final-block prefetch suppression through NRC/busy and 5/6/7/8/9/10 ordering",
            DIV, FIFO_DEPTH, cases, cycles);
        $finish;
    end
endmodule
