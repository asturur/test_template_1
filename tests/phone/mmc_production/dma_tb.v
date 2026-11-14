`timescale 1ns / 1ps
`ifndef HOST_MODULE
`define HOST_MODULE ngage_mmc_host
`endif
// Authored register/native-pin peer. No hierarchy reads, force or state restore.
module tb;
    parameter RX_CONTROL = 2;
    wire local_waiting;
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
    wire claim, ready, bad, initialized, irq_line, cpu_lock;
    wire bcyc, bstb, bwe, baccess, lcd_claim, lcd_bad, lcd_ready;
    wire [31:0] baddr, bdata, periph_data, lcd_data;
    wire [3:0] bsel;
    wire cpu_ack = bcyc && bstb && ((lcd_claim && lcd_ready) || (!lcd_claim && claim && ready));
    wire cpu_error = cpu_ack && (lcd_claim ? lcd_bad : bad);
    wire [31:0] cpu_read = lcd_claim ? lcd_data : periph_data;
    wire cv, cr, cw, rv, re, lv, lr, lw, ld, le, mreq, mwrite, mack;
    wire [31:0] ca, cd, rr, la, ldata, lrdata, mdata;
    wire [24:0] ma;
    wire [3:0] cb, lbe, mbe;
    wire [7:0] dma_errors;
    reg  [7:0] memory       [0:4095];
    reg  [2:0] delay = 0;
    reg        hold_ram = 0;
    assign mack = mreq && delay == 3 && !hold_ram;
    wire [31:0] mrdata = {
        memory[ma[11:0]+3], memory[ma[11:0]+2], memory[ma[11:0]+1], memory[ma[11:0]]
    };
    integer lane;
    always @(posedge clk) begin
        if (reset || !mreq || mack) delay <= 0;
        else if (delay < 3) delay <= delay + 1;
        if (mack && mwrite)
            for (lane = 0; lane < 4; lane = lane + 1)
            if (mbe[lane]) memory[ma[11:0]+lane] <= mdata[lane*8+:8];
    end
    // An authored Wishbone master substitutes only the CPU leaf. The actual
    // UPP memory route, capture bridge, local arbiter and response owner run.
    ngage_upp #(
        .INTERNAL_CPU    (1),
        .GENERAL_DMA     (1),
        .MMC_ENABLE      (1),
        .MMC_TIMEOUT_LOG2(12)
    ) dut (
        .clk              (clk),
        .rst              (reset),
        .init_rst         (reset),
        .cpu_ack          (cpu_ack),
        .cpu_err          (cpu_error),
        .cpu_rdata        (cpu_read),
        .bus_cyc          (bcyc),
        .bus_stb          (bstb),
        .bus_we           (bwe),
        .bus_access       (baccess),
        .bus_adr          (baddr),
        .bus_din          (bdata),
        .bus_sel          (bsel),
        .claim            (claim),
        .ready            (ready),
        .unmodeled        (bad),
        .dout             (periph_data),
        .init_done        (initialized),
        .cpu_lock         (cpu_lock),
        .lcd_dma_claim    (lcd_claim),
        .lcd_dma_ready    (lcd_ready),
        .lcd_dma_bad      (lcd_bad),
        .lcd_dma_reg_data (lcd_data),
        .irq              (irq_line),
        .cfg_lcd          (1'b0),
        .cfg_keypad       (1'b0),
        .cfg_clocks       (1'b0),
        .lcd_queue_empty  (1'b1),
        .lcd_sink_ready   (1'b1),
        .lcd_pixel_mode   (1'b0),
        .lcd_fast_ready   (1'b1),
        .lcd_fast_error   (1'b1),
        .dma_mem_accept   (1'b0),
        .dma_mem_ack      (1'b0),
        .dma_mem_data     (32'd0),
        .dma_cmd_valid    (cv),
        .dma_cmd_ready    (cr),
        .dma_cmd_write    (cw),
        .dma_cmd_addr     (ca),
        .dma_cmd_data     (cd),
        .dma_cmd_be       (cb),
        .dma_rsp_valid    (rv),
        .dma_rsp_error    (re),
        .dma_rsp_data     (rr),
        .dma_error_pending(dma_errors),
        .dma_local_valid  (lv),
        .dma_local_waiting(local_waiting),
        .dma_local_ready  (lr),
        .dma_local_write  (lw),
        .dma_local_addr   (la),
        .dma_local_data   (ldata),
        .dma_local_be     (lbe),
        .dma_local_done   (ld),
        .dma_local_error  (le),
        .dma_local_rdata  (lrdata),
        .dma_irq_pending  (1'b0),
        .sim_fiq_pending  (1'b0),
        .keys             (26'd0),
        .sim_present      (1'b0),
        .card_rx_valid    (1'b0),
        .card_tx_will_emit(1'b0),
        .card_overflow    (1'b0),
        .card_rx_data     (8'd0),
        .card_available   (7'd0),
        .card_busy        (1'b0),
        .cbus_claim       (1'b0),
        .cbus_bad         (1'b0),
        .cbus_irq         (1'b0),
        .cbus_data        (32'd0),
        .route2a          (16'd0),
        .route2c          (16'd0),
        .route3b          (16'd0),
        .cbus8d_written   (1'b0),
        .mdi_claim        (1'b0),
        .mdi_bad          (1'b0),
        .mdi_data         (32'd0),
        .mdi_events       (16'd0),
        .mmc_clk          (mmc_clk),
        .mmc_cmd_o        (cmd_o),
        .mmc_cmd_oe       (cmd_oe),
        .mmc_cmd_i        (cmd_i),
        .mmc_dat_o        (dat_o),
        .mmc_dat_oe       (dat_oe),
        .mmc_dat_i        (dat_i)
    );
    ngage_dma_route route (
        .clk          (clk),
        .reset        (reset),
        .cpu_lock     (cpu_lock),
        .cmd_valid    (cv),
        .cmd_ready    (cr),
        .cmd_write    (cw),
        .cmd_addr     (ca),
        .cmd_data     (cd),
        .cmd_be       (cb),
        .rsp_valid    (rv),
        .rsp_error    (re),
        .rsp_data     (rr),
        .ram_req      (mreq),
        .ram_write    (mwrite),
        .ram_addr     (ma),
        .ram_data     (mdata),
        .ram_be       (mbe),
        .ram_ack      (mack),
        .ram_rdata    (mrdata),
        .local_valid  (lv),
        .local_waiting(local_waiting),
        .local_ready  (lr),
        .local_write  (lw),
        .local_addr   (la),
        .local_data   (ldata),
        .local_be     (lbe),
        .local_done   (ld),
        .local_error  (le),
        .local_rdata  (lrdata)
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
    task reg_write;
        input [31:0] address, data;
        reg [31:0] unused;
        begin
            dut.cpu_inside.cpu.transfer(1, address, data, 15, unused);
        end
    endtask
    task reg_read;
        input [31:0] address;
        output [31:0] data;
        begin
            dut.cpu_inside.cpu.transfer(0, address, 0, 15, data);
        end
    endtask
    task write_register;
        input [5:0] address;
        input [31:0] data;
        begin
            reg_write(32'h0c120600 + address, data);
        end
    endtask
    task read_register;
        input [5:0] address;
        output [31:0] data;
        begin
            reg_read(32'h0c120600 + address, data);
        end
    endtask
    task configure_dma;
        input integer channel, receive, count;
        reg [31:0] address;
        begin
            address = 32'h0c120300 + channel * 64;
            reg_write(32'h0c120068, 15 << (channel * 4));
            reg_write(32'h0c120064, 2 << (channel * 4));
            reg_write(address + 4, 1);
            reg_write(address + 20, receive ? 32'h10120624 : 32'h0a000100);
            reg_write(address + 24, receive ? 0 : 1);
            reg_write(address + 28, receive ? 8 : 32);
            reg_write(address + 32, receive ? 32'h0a000100 : 32'h10120624);
            reg_write(address + 36, receive ? 1 : 0);
            reg_write(address + 40, receive ? 32 : 8);
            reg_write(address + 44, ((count + 3) / 4) * 4 - 1);
        end
    endtask
    task await_dma;
        input integer channel;
        integer        polls;
        reg     [31:0] value;
        begin
            value = 1;
            polls = 0;
            while (value != 0) begin
                reg_read(32'h0c120308 + channel * 64, value);
                polls = polls + 1;
                if (polls > 10000) $fatal(1, "DMA stuck channel%0d", channel);
            end
            if (dma_errors) $fatal(1, "DMA error %h", dma_errors);
            reg_write(32'h0c120108, 1 << (6 + channel));
            reg_read(32'h0c120114, value);
            if (value !== 7 + channel)
                $fatal(1, "DMA IRQ map channel%0d current%0d", channel, value);
            reg_write(32'h0c12010c, 1 << (6 + channel));
            reg_read(32'h0c120114, value);
            if (value) $fatal(1, "ICU disable failed");
            reg_write(32'h0c120108, 1 << (6 + channel));
            reg_read(32'h0c120114, value);
            if (value !== 7 + channel) $fatal(1, "mask clear consumed DMA pending");
            reg_write(32'h0c120304 + channel * 64, 0);
            reg_read(32'h0c120114, value);
            if (value) $fatal(1, "channel ACK failed");
            reg_write(32'h0c12010c, 1 << (6 + channel));
        end
    endtask
    task finish_status;
        input [31:0] expected;
        integer polls;
        begin
            status = 12;
            polls  = 0;
            while (status & 12) begin
                read_register(6'h18, status);
                polls = polls + 1;
                if (polls > 10000) $fatal(1, "host busy forever");
            end
            if (status !== expected) $fatal(1, "host status %h expected%h", status, expected);
            cases = cases + 1;
        end
    endtask
    task command_peer;
        input integer command, ordering;
        reg [47:0] packet, reply;
        reg     [39:0] head;
        integer        bit_index;
        begin
            wait (cmd_oe);
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
    task card_collect_write;
        input integer count, tag, token_mode, busy_clocks;
        reg [8191:0] bits, division;
        reg [4:0] token;
        integer n, i, k;
        begin
            wait (dat_oe);
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
                if (busy_clocks < 0) $fatal(1, "unsupported peer option");
                else repeat (busy_clocks) @(posedge mmc_clk);
                @(negedge clk);
                peer_dat = 1;
            end
            tx_finished = 1;
        end
    endtask
    task reset_composition;
        begin
            @(negedge clk);
            reset    = 1;
            peer_cmd = 1;
            peer_dat = 1;
            hold_ram = 0;
            repeat (4) @(negedge clk);
            reset = 0;
            wait (initialized);
            repeat (2) @(negedge clk);
            if (dma_errors || cv || mreq || lv) $fatal(1, "reset retained DMA ownership");
        end
    endtask
    task wait_inactive;
        input integer channel;
        integer        polls;
        reg     [31:0] v;
        begin
            polls = 0;
            v     = 1;
            while (v) begin
                reg_read(32'h0c120308 + channel * 64, v);
                polls = polls + 1;
                if (polls > 1000) $fatal(1, "cancel did not drain");
            end
        end
    endtask
    task require_no_irq;
        input integer channel;
        reg [31:0] v;
        begin
            reg_write(32'h0c120108, 1 << (6 + channel));
            reg_read(32'h0c120114, v);
            if (v) $fatal(1, "canceled/error DMA asserted success IRQ%0d", v);
            reg_write(32'h0c12010c, 1 << (6 + channel));
        end
    endtask
    task focused_boundaries;
        integer        k;
        reg     [31:0] v;
        begin
            reset_composition();
            // No incoming data: paced RX must not reserve the global route or
            // local bus. A CPU-programmed peer memory copy still completes.
            configure_dma(0, 1, 8);
            write_register(6'h08, 8);
            write_register(6'h04, 37);
            reg_write(32'h0c120308, RX_CONTROL);
            for (k = 0; k < 8; k = k + 1) memory[768+k] = 8'h40 + k;
            reg_write(32'h0c120344, 1);
            reg_write(32'h0c120354, 32'h0a000300);
            reg_write(32'h0c120358, 1);
            reg_write(32'h0c12035c, 32);
            reg_write(32'h0c120360, 32'h0a000380);
            reg_write(32'h0c120364, 1);
            reg_write(32'h0c120368, 32);
            reg_write(32'h0c12036c, 3);
            reg_write(32'h0c120348, 1);
            await_dma(1);
            for (k = 0; k < 8; k = k + 1)
            if (memory[896+k] !== 8'h40 + k) $fatal(1, "blocked MMC starved peer RAM copy");
            reg_read(32'h0c120308, v);
            if (v !== RX_CONTROL) $fatal(1, "blocked MMC completed without bytes");
            reg_write(32'h0c120308, 0);
            wait_inactive(0);
            require_no_irq(0);
            if (dma_errors) $fatal(1, "stop became an error");

            reset_composition();
            // Stop after the route owns the source read. It must drain ACK,
            // suppress its not-yet-published FIFO byte and retain busy until ACK.
            configure_dma(2, 0, 8);
            write_register(6'h08, 8);
            write_register(6'h04, 25);
            hold_ram = 1;
            reg_write(32'h0c120388, 2);
            wait (mreq);
            // mreq includes a combinational offer. Wait for its accepting edge
            // before testing cancellation/reset of an owned memory transaction.
            @(posedge clk);
            #1;
            if (route.state != 3'd1) $fatal(1, "RAM offer was not accepted");
            reg_write(32'h0c120388, 0);
            reg_read(32'h0c120388, v);
            if (!v) $fatal(1, "stop discarded accepted RAM owner");
            @(negedge clk);
            hold_ram = 0;
            wait_inactive(2);
            require_no_irq(2);
            if (dat_oe || dma_errors) $fatal(1, "stop published canceled FIFO byte");

            reset_composition();
            // A replacement descriptor queues behind the canceled accepted
            // read and then executes from its new immutable fields.
            configure_dma(2, 0, 8);
            write_register(6'h08, 5);
            write_register(6'h04, 25);
            for (k = 0; k < 8; k = k + 1) memory[512+k] = pattern(k, 27);
            hold_ram = 1;
            reg_write(32'h0c120388, 2);
            wait (mreq);
            // mreq includes a combinational offer. Wait for its accepting edge
            // before testing cancellation/reset of an owned memory transaction.
            @(posedge clk);
            #1;
            if (route.state != 3'd1) $fatal(1, "RAM offer was not accepted");
            reg_write(32'h0c120394, 32'h0a000200);
            reg_write(32'h0c1203ac, 7);
            fork
                card_collect_write(5, 27, 0, 3);
                begin
                    reg_write(32'h0c120388, 2);
                    @(negedge clk);
                    hold_ram = 0;
                    await_dma(2);
                end
            join
            finish_status(0);

            reset_composition();
            configure_dma(3, 0, 4);
            reg_write(32'h0c120068, 15 << 12);
            reg_write(32'h0c120064, 9 << 12);
            reg_write(32'h0c1203c8, 2);
            wait_inactive(3);
            require_no_irq(3);
            if (dma_errors !== 8'h08 || mreq || lv)
                $fatal(1, "unknown selector did not fail before traffic");
            reg_write(32'h0c1203c4, 0);
            if (dma_errors) $fatal(1, "diagnostic ACK failed");
            configure_dma(3, 0, 4);
            reg_write(32'h0c1203c8, 1);
            wait_inactive(3);
            require_no_irq(3);
            if (dma_errors !== 8'h08) $fatal(1, "control1 bypassed FIFO pacing");

            reset_composition();
            configure_dma(4, 0, 8);
            hold_ram = 1;
            reg_write(32'h0c120408, 2);
            wait (mreq);
            // mreq includes a combinational offer. Wait for its accepting edge
            // before testing cancellation/reset of an owned memory transaction.
            @(posedge clk);
            #1;
            if (route.state != 3'd1) $fatal(1, "RAM offer was not accepted");
            reset_composition();
            // Fresh transfer after canceled route ownership; no stale data.
            configure_dma(4, 1, 5);
            write_register(6'h08, 5);
            fork
                card_read_data(5, 28, 0, 0);
                begin
                    write_register(6'h04, 37);
                    reg_write(32'h0c120408, RX_CONTROL);
                    await_dma(4);
                end
            join
            finish_status(0);
            for (k = 0; k < 8; k = k + 1)
            if (memory[256+k] !== (k < 5 ? pattern(k, 28) : 8'd0)) $fatal(1, "fresh reset RX tail");
        end
    endtask
    integer ch, i, rx, rounded;
    initial begin
        repeat (4) @(negedge clk);
        reset = 0;
        wait (initialized);
        for (ch = 0; ch < 8; ch = ch + 1) begin
            for (seed = 0; seed < 6; seed = seed + 1) begin
                case (seed)
                    0:       length = 1;
                    1:       length = 2;
                    2:       length = 3;
                    3:       length = 5;
                    4:       length = 511;
                    default: length = 512;
                endcase
                rounded = ((length + 3) / 4) * 4;
                for (rx = 0; rx < 2; rx = rx + 1) begin
                    for (i = 0; i < 1024; i = i + 1) memory[i] = 8'hdb;
                    if (!rx)
                        for (i = 0; i < rounded; i = i + 1) memory[256+i] = pattern(i, ch + seed);
                    configure_dma(ch, rx, length);
                    write_register(6'h08, length);
                    tx_finished = 0;
                    rx_finished = 0;
                    fork
                        begin
                            write_register(6'h04, rx ? 37 : 25);
                            reg_write(32'h0c120308 + ch * 64, rx ? RX_CONTROL : 2);
                            // Live selector edits must not change an accepted descriptor.
                            reg_write(32'h0c120068, 15 << (ch * 4));
                            await_dma(ch);
                        end
                        begin
                            if (rx) card_read_data(length, ch + seed, 0, 0);
                            else card_collect_write(length, ch + seed, 0, 4);
                        end
                    join
                    finish_status(0);
                    if (rx) begin
                        for (i = 0; i < rounded; i = i + 1)
                        if (memory[256+i] !== (i < length ? pattern(i, ch + seed) : 8'd0))
                            $fatal(
                                1,
                                "DMA RX/tail channel%0d count%0d byte%0d got%h",
                                ch,
                                length,
                                i,
                                memory[256+i]
                            );
                    end
                    if (memory[255] !== 8'hdb || memory[256+rounded] !== 8'hdb)
                        $fatal(1, "DMA memory overrun");
                end
            end
        end
        focused_boundaries();
        $display(
            "PASS MMC production UPP/DMA: all8 channels TX2/RX%0d selector2, 1/2/3/5/511/512, exact native bits and rounded4 tails, immutable selector, blocked-peer progress, owned stop/restart/reset, selector errors, ICU masking and channel ACK cases=%0d clocks=%0d",
            RX_CONTROL, cases, cycles);
        $finish;
    end
endmodule
