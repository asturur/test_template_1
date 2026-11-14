`timescale 1ns / 1ps
// Independent byte-queue scoreboard: saturation, wrap, and pop + response
// on the same edge. APDU/status contents are covered by the reference test.
module tb;
    reg clk = 0, reset = 1, tx_valid = 0, rx_pop = 0;
    reg [7:0] tx_data = 0;
    wire rx_valid, overflow, will_emit, busy;
    wire [7:0] rx_data;
    wire [6:0] available;
    reg  [7:0] queue     [0:63];
    integer head = 0, tail = 0, used = 0, sticky = 0;
    integer seed = 73492, command, byte_index, n;
    reg [199:0] response;
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
    task step;
        input transmit;
        input [7:0] data;
        input pop;
        input integer count;
        input [199:0] bytes;
        integer i, pending_used;
        begin
            @(negedge clk);
            tx_valid     = transmit;
            tx_data      = data;
            rx_pop       = pop;
            pending_used = used - ((pop && used != 0) ? 1 : 0);
            if (pop && used != 0) begin
                head = (head + 1) % 64;
                used = used - 1;
            end
            for (i = 0; i < count; i = i + 1) begin
                if (used < 64) begin
                    queue[tail] = bytes[i*8+:8];
                    tail        = (tail + 1) % 64;
                    used        = used + 1;
                end else sticky = 1;
            end
            @(posedge clk);
            #1;
            @(negedge clk);
            tx_valid = 0;
            rx_pop   = 0;
            while (busy) begin
                // Accepted bytes remain private until the final RAM write.
                if (available !== pending_used) $fatal(1, "partial response published");
                @(negedge clk);
            end
            #1;
            if (available !== used || overflow !== (sticky != 0) || rx_valid !== (used != 0))
                $fatal(
                    1, "FIFO counts expected=%0d actual=%0d sticky=%b", used, available, overflow
                );
            if (used != 0 && rx_data !== queue[head])
                $fatal(1, "FIFO byte expected=%h actual=%h", queue[head], rx_data);
        end
    endtask
    initial begin
        repeat (2) @(negedge clk);
        reset = 0;
        for (command = 0; command < 600; command = command + 1) begin
            // Valid STATUS(22) yields 25 bytes, bad CLA yields two bytes.
            // Drive both through a full queue, then through changing free space.
            response = 0;
            if (command % 3 == 0) begin
                response[0+:8] = 8'h6e;
                n              = 2;
            end else begin
                response[0+:8]    = 8'hf2;
                response[5*8+:8]  = 8'h3f;
                response[7*8+:8]  = 1;
                response[13*8+:8] = 9;
                response[14*8+:8] = 8'hb0;
                response[17*8+:8] = 2;
                response[19*8+:8] = 8'h83;
                response[20*8+:8] = 8'h8a;
                response[21*8+:8] = 8'h83;
                response[22*8+:8] = 8'h8a;
                response[23*8+:8] = 8'h90;
                n                 = 25;
            end
            step(1, command % 3 == 0 ? 0 : 8'ha0, $random(seed) & 1, 0, 0);
            step(1, 8'hf2, $random(seed) & 1, 0, 0);
            step(1, 0, $random(seed) & 1, 0, 0);
            step(1, 0, $random(seed) & 1, 0, 0);
            step(1, 22, $random(seed) & 1, n, response);
            // Alternate filling and draining; exercise all ring positions.
            for (byte_index = 0; byte_index < command % 39; byte_index = byte_index + 1)
            step(0, 0, 1, 0, 0);
        end
        repeat (64) step(0, 0, 1, 0, 0);
        $display(
            "PASS diagnostic SIM FIFO scoreboard: 600 responses, wrap, saturation and concurrent pop");
        $finish;
    end
endmodule
