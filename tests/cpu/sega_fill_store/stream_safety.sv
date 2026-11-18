// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
module test;
    reg clk = 0, reset = 1;
    reg rd = 0, fast = 1, fault = 0, invalidate = 0;
    reg [31:0] address = 0, generation = 0;
    wire ack, err, invalidate_done, bus, write;
    wire [31:0] data, bus_address;
    integer bus_reads = 0;
    localparam [31:0] A = 32'h80001000, B = 32'h80001020, C = 32'h80001100;
    always #5 clk = !clk;

    wire bus_ack = dut.inflight;
    always @(posedge clk)
        if (!reset && bus_ack) begin
            if (write) $fatal(1, "instruction cache wrote the external bus");
            bus_reads <= bus_reads + 1;
        end

    arm920_cache_adapter #(.READ_ONLY(1)) dut (
        .clk(clk),
        .reset(reset),
        .discard_refill(1'b0),
        .external_permit(1'b1),
        .fast_enable(fast),
        .fast_next_address(32'h70000000),
        .data_probe_valid(1'b0),
        .data_probe_address(32'b0),
        .address(address),
        .physical(address),
        .din(32'b0),
        .far_in(address),
        .rd(rd),
        .wr(1'b0),
        .ben(4'hf),
        .swp_tag(2'd0),
        .alignment_fault(1'b0),
        .alignment_far(address),
        .fault(fault),
        .fsr_in(8'h05),
        .external_fsr(8'h08),
        .tlb_busy(1'b0),
        .translation_wait(1'b0),
        .cache_enable(1'b1),
        .cache_rr(1'b1),
        .cacheable(1'b1),
        .bufferable(1'b0),
        .cache_invalidate(invalidate),
        .cache_clean(1'b0),
        .cache_lock_write(1'b0),
        .cache_lock_base(6'd0),
        .cache_op_single(1'b0),
        .cache_op_by_mva(1'b0),
        .cache_op_address(32'd0),
        .data(data),
        .request_ack(ack),
        .err(err),
        .cache_inv_done(invalidate_done),
        .wb_stb(bus),
        .wb_wen(write),
        .wb_adr(bus_address),
        .wb_ack(bus_ack),
        .wb_err(1'b0),
        .wb_rdata(bus_address ^ 32'h12349876 ^ generation)
    );

    task read_word(input [31:0] va, input reg expect_fast);
        integer waited;
        begin
            @(negedge clk);
            address = va;
            rd = 1;
            #1;
            if (dut.fast_hit != expect_fast)
                $fatal(1, "fast path at %h: got %b expected %b", va, dut.fast_hit, expect_fast);
            waited = 0;
            while (!ack && waited < 500) begin
                @(negedge clk);
                #1;
                waited = waited + 1;
            end
            if (!ack || err || data !== (va ^ 32'h12349876 ^ generation))
                $fatal(1, "incorrect instruction reply at %h", va);
            @(posedge clk);
            @(negedge clk);
            rd = 0;
        end
    endtask

    integer count_before;
    initial begin
        repeat (3) @(negedge clk);
        reset = 0;
        read_word(A, 0);
        read_word(B, 0);
        read_word(A, 0);
        count_before = bus_reads;
        read_word(B, 1);
        read_word(A+4, 1);
        if (bus_reads != count_before) $fatal(1, "resident alternation fetched external memory");

        @(negedge clk);
        address = B;
        fault = 1;
        rd = 1;
        #1;
        if (!ack || !err || dut.fast_hit) $fatal(1, "resident line bypassed translation denial");
        @(negedge clk);
        rd = 0;
        fault = 0;

        fast = 0;
        @(negedge clk);
        if (dut.cache.stream_valid != 0) $fatal(1, "context gate retained a copied line");
        fast = 1;
        read_word(A, 0);
        read_word(B, 0);
        read_word(A, 1);

        read_word(C, 0);
        if (dut.cache.stream_valid != 2'b01)
            $fatal(1, "refill did not revoke the other slot");
        read_word(B, 0);
        read_word(C, 1);

        @(negedge clk);
        invalidate = 1;
        @(negedge clk);
        while (!invalidate_done) @(negedge clk);
        if (dut.cache.stream_valid != 0) $fatal(1, "invalidate retained instruction copies");
        invalidate = 0;
        generation = 32'ha5a5a5a5;
        read_word(B, 0);
        read_word(C, 0);
        $display("PASS resident alternation, permission gate, context clear, refill and invalidate");
        $finish;
    end

    initial begin
        #40000;
        $fatal(1, "stream safety timeout");
    end
endmodule
