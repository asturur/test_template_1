`timescale 1ns / 1ps
module tb;
    reg clk = 0, reset = 1, tx_valid = 0, rx_pop = 0;
    reg [7:0] tx_data = 0;
    wire rx_valid, overflow, busy;
    wire [7:0] rx_data;
    wire [6:0] available;
    integer f, rc, line = 0;
    reg [7:0] op;
    reg [31:0] value, count;
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
        .tx_will_emit(),
        .busy        (busy)
    );
    initial begin
        f = $fopen("build/sim/unit-test-sim/reference.tsv", "r");
        if (!f) begin
            $display("FAIL missing card reference");
            $finish;
        end
        @(negedge clk);
        reset = 0;
        while (!$feof(
            f
        )) begin
            rc = $fscanf(f, "%c %h %h\n", op, value, count);
            if (rc == 3) begin
                line     = line + 1;
                tx_valid = 0;
                rx_pop   = 0;
                if (op == "W") begin
                    tx_data  = value[7:0];
                    tx_valid = 1;
                end else if (op == "R") begin
                    if (!rx_valid || rx_data !== value[7:0]) begin
                        $display("FAIL byte line %0d got %h expected %h", line, rx_data, value);
                        $finish;
                    end
                    rx_pop = 1;
                end else begin
                    $display("FAIL operation");
                    $finish;
                end
                @(posedge clk);
                #1;
                @(negedge clk);
                tx_valid = 0;
                rx_pop   = 0;
                while (busy) @(negedge clk);
                #1;
                if (overflow || available !== count[6:0]) begin
                    $display("FAIL queue line %0d got %0d expected %0d", line, available, count);
                    $finish;
                end
                @(negedge clk);
            end
        end
        $display("PASS diagnostic SIM bytes and FIFO against C++ (%0d operations)", line);
        $finish;
    end
endmodule
