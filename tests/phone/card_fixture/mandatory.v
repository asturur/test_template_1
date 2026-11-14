`timescale 1ns / 1ps
// Independent TS51.011 read vectors for the native post-ready file phase.
module tb;
    parameter integer CLOCK_DIV = 1;
    reg clk = 0, reset = 1, tx_valid = 0, rx_pop = 0;
    reg [7:0] tx_data = 0;
    wire rx_valid, overflow, busy;
    wire [7:0] rx_data;
    wire [6:0] available;
    integer waits, checks = 0, n, pass;
    always #5 clk = ~clk;
    ngage_test_sim #(
        .CLOCK_DIV(CLOCK_DIV)
    ) dut (
        .clk         (clk),
        .reset       (reset),
        .tx_valid    (tx_valid),
        .tx_data     (tx_data),
        .rx_pop      (rx_pop),
        .rx_valid    (rx_valid),
        .rx_data     (rx_data),
        .overflow    (overflow),
        .available   (available),
        .tx_will_emit(),
        .busy        (busy)
    );
    task settle;
        begin
            waits = 0;
            while (busy) begin
                @(negedge clk);
                waits = waits + 1;
                if (waits > 120) $fatal(1, "card response stalled");
            end
            if (overflow) $fatal(1, "unexpected overflow");
        end
    endtask
    task send;
        input [7:0] value;
        begin
            @(negedge clk);
            tx_valid = 1;
            tx_data  = value;
            @(negedge clk);
            tx_valid = 0;
            settle;
        end
    endtask
    task receive;
        input [7:0] expected;
        begin
            if (!rx_valid || rx_data !== expected)
                $fatal(
                    1, "byte %0d got %h expected %h count %0d", checks, rx_data, expected, available
                );
            checks = checks + 1;
            @(negedge clk);
            rx_pop = 1;
            @(negedge clk);
            rx_pop = 0;
            settle;
        end
    endtask
    task command;
        input [7:0] ins, count;
        begin
            send(8'ha0);
            send(ins);
            send(0);
            send(0);
            send(count);
        end
    endtask
    task select_file;
        input [15:0] file;
        input [15:0] status;
        begin
            command(8'ha4, 2);
            receive(8'ha4);
            send(file[15:8]);
            send(file[7:0]);
            receive(status[15:8]);
            receive(status[7:0]);
        end
    endtask
    task file_read;
        input [15:0] file;
        input [7:0] length;
        begin
            select_file(file, 16'h9f0f);
            command(8'hc0, 15);
            if (available !== 18) $fatal(1, "EF metadata length");
            receive(8'hc0);
            receive(0);
            receive(0);
            receive(0);
            receive(length);
            receive(file[15:8]);
            receive(file[7:0]);
            receive(4);
            receive(0);
            receive(8'h0f);
            receive(8'hff);
            receive(8'hff);
            receive(1);
            receive(2);
            receive(0);
            receive(0);
            receive(8'h90);
            receive(0);
            command(8'hb0, length);
            if (available !== length + 3) $fatal(1, "EF data length");
            receive(8'hb0);
            for (n = 0; n < length; n = n + 1) begin
                if (file == 16'h6f7b) receive(8'hff);
                else if (file == 16'h6f20 && n == 8) receive(7);
                else receive(0);
            end
            receive(8'h90);
            receive(0);
            // A malformed length must not return a truncated success.
            command(8'hb0, length - 1'b1);
            receive(8'h6d);
            receive(0);
            if (available !== 0) $fatal(1, "EF response did not drain");
        end
    endtask
    initial begin
        repeat (2) @(negedge clk);
        reset = 0;
        // GSM files must not become selectable at the master-file level.
        select_file(16'h6f74, 16'h9404);
        select_file(16'h6f20, 16'h9404);
        select_file(16'h6f7b, 16'h9404);
        select_file(16'h7f20, 16'h9f16);
        // Repeat enough bytes to wrap the physical64-byte FIFO many times.
        for (pass = 0; pass < 4; pass = pass + 1) begin
            file_read(16'h6f74, 16);
            file_read(16'h6f20, 9);
            file_read(16'h6f7b, 12);
        end
        select_file(16'h6fc6, 16'h9404);
        $display(
            "PASS mandatory SIM files DIV=%0d bytes=%0d: exact metadata/data, no-key sequence7, directory/length errors and FIFO wrap",
            CLOCK_DIV, checks);
        $finish;
    end
endmodule
