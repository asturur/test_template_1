/*  Cross-check testbench: drives rtl/ngage_modem.v with the vectors the C
    model produced (gen_vectors.c -> vectors.hex) and compares every reply
    byte. Random rx gaps and tx backpressure exercise the handshake.
    Run:  iverilog -g2001 -o tb tb_modem.v ../../rtl/ngage_modem.v && vvp tb
    Made with Claude, 2026-10-31.
*/
`timescale 1ns/1ns

module tb_modem;

reg        rst, clk, rx_v, tx_ready;
reg  [7:0] rx_d;
wire       tx_v, busy;
wire [7:0] tx_d;

ngage_modem dut(
    .rst(rst), .clk(clk),
    .rx_v(rx_v), .rx_d(rx_d),
    .tx_v(tx_v), .tx_d(tx_d), .tx_ready(tx_ready), .busy(busy),
    .own_dev(8'h00),
    .imei(128'h30303434_30303031_32333435_36373800), // "004400012345678\0"
    .chg_status(8'd1), .chg_raw(8'd0),
    .bat_status(8'd1), .bat_bars(8'd7),
    .bat_mv(16'h0fa0), .bat_aux(16'd0),
    .sim_reg(1'b0)
);

always #5 clk = ~clk;

reg [7:0] vec [0:262143];
integer vp, nvec, fails;
integer i, rl, got;
reg [7:0] req_len, exp_len;
reg [7:0] expect [0:63];
reg [7:0] rxbuf  [0:63];

task step; begin @(posedge clk); #1; end endtask

initial begin
    $readmemh("vectors.hex", vec);
    clk = 0; rst = 1; rx_v = 0; rx_d = 0; tx_ready = 0;
    vp = 0; nvec = 0; fails = 0;
    repeat (4) step;
    rst = 0;
    repeat (2) step;

    while (vec[vp] !== 8'hff && vec[vp] !== 8'hxx) begin
        req_len = vec[vp]; vp = vp + 1;
        for (i = 0; i < req_len; i = i + 1) begin
            rxbuf[i] = vec[vp]; vp = vp + 1;
        end
        exp_len = vec[vp]; vp = vp + 1;
        for (i = 0; i < exp_len; i = i + 1) begin
            expect[i] = vec[vp]; vp = vp + 1;
        end

        // drive the request with random gaps
        for (i = 0; i < req_len; i = i + 1) begin
            while ($random & 3) step;      // 0-n idle cycles
            rx_v = 1; rx_d = rxbuf[i]; step;
            rx_v = 0;
        end

        // collect the reply with random backpressure. Sample tx_v/tx_d
        // BEFORE the edge: that pair is what the DUT commits at the edge.
        got = 0; rl = 0;
        while (rl < 2000 && (got < exp_len || exp_len == 0)) begin
            tx_ready = ($random & 3) != 0;
            #1;
            if (tx_v && tx_ready) begin
                if (got < exp_len) begin
                    if (tx_d !== expect[got]) begin
                        $display("FAIL vec %0d byte %0d: got %02x want %02x",
                                 nvec, got, tx_d, expect[got]);
                        fails = fails + 1;
                    end
                end else begin
                    $display("FAIL vec %0d: unexpected extra byte %02x",
                             nvec, tx_d);
                    fails = fails + 1;
                end
                got = got + 1;
            end
            step;
            rl = rl + 1;
            if (exp_len == 0 && rl > 120 && !busy) rl = 2000; // silence OK
        end
        if (exp_len != 0 && got < exp_len) begin
            $display("FAIL vec %0d: reply truncated at %0d of %0d",
                     nvec, got, exp_len);
            fails = fails + 1;
        end
        // drain: make sure nothing trails
        tx_ready = 1;
        repeat (8) begin
            #1;
            if (tx_v) begin
                $display("FAIL vec %0d: trailing tx_v", nvec);
                fails = fails + 1;
            end
            step;
        end
        tx_ready = 0;
        nvec = nvec + 1;
    end

    if (fails == 0)
        $display("ALL %0d VECTORS PASS (RTL == C model, byte-exact)", nvec);
    else
        $display("%0d FAILURES over %0d vectors", fails, nvec);
    $finish;
end

initial begin
    #80_000_000;
    $display("TIMEOUT");
    $finish;
end

endmodule
