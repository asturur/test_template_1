`timescale 1ns / 1ps
module tb;
    reg clk = 0, reset = 1, request = 0, accept = 0, release_complete = 0;
    wire ready, valid, complete;
    wire [7:0] data;
    integer i, round, count = 0;
    reg  [223:0] observed = 0;
    reg  [  7:0] held;
    real         half_period = 6.410256;
    initial
        if ($value$plusargs("half_period=%f", half_period)) begin
        end
    always #(half_period) clk = ~clk;
    ngage_adsp_bootstrap_tx dut (
        .clk           (clk),
        .reset         (reset),
        .request_valid (request),
        .request_ready (ready),
        .tx_valid      (valid),
        .tx_ready      (accept),
        .tx_data       (data),
        .complete_valid(complete),
        .complete_ready(release_complete)
    );
    always @(posedge clk)
        if (!reset && valid && accept) begin
            observed <= {observed[215:0], data};
            count    <= count + 1;
        end
    initial begin
        repeat (3) @(negedge clk);
        reset = 0;
        #1;
        for (round = 0; round < 2; round = round + 1) begin
            if (!ready || valid || complete) $fatal(1, "idle ownership");
            request = 1;
            @(negedge clk);
            request = 0;
            for (i = 0; i < 28; i = i + 1) begin
                held = data;
                repeat (3) begin
                    @(negedge clk);
                    if (!valid || data !== held || complete || ready) $fatal(1, "stalled byte");
                end
                accept = 1;
                @(negedge clk);
                accept = 0;
            end
            if (!complete || valid || ready || count != 28 * (round + 1)) $fatal(1, "completion");
            if (observed !== 224'h5555200078d000040111016058a55555200078d00003040160003cd2)
                $fatal(1, "wrong native startup packets: %h", observed);
            repeat (4) begin
                @(negedge clk);
                if (!complete || valid || ready) $fatal(1, "completion ownership");
            end
            release_complete = 1;
            @(negedge clk);
            release_complete = 0;
        end
        // A reset cancels an interrupted stream; the next request starts at
        // the first sync byte and never resumes a partial old packet.
        request = 1;
        @(negedge clk);
        request = 0;
        accept  = 1;
        repeat (7) @(negedge clk);
        accept = 0;
        reset  = 1;
        #1;
        if (valid || complete || ready) $fatal(1, "reset gating");
        @(negedge clk);
        reset = 0;
        #1;
        if (!ready || valid || complete) $fatal(1, "reset ownership");
        request = 1;
        @(negedge clk);
        request = 0;
        if (!valid || data !== 8'h55) $fatal(1, "restart sync");
        $display(
            "PASS D550 bootstrap: original D0/01+D0/04 bytes, stalls, exact-once delivery, completion hold, repetition and partial-stream reset");
        $finish;
    end
    initial begin
        #100000;
        $fatal(1, "timeout");
    end
endmodule
