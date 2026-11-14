`timescale 1ns / 1ps
module tb;
    reg clk = 0, reset = 1, req = 0, commit = 0, we = 0, tr = 0, rv = 0;
    reg [31:0] addr = 0, din = 0;
    reg [3:0] sel = 15;
    reg [7:0] rd = 0;
    wire claim, bad, ready, irq, tv, rr;
    wire [31:0] dout;
    wire [ 7:0] td;
    integer cycles = 0, i, received = 0;
    reg [ 7:0] sent   [0:63];
    reg [31:0] result;
    ngage_upp_euart dut (
        clk,
        reset,
        req,
        commit,
        we,
        addr,
        din,
        sel,
        claim,
        bad,
        ready,
        dout,
        irq,
        tv,
        tr,
        td,
        rv,
        rr,
        rd,
    );
    always #5 clk = ~clk;
    always @(posedge clk) begin
        cycles <= cycles + 1;
        if (tv && tr) begin
            sent[received] <= td;
            received       <= received + 1;
        end
        if (cycles > 10000) $fatal(1, "UART test timeout");
    end
    task bus;
        input w;
        input [31:0] a, d;
        input [3:0] s;
        input error;
        begin
            @(negedge clk);
            req    = 1;
            we     = w;
            addr   = a;
            din    = d;
            sel    = s;
            commit = 0;
            #1;
            while (!ready) begin
                @(negedge clk);
                #1;
            end
            if (!claim || bad !== error) $fatal(1, "UART bus %h bad%b expected%b", a, bad, error);
            result = dout;
            // Held uncommitted accesses must not change queue ownership.
            repeat (3) @(negedge clk);
            if (!ready || dout !== result) $fatal(1, "held read changed");
            commit = 1;
            @(negedge clk);
            req    = 0;
            commit = 0;
        end
    endtask
    task mask_write;
        input [31:0] value;
        begin
            @(negedge clk);
            req    = 1;
            commit = 1;
            we     = 1;
            addr   = 'h0c15000c;
            din    = value;
            sel    = 15;
            @(negedge clk);
            req    = 0;
            commit = 0;
        end
    endtask
    task push;
        input [7:0] b;
        begin
            @(negedge clk);
            rv = 1;
            rd = b;
            #1;
            while (!rr) begin
                @(negedge clk);
                #1;
            end
            @(negedge clk);
            rv = 0;
        end
    endtask
    initial begin
        repeat (3) @(negedge clk);
        reset = 0;
        // Original TX driver writes count-minus-one, then bytes high in16bits.
        bus(1, 'h0c150558, 'h00020000, 12, 0);
        bus(1, 'h0c150554, 'h7e00, 3, 0);
        bus(1, 'h0c150554, 'h8200, 3, 0);
        bus(1, 'h0c150554, 'h2b00, 3, 0);
        repeat (5) @(negedge clk);
        if (!tv || td !== 'h7e || received != 0) $fatal(1, "TX stall/ownership");
        tr = 1;
        wait (received == 3);
        @(negedge clk);
        tr = 0;
        if (sent[0] !== 'h7e || sent[1] !== 'h82 || sent[2] !== 'h2b) $fatal(1, "TX byte order");
        bus(0, 'h0c1500b8, 0, 12, 0);
        if (result !== 'h00100000 || irq) $fatal(1, "TX completion mask");
        mask_write('h00100000);
        if (!irq) $fatal(1, "TX completion enable");
        bus(1, 'h0c1500b8, 'h00100000, 12, 0);
        if (irq) $fatal(1, "TX completion ACK");
        mask_write('h00080000);
        for (i = 0; i < 15; i = i + 1) push(8'h40 + i);
        if (rr || !irq) $fatal(1, "RX full/mask");
        bus(0, 'h0c150560, 0, 12, 0);
        if (result !== 'h00f00000) $fatal(1, "RX producer index %h", result);
        bus(1, 'h0c1500b8, 'h00080000, 12, 0);
        if (!irq) $fatal(1, "RX pending data lost on ACK");
        for (i = 0; i < 15; i = i + 1) begin
            bus(0, 'h0c150554, 0, 12, 0);
            if (result !== ((32'h40 + i) << 24)) $fatal(1, "RX data/order %h at%0d", result, i);
        end
        if (irq || !rr) $fatal(1, "RX drain");
        bus(0, 'h0c150554, 0, 12, 1);
        // Wrap both sides of RX; stale BRAM bytes never acquire ownership.
        push('ha5);
        push('h5a);
        bus(0, 'h0c150554, 0, 12, 0);
        if (result !== 'ha5000000) $fatal(1, "RX wrap first");
        bus(0, 'h0c150554, 0, 12, 0);
        if (result !== 'h5a000000) $fatal(1, "RX wrap second");
        // Two16-byte batches naturally saturate and wrap TX ownership.
        for (i = 0; i < 2; i = i + 1) begin : batches
            integer j, base;
            base = received;
            bus(1, 'h0c150558, 'h000f0000, 12, 0);
            for (j = 0; j < 16; j = j + 1) bus(1, 'h0c150554, (32'h80 + i * 16 + j) << 8, 3, 0);
            @(negedge clk);
            req    = 1;
            we     = 1;
            addr   = 'h0c150554;
            sel    = 3;
            commit = 0;
            #1;
            if (ready) $fatal(1, "full TX did not backpressure");
            @(negedge clk);
            req = 0;
            tr  = 1;
            wait (received == base + 16);
            @(negedge clk);
            tr = 0;
            for (j = 0; j < 16; j = j + 1)
            if (sent[base+j] !== 8'h80 + i * 16 + j) $fatal(1, "TX wrap/order");
            bus(1, 'h0c1500b8, 'h00100000, 12, 0);
        end
        push('hf0);
        @(negedge clk);
        rv = 1;
        rd = 'hf1;
        bus(1, 'h0c150560, 7, 3, 0);
        rv = 0;
        if (dut.rx_count != 0) $fatal(1, "RX flush lost priority");
        bus(1, 'h0c150558, 'h00000000, 12, 0);
        bus(1, 'h0c150554, 'h9900, 3, 0);
        reset = 1;
        @(negedge clk);
        reset = 0;
        repeat (4) @(negedge clk);
        if (tv || irq || dut.tx_count != 0 || dut.rx_count != 0) $fatal(1, "reset ownership");
        $display(
            "PASS UPP EUART native byte lanes, batches, BRAM latency, stalls, FIFO saturation/wrap, IRQ masks/ACK, flush/reset");
        $finish;
    end
endmodule
