`timescale 1ns / 1ps
// ngage_sdram_fast against the SDRAM chip model: random scalar reads and
// writes with byte lanes, 32-byte line reads, and phone_reset during reads,
// checked against a shadow of the memory. The clock is the forwarded,
// inverted one of the production wrapper.
module tb;
    parameter integer SYS_CLK_HZ = 78000000;
    parameter integer OPERATIONS = 20000;
    localparam integer WORDS = 16384;  // shadowed words; spread over rows and banks below

    reg clk = 0, rst = 1, phone_reset = 0;
    always #(500000000.0 / SYS_CLK_HZ) clk = ~clk;

    reg         req = 0, we = 0;
    reg  [24:0] addr = 0;
    reg  [31:0] din = 0;
    reg  [ 3:0] be = 0;
    wire        ack;
    wire [31:0] dout;
    reg         line_req = 0;
    reg  [24:0] line_addr = 0;
    wire line_ready, line_valid, line_last, scrub_done, owner_ready, init;
    wire [15:0] line_data;
    wire cke, ncs, nras, ncas, nwe, dqml, dqmh, memclk;
    wire [ 1:0] bank;
    wire [12:0] sdram_a;
    wire [15:0] dq_o, dq_oe;
    tri  [15:0] dq;
    reg  [15:0] dq_seen = 0;
    // The chip's data as the controller's input registers see it: the board's
    // clock-out and input delays put the capture edge inside the data window.
    always @(negedge clk) dq_seen <= memory.Dq_reg;

    ngage_sdram_clock forward_clock (
        .clk      (clk),
        .sdram_clk(memclk)
    );
    ngage_sdram_fast #(
        .CLK_HZ   (SYS_CLK_HZ),
        .RAM_BYTES(64)
    ) dut (
        .clk        (clk),
        .rst        (rst),
        .phone_reset(phone_reset),
        .init       (init),
        .req        (req),
        .we         (we),
        .addr       (addr),
        .din        (din),
        .be         (be),
        .ack        (ack),
        .dout       (dout),
        .line_req   (line_req),
        .line_addr  (line_addr),
        .line_ready (line_ready),
        .line_valid (line_valid),
        .line_data  (line_data),
        .line_last  (line_last),
        .scrub_done (scrub_done),
        .owner_ready(owner_ready),
        .sdram_cke  (cke),
        .sdram_cs_n (ncs),
        .sdram_ras_n(nras),
        .sdram_cas_n(ncas),
        .sdram_we_n (nwe),
        .sdram_ba   (bank),
        .sdram_a    (sdram_a),
        .sdram_dqml (dqml),
        .sdram_dqmh (dqmh),
        .sdram_dq_o (dq_o),
        .sdram_dq_oe(dq_oe),
        .sdram_dq_i (dq_seen)
    );
    mt48lc16m16a2 memory (
        .Dq_write   (dq_o),
        .Clk        (memclk),
        .Cke        (cke),
        .Dq         (dq),
        .Addr       (sdram_a),
        .Ba         (bank),
        .Cs_n       (ncs),
        .Ras_n      (nras),
        .Cas_n      (ncas),
        .We_n       (nwe),
        .Dqm        ({dqmh, dqml}),
        .downloading(1'b0),
        .VS         (1'b0),
        .frame_cnt  (32'b0)
    );

    reg [31:0] shadow[0:WORDS-1];
    reg [31:0] seed = 32'h1badf00d;
    function [31:0] next_random;
        input [31:0] value;
        begin
            next_random = value ^ (value << 13);
            next_random = next_random ^ (next_random >> 17);
            next_random = next_random ^ (next_random << 5);
        end
    endfunction
    // Shadow word k lives at a byte address that walks rows, the 4 KB bank
    // interleave and both halves of the phone's 16 MB.
    function [24:0] place;
        input [13:0] k;
        begin
            place = {k[13], 3'b000, k[12:8], 6'b000000, k[7:0], 2'b00} + (k[12] ? 25'h0012340 : 25'h0);
        end
    endfunction

    integer errors = 0, scalar_reads = 0, scalar_writes = 0, line_reads = 0, discarded = 0;
    integer waited;
    integer n, beat;
    reg [13:0] k;
    reg [31:0] expected, got;
    reg [15:0] low;

    task scalar_write;
        input [13:0] index;
        input [31:0] data;
        input [ 3:0] lanes;
        integer lane;
        begin
            @(posedge clk);
            req <= 1; we <= 1; addr <= place(index); din <= data; be <= lanes;
            @(posedge clk);
            while (!ack) @(posedge clk);
            req <= 0;
            for (lane = 0; lane < 4; lane = lane + 1)
                if (lanes[lane]) shadow[index][lane*8+:8] = data[lane*8+:8];
            scalar_writes = scalar_writes + 1;
            @(posedge clk);
        end
    endtask

    task scalar_read;
        input [13:0] index;
        begin
            @(posedge clk);
            req <= 1; we <= 0; addr <= place(index) | 25'd3; be <= 4'hf;
            @(posedge clk);
            while (!ack) @(posedge clk);
            req <= 0;
            if (dout !== shadow[index]) begin
                errors = errors + 1;
                if (errors < 10) $display("FAIL read %h: %h expected %h", place(index), dout, shadow[index]);
            end
            scalar_reads = scalar_reads + 1;
            @(posedge clk);
        end
    endtask

    // An aligned 32-byte line holds eight consecutive shadow words.
    task line_read;
        input [13:0] index;
        reg   [13:0] first;
        begin
            first = {index[13:3], 3'b000};
            @(posedge clk);
            line_req <= 1; line_addr <= place(first) | 25'h1f;
            @(posedge clk);
            while (!line_ready) @(posedge clk);
            line_req <= 0;
            beat = 0;
            while (beat < 16) begin
                @(posedge clk);
                if (line_valid) begin
                    if (beat[0]) begin
                        got = {line_data, low};
                        if (got !== shadow[first+(beat>>1)]) begin
                            errors = errors + 1;
                            if (errors < 10)
                                $display("FAIL line %h word %0d: %h expected %h", place(first), beat >> 1, got, shadow[first+(beat>>1)]);
                        end
                    end else low = line_data;
                    if (line_last !== (beat == 15)) begin
                        errors = errors + 1;
                        if (errors < 10) $display("FAIL line_last at beat %0d", beat);
                    end
                    beat = beat + 1;
                end
            end
            line_reads = line_reads + 1;
        end
    endtask

    // A read whose owner is reset: no answer may come, the service drains.
    task discarded_read;
        input [13:0] index;
        begin
            @(posedge clk);
            req <= 1; we <= 0; addr <= place(index); be <= 4'hf;
            @(posedge clk);
            @(posedge clk);
            phone_reset <= 1;
            req <= 0;
            waited = 0;
            while (waited < 40) begin
                @(posedge clk);
                if (ack || line_valid) begin
                    errors = errors + 1;
                    if (errors < 10) $display("FAIL answer after phone_reset");
                end
                waited = waited + 1;
            end
            phone_reset <= 0;
            @(posedge clk);
            while (!owner_ready) @(posedge clk);
            discarded = discarded + 1;
        end
    endtask

    always @(posedge clk)
        if (ack && !req) begin
            errors = errors + 1;
            if (errors < 10) $display("FAIL ack without a request");
        end

    initial begin
        repeat (4) @(posedge clk);
        rst <= 0;
        while (!scrub_done) @(posedge clk);
        for (n = 0; n < WORDS; n = n + 1) begin
            seed = next_random(seed);
            shadow[n] = 0;
            scalar_write(n[13:0], seed, 4'hf);
        end
        for (n = 0; n < OPERATIONS; n = n + 1) begin
            seed = next_random(seed);
            k    = seed[13:0];
            case (seed[18:16])
                0, 1:    scalar_write(k, next_random(seed ^ 32'h5555aaaa), seed[23:20] == 0 ? 4'hf : seed[23:20]);
                2:       scalar_write(k, next_random(seed ^ 32'h5555aaaa), 4'hf);
                3, 4:    scalar_read(k);
                5, 6:    line_read(k);
                default: if (seed[27:24] == 0) discarded_read(k); else scalar_read(k);
            endcase
            if (seed[31:29] == 0) repeat (seed[28:25]) @(posedge clk);
        end
        for (n = 0; n < WORDS; n = n + 8) line_read(n[13:0]);
        if (errors != 0) $fatal(1, "FAIL %0d errors", errors);
        $display("PASS ngage_sdram_fast %0d Hz: %0d scalar writes, %0d scalar reads, %0d line reads, %0d discarded reads",
                 SYS_CLK_HZ, scalar_writes, scalar_reads, line_reads, discarded);
        $finish;
    end
    initial begin
        #2000000000;
        $fatal(1, "timeout");
    end
endmodule
