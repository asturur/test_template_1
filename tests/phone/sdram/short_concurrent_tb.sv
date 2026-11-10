`timescale 1ns / 1ps
// Concurrent physical-bank clients: BST must retain its command slot without
// allowing another bank to advance on that slot. Original Micron timing model.
module tb;
    parameter SYS_CLK_HZ = 104000000;
    parameter SHORT_READS = 1, LINE_REFILL = 1, CAPTURE_NEGEDGE = 1;
    localparam real HALF_PERIOD = 500000000.0 / SYS_CLK_HZ;
    reg clk = 0;
    always #(HALF_PERIOD) clk = ~clk;
    wire memclk;
    ngage_sdram_clock clock_pin (
        .clk(clk),
        .sdram_clk(memclk)
    );
    reg  rst = 1;
    wire init;
    reg [21:0] address0 = 0, address1 = 0;
    wire [15:0] ba_din = 0;
    wire [ 1:0] ba_dsn = 3;
    reg  [ 3:0] rd = 0;
    wire [ 3:0] wr = 0;
    wire [3:0] ba_ack, ba_dst, ba_dok, ba_rdy;
    wire [15:0] ba_dout;
    tri  [15:0] dq;
    wire [12:0] a;
    wire [ 1:0] bank;
    wire dqml, dqmh, nwe, ncas, nras, ncs, cke;
    reg [1:0] long_read = 0;
    reg rfsh = 0;
    integer refresh_clock = 0;
    always @(posedge clk) begin
        rfsh <= 0;
        if (!init) begin
            refresh_clock <= refresh_clock + 1;
            if (refresh_clock % 401 == 400) rfsh <= 1;
        end
    end
    jtframe_sdram64 #(
        .SHORT_READS(SHORT_READS),
        .DYNAMIC_LINE(LINE_REFILL),
        .AW(22),
        .HF(1),
        .READ_CAPTURE_NEGEDGE(CAPTURE_NEGEDGE),
        .BA0_LEN(LINE_REFILL ? 128 : 32),
        .BA1_LEN(LINE_REFILL ? 128 : 32),
        .BA2_LEN(16),
        .BA3_LEN(16),
        .PROG_LEN(16),
        .BA0_WEN(1),
        .BA1_WEN(1),
        .BAPRIO(0)
    ) ctrl (
        .line_read(long_read),
        .rst(rst),
        .clk(clk),
        .init(init),
        .ba0_addr(address0),
        .ba1_addr(address1),
        .ba2_addr(22'b0),
        .ba3_addr(22'b0),
        .rd(rd),
        .wr(wr),
        .ba0_din(ba_din),
        .ba1_din(ba_din),
        .ba2_din(16'b0),
        .ba3_din(16'b0),
        .ba0_dsn(ba_dsn),
        .ba1_dsn(ba_dsn),
        .ba2_dsn(2'b11),
        .ba3_dsn(2'b11),
        .prog_en(1'b0),
        .prog_addr(22'b0),
        .prog_rd(1'b0),
        .prog_wr(1'b0),
        .prog_din(16'b0),
        .prog_dsn(2'b11),
        .prog_ba(2'b0),
        .prog_dst(),
        .prog_dok(),
        .prog_rdy(),
        .prog_ack(),
        .rfsh(rfsh),
        .ack(ba_ack),
        .dst(ba_dst),
        .dok(ba_dok),
        .rdy(ba_rdy),
        .dout(ba_dout),
        .sdram_dq(dq),
        .sdram_a(a),
        .sdram_dqml(dqml),
        .sdram_dqmh(dqmh),
        .sdram_ba(bank),
        .sdram_nwe(nwe),
        .sdram_ncas(ncas),
        .sdram_nras(nras),
        .sdram_ncs(ncs),
        .sdram_cke(cke)
    );
    mt48lc16m16a2 ram (
        .Clk(memclk),
        .Cke(cke),
        .Dq(dq),
        .Addr(a),
        .Ba(bank),
        .Cs_n(ncs),
        .Ras_n(nras),
        .Cas_n(ncas),
        .We_n(nwe),
        .Dqm({dqmh, dqml}),
        .downloading(1'b0),
        .VS(1'b0),
        .frame_cnt(32'b0)
    );

    integer physical_beats = 0, commands = 0, stops = 0, refreshes = 0, clocks = 0;
    always @(posedge clk) if (!init) clocks = clocks + 1;
    always @(posedge memclk) begin
        if (!init) begin
            if ({ncs, nras, ncas, nwe} == 4'b0101) commands = commands + 1;
            if ({ncs, nras, ncas, nwe} == 4'b0110) stops = stops + 1;
            if ({ncs, nras, ncas, nwe} == 4'b0001) refreshes = refreshes + 1;
        end
        #0.001;
        if (ram.Data_out_enable) physical_beats = physical_beats + 1;
    end
    integer round, j, b, n, timeout, expected_beats = 0;
    integer captured[0:1];
    reg [1:0] pending, receiving, finished;
    reg [15:0] expected;
    reg [21:0] word_address;
    initial begin
        for (j = 0; j < 2048; j = j + 1) begin
            ram.Bank0[j] = 16'ha000 ^ j;
            ram.Bank1[j] = 16'h5000 ^ j;
        end
        repeat (5) @(negedge clk);
        rst = 0;
        wait (!init);
        repeat (5) @(negedge clk);
        for (round = 0; round < 300; round = round + 1) begin
            address0 = ((round * 37) % 256) * 8;
            address1 = ((round * 67) % 256) * 8;
            long_read = round % 4;
            pending = 3;
            rd = 3;
            receiving = 0;
            finished = 0;
            captured[0] = 0;
            captured[1] = 0;
            timeout = 0;
            expected_beats=expected_beats+((long_read[0] || !SHORT_READS)?8:2)+((long_read[1] || !SHORT_READS)?8:2);
            while (finished != 3 && timeout < 10000) begin
                @(negedge clk);
                timeout = timeout + 1;
                for (b = 0; b < 2; b = b + 1) begin
                    if (ba_ack[b]) begin
                        if (!pending[b]) $fatal(1, "duplicate ack bank%0d", b);
                        pending[b] = 0;
                        rd[b] = 0;
                    end
                    if (ba_dst[b]) begin
                        if (receiving[b] || finished[b]) $fatal(1, "duplicate dst bank%0d", b);
                        receiving[b] = 1;
                    end
                    if (receiving[b]) begin
                        word_address = (b == 0 ? address0 : address1) + captured[b];
                        expected = (b == 0 ? 16'ha000 : 16'h5000) ^ word_address;
                        if (ba_dout !== expected)
                            $fatal(
                                1,
                                "round%0d bank%0d beat%0d got%h want%h",
                                round,
                                b,
                                captured[b],
                                ba_dout,
                                expected
                            );
                        captured[b] = captured[b] + 1;
                    end
                    if (ba_rdy[b]) begin
                        if (!receiving[b] || captured[b] != (long_read[b] ? 8 : 2))
                            $fatal(1, "wrong beat count bank%0d count%0d", b, captured[b]);
                        receiving[b] = 0;
                        finished[b]  = 1;
                    end
                end
            end
            if (finished != 3)
                $fatal(1, "starvation round%0d pending%b receiving%b", round, pending, receiving);
            repeat (3) @(negedge clk);
            if (SHORT_READS && ba_dok[1:0] != 0) $fatal(1, "dok stuck after short read");
        end
        repeat (30) @(negedge clk);
        if(commands!=600 || stops!=(SHORT_READS?300:0) || physical_beats!=expected_beats || refreshes==0)
            $fatal(
                1,
                "traffic totals reads%0d stops%0d beats%0d expected%0d refresh%0d",
                commands,
                stops,
                physical_beats,
                expected_beats,
                refreshes
            );
        $display(
            "PASS concurrent SDRAM banks: commands=%0d stops=%0d halfwords=%0d refreshes=%0d clocks=%0d",
            commands, stops, physical_beats, refreshes, clocks);
        $finish;
    end
    initial begin
        #10000000;
        $fatal(1, "timeout");
    end
endmodule
