`timescale 1ns / 1ps
module tb;
    reg clk = 0, rst = 1, cold = 1, req = 0, we = 0, authorize = 0, legacy_done = 0;
    reg tx_ready = 0, rx_valid = 0;
    reg [7:0] rx_data = 0;
    wire [1:0] tx_valid, rx_ready, fiqs;
    wire    [7:0] tx_data [0:1];
    integer       tx_count[0:1];
    reg [31:0] addr = 0, din = 0;
    reg [3:0] sel = 15;
    wire [1:0] claim, ready, bad, init, trace_valid;
    wire [31:0] dout[0:1];
    integer traces0 = 0, traces1 = 0, checks = 0;
    always #5 clk = ~clk;
    genvar n;
    generate
        for (n = 0; n < 2; n = n + 1) begin : g
            ngage_board #(
                .ADSP_EXTERNAL(1),
                .SIMIF_ENABLE (1),
                .KEYPAD_ENABLE(1)
            ) dut (
                .clk            (clk),
                .rst            (rst),
                .init_rst       (cold),
                .cyc            (req),
                .stb            (req),
                .we             (we),
                .adr            (addr),
                .din            (din),
                .sel            (sel),
                .commit         (authorize && (n == 1 || (!legacy_done && ready[n]))),
                .cfg_lcd        (1'b1),
                .cfg_keypad     (1'b1),
                .cfg_clocks     (1'b1),
                .keys           (27'b0),
                .sim_present    (1'b1),
                .dma_irq_pending(1'b0),
                .sim_fiq_pending(1'b0),
                .adsp_tx_valid  (tx_valid[n]),
                .adsp_tx_ready  (tx_ready),
                .adsp_tx_data   (tx_data[n]),
                .adsp_rx_valid  (rx_valid),
                .adsp_rx_ready  (rx_ready[n]),
                .adsp_rx_data   (rx_data),
                .fiq            (fiqs[n]),
                .claim          (claim[n]),
                .ready          (ready[n]),
                .unmodeled      (bad[n]),
                .dout           (dout[n]),
                .init_done      (init[n]),
                .trace_valid    (trace_valid[n])
            );
            defparam dut.upp.peripherals.REGISTER_RESPONSES = n;
        end
    endgenerate
    always @(posedge clk) begin
        if (tx_valid[0] && tx_ready) tx_count[0] <= tx_count[0] + 1;
        if (tx_valid[1] && tx_ready) tx_count[1] <= tx_count[1] + 1;
        if (trace_valid[0]) traces0 = traces0 + 1;
        if (trace_valid[1]) traces1 = traces1 + 1;
    end
    task tick;
        begin
            @(negedge clk);
            #1;
        end
    endtask
    task transfer;
        input wr;
        input [31:0] a, d;
        input [3:0] lanes;
        reg     [31:0] expected;
        reg            expected_bad;
        integer        waits;
        begin
            tick();
            req         = 1;
            we          = wr;
            addr        = a;
            din         = d;
            sel         = lanes;
            authorize   = 0;
            legacy_done = 0;
            #1;
            // Lookup may run before authorization, but neither response nor effects
            // can be published by the registered boundary until accepted.
            repeat (2) tick();
            if (ready[1]) $fatal(1, "response before authorization");
            waits = 0;
            while (!ready[0]) begin
                tick();
                waits = waits + 1;
                if (waits > 80) $fatal(1, "local timeout %h", a);
            end
            expected     = dout[0];
            expected_bad = bad[0];
            authorize    = 1;
            tick();
            legacy_done = 1;
            if (!ready[1] || !claim[1] || bad[1] !== expected_bad || (!wr && dout[1] !== expected))
                $fatal(
                    1,
                    "response mismatch a=%h ready=%b bad=%b/%b data=%h/%h",
                    a,
                    ready[1],
                    bad[1],
                    expected_bad,
                    dout[1],
                    expected
                );
            expected = dout[1];
            repeat (5) begin
                tick();
                if (!ready[1] || !claim[1] || bad[1] !== expected_bad || dout[1] !== expected)
                    $fatal(1, "held result changed %h", a);
            end
            authorize = 0;
            req       = 0;
            tick();
            checks = checks + 1;
        end
    endtask

    task expect_read;
        input [31:0] a, expected;
        input [3:0] lanes;
        begin
            transfer(0, a, 0, lanes);
            if (dout[1] !== expected)
                $fatal(1, "CTSI read %h got%h expected%h", a, dout[1], expected);
        end
    endtask
    initial begin
        tx_count[0] = 0;
        tx_count[1] = 0;
        repeat (2) tick();
        cold = 0;
        wait (&init);
        tick();
        rst = 0;
        repeat (65) tick();
        // Real card ATR and UART share status word but own separate byte lanes.
        transfer(1, 'h0c150808, 1, 3);
        tick();
        rx_valid = 1;
        rx_data  = 'ha5;
        tick();
        rx_valid = 0;
        expect_read('h0c1500b8, 'h00080004, 15);
        if (fiqs !== 0) $fatal(1, "masked FIQ");
        transfer(1, 'h0c1201c8, 'h04000000, 15);
        if (fiqs !== 3) $fatal(1, "SIM source26");
        transfer(1, 'h0c150800, 16, 3);
        if (fiqs !== 0) $fatal(1, "UART mask or SIM release");
        transfer(1, 'h0c15000c, 'h00080000, 12);
        if (fiqs !== 3) $fatal(1, "UART CTSI source26");
        expect_read('h0c1500b8, 0, 3);
        expect_read('h0c1500b8, 'h00080000, 12);
        transfer(1, 'h0c1500b8, 'h00080000, 12);
        if (fiqs !== 3) $fatal(1, "early RX ACK lost ownership");
        expect_read('h0c150554, 'ha5000000, 12);
        if (fiqs !== 0) $fatal(1, "RX did not drain exactly once");
        transfer(1, 'h0c150558, 'h00020000, 12);
        transfer(1, 'h0c150554, 'h5500, 3);
        transfer(1, 'h0c150554, 'h7800, 3);
        transfer(1, 'h0c150554, 'h8200, 3);
        expect_read('h0c150514, 0, 3);
        if(g[0].dut.upp.peripherals.euart1.tx_count!==3 || g[1].dut.upp.peripherals.euart1.tx_count!==3)
            $fatal(1, "held response duplicated TX");
        tx_ready = 1;
        wait (tx_count[0] == 3 && tx_count[1] == 3);
        tick();
        tx_ready = 0;
        expect_read('h0c150514, 4, 3);
        expect_read('h0c1500b8, 'h00100000, 12);
        transfer(1, 'h0c15000c, 'h00100000, 12);
        if (fiqs !== 3) $fatal(1, "TX completion CTSI");
        transfer(1, 'h0c1500b8, 'h00100000, 12);
        if (fiqs !== 0) $fatal(1, "TX completion ACK");
        rst = 1;
        repeat (2) tick();
        rst = 0;
        tick();
        expect_read('h0c1500b8, 0, 15);
        if (fiqs !== 0 || tx_valid !== 0) $fatal(1, "reset stale ownership");
        $display(
            "PASS production CTSI: SIM/UART status lanes, FIQ26 masks/ACK, TX backpressure, exactly-once registered responses and reset");
        $finish;
    end
    initial begin
        #10000000;
        $fatal(1, "timeout");
    end
endmodule
