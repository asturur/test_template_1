`timescale 1ns/1ps
module tb;
    reg clk = 0;
    always #5 clk = !clk;
    reg reset = 1;
    reg transfer_valid = 0;
    wire transfer_ready;
    reg [31:0] source_addr = 0;
    reg [32:0] transfer_words = 0;
    reg stop = 0;
    wire busy, done, error, aborted;
    wire mem_req, mem_accept, mem_ack;
    wire [24:0] mem_addr;
    wire [31:0] mem_data;
    wire pixel_valid;
    wire [31:0] pixel_data;
    reg pixel_ready = 1, pixel_error = 0;
    reg allow_mem = 1, stray_ack = 0;
    integer latency = 1;
    reg pending = 0;
    reg [24:0] held_addr;
    integer delay_left;
    integer cycles = 0, reads = 0, responses = 0, pixels = 0, rejects = 0;
    integer cases = 0, target_words = 0, start_cycle, elapsed;
    reg [24:0] expected_base = 0;
    reg held_pixel = 0;
    reg [31:0] last_pixel;
    reg stall_pattern = 0;
    wire bus_req, bus_ack;
    wire [24:0] bus_addr;
    wire [31:0] bus_data;
    wire bus_accept = bus_req && !pending && allow_mem;
    assign bus_ack = stray_ack || (pending && delay_left == 0) ||
                     (latency == 0 && bus_accept);
    function [31:0] word_at;
        input [24:0] addr;
        begin word_at = (32'h9d4b03a7 ^ {7'b0,addr}) + ((addr >> 2) * 32'h1234567); end
    endfunction
    assign bus_data = word_at(pending ? held_addr : bus_addr);
`ifdef NATIVE_ARBITER
    wire unused_cpu_ack, unused_cpu_accept;
    wire [31:0] unused_cpu_data, unused_write_data;
    wire unused_we;
    wire [3:0] unused_be;
    ngage_sdram_arbiter ram_arbiter (
        .clk(clk), .reset(reset), .cpu_lock(!allow_mem), .cpu_req(1'b0),
        .cpu_we(1'b0), .cpu_addr(25'b0), .cpu_data(32'b0), .cpu_be(4'b0),
        .cpu_ack(unused_cpu_ack), .cpu_rdata(unused_cpu_data),
        .cpu_accept(unused_cpu_accept), .dma_req(mem_req), .dma_we(1'b0),
        .dma_addr(mem_addr), .dma_data(32'b0), .dma_be(4'hf),
        .dma_ack(mem_ack), .dma_rdata(mem_data), .dma_accept(mem_accept),
        .mem_req(bus_req), .mem_we(unused_we), .mem_addr(bus_addr),
        .mem_data(unused_write_data), .mem_be(unused_be),
        .mem_ack(bus_ack), .mem_rdata(bus_data)
    );
`else
    assign bus_req = mem_req;
    assign bus_addr = mem_addr;
    assign mem_accept = bus_accept;
    assign mem_ack = bus_ack;
    assign mem_data = bus_data;
`endif
    ngage_lcd_stream dut (
        .clk(clk), .reset(reset), .transfer_valid(transfer_valid),
        .transfer_ready(transfer_ready), .source_addr(source_addr),
        .transfer_words(transfer_words), .stop(stop), .busy(busy),
        .done(done), .error(error), .aborted(aborted), .mem_req(mem_req),
        .mem_addr(mem_addr), .mem_accept(mem_accept), .mem_ack(mem_ack),
        .mem_data(mem_data), .pixel_valid(pixel_valid), .pixel_data(pixel_data),
        .pixel_ready(pixel_ready), .pixel_error(pixel_error)
    );
    task fail;
        input [511:0] why;
        begin $display("FAIL cycle=%0d case=%0d pixels=%0d reads=%0d %0s", cycles,cases,pixels,reads,why); $finish(1); end
    endtask
    always @(posedge clk) begin
        cycles = cycles + 1;
        if (reset) begin
            pending <= 0;
            held_pixel <= 0;
        end else begin
            if ((done + error + aborted) > 1) fail("nonexclusive terminals");
            if (pending) begin
                if (!bus_req || bus_addr !== held_addr) fail("RAM ownership not held through ACK");
                if (bus_ack) pending <= 0;
                else delay_left <= delay_left - 1;
            end
            if (bus_accept) begin
                if (!bus_ack) begin
                    pending <= 1;
                    held_addr <= bus_addr;
                    delay_left <= latency - 1;
                end
            end
            if (mem_req && mem_accept) begin
                if (mem_addr !== expected_base + reads*4) fail("read address/order/captured descriptor");
                reads = reads + 1;
                if (reads > target_words) fail("read past literal extent");
            end
            if (mem_ack && (dut.owned || (mem_req && mem_accept))) responses = responses + 1;
            if (held_pixel && !stop && (!pixel_valid || pixel_data !== last_pixel)) fail("unstable stalled pixel");
            held_pixel <= pixel_valid && !pixel_ready;
            last_pixel <= pixel_data;
            if (pixel_valid && pixel_ready) begin
                if (stop) fail("pixel accepted during stop");
                if (pixel_data !== word_at(expected_base + pixels*4)) fail("independent pixel oracle mismatch");
                if (pixel_error) rejects = rejects + 1;
                else pixels = pixels + 1;
                if (pixels > target_words) fail("extra pixel");
            end
        end
    end
    always @(negedge clk) begin
        if (stall_pattern) pixel_ready = (cycles % 17 > 5) && (cycles % 29 != 0);
    end
    task tick;
        begin @(posedge clk); #1; end
    endtask
    task launch;
        input [31:0] base;
        input [32:0] words;
        begin
            @(negedge clk);
            cases = cases + 1;
            reads = 0; responses = 0; pixels = 0; rejects = 0;
            expected_base = base[24:0]; target_words = words;
            source_addr = base; transfer_words = words;
            transfer_valid = 1;
            if (!transfer_ready) fail("not ready before launch");
            tick;
            start_cycle = cycles;
            @(negedge clk); transfer_valid = 0;
        end
    endtask
    task terminal;
        input integer kind;
        integer deadline;
        begin
            deadline = cycles + 500000;
            while (!(done || error || aborted) && cycles < deadline) tick;
            if (cycles >= deadline) fail("terminal timeout");
            if (busy || (kind == 0 && !done) || (kind == 1 && !error) || (kind == 2 && !aborted)) fail("wrong terminal");
            if (kind == 0 && (pixels != target_words || reads != target_words || responses != target_words)) fail("incomplete success");
            elapsed = cycles - start_cycle;
            tick;
            if (done || error || aborted) fail("terminal did not pulse");
        end
    endtask
    task invalid;
        input [31:0] base;
        input [32:0] words;
        begin
            launch(base,words); terminal(1);
            if (reads != 0 || pixels != 0) fail("invalid descriptor issued traffic");
        end
    endtask
    task reset_all;
        begin
            @(negedge clk); reset = 1; stop = 0; pixel_error = 0;
            transfer_valid = 0; stall_pattern = 0; pixel_ready = 1;
            repeat (2) tick;
            @(negedge clk); reset = 0;
            tick;
        end
    endtask
    integer i;
    initial begin
        reset_all;
        // Full display extent, synthetic latency measurements, immutable inputs.
        latency = 1;
        launch(32'h0a003000,18304);
        source_addr = 32'hdeadbeef; transfer_words = 33'h100000001;
        terminal(0);
        $display("METRIC latency=1 words=18304 elapsed=%0d clocks_per_word_x1000=%0d",elapsed,elapsed*1000/18304);
        latency = 3;
        launch(32'h0a000000,18304); terminal(0);
        $display("METRIC latency=3 words=18304 elapsed=%0d clocks_per_word_x1000=%0d",elapsed,elapsed*1000/18304);
        stall_pattern = 1;
        launch(32'h0a001004,18304); terminal(0);
        stall_pattern = 0; pixel_ready = 1;
        // Simultaneous RAM acceptance/response is legal; zero wait response.
        latency = 0;
        launch(32'h0afffffc,1); terminal(0);
        launch(32'h0afffff0,4); terminal(0);
        invalid(32'h0a000000,0);
        invalid(32'h09fffffc,1);
        invalid(32'h0b000000,1);
        invalid(32'h0a000001,1);
        invalid(32'h0afffffc,2);
        invalid(32'h0a000000,33'h100000000);
        invalid(32'h0a000000,33'h1ffffffff);
        // Last legal SDRAM span is validated without reading its huge extent.
        allow_mem = 0;
        launch(32'h0a000000,4194304);
        if (!busy || error) fail("valid exact range rejected");
        stop = 1; terminal(2); stop = 0;
        if (reads != 0) fail("withdrawn request accepted");
        allow_mem = 1;
        // Stop with an accepted, delayed RAM request: hold until ACK, discard.
        latency = 8;
        launch(32'h0a000100,20);
        while (!dut.owned) tick;
        @(negedge clk); stop = 1;
        tick;
        if (!busy || aborted) fail("aborted before owned read drained");
        @(negedge clk); stop = 0;
        terminal(2);
        if (pixels != 0 || reads != 1 || responses != 1) fail("cancelled response leaked");
        // Stop on the final owned ACK: drain the RAM beat without publishing it.
        launch(32'h0a000180,1);
        while (!dut.owned) tick;
        while (!mem_ack) begin @(negedge clk); #1; end
        stop = 1;
        terminal(2); stop = 0;
        if (pixels != 0 || reads != 1 || responses != 1) fail("final ACK beat escaped stop");
        // Stall tail, then stop exactly when the final pixel would be accepted.
        latency = 1; pixel_ready = 0;
        launch(32'h0a000200,1);
        while (!pixel_valid) tick;
        repeat (13) tick;
        @(negedge clk); stop = 1; pixel_ready = 1;
        terminal(2); stop = 0;
        if (pixels != 0) fail("stop lost to final pixel");
        // A partial accepted prefix survives stop; no outstanding pixel leaks.
        launch(32'h0a000300,31);
        while (pixels < 7) tick;
        @(negedge clk); stop = 1;
        terminal(2); stop = 0;
        if (pixels != 7) fail("partial stop prefix changed");
        // Sink rejection terminates with error; no rejection counts as enqueue.
        launch(32'h0a000500,17);
        while (pixels < 4) tick;
        @(negedge clk); pixel_error = 1;
        terminal(1); pixel_error = 0;
        if (pixels != 4 || rejects != 1) fail("sink failure prefix wrong");
        // Reset the transport and arbiter together while a read is owned.
        latency = 9;
        launch(32'h0a000700,4);
        while (!dut.owned) tick;
        reset_all;
        latency = 1;
        // An unowned stale ACK cannot create pixels or completion.
        stray_ack = 1; repeat (3) tick;
        stray_ack = 0;
        if (pixel_valid || busy || done || error || aborted) fail("stale ACK resumed old transfer");
        launch(32'h0a000800,23); terminal(0);
        // Hold the first word indefinitely: RAM is released without extra reads.
        pixel_ready = 0;
        launch(32'h0a000900,3);
        while (!pixel_valid) tick;
        repeat (41) tick;
        if (reads != 1 || dut.owned || pending) fail("stall retained RAM or overfetched");
        @(negedge clk); pixel_ready = 1;
        terminal(0);
        // Stray ACK while an unaccepted descriptor is busy cannot advance it.
        allow_mem = 0;
        launch(32'h0a000a00,2);
        stray_ack = 1; repeat (5) tick; stray_ack = 0;
        if (pixels || reads || responses || !busy) fail("unowned ACK advanced descriptor");
        allow_mem = 1; terminal(0);
        // Varied short descriptors stress empty/full skid transitions and tails.
        stall_pattern = 1;
        for (i = 0; i < 100; i = i + 1) begin
            latency = i % 5;
            launch(32'h0a100000 + i*512,1 + (i*37)%101);
            source_addr = ~source_addr;
            transfer_words = 33'h1ffffffff;
            terminal(0);
        end
        stall_pattern = 0;
        $display("PASS LCD stream cases=%0d cycles=%0d", cases, cycles);
        $finish;
    end
endmodule
