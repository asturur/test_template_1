`timescale 1ns / 1ps
module tb;
    parameter ENGINES = 3;
    reg clk = 0;
    always #5 clk = ~clk;
    reg reset = 1, req = 0, commit = 0, we = 0;
    reg [31:0] addr = 0, din = 0;
    reg [3:0] sel = 15;
    wire claim, bad;
    wire [31:0] dout;
    wire [7:0] irq, errors, active;
    reg [7:0] src_ready = 255, dst_ready = 255;
    wire cmd_valid, cmd_ready, cmd_write, rsp_valid, rsp_error;
    wire [31:0] cmd_addr, cmd_data, rsp_data;
    wire [3:0] cmd_be;
    reg lock = 0, hold_ram = 0, inject_error = 0;
    wire ram_req, ram_write, ram_ack;
    wire [24:0] ram_addr;
    wire [31:0] ram_data;
    wire [ 3:0] ram_be;
    reg  [ 7:0] ram                                                                [0:4095];
    reg  [ 7:0] chip                                                               [0:4095];
    reg  [ 3:0] ram_delay = 0;
    wire [11:0] rbase = ram_addr[11:0];
    wire [31:0] ram_rdata = {ram[rbase+3], ram[rbase+2], ram[rbase+1], ram[rbase]};
    assign ram_ack = ram_req && ram_delay == 3 && !hold_ram;
    wire local_valid, local_ready, local_write;
    wire [31:0] local_addr, local_data;
    wire [3:0] local_be;
    reg        local_busy = 0;
    reg  [1:0] local_delay = 0;
    wire       local_done = local_busy && local_delay == 2;
    assign local_ready = !local_busy && !lock;
    wire [11:0] lbase = local_addr[11:0];
    wire [31:0] local_rdata = {chip[lbase+3], chip[lbase+2], chip[lbase+1], chip[lbase]};
    integer fifo_count = 0, commands = 0, writes = 0, byte_fifo_count = 0, i;
    reg [ 7:0] byte_fifo[0:31];
    reg [31:0] fifo     [0:31];

    ngage_dma_channels #(
        .ENGINES(ENGINES)
    ) dut (
        .clk              (clk),
        .reset            (reset),
        .req              (req),
        .commit           (commit),
        .we               (we),
        .addr             (addr),
        .din              (din),
        .sel              (sel),
        .claim            (claim),
        .bad              (bad),
        .dout             (dout),
        .irq_pending      (irq),
        .error_pending    (errors),
        .active_channels  (active),
        .source_ready     (src_ready),
        .destination_ready(dst_ready),
        .cmd_valid        (cmd_valid),
        .cmd_ready        (cmd_ready),
        .cmd_write        (cmd_write),
        .cmd_addr         (cmd_addr),
        .cmd_data         (cmd_data),
        .cmd_be           (cmd_be),
        .rsp_valid        (rsp_valid),
        .rsp_error        (rsp_error),
        .rsp_data         (rsp_data)
    );
    ngage_dma_route route (
        .clk        (clk),
        .reset      (reset),
        .cpu_lock   (lock),
        .cmd_valid  (cmd_valid),
        .cmd_ready  (cmd_ready),
        .cmd_write  (cmd_write),
        .cmd_addr   (cmd_addr),
        .cmd_data   (cmd_data),
        .cmd_be     (cmd_be),
        .rsp_valid  (rsp_valid),
        .rsp_error  (rsp_error),
        .rsp_data   (rsp_data),
        .ram_req    (ram_req),
        .ram_write  (ram_write),
        .ram_addr   (ram_addr),
        .ram_data   (ram_data),
        .ram_be     (ram_be),
        .ram_ack    (ram_ack),
        .ram_rdata  (ram_rdata),
        .local_valid(local_valid),
        .local_ready(local_ready),
        .local_write(local_write),
        .local_addr (local_addr),
        .local_data (local_data),
        .local_be   (local_be),
        .local_done (local_done),
        .local_error(inject_error),
        .local_rdata(local_rdata)
    );
    always @(posedge clk) begin
        if (reset) begin
            ram_delay   <= 0;
            local_busy  <= 0;
            local_delay <= 0;
        end else begin
            if (!ram_req || ram_ack) ram_delay <= 0;
            else if (ram_delay < 3) ram_delay <= ram_delay + 1;
            if (cmd_valid && cmd_ready) commands <= commands + 1;
            if (ram_ack && ram_write) begin
                writes <= writes + 1;
                for (i = 0; i < 4; i = i + 1) if (ram_be[i]) ram[rbase+i] <= ram_data[i*8+:8];
            end
            if (local_valid && local_ready) begin
                local_busy  <= 1;
                local_delay <= 0;
            end else if (local_done) begin
                local_busy <= 0;
                if (local_write && !inject_error) begin
                    if (local_addr == 32'h0c004080) begin
                        if (local_be !== 1) $fatal(1, "byte FIFO width");
                        byte_fifo[byte_fifo_count] <= local_data[7:0];
                        byte_fifo_count            <= byte_fifo_count + 1;
                    end else if (local_addr == 32'h0c121208) begin
                        fifo[fifo_count] <= local_data;
                        fifo_count       <= fifo_count + 1;
                    end else begin
                        for (i = 0; i < 4; i = i + 1)
                        if (local_be[i]) chip[lbase+i] <= local_data[i*8+:8];
                    end
                end
            end else if (local_busy) local_delay <= local_delay + 1;
        end
    end

    // A stalled command must retain its selected engine and complete packet.
    reg        stalled = 0;
    reg [68:0] stalled_packet;
    always @(posedge clk) begin
        if (!reset && stalled && cmd_valid &&
            {cmd_write, cmd_addr, cmd_data, cmd_be} !== stalled_packet)
            $fatal(1, "DMA command changed under backpressure");
        stalled        <= !reset && cmd_valid && !cmd_ready;
        stalled_packet <= {cmd_write, cmd_addr, cmd_data, cmd_be};
    end

    task put;
        input integer channel;
        input [5:0] off;
        input [31:0] value;
        begin
            @(negedge clk);
            addr   = 32'h0c120300 + channel * 64 + off;
            din    = value;
            req    = 1;
            commit = 1;
            we     = 1;
            #1;
            if (!claim || bad) $fatal(1, "register rejected ch=%0d off=%h", channel, off);
            @(negedge clk);
            req    = 0;
            commit = 0;
            we     = 0;
        end
    endtask
    task get;
        input integer channel;
        input [5:0] off;
        input [31:0] value;
        begin
            @(negedge clk);
            addr = 32'h0c120300 + channel * 64 + off;
            req  = 1;
            #1;
            if (!claim || bad || dout !== value)
                $fatal(1, "register ch=%0d off=%h got=%h expected=%h", channel, off, dout, value);
            @(negedge clk);
            req = 0;
        end
    endtask
    task setup;
        input integer channel;
        input [31:0] source, destination, units_minus_one;
        input [31:0] sw, dw, si, di;
        begin
            put(channel, 6'h04, 1);
            put(channel, 6'h14, source);
            put(channel, 6'h18, si);
            put(channel, 6'h1c, sw);
            put(channel, 6'h20, destination);
            put(channel, 6'h24, di);
            put(channel, 6'h28, dw);
            put(channel, 6'h2c, units_minus_one);
        end
    endtask
    task idle;
        begin
            wait (active == 0);
            repeat (3) @(negedge clk);
        end
    endtask
    integer ch, j, old_commands, old_writes;
    initial begin
        for (j = 0; j < 4096; j = j + 1) begin
            ram[j]  = (j * 37 + (j >> 3) + 5) & 255;
            chip[j] = 8'ha5;
        end
        repeat (4) @(negedge clk);
        reset = 0;

        // Fill the engine pool and queue every remaining channel behind it.
        hold_ram = 1;
        for (ch = 0; ch < 8; ch = ch + 1) begin
            setup(ch, 32'h0a000000 + ch * 32, 32'h0a000400 + ch * 32, 6, 16, 32, 4, 4);
            put(ch, 6'h08, 1);
        end
        if (active !== 8'hff || irq != 0) $fatal(1, "queued channels lost");
        // Queued descriptors cannot observe later programming-latch writes.
        put(7, 6'h14, 32'h0b000000);
        hold_ram = 0;
        idle;
        if (irq !== 8'hff || errors != 0) $fatal(1, "multi-channel completion ownership");
        for (ch = 0; ch < 8; ch = ch + 1) begin
            for (j = 0; j < 14; j = j + 1)
            if (ram[1024+ch*32+j] !== ram[ch*32+j]) $fatal(1, "channel %0d byte %0d", ch, j);
            get(ch, 6'h08, 0);
        end
        put(3, 6'h04, 0);
        if (irq !== 8'hf7) $fatal(1, "ACK cleared wrong channel");
        for (ch = 0; ch < 8; ch = ch + 1) put(ch, 6'h08, 0);
        if (irq != 0) $fatal(1, "stop ACK");

        // Original memory control counts halfwords even with 32-bit widths.
        // Ten bytes require partial source reads and destination writes.
        setup(6, 32'h0a000200, 32'h0a000800, 4, 32, 32, 4, 4);
        put(6, 6'h08, 1);
        idle;
        if (irq !== 64 || errors != 0) $fatal(1, "memory byte-budget completion");
        for (j = 0; j < 10; j = j + 1)
        if (ram[2048+j] !== ram[512+j]) $fatal(1, "memory halfword count byte %0d", j);
        if (ram[2058] !== ((2058 * 37 + (2058 >> 3) + 5) & 255)) $fatal(1, "memory count overrun");
        put(6, 6'h04, 0);

        // Paced count belongs to the fixed peripheral width. A byte FIFO must
        // receive ten bytes from a 32-bit memory source, not forty bytes.
        setup(6, 32'h0a000200, 32'h0c004080, 9, 32, 8, 4, 0);
        put(6, 6'h08, 2);
        idle;
        if (irq !== 64 || errors != 0 || byte_fifo_count != 10)
            $fatal(1, "peripheral byte count completion/count");
        for (j = 0; j < 10; j = j + 1)
        if (byte_fifo[j] !== ram[512+j]) $fatal(1, "peripheral count byte %0d", j);
        put(6, 6'h04, 0);
        chip[144] = 8'h6d;
        setup(6, 32'h0c004090, 32'h0a000840, 9, 8, 32, 0, 4);
        put(6, 6'h08, 2);
        idle;
        if (irq !== 64 || errors != 0) $fatal(1, "receive byte count completion");
        for (j = 0; j < 10; j = j + 1)
        if (ram[2112+j] !== 8'h6d) $fatal(1, "receive count byte %0d", j);
        if (ram[2122] !== ((2122 * 37 + (2122 >> 3) + 5) & 255)) $fatal(1, "receive count overrun");
        put(6, 6'h04, 0);

        // A paced engine waits before bus ownership; another engine progresses.
        dst_ready[0] = 0;
        setup(0, 32'h0a000100, 32'h10121208, 2, 32, 32, 4, 0);
        put(0, 6'h08, 2);
        setup(1, 32'h0a000120, 32'h0c004020, 1, 8, 16, 4, 2);
        put(1, 6'h08, 1);
        if (ENGINES > 1) begin
            wait (irq[1]);
            if (!active[0] || fifo_count != 0) $fatal(1, "pacing blocked peer or leaked word");
        end
        dst_ready[0] = 1;
        idle;
        if (irq !== 3 || fifo_count != 3) $fatal(1, "paced transfer completion");
        for (j = 0; j < 3; j = j + 1)
        if (fifo[j] !== {ram[259+j*4], ram[258+j*4], ram[257+j*4], ram[256+j*4]})
            $fatal(1, "paced FIFO word %0d", j);
        for (j = 0; j < 4; j = j + 1)
        if (chip[32+j] !== ram[288+j]) $fatal(1, "shared RAM byte %0d", j);
        put(0, 6'h04, 0);
        put(1, 6'h04, 0);

        // Stop owns the accepted read until its delayed response, with no write.
        hold_ram = 1;
        setup(2, 32'h0a000140, 32'h0a000600, 7, 32, 32, 4, 4);
        put(2, 6'h08, 1);
        wait (ram_req && route.state == 1);
        put(2, 6'h08, 0);
        get(2, 6'h08, 1);
        old_writes = writes;
        hold_ram   = 0;
        idle;
        if (irq != 0 || errors != 0 || writes != old_writes)
            $fatal(1, "stopped descriptor wrote/completed");
        get(2, 6'h08, 0);

        // Restart drains old work, then executes only the captured replacement.
        hold_ram = 1;
        put(2, 6'h08, 1);
        wait (ram_req && route.state == 1);
        put(2, 6'h14, 32'h0a000180);
        put(2, 6'h20, 32'h0a000640);
        put(2, 6'h2c, 1);
        put(2, 6'h08, 1);
        hold_ram = 0;
        idle;
        if (irq !== 4 || writes != old_writes + 1) $fatal(1, "restart completion/tail");
        for (j = 0; j < 4; j = j + 1)
        if (ram[1600+j] !== ram[384+j]) $fatal(1, "restart used stale descriptor");
        put(2, 6'h04, 0);

        // Router rejection and target errors stop without claiming success.
        setup(4, 32'h0b000000, 32'h0a000680, 0, 32, 32, 4, 4);
        put(4, 6'h08, 1);
        idle;
        if (errors !== 16 || irq != 0) $fatal(1, "route error reported success");
        put(4, 6'h04, 0);
        inject_error = 1;
        setup(5, 32'h0a000100, 32'h0c004040, 0, 32, 32, 4, 4);
        put(5, 6'h08, 1);
        idle;
        if (errors !== 32 || irq != 0 || chip[64] !== 8'ha5) $fatal(1, "target error");
        inject_error = 0;
        put(5, 6'h04, 0);

        // Invalid descriptor emits no bus access and preserves channel identity.
        setup(6, 32'h0a000101, 32'h0a000680, 0, 16, 32, 4, 4);
        old_commands = commands;
        put(6, 6'h08, 1);
        idle;
        if (errors !== 64 || irq != 0 || commands != old_commands) $fatal(1, "invalid descriptor");
        put(6, 6'h04, 0);

        // Unknown paced count rules must not silently use the source width.
        setup(6, 32'h0a000100, 32'h0c004080, 9, 32, 8, 0, 0);
        old_commands = commands;
        put(6, 6'h08, 2);
        idle;
        if (errors !== 64 || irq != 0 || commands != old_commands)
            $fatal(1, "unknown fixed/fixed paced count admitted");
        put(6, 6'h04, 0);
        setup(6, 32'h0a000100, 32'h0a000680, 9, 32, 32, 4, 4);
        put(6, 6'h08, 2);
        idle;
        if (errors !== 64 || irq != 0 || commands != old_commands)
            $fatal(1, "unknown increment/increment paced count admitted");
        put(6, 6'h04, 0);

        // Lock stalls a captured offer; queued peers cannot change that packet.
        lock = 1;
        setup(0, 32'h0a000100, 32'h0a000700, 0, 32, 32, 4, 4);
        put(0, 6'h08, 1);
        wait (cmd_valid);
        old_commands = commands;
        setup(1, 32'h0a000120, 32'h0a000704, 0, 32, 32, 4, 4);
        put(1, 6'h08, 1);
        repeat (8) @(negedge clk);
        if (commands != old_commands) $fatal(1, "lock accepted command");
        lock = 0;
        idle;
        if (irq !== 3 || errors != 0) $fatal(1, "unlock completion");

        // Shared reset cancels queue, owner and route response together.
        hold_ram = 1;
        put(3, 6'h08, 1);
        wait (ram_req && route.state == 1);
        @(negedge clk);
        reset = 1;
        repeat (3) @(negedge clk);
        reset    = 0;
        hold_ram = 0;
        repeat (8) @(negedge clk);
        if (active != 0 || irq != 0 || errors != 0 || cmd_valid || rsp_valid)
            $fatal(1, "reset leaked old ownership");
        // Claim only implemented aligned full-word registers.
        addr = 32'h0c120314;
        req  = 1;
        sel  = 3;
        #1;
        if (!claim || !bad) $fatal(1, "partial programming access accepted");
        addr = 32'h0c120300;
        sel  = 15;
        #1;
        if (claim) $fatal(1, "unknown register claimed");
        req = 0;
        $display(
            "PASS DMA channels engines=%0d queue, snapshots, IRQ ACK, paced peers, stop/restart, route/errors, lock/reset",
            ENGINES);
        $finish;
    end
    initial begin
        #300000;
        $fatal(1, "DMA channel test timeout active=%h irq=%h errors=%h", active, irq, errors);
    end
endmodule
