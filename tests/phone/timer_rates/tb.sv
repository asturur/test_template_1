`timescale 1ns/1ps
module tb;
    parameter integer SYS_CLK_HZ = 78000000;
    localparam integer DIV = SYS_CLK_HZ / 26000000;
    localparam integer PERIOD = SYS_CLK_HZ / 64;
    reg clk = 0;
    always #5 clk = ~clk;
    reg reset = 1, req = 0, commit = 0, we = 0;
    reg [31:0] addr = 0, din = 0;
    wire claim, bad, pending;
    wire [31:0] data_out;
    wire nos_claim, nos_bad, nos_irq, nos_tick;
    wire [31:0] nos_data;
    integer elapsed = 0, first_irq = 0, second_irq = 0;
    integer nos_ticks = 0;
    integer nos_irqs = 0;
    reg previous_nos = 0;
    reg previous_irq = 0;
    ngage_timers #(.CLOCK_DIV(DIV)) timers (
        .clk(clk), .reset(reset), .req(req), .commit(commit), .we(we),
        .addr(addr), .din(din), .sel(4'hf), .clear_unit1(1'b0),
        .claim(claim), .bad(bad), .dout(data_out), .timer0_pending(pending),
        .unit1_pending(), .unit60_pending(), .timer0_rearm(),
        .periodic_active(), .sysc74_seen(1'b1)
    );
    ngage_nos_io #(.TICK_DIV(PERIOD), .FAST_DIV(SYS_CLK_HZ / 32768)) nos (
        .clk(clk), .reset(reset), .req(req), .commit(commit), .we(we),
        .addr(32'h0c150100), .din(32'h80), .sel(4'hf), .claim(nos_claim),
        .bad(nos_bad), .dout(nos_data), .irq(nos_irq),
        .event_bits(16'b0), .nos_tick(nos_tick)
    );
    task tick;
        begin @(posedge clk); #1; end
    endtask
    task write_timer(input [31:0] address, input [31:0] value);
        begin
            @(negedge clk); req=1; commit=1; we=1; addr=address; din=value;
            #1; if (!claim || bad) $fatal(1,"timer bus programming rejected");
            tick(); @(negedge clk); req=0; commit=0; we=0;
        end
    endtask
    initial begin
        repeat (2) tick();
        @(negedge clk);
        reset = 0;
        // Exact original NEM-4 tick sequence: ctrl2, reload406250,
        // live-count406250, ACK0. No force of internal timer state.
        write_timer(32'h0c120a04,2);
        write_timer(32'h0c120a18,406250);
        @(negedge clk);
        while(timers.divider != DIV-1) @(negedge clk);
        req=1; commit=1; we=1; addr=32'h0c120a10; din=406250;
        tick();
        @(negedge clk); req=0; commit=0; we=0;
        nos.counter=0; nos.divider=0;
        nos.enable_bits = 16'h80;
        nos.compare_valid = 1;
        nos.compare_reg = 1;
        while (elapsed < 2 * PERIOD + DIV) begin
            // Count pre-edge enables, then observe the resulting latched IRQ.
            if (nos_tick) nos_ticks = nos_ticks + 1;
            tick();
            elapsed = elapsed + 1;
            if (req && pending) $fatal(1, "ACK waited for counter enable");
            if (nos_irq && !previous_nos) nos_irqs = nos_irqs + 1;
            previous_nos = nos_irq;
            if (pending && !previous_irq) begin
                if (!first_irq) first_irq = elapsed;
                else if (!second_irq) second_irq = elapsed;
            end
            previous_irq = pending;
            @(negedge clk);
            // ACK a latched IRQ on a non-counter edge. Bus writes must not
            // wait for the 26 MHz clock enable.
            req = pending && timers.divider != DIV - 1;
            commit = req;
            we = req;
            addr = 32'h0c120a08;
            din = 0;
        end
        if (first_irq != PERIOD || second_irq - first_irq != PERIOD)
            $fatal(1, "timer rate: first=%0d second=%0d expected=%0d", first_irq, second_irq, PERIOD);
        if (nos_ticks != 2 || nos.counter != 2)
            $fatal(1, "NOS 64Hz counter did not advance twice");
        if (nos_irqs != 1 || nos_irq) $fatal(1, "NOS deadline IRQ forced on every tick");
        if (bad) $fatal(1, "timer ACK rejected");
        $display("PASS timer26MHz/OS64Hz/NOS64Hz at CPU %0d", SYS_CLK_HZ);
        $finish;
    end
endmodule
