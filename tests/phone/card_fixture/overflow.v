`timescale 1ns / 1ps
module tb;
    reg clk = 0, reset = 1, tx_valid = 0, rx_pop = 0;
    reg [7:0] tx_data = 0;
    wire rx_valid, overflow, will_emit, busy;
    wire [7:0] rx_data;
    wire [6:0] available;
    always #5 clk = ~clk;
    ngage_test_sim dut (
        .clk         (clk),
        .reset       (reset),
        .tx_valid    (tx_valid),
        .tx_data     (tx_data),
        .rx_pop      (rx_pop),
        .rx_valid    (rx_valid),
        .rx_data     (rx_data),
        .overflow    (overflow),
        .available   (available),
        .tx_will_emit(will_emit),
        .busy        (busy)
    );
    task send;
        input [7:0] b;
        begin
            @(negedge clk);
            tx_data  = b;
            tx_valid = 1;
            @(negedge clk);
            tx_valid = 0;
            while (busy) @(negedge clk);
        end
    endtask
    task status22;
        begin
            send('ha0);
            send('hf2);
            send(0);
            send(0);
            send(22);
        end
    endtask
    initial begin
        repeat (2) @(negedge clk);
        reset = 0;
        status22;
        status22;
        if (available !== 50 || overflow) begin
            $display("FAIL pre-overflow count %d", available);
            $finish;
        end
        status22;
        if (available !== 64 || !overflow) begin
            $display("FAIL overflow count %d overflow %b", available, overflow);
            $finish;
        end
        @(negedge clk);
        rx_pop = 1;
        @(negedge clk);
        rx_pop = 0;
        if (available !== 63 || !overflow) begin
            $display("FAIL overflow must remain sticky");
            $finish;
        end
        reset = 1;
        @(negedge clk);
        reset = 0;
        #1;
        if (available !== 0 || overflow) begin
            $display("FAIL reset clears FIFO and overflow");
            $finish;
        end
        // Reset cancels an unpublished multi-byte response, including RAM writes.
        send('ha0);
        send('hf2);
        send(0);
        send(0);
        @(negedge clk);
        tx_data  = 22;
        tx_valid = 1;
        @(negedge clk);
        tx_valid = 0;
        if (!busy || available != 0) $fatal(1, "response must be private while writing");
        repeat (3) @(negedge clk);
        reset = 1;
        @(negedge clk);
        reset = 0;
        #1;
        if (busy || available != 0 || overflow) $fatal(1, "reset published partial response");
        $display("PASS diagnostic SIM bounded FIFO overflow and reset");
        $finish;
    end
endmodule
